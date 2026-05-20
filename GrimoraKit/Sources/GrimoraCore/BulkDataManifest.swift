import Foundation

public struct BulkDataManifest: Decodable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var updatedAt: String
    public var name: String
    public var size: Int
    public var downloadURI: URL

    public init(id: String, type: String, updatedAt: String, name: String, size: Int, downloadURI: URL) {
        self.id = id
        self.type = type
        self.updatedAt = updatedAt
        self.name = name
        self.size = size
        self.downloadURI = downloadURI
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case updatedAt = "updated_at"
        case name
        case size
        case downloadURI = "download_uri"
    }
}

private struct BulkDataListResponse: Decodable {
    var data: [BulkDataManifest]
}

public final class BulkDataClient: Sendable {
    public static let bulkDataURL = URL(string: "https://api.scryfall.com/bulk-data")!

    private let network: NetworkClient
    private let decoder: JSONDecoder

    public init(network: NetworkClient, decoder: JSONDecoder = JSONDecoder()) {
        self.network = network
        self.decoder = decoder
    }

    public func fetchDefaultCardsManifest() async throws -> BulkDataManifest {
        let data = try await network.data(from: Self.bulkDataURL, purpose: .manifestCheck)
        let response = try decoder.decode(BulkDataListResponse.self, from: data)
        guard let manifest = response.data.first(where: { $0.type == "default_cards" }) else {
            throw BulkDataClientError.defaultCardsMissing
        }
        return manifest
    }

    public func downloadDefaultCards(
        manifest: BulkDataManifest,
        to destination: URL,
        progress: (@Sendable (NetworkDownloadProgress) async -> Void)? = nil
    ) async throws {
        try await network.download(
            from: manifest.downloadURI,
            to: destination,
            purpose: .bulkDownload,
            progress: progress
        )
    }
}

public enum BulkDataClientError: Error, Equatable, Sendable {
    case defaultCardsMissing
}
