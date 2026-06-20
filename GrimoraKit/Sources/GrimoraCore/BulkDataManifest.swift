import Foundation

public struct BulkDataManifest: Decodable, Equatable, Sendable {
    public static let grimoraCatalogType = "grimora_catalog"

    public var id: String
    public var type: String
    public var updatedAt: String
    public var name: String
    public var size: Int
    public var downloadURI: URL
    public var catalog: CatalogManifest?

    public init(
        id: String,
        type: String,
        updatedAt: String,
        name: String,
        size: Int,
        downloadURI: URL,
        catalog: CatalogManifest? = nil
    ) {
        self.id = id
        self.type = type
        self.updatedAt = updatedAt
        self.name = name
        self.size = size
        self.downloadURI = downloadURI
        self.catalog = catalog
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case updatedAt = "updated_at"
        case name
        case size
        case downloadURI = "download_uri"
        case catalog
    }
}

private struct BulkDataListResponse: Decodable {
    var data: [BulkDataManifest]
}

public final class BulkDataClient: Sendable {
    public static let bulkDataURL = URL(string: "https://api.scryfall.com/bulk-data")!

    private let network: NetworkClient
    private let decoder: JSONDecoder
    private let catalogAPIURL: URL?

    public init(
        network: NetworkClient,
        decoder: JSONDecoder = JSONDecoder(),
        catalogAPIURL: URL? = nil
    ) {
        self.network = network
        self.decoder = decoder
        self.catalogAPIURL = catalogAPIURL
    }

    public func fetchDefaultCardsManifest() async throws -> BulkDataManifest {
        if let catalogAPIURL {
            let data = try await network.data(from: catalogAPIURL, purpose: .manifestCheck)
            return try CatalogManifest.decoder()
                .decode(CatalogManifest.self, from: data)
                .bulkDataManifest
        }
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
        purpose: NetworkPurpose = .bulkDownload,
        progress: (@Sendable (NetworkDownloadProgress) async -> Void)? = nil
    ) async throws {
        try await network.download(
            from: manifest.downloadURI,
            to: destination,
            purpose: purpose,
            progress: progress
        )
    }
}

public enum BulkDataClientError: Error, Equatable, Sendable {
    case defaultCardsMissing
}
