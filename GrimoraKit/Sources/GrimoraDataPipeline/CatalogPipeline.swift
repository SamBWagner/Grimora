import Foundation
import GrimoraCore

public protocol CatalogEnrichmentStage: Sendable {
  var identifier: String { get }
  var version: Int { get }
  func enrich(database: CardDatabase) async throws
}

public struct CatalogBuildInputs: Sendable {
  public var scryfallJSONURL: URL
  public var mtgjsonIdentifiersGzipURL: URL
  public var mtgjsonPricesGzipURL: URL
  public var sources: CatalogSourceVersions

  public init(
    scryfallJSONURL: URL,
    mtgjsonIdentifiersGzipURL: URL,
    mtgjsonPricesGzipURL: URL,
    sources: CatalogSourceVersions
  ) {
    self.scryfallJSONURL = scryfallJSONURL
    self.mtgjsonIdentifiersGzipURL = mtgjsonIdentifiersGzipURL
    self.mtgjsonPricesGzipURL = mtgjsonPricesGzipURL
    self.sources = sources
  }
}

public struct CatalogPipelineProgress: Equatable, Sendable {
  public enum Stage: String, Equatable, Sendable {
    case preparing
    case ingestingScryfall
    case ingestingPrices
    case enriching
    case finalizing
    case validating
  }

  public var stage: Stage
  public var completed: Int
  public var total: Int?

  public init(stage: Stage, completed: Int = 0, total: Int? = nil) {
    self.stage = stage
    self.completed = completed
    self.total = total
  }
}

public struct CatalogPipelineResult: Equatable, Sendable {
  public var databaseURL: URL
  public var counts: CatalogCounts
  public var importedPricePoints: Int
  public var enrichments: [CatalogEnrichmentVersion]

  public init(
    databaseURL: URL,
    counts: CatalogCounts,
    importedPricePoints: Int,
    enrichments: [CatalogEnrichmentVersion]
  ) {
    self.databaseURL = databaseURL
    self.counts = counts
    self.importedPricePoints = importedPricePoints
    self.enrichments = enrichments
  }
}

public struct CatalogPipeline: Sendable {
  public static let currentVersion = 1

  private let enrichmentStages: [any CatalogEnrichmentStage]
  private let cardBatchSize: Int

  public init(
    enrichmentStages: [any CatalogEnrichmentStage] = [],
    cardBatchSize: Int = 500
  ) {
    self.enrichmentStages = enrichmentStages
    self.cardBatchSize = max(1, cardBatchSize)
  }

  public func build(
    inputs: CatalogBuildInputs,
    databaseURL: URL,
    temporaryDirectory: URL,
    progress: (@Sendable (CatalogPipelineProgress) async -> Void)? = nil
  ) async throws -> CatalogPipelineResult {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    for url in [
      databaseURL,
      URL(fileURLWithPath: databaseURL.path + "-wal"),
      URL(fileURLWithPath: databaseURL.path + "-shm"),
    ] where fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }

    await progress?(CatalogPipelineProgress(stage: .preparing))
    let database = try CardDatabase(storage: .file(databaseURL))
    try database.resetForStreamingCatalogBuild()

    let sourceSize = try? fileManager.attributesOfItem(
      atPath: inputs.scryfallJSONURL.path
    )[.size] as? NSNumber
    var batch: [CardRecord] = []
    batch.reserveCapacity(cardBatchSize)
    var cardCount = 0
    try await ScryfallJSONArrayScanner.scan(
      url: inputs.scryfallJSONURL,
      progress: { scannedBytes in
        await progress?(
          CatalogPipelineProgress(
            stage: .ingestingScryfall,
            completed: Int(clamping: scannedBytes),
            total: sourceSize.map { Int(clamping: $0.int64Value) }
          )
        )
      }
    ) { objectData in
      batch.append(try ScryfallCatalogDecoder.decodeRecord(from: objectData))
      if batch.count >= cardBatchSize {
        try database.appendCatalogCards(batch)
        cardCount += batch.count
        batch.removeAll(keepingCapacity: true)
      }
    }
    if !batch.isEmpty {
      try database.appendCatalogCards(batch)
      cardCount += batch.count
    }

    await progress?(CatalogPipelineProgress(stage: .ingestingPrices))
    let priceSummary = try await MTGJSONPriceHistoryImporter(database: database)
      .importCompactHistory(
        meta: MTGJSONPriceHistoryMeta(
          date: inputs.sources.mtgjsonDate,
          version: inputs.sources.mtgjsonVersion
        ),
        allPrintingsGzipURL: inputs.mtgjsonIdentifiersGzipURL,
        allPricesGzipURL: inputs.mtgjsonPricesGzipURL,
        temporaryDirectory: temporaryDirectory,
        progress: { importProgress in
          switch importProgress {
          case let .buildingPriceIDMapProgress(scannedBytes, totalBytes, _),
            let .importingPriceHistoryProgress(scannedBytes, totalBytes, _):
            await progress?(
              CatalogPipelineProgress(
                stage: .ingestingPrices,
                completed: Int(clamping: scannedBytes),
                total: totalBytes.map { Int(clamping: $0) }
              )
            )
          default:
            break
          }
        }
      )

    for (index, stage) in enrichmentStages.enumerated() {
      await progress?(
        CatalogPipelineProgress(
          stage: .enriching,
          completed: index,
          total: enrichmentStages.count
        )
      )
      try await stage.enrich(database: database)
    }

    await progress?(CatalogPipelineProgress(stage: .finalizing, completed: cardCount))
    try database.finalizeStreamingCatalogBuild(sources: inputs.sources)
    try database.prepareForCatalogDistribution()
    await progress?(CatalogPipelineProgress(stage: .validating))
    let counts = try CardDatabase.validateCatalog(at: databaseURL)
    return CatalogPipelineResult(
      databaseURL: databaseURL,
      counts: counts,
      importedPricePoints: priceSummary.importedPricePoints,
      enrichments: enrichmentStages.map {
        CatalogEnrichmentVersion(identifier: $0.identifier, version: $0.version)
      }
    )
  }
}
