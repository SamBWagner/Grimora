import Foundation

public struct CatalogSourceVersions: Codable, Equatable, Sendable {
  public var scryfallUpdatedAt: String
  public var mtgjsonDate: String
  public var mtgjsonVersion: String
  /// The source identity embedded in semantic rows as `scryfall-oracle-tags@<updatedAt>`.
  public var oracleTagsUpdatedAt: String?
  /// Remote-source provenance for the build. Semantic rows keep the compact timestamp identity;
  /// the manifest is the authority for the exact downloaded URI.
  public var oracleTagsDownloadURI: URL?

  public init(
    scryfallUpdatedAt: String,
    mtgjsonDate: String,
    mtgjsonVersion: String,
    oracleTagsUpdatedAt: String? = nil,
    oracleTagsDownloadURI: URL? = nil
  ) {
    self.scryfallUpdatedAt = scryfallUpdatedAt
    self.mtgjsonDate = mtgjsonDate
    self.mtgjsonVersion = mtgjsonVersion
    self.oracleTagsUpdatedAt = oracleTagsUpdatedAt
    self.oracleTagsDownloadURI = oracleTagsDownloadURI
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

public struct CatalogSemanticCounts: Codable, Equatable, Sendable {
  public var tags: Int
  public var aliases: Int
  public var edges: Int
  public var cardTags: Int
  public var tagStats: Int

  public init(tags: Int, aliases: Int, edges: Int, cardTags: Int, tagStats: Int) {
    self.tags = tags
    self.aliases = aliases
    self.edges = edges
    self.cardTags = cardTags
    self.tagStats = tagStats
  }
}

public struct CatalogCounts: Codable, Equatable, Sendable {
  public var cards: Int
  public var priceSeries: Int
  public var semantic: CatalogSemanticCounts?

  public init(
    cards: Int,
    priceSeries: Int,
    semantic: CatalogSemanticCounts? = nil
  ) {
    self.cards = cards
    self.priceSeries = priceSeries
    self.semantic = semantic
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
  /// Logical content digests for this build, added for incremental updates. Optional so the field
  /// is additive: older clients ignore it, and a manifest produced before this feature decodes with
  /// `nil` (which simply means no incremental path is advertised — clients full-download as before).
  public var contentDigests: CatalogContentDigests?

  public init(
    version: String,
    generatedAt: Date,
    catalogSchemaVersion: Int = CatalogManifest.currentSchemaVersion,
    sources: CatalogSourceVersions,
    enrichments: [CatalogEnrichmentVersion] = [],
    artifact: CatalogArtifact,
    counts: CatalogCounts,
    contentDigests: CatalogContentDigests? = nil
  ) {
    self.version = version
    self.generatedAt = generatedAt
    self.catalogSchemaVersion = catalogSchemaVersion
    self.sources = sources
    self.enrichments = enrichments
    self.artifact = artifact
    self.counts = counts
    self.contentDigests = contentDigests
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
