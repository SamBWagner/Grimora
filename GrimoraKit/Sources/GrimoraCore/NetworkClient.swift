import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NetworkPurpose: String, Equatable, Hashable, Sendable {
    case manifestCheck
    case bulkDownload
    case automaticCatalogDownload
    case imageDownload
    case deckImport
    case priceHistoryDownload
}

public struct NetworkDownloadProgress: Equatable, Sendable {
    public var completedBytes: Int64
    public var totalBytes: Int64?

    public init(completedBytes: Int64, totalBytes: Int64?) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    public var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else {
            return nil
        }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }
}

public protocol NetworkClient: Sendable {
    func data(from url: URL, purpose: NetworkPurpose) async throws -> Data
    func download(
        from url: URL,
        to destination: URL,
        purpose: NetworkPurpose,
        progress: (@Sendable (NetworkDownloadProgress) async -> Void)?
    ) async throws
}

public extension NetworkClient {
    func download(from url: URL, to destination: URL, purpose: NetworkPurpose) async throws {
        try await download(from: url, to: destination, purpose: purpose, progress: nil)
    }
}

public enum NetworkClientError: Error, Equatable, Sendable {
    case blocked(NetworkPurpose, URL)
    case badHTTPStatus(Int)
}

public struct URLSessionNetworkClient: NetworkClient {
    private let session: URLSession
    private let userAgent: String

    public init(
        session: URLSession = .shared,
        userAgent: String = "Grimora/1.0 (offline Scryfall bulk client)"
    ) {
        self.session = session
        self.userAgent = userAgent
    }

    public func data(from url: URL, purpose: NetworkPurpose) async throws -> Data {
        let (data, response) = try await session.data(for: request(for: url, purpose: purpose))
        try validate(response)
        return data
    }

    public func download(
        from url: URL,
        to destination: URL,
        purpose: NetworkPurpose,
        progress: (@Sendable (NetworkDownloadProgress) async -> Void)? = nil
    ) async throws {
        #if os(Linux)
        let (data, response) = try await session.data(for: request(for: url, purpose: purpose))
        try validate(response)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        await progress?(
            NetworkDownloadProgress(
                completedBytes: Int64(data.count),
                totalBytes: Int64(data.count)
            )
        )
        #else
        let (bytes, response) = try await session.bytes(for: request(for: url, purpose: purpose))
        try validate(response)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent)-\(UUID().uuidString).download")
        _ = FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let file = try FileHandle(forWritingTo: temporaryURL)
        defer {
            try? file.close()
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let totalBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        var completedBytes: Int64 = 0
        var lastReportedBytes: Int64 = -1
        let reportInterval = max((totalBytes ?? 0) / 200, 1_048_576)

        func reportDownloadProgress(force: Bool = false) async {
            guard let progress else {
                return
            }
            guard force || completedBytes - lastReportedBytes >= reportInterval else {
                return
            }
            lastReportedBytes = completedBytes
            await progress(NetworkDownloadProgress(completedBytes: completedBytes, totalBytes: totalBytes))
        }

        await reportDownloadProgress(force: true)
        var buffer = Data()
        buffer.reserveCapacity(65_536)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 65_536 {
                try file.write(contentsOf: buffer)
                completedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                await reportDownloadProgress()
            }
        }

        if !buffer.isEmpty {
            try file.write(contentsOf: buffer)
            completedBytes += Int64(buffer.count)
        }
        try file.close()

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        await reportDownloadProgress(force: true)
        #endif
    }

    private func request(for url: URL, purpose: NetworkPurpose) -> URLRequest {
        var request = URLRequest(url: url)
        #if !os(Linux)
        if purpose == .automaticCatalogDownload {
            request.allowsExpensiveNetworkAccess = false
            request.allowsConstrainedNetworkAccess = false
        }
        #endif
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClientError.badHTTPStatus(http.statusCode)
        }
    }
}

public struct BlockingNetworkClient: NetworkClient {
    public init() {}

    public func data(from url: URL, purpose: NetworkPurpose) async throws -> Data {
        throw NetworkClientError.blocked(purpose, url)
    }

    public func download(
        from url: URL,
        to destination: URL,
        purpose: NetworkPurpose,
        progress: (@Sendable (NetworkDownloadProgress) async -> Void)? = nil
    ) async throws {
        throw NetworkClientError.blocked(purpose, url)
    }
}
