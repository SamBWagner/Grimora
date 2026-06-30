import Foundation
import GrimoraCore
import GrimoraDataPipeline
import Testing

/// Deterministic "golden ticket" test: runs the real `CatalogPipeline` over a small set of
/// checked-in fixture inputs and asserts the built catalog matches a checked-in golden snapshot.
///
/// This runs offline in CI every time — the inputs are fixed, so the output is fixed. If the
/// pipeline's output legitimately changes, regenerate the golden with:
///
///     GRIMORA_UPDATE_GOLDEN=1 swift test --package-path GrimoraKit --filter CatalogGoldenPipelineTests
///
/// For a *real* pull against live Scryfall/MTGJSON, see the env-gated tests in
/// `GrimoraDataEngineTests` (`GRIMORA_LIVE_TESTS` / `GRIMORA_LIVE_FULL_BUILD`).
struct CatalogGoldenPipelineTests {
  @Test
  func builtCatalogMatchesGoldenSnapshot() async throws {
    let workspace = try FixtureWorkspace()
    defer { workspace.cleanup() }

    let inputs = try workspace.makeBuildInputs()
    let databaseURL = workspace.directory.appendingPathComponent("catalog.sqlite")
    let result = try await CatalogPipeline().build(
      inputs: inputs,
      databaseURL: databaseURL,
      temporaryDirectory: workspace.directory.appendingPathComponent("Temporary", isDirectory: true)
    )

    // The validator is the same one the engine runs before publishing.
    let counts = try CardDatabase.validateCatalog(at: databaseURL)
    #expect(counts == result.counts)

    let snapshot = try CatalogSnapshot.capture(
      catalogURL: databaseURL,
      userDatabaseURL: workspace.directory.appendingPathComponent("user.sqlite"),
      counts: counts
    )

    if ProcessInfo.processInfo.environment["GRIMORA_UPDATE_GOLDEN"] != nil {
      try snapshot.writeToSourceFixtures()
      return
    }

    let golden = try CatalogSnapshot.loadGolden()
    #expect(
      snapshot == golden,
      "Built catalog diverged from the golden snapshot. If this change is intentional, regenerate with GRIMORA_UPDATE_GOLDEN=1."
    )
  }
}

// MARK: - Golden snapshot

/// A stable, human-readable projection of the built catalog used as the golden value.
struct CatalogSnapshot: Codable, Equatable {
  struct Face: Codable, Equatable {
    var name: String
    var typeLine: String
    var oracleText: String
  }

  struct Card: Codable, Equatable {
    var id: String
    var name: String
    var typeLine: String
    var oracleText: String
    var manaCost: String
    var manaValue: Double?
    var colors: [String]
    var colorIdentity: [String]
    var producedMana: [String]
    var power: String?
    var toughness: String?
    var layout: String
    var faces: [Face]
    /// Latest price from the imported value history, if any.
    var currentPrice: Double?
  }

  var cardCount: Int
  var priceSeriesCount: Int
  var cards: [Card]

  /// The card ids snapshotted in detail, in a fixed order. Covers a vanilla creature with a
  /// price, an instant, a colorless artifact, a modal DFC, and a multicolor legend.
  static let snapshottedIDs = [
    "golden-llanowar",
    "golden-counterspell",
    "golden-relic",
    "golden-dfc",
    "golden-legend",
  ]

  static func capture(
    catalogURL: URL,
    userDatabaseURL: URL,
    counts: CatalogCounts
  ) throws -> CatalogSnapshot {
    let database = try CardDatabase(userDatabaseURL: userDatabaseURL, catalogURL: catalogURL)
    let cards = try snapshottedIDs.map { id -> Card in
      guard let record = try database.card(id: id) else {
        throw FixtureError.missingCard(id)
      }
      let currentPrice = try database.valueGuide(forCardID: id).entries.first?.currentPrice
      return Card(
        id: record.id,
        name: record.name,
        typeLine: record.typeLine,
        oracleText: record.oracleText,
        manaCost: record.manaCost,
        manaValue: record.manaValue,
        colors: record.colors,
        colorIdentity: record.colorIdentity,
        producedMana: record.producedMana,
        power: record.power,
        toughness: record.toughness,
        layout: record.layout,
        faces: record.faces
          .sorted { $0.faceIndex < $1.faceIndex }
          .map { Face(name: $0.name, typeLine: $0.typeLine, oracleText: $0.oracleText) },
        currentPrice: currentPrice
      )
    }
    return CatalogSnapshot(
      cardCount: counts.cards,
      priceSeriesCount: counts.priceSeries,
      cards: cards
    )
  }

  static func loadGolden() throws -> CatalogSnapshot {
    guard let url = Bundle.module.url(
      forResource: "golden-catalog",
      withExtension: "json",
      subdirectory: "Fixtures"
    ) else {
      throw FixtureError.missingResource("golden-catalog.json")
    }
    return try JSONDecoder().decode(CatalogSnapshot.self, from: Data(contentsOf: url))
  }

  /// Writes this snapshot back to the checked-in source fixture (not the built bundle copy).
  func writeToSourceFixtures(file: StaticString = #filePath) throws {
    let sourceDirectory = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
    let destination = sourceDirectory
      .appendingPathComponent("Fixtures/golden-catalog.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(self).write(to: destination, options: .atomic)
  }
}

// MARK: - Fixture workspace

/// Materializes the checked-in fixtures into a temporary working directory: the Scryfall JSON is
/// copied as-is, and the MTGJSON JSON is gzip-compressed (the pipeline consumes `.json.gz`), mirroring
/// the real source layout.
struct FixtureWorkspace {
  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("CatalogGoldenPipelineTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: directory)
  }

  func makeBuildInputs() throws -> CatalogBuildInputs {
    let scryfallURL = try copyFixture("scryfall-default-cards", extension: "json")
    let identifiersGzip = try gzippedFixture("mtgjson-allprintings", to: "mtgjson-allprintings.json.gz")
    let pricesGzip = try gzippedFixture("mtgjson-allprices", to: "mtgjson-allprices.json.gz")
    return CatalogBuildInputs(
      scryfallJSONURL: scryfallURL,
      mtgjsonIdentifiersGzipURL: identifiersGzip,
      mtgjsonPricesGzipURL: pricesGzip,
      sources: CatalogSourceVersions(
        scryfallUpdatedAt: "2026-06-14T09:00:00.000+00:00",
        mtgjsonDate: "2026-06-14",
        mtgjsonVersion: "5.3.0"
      )
    )
  }

  private func fixtureURL(_ name: String, extension ext: String) throws -> URL {
    guard let url = Bundle.module.url(
      forResource: name,
      withExtension: ext,
      subdirectory: "Fixtures"
    ) else {
      throw FixtureError.missingResource("\(name).\(ext)")
    }
    return url
  }

  private func copyFixture(_ name: String, extension ext: String) throws -> URL {
    let destination = directory.appendingPathComponent("\(name).\(ext)")
    try FileManager.default.copyItem(at: try fixtureURL(name, extension: ext), to: destination)
    return destination
  }

  private func gzippedFixture(_ name: String, to fileName: String) throws -> URL {
    let plaintext = try copyFixture(name, extension: "json")
    let destination = directory.appendingPathComponent(fileName)
    try GzipArchive.compressFile(at: plaintext, to: destination)
    return destination
  }
}

enum FixtureError: Error, CustomStringConvertible {
  case missingResource(String)
  case missingCard(String)

  var description: String {
    switch self {
    case .missingResource(let name): "missing test fixture resource: \(name)"
    case .missingCard(let id): "built catalog is missing expected card: \(id)"
    }
  }
}
