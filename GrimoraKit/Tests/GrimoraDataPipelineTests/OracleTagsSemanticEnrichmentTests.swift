import Foundation
import GrimoraCore
import Testing
@testable import GrimoraDataPipeline

struct OracleTagsSemanticEnrichmentTests {
  @Test
  func semanticEnrichmentBumpsThePipelineIdentity() {
    #expect(CatalogPipeline.currentVersion == 2)
    #expect(ScryfallOracleTagsSemanticEnrichmentStage.version == 2)
  }

  @Test
  func defaultPipelineMaterializesDeterministicOracleFirstSemanticSnapshot() async throws {
    let workspace = try FixtureWorkspace()
    defer { workspace.cleanup() }
    let databaseURL = workspace.directory.appendingPathComponent("semantic-catalog.sqlite")

    let result = try await CatalogPipeline().build(
      inputs: workspace.makeBuildInputs(),
      databaseURL: databaseURL,
      temporaryDirectory: workspace.directory.appendingPathComponent("Temporary", isDirectory: true)
    )

    #expect(result.enrichments == [
      CatalogEnrichmentVersion(identifier: "scryfall-oracle-tags", version: 2),
    ])

    let database = try CardDatabase(
      userDatabaseURL: workspace.directory.appendingPathComponent("semantic-user.sqlite"),
      catalogURL: databaseURL
    )
    let snapshot = try database.semanticCatalogSnapshot()
    let source = "scryfall-oracle-tags@2026-06-14T21:00:00.000+00:00"

    #expect(snapshot.tags.count == 6)
    #expect(snapshot.aliases == [
      SemanticTagAliasRecord(
        tagID: "tag-cycle-golden",
        alias: "Golden Set Cycle",
        aliasKey: "golden set cycle"
      ),
      SemanticTagAliasRecord(
        tagID: "tag-draw-engine",
        alias: "Card Draw Engine",
        aliasKey: "card draw engine"
      ),
    ])
    #expect(snapshot.edges == [
      SemanticTagEdgeRecord(parentTagID: "tag-card-advantage", childTagID: "tag-draw-engine"),
      SemanticTagEdgeRecord(parentTagID: "tag-card-names", childTagID: "tag-alliteration"),
      SemanticTagEdgeRecord(parentTagID: "tag-cycle", childTagID: "tag-cycle-golden"),
    ])
    #expect(snapshot.cardTags == [
      SemanticCardTagRecord(
        cardKey: SemanticCardKey(rawValue: "o:oracle-golden-counterspell"),
        tagID: "tag-alliteration",
        weightMillis: 500,
        annotation: "name trivia",
        source: source
      ),
      SemanticCardTagRecord(
        cardKey: SemanticCardKey(rawValue: "o:oracle-golden-counterspell"),
        tagID: "tag-cycle-golden",
        weightMillis: 1_500,
        annotation: nil,
        source: source
      ),
      SemanticCardTagRecord(
        cardKey: SemanticCardKey(rawValue: "o:oracle-golden-llanowar"),
        tagID: "tag-draw-engine",
        weightMillis: 1_000,
        annotation: "fixture draw",
        source: source
      ),
      SemanticCardTagRecord(
        cardKey: SemanticCardKey(rawValue: "o:oracle-golden-relic"),
        tagID: "tag-draw-engine",
        weightMillis: 2_000,
        annotation: nil,
        source: source
      ),
    ])
    #expect(!snapshot.cardTags.contains {
      $0.cardKey.rawValue == "o:oracle-not-in-catalog"
    })
    #expect(snapshot.stats == [
      SemanticTagStatsRecord(
        tagID: "tag-alliteration",
        directCardCount: 1,
        effectiveCardCount: 1,
        inverseFrequencyMillis: 0
      ),
      SemanticTagStatsRecord(
        tagID: "tag-card-advantage",
        directCardCount: 0,
        effectiveCardCount: 2,
        inverseFrequencyMillis: 1_288
      ),
      SemanticTagStatsRecord(
        tagID: "tag-card-names",
        directCardCount: 0,
        effectiveCardCount: 1,
        inverseFrequencyMillis: 0
      ),
      SemanticTagStatsRecord(
        tagID: "tag-cycle",
        directCardCount: 0,
        effectiveCardCount: 1,
        inverseFrequencyMillis: 0
      ),
      SemanticTagStatsRecord(
        tagID: "tag-cycle-golden",
        directCardCount: 1,
        effectiveCardCount: 1,
        inverseFrequencyMillis: 0
      ),
      SemanticTagStatsRecord(
        tagID: "tag-draw-engine",
        directCardCount: 2,
        effectiveCardCount: 2,
        inverseFrequencyMillis: 1_288
      ),
    ])

    let tagsBySlug = Dictionary(uniqueKeysWithValues: snapshot.tags.map { ($0.slug, $0) })
    #expect(tagsBySlug["draw-engine"]?.namespace == "oracle")
    #expect(tagsBySlug["draw-engine"]?.source == source)
    #expect(tagsBySlug["draw-engine"]?.similarityEnabled == true)
    #expect(tagsBySlug["alliteration"]?.similarityEnabled == false)
    #expect(tagsBySlug["card-names"]?.similarityEnabled == false)
    #expect(tagsBySlug["cycle"]?.similarityEnabled == false)
    #expect(tagsBySlug["cycle-golden"]?.similarityEnabled == false)
  }

  @Test
  func normalizedDuplicateAliasesProduceTheSameSnapshotRegardlessOfSourceOrder() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OracleTagsAliasOrder-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let forwardURL = directory.appendingPathComponent("forward.jsonl")
    let reversedURL = directory.appendingPathComponent("reversed.jsonl")
    try oracleTagLine(aliases: ["Draw Engine", "draw engine"]).write(
      to: forwardURL,
      atomically: true,
      encoding: .utf8
    )
    try oracleTagLine(aliases: ["draw engine", "Draw Engine"]).write(
      to: reversedURL,
      atomically: true,
      encoding: .utf8
    )

    let forward = try await enrichedSnapshot(from: forwardURL)
    let reversed = try await enrichedSnapshot(from: reversedURL)

    #expect(forward == reversed)
    #expect(forward.aliases == [
      SemanticTagAliasRecord(
        tagID: "tag-draw-engine",
        alias: "Draw Engine",
        aliasKey: "draw engine"
      ),
    ])
  }

  @Test
  func enrichedCatalogValidationRequiresTheCompleteSemanticSchema() async throws {
    let workspace = try FixtureWorkspace()
    defer { workspace.cleanup() }
    let databaseURL = workspace.directory.appendingPathComponent("incomplete-semantic.sqlite")
    let result = try await CatalogPipeline().build(
      inputs: workspace.makeBuildInputs(),
      databaseURL: databaseURL,
      temporaryDirectory: workspace.directory.appendingPathComponent("Temporary", isDirectory: true)
    )
    let raw = try SQLiteDatabase(storage: .file(databaseURL))
    try raw.execute("DROP TABLE semantic_tag_stats")
    try raw.execute("CREATE VIEW semantic_tag_stats AS SELECT 1 AS bogus")

    #expect(throws: (any Error).self) {
      _ = try CardDatabase.validateCatalog(at: databaseURL)
    }
    #expect(result.enrichments.contains {
      $0.identifier == ScryfallOracleTagsSemanticEnrichmentStage.identifier
    })
  }

  @Test
  func enrichedCatalogValidationRequiresSemanticTableColumns() async throws {
    let workspace = try FixtureWorkspace()
    defer { workspace.cleanup() }
    let databaseURL = workspace.directory.appendingPathComponent("malformed-semantic.sqlite")
    _ = try await CatalogPipeline().build(
      inputs: workspace.makeBuildInputs(),
      databaseURL: databaseURL,
      temporaryDirectory: workspace.directory.appendingPathComponent("Temporary", isDirectory: true)
    )
    let raw = try SQLiteDatabase(storage: .file(databaseURL))
    try raw.execute("DROP TABLE semantic_tag_stats")
    try raw.execute("CREATE TABLE semantic_tag_stats (tag_id TEXT PRIMARY KEY)")

    #expect(throws: (any Error).self) {
      _ = try CardDatabase.validateCatalog(at: databaseURL)
    }
  }

  @Test
  func enrichedCatalogValidationDetectsCaseVariantSemanticObjects() async throws {
    let workspace = try FixtureWorkspace()
    defer { workspace.cleanup() }
    let databaseURL = workspace.directory.appendingPathComponent("case-variant-semantic.sqlite")
    _ = try await CatalogPipeline().build(
      inputs: workspace.makeBuildInputs(),
      databaseURL: databaseURL,
      temporaryDirectory: workspace.directory.appendingPathComponent("Temporary", isDirectory: true)
    )
    let raw = try SQLiteDatabase(storage: .file(databaseURL))
    for table in [
      "semantic_tags",
      "semantic_tag_aliases",
      "semantic_tag_edges",
      "semantic_card_tags",
      "semantic_tag_stats",
    ] {
      try raw.execute("DROP TABLE \(table)")
    }
    try raw.execute("CREATE VIEW SEMANTIC_TAGS AS SELECT 1 AS bogus")

    #expect(throws: (any Error).self) {
      _ = try CardDatabase.validateCatalog(at: databaseURL)
    }
  }

  @Test
  func enrichedCatalogValidationAcceptsCaseVariantSemanticColumnNames() async throws {
    let workspace = try FixtureWorkspace()
    defer { workspace.cleanup() }
    let databaseURL = workspace.directory.appendingPathComponent("case-variant-column.sqlite")
    let result = try await CatalogPipeline().build(
      inputs: workspace.makeBuildInputs(),
      databaseURL: databaseURL,
      temporaryDirectory: workspace.directory.appendingPathComponent("Temporary", isDirectory: true)
    )
    let raw = try SQLiteDatabase(storage: .file(databaseURL))
    try raw.execute("ALTER TABLE semantic_tags RENAME COLUMN description TO description_temporary")
    try raw.execute("ALTER TABLE semantic_tags RENAME COLUMN description_temporary TO DESCRIPTION")

    #expect(try CardDatabase.validateCatalog(at: databaseURL) == result.counts)
  }

  @Test
  func emptyOracleTagsSourceDoesNotReplaceAnExistingSemanticSnapshot() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OracleTagsEmpty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("empty.jsonl")
    try Data().write(to: sourceURL)

    let database = try CardDatabase(storage: .inMemory)
    let original = existingSemanticSnapshot()
    try database.replaceSemanticCatalog(with: original)
    let stage = ScryfallOracleTagsSemanticEnrichmentStage(
      oracleTagsJSONLURL: sourceURL,
      sourceUpdatedAt: "2026-06-14T21:00:00.000+00:00"
    )

    await #expect(throws: ScryfallOracleTagsSemanticEnrichmentError.emptySource) {
      try await stage.enrich(database: database)
    }
    #expect(try database.semanticCatalogSnapshot() == original)
  }

  @Test(arguments: [
    "[{\"object\":\"tag\",\"id\":\"tag-new\",\"label\":\"new\",\"slug\":\"new\",\"type\":\"oracle\",\"uri\":\"https://tagger.scryfall.com/tags/card/new\",\"description\":null,\"parent_ids\":[],\"child_ids\":[],\"aliases\":[],\"taggings\":[]}",
    "{\"object\":\"tag\",\"id\":\"tag-new\",\"label\":\"new\",\"slug\":\"new\",\"type\":\"oracle\",\"uri\":\"https://tagger.scryfall.com/tags/card/new\",\"description\":null,\"parent_ids\":[],\"child_ids\":[],\"aliases\":[],\"taggings\":[]}\ngarbage",
    "{\"object\":\"tag\",\"id\":\"tag-new\",\"label\":\"new\",\"slug\":\"new\",\"type\":\"oracle\",\"uri\":\"https://tagger.scryfall.com/tags/card/new\",\"description\":null,\"parent_ids\":[],\"child_ids\":[],\"aliases\":[],\"taggings\":[]} {\"object\":\"tag\",\"id\":\"tag-second\",\"label\":\"second\",\"slug\":\"second\",\"type\":\"oracle\",\"uri\":\"https://tagger.scryfall.com/tags/card/second\",\"description\":null,\"parent_ids\":[],\"child_ids\":[],\"aliases\":[],\"taggings\":[]}",
    "{\"object\":\"tag\",\n\"id\":\"tag-new\",\"label\":\"new\",\"slug\":\"new\",\"type\":\"oracle\",\"uri\":\"https://tagger.scryfall.com/tags/card/new\",\"description\":null,\"parent_ids\":[],\"child_ids\":[],\"aliases\":[],\"taggings\":[]}",
  ])
  func malformedNonEmptyOracleTagsSourceDoesNotReplaceAnExistingSemanticSnapshot(
    source: String
  ) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OracleTagsMalformed-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("malformed.jsonl")
    try source.write(to: sourceURL, atomically: true, encoding: .utf8)

    let database = try CardDatabase(storage: .inMemory)
    let original = existingSemanticSnapshot()
    try database.replaceSemanticCatalog(with: original)
    let stage = ScryfallOracleTagsSemanticEnrichmentStage(
      oracleTagsJSONLURL: sourceURL,
      sourceUpdatedAt: "2026-06-14T21:00:00.000+00:00"
    )

    await #expect(throws: (any Error).self) {
      try await stage.enrich(database: database)
    }
    #expect(try database.semanticCatalogSnapshot() == original)
  }

  private func enrichedSnapshot(from sourceURL: URL) async throws -> SemanticCatalogSnapshot {
    let database = try CardDatabase(storage: .inMemory)
    let stage = ScryfallOracleTagsSemanticEnrichmentStage(
      oracleTagsJSONLURL: sourceURL,
      sourceUpdatedAt: "2026-06-14T21:00:00.000+00:00"
    )
    try await stage.enrich(database: database)
    return try database.semanticCatalogSnapshot()
  }

  private func oracleTagLine(aliases: [String]) -> String {
    let aliasesJSON = aliases.map { "\"\($0)\"" }.joined(separator: ",")
    return """
    {"object":"tag","id":"tag-draw-engine","label":"draw engine","slug":"draw-engine","type":"oracle","uri":"https://tagger.scryfall.com/tags/card/draw-engine","description":"Repeatable card draw.","parent_ids":[],"child_ids":[],"aliases":[\(aliasesJSON)],"taggings":[]}
    """
  }

  private func existingSemanticSnapshot() -> SemanticCatalogSnapshot {
    SemanticCatalogSnapshot(
      tags: [
        SemanticTagRecord(
          id: "existing-tag",
          namespace: "oracle",
          slug: "existing-tag",
          label: "Existing Tag",
          description: nil,
          similarityEnabled: true,
          source: "existing-source"
        ),
      ],
      aliases: [],
      edges: [],
      cardTags: [],
      stats: [
        SemanticTagStatsRecord(
          tagID: "existing-tag",
          directCardCount: 0,
          effectiveCardCount: 0,
          inverseFrequencyMillis: 1_000
        ),
      ]
    )
  }
}
