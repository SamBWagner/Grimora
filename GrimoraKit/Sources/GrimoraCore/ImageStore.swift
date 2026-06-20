import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public struct ImageStore: Sendable {
    public var rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func localURL(for remoteURL: URL, cardID: String, faceIndex: Int?, quality: String) -> URL {
        let extensionName = remoteURL.pathExtension.isEmpty ? "jpg" : remoteURL.pathExtension
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let faceComponent = faceIndex.map { "face-\($0)" } ?? "front"
        return rootDirectory
            .appendingPathComponent(cardID, isDirectory: true)
            .appendingPathComponent(faceComponent, isDirectory: true)
            .appendingPathComponent("\(quality)-\(digest).\(extensionName)")
    }

    public func removeAllImages(
        fileManager: FileManager = .default,
        progress: ((ImageStoreRemovalProgress) -> Void)? = nil
    ) throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            progress?(ImageStoreRemovalProgress(removedItems: 0, totalItems: 0))
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            return
        }

        let items = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )
        let totalItems = items.count
        progress?(ImageStoreRemovalProgress(removedItems: 0, totalItems: totalItems))

        for (index, item) in items.enumerated() {
            try fileManager.removeItem(at: item)
            let removedItems = index + 1
            if Self.shouldReportRemovalProgress(removedItems: removedItems, totalItems: totalItems) {
                progress?(ImageStoreRemovalProgress(removedItems: removedItems, totalItems: totalItems))
            }
        }

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    static func shouldReportRemovalProgress(removedItems: Int, totalItems: Int) -> Bool {
        totalItems == 0 || removedItems == 1 || removedItems == totalItems || removedItems.isMultiple(of: 100)
    }
}

public struct ImageStoreRemovalProgress: Equatable, Sendable {
    public var removedItems: Int
    public var totalItems: Int

    public var fraction: Double {
        guard totalItems > 0 else {
            return 1
        }
        return Double(min(max(removedItems, 0), totalItems)) / Double(totalItems)
    }

    public init(removedItems: Int, totalItems: Int) {
        self.totalItems = max(totalItems, 0)
        self.removedItems = min(max(removedItems, 0), self.totalItems)
    }
}

enum LocalImageFileValidator {
    static func fileSystemPath(from storedPath: String) -> String {
        guard let url = URL(string: storedPath), url.isFileURL else {
            return storedPath
        }

        return url.path
    }

    static func isUsableCachedImageFile(
        atPath path: String,
        fileManager: FileManager = .default
    ) -> Bool {
        let filePath = fileSystemPath(from: path)
        guard fileManager.fileExists(atPath: filePath) else {
            return false
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0
        else {
            return false
        }

        guard let handle = FileHandle(forReadingAtPath: filePath) else {
            return false
        }
        defer { try? handle.close() }

        let header = (try? handle.read(upToCount: 16)) ?? Data()
        return hasSupportedImageSignature(header)
    }

    static func hasSupportedImageSignature(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(16))

        if bytes.starts(with: [0xff, 0xd8, 0xff]) {
            return true
        }

        if bytes.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
            return true
        }

        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return true
        }

        if bytes.count >= 12,
           Array(bytes[0..<4]) == Array("RIFF".utf8),
           Array(bytes[8..<12]) == Array("WEBP".utf8)
        {
            return true
        }

        return false
    }
}

public struct ImageResolution: Equatable, Sendable {
    public var paths: LocalImagePair
    public var failedURLs: [URL]

    public init(paths: LocalImagePair, failedURLs: [URL] = []) {
        self.paths = paths
        self.failedURLs = failedURLs
    }
}

public enum CardImageQuality: String, CaseIterable, Hashable, Sendable {
    case small
    case normal
    case large
    case artCrop = "art_crop"
}

public protocol ImageResolving: Sendable {
    func localPaths(
        for remoteURLs: ImageURLPair,
        cardID: String,
        faceIndex: Int?
    ) -> LocalImagePair

    func resolve(
        _ remoteURLs: ImageURLPair,
        cardID: String,
        faceIndex: Int?,
        qualities: Set<CardImageQuality>
    ) async -> ImageResolution
}

public extension ImageResolving {
    func localPaths(for remoteURLs: ImageURLPair, cardID: String, faceIndex: Int?) -> LocalImagePair {
        LocalImagePair()
    }

    func resolve(_ remoteURLs: ImageURLPair, cardID: String, faceIndex: Int?) async -> ImageResolution {
        await resolve(remoteURLs, cardID: cardID, faceIndex: faceIndex, qualities: Set(CardImageQuality.allCases))
    }
}

public struct NoImageResolver: ImageResolving {
    public init() {}

    public func resolve(
        _ remoteURLs: ImageURLPair,
        cardID: String,
        faceIndex: Int?,
        qualities: Set<CardImageQuality>
    ) async -> ImageResolution {
        ImageResolution(paths: LocalImagePair())
    }
}

public struct DownloadingImageResolver: ImageResolving {
    private let store: ImageStore
    private let network: NetworkClient

    public init(store: ImageStore, network: NetworkClient) {
        self.store = store
        self.network = network
    }

    public func localPaths(for remoteURLs: ImageURLPair, cardID: String, faceIndex: Int?) -> LocalImagePair {
        LocalImagePair(
            smallPath: remoteURLs.small.map {
                store.localURL(for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.small.rawValue).path
            },
            normalPath: remoteURLs.normal.map {
                store.localURL(for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.normal.rawValue).path
            },
            largePath: remoteURLs.large.map {
                store.localURL(for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.large.rawValue).path
            },
            artCropPath: remoteURLs.artCrop.map {
                store.localURL(for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.artCrop.rawValue).path
            }
        )
    }

    public func resolve(
        _ remoteURLs: ImageURLPair,
        cardID: String,
        faceIndex: Int?,
        qualities: Set<CardImageQuality>
    ) async -> ImageResolution {
        var paths = LocalImagePair()
        var failures: [URL] = []

        for quality in CardImageQuality.allCases where qualities.contains(quality) {
            guard let remoteURL = remoteURL(for: quality, in: remoteURLs, requestedQualities: qualities) else {
                continue
            }

            let localURL = store.localURL(
                for: remoteURL,
                cardID: cardID,
                faceIndex: faceIndex,
                quality: quality.rawValue
            )

            if !(await downloadIfNeeded(remoteURL: remoteURL, localURL: localURL)) {
                failures.append(remoteURL)
                continue
            }

            switch quality {
            case .small:
                paths.smallPath = localURL.path
            case .normal:
                paths.normalPath = localURL.path
            case .large:
                paths.largePath = localURL.path
            case .artCrop:
                paths.artCropPath = localURL.path
            }
        }

        return ImageResolution(paths: paths, failedURLs: failures)
    }

    private func remoteURL(
        for quality: CardImageQuality,
        in remoteURLs: ImageURLPair,
        requestedQualities: Set<CardImageQuality>
    ) -> URL? {
        switch quality {
        case .small:
            remoteURLs.small
        case .normal:
            remoteURLs.normal
        case .large:
            remoteURLs.large
        case .artCrop:
            remoteURLs.artCrop
        }
    }

    private func downloadIfNeeded(remoteURL: URL, localURL: URL) async -> Bool {
        if LocalImageFileValidator.isUsableCachedImageFile(atPath: localURL.path) {
            return true
        }

        do {
            let data = try await network.data(from: remoteURL, purpose: .imageDownload)
            guard LocalImageFileValidator.hasSupportedImageSignature(data) else {
                return false
            }

            try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try data.write(to: localURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
