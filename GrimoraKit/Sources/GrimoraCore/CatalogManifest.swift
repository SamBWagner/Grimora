import Foundation

public struct CatalogSourceVersions: Codable, Equatable, Sendable {
  public var scryfallUpdatedAt: String
  public var mtgjsonDate: String
  public var mtgjsonVersion: String

  public init(
    scryfallUpdatedAt: String,
    mtgjsonDate: String,
    mtgjsonVersion: String
  ) {
    self.scryfallUpdatedAt = scryfallUpdatedAt
    self.mtgjsonDate = mtgjsonDate
    self.mtgjsonVersion = mtgjsonVersion
  }
}

public struct CatalogArtifact: Codable, Equatable, Sendable {
  public var downloadURL: URL
  public var compressedBytes: Int64
  public var uncompressedBytes: Int64
  public var sha256: String
  public var uncompressedSHA256: String

  public init(
    downloadURL: URL,
    compressedBytes: Int64,
    uncompressedBytes: Int64,
    sha256: String,
    uncompressedSHA256: String
  ) {
    self.downloadURL = downloadURL
    self.compressedBytes = compressedBytes
    self.uncompressedBytes = uncompressedBytes
    self.sha256 = sha256
    self.uncompressedSHA256 = uncompressedSHA256
  }
}

public struct CatalogCounts: Codable, Equatable, Sendable {
  public var cards: Int
  public var priceSeries: Int

  public init(cards: Int, priceSeries: Int) {
    self.cards = cards
    self.priceSeries = priceSeries
  }
}

public struct CatalogEnrichmentVersion: Codable, Equatable, Sendable {
  public var identifier: String
  public var version: Int

  public init(identifier: String, version: Int) {
    self.identifier = identifier
    self.version = version
  }
}

public struct CatalogManifest: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var version: String
  public var generatedAt: Date
  public var catalogSchemaVersion: Int
  public var sources: CatalogSourceVersions
  public var enrichments: [CatalogEnrichmentVersion]
  public var artifact: CatalogArtifact
  public var counts: CatalogCounts

  public init(
    version: String,
    generatedAt: Date,
    catalogSchemaVersion: Int = CatalogManifest.currentSchemaVersion,
    sources: CatalogSourceVersions,
    enrichments: [CatalogEnrichmentVersion] = [],
    artifact: CatalogArtifact,
    counts: CatalogCounts
  ) {
    self.version = version
    self.generatedAt = generatedAt
    self.catalogSchemaVersion = catalogSchemaVersion
    self.sources = sources
    self.enrichments = enrichments
    self.artifact = artifact
    self.counts = counts
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  public static func encoder(prettyPrinted: Bool = false) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    return encoder
  }

  public var bulkDataManifest: BulkDataManifest {
    BulkDataManifest(
      id: version,
      type: BulkDataManifest.grimoraCatalogType,
      updatedAt: version,
      name: "Grimora Catalog",
      size: Int(clamping: artifact.compressedBytes),
      downloadURI: artifact.downloadURL,
      catalog: self
    )
  }
}
