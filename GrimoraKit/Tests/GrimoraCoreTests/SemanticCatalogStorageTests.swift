@testable import GrimoraCore
import Foundation
import Testing

struct SemanticCatalogStorageTests {
  @Test
  func replacementPersistsAllSemanticRecordsAndSupportsBothTraversalDirections() throws {
    let database = try CardDatabase(storage: .inMemory)
    let snapshot = semanticSnapshot()

    try database.replaceSemanticCatalog(with: snapshot)

    #expect(try database.semanticCatalogSnapshot() == snapshot)
    #expect(
      try database.semanticTagIDs(for: SemanticCardKey(oracleID: "oracle-card", printingID: "print-a"))
        == ["tag-card-draw"]
    )
    #expect(
      try database.semanticCardKeys(tagID: "tag-card-draw")
        == [SemanticCardKey(oracleID: "oracle-card", printingID: "print-b")]
    )
    #expect(try semanticIndexNames(database: database).isSuperset(of: [
      "idx_semantic_card_tags_card_tag",
      "idx_semantic_card_tags_tag_card",
      "idx_semantic_tag_aliases_key",
      "idx_semantic_tag_edges_child_parent",
    ]))
  }

  @Test
  func malformedReplacementRollsBackToThePreviousSemanticCatalog() throws {
    let database = try CardDatabase(storage: .inMemory)
    let original = semanticSnapshot()
    try database.replaceSemanticCatalog(with: original)

    var malformed = original
    malformed.edges.append(
      SemanticTagEdgeRecord(parentTagID: "missing-parent", childTagID: "tag-card-draw")
    )

    #expect(throws: (any Error).self) {
      try database.replaceSemanticCatalog(with: malformed)
    }
    #expect(try database.semanticCatalogSnapshot() == original)
  }

  @Test
  func invalidSemanticRecordsAreRejectedWithoutReplacingThePreviousCatalog() throws {
    let original = semanticSnapshot()

    var blankTag = original
    blankTag.tags[0].id = " "

    var emptyCardIdentity = original
    emptyCardIdentity.cardTags[0].cardKey = SemanticCardKey(rawValue: "o:")

    var mismatchedAliasKey = original
    mismatchedAliasKey.aliases[0].aliasKey = "not-the-normalized-alias"

    var duplicateMembership = original
    duplicateMembership.cardTags.append(original.cardTags[0])

    var invalidStats = original
    invalidStats.stats[0].effectiveCardCount = -1

    for invalid in [
      blankTag,
      emptyCardIdentity,
      mismatchedAliasKey,
      duplicateMembership,
      invalidStats,
    ] {
      try expectRejectedSemanticReplacement(invalid, preserving: original)
    }
  }

  @Test
  func cyclicHierarchyIsRejectedWithoutReplacingThePreviousCatalog() throws {
    let original = semanticSnapshot()
    var cyclic = original
    cyclic.edges.append(
      SemanticTagEdgeRecord(
        parentTagID: "tag-card-draw",
        childTagID: "tag-card-advantage"
      )
    )

    try expectRejectedSemanticReplacement(cyclic, preserving: original)
  }

  @Test
  func cardToTagTraversalDeduplicatesMembershipsFromMultipleSources() throws {
    let database = try CardDatabase(storage: .inMemory)
    var snapshot = semanticSnapshot()
    var secondSource = snapshot.cardTags[0]
    secondSource.source = "curated-overrides"
    snapshot.cardTags.append(secondSource)

    try database.replaceSemanticCatalog(with: snapshot)

    #expect(
      try database.semanticTagIDs(for: snapshot.cardTags[0].cardKey)
        == ["tag-card-draw"]
    )
  }

  @Test
  func semanticReadsSupportCaseVariantTableNames() throws {
    let database = try CardDatabase(storage: .inMemory)
    let snapshot = semanticSnapshot()
    try database.replaceSemanticCatalog(with: snapshot)
    try renameSemanticTablesToUppercase(database.database)

    #expect(try database.semanticCatalogSnapshot() == snapshot)
    #expect(
      try database.semanticTagIDs(for: snapshot.cardTags[0].cardKey)
        == ["tag-card-draw"]
    )
    #expect(
      try database.semanticCardKeys(tagID: "tag-card-draw")
        == [snapshot.cardTags[0].cardKey]
    )
  }

  @Test
  func attachedCatalogReadsSemanticTablesInsteadOfEmptyMainShadowCopies() throws {
    let directory = semanticTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let catalogURL = directory.appendingPathComponent("Catalog.sqlite")
    let snapshot = semanticSnapshot()

    var catalog: CardDatabase? = try CardDatabase(storage: .file(catalogURL))
    try catalog?.replaceAllCards([Fixtures.records()[0]])
    try catalog?.replaceSemanticCatalog(with: snapshot)
    try catalog?.prepareForCatalogDistribution()
    catalog = nil

    let attached = try CardDatabase(
      userDatabaseURL: directory.appendingPathComponent("User.sqlite"),
      catalogURL: catalogURL
    )

    #expect(try attached.semanticCatalogSnapshot() == snapshot)
  }

  @Test
  func legacyCatalogWithoutSemanticTablesOpensWithAnEmptySemanticSnapshot() throws {
    let directory = semanticTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let catalogURL = directory.appendingPathComponent("LegacyCatalog.sqlite")

    var catalog: CardDatabase? = try CardDatabase(storage: .file(catalogURL))
    try catalog?.replaceAllCards([Fixtures.records()[0]])
    try catalog?.prepareForCatalogDistribution()
    catalog = nil

    var rawCatalog: SQLiteDatabase? = try SQLiteDatabase(storage: .file(catalogURL))
    try rawCatalog?.execute(
      """
      DROP TABLE semantic_tag_stats;
      DROP TABLE semantic_card_tags;
      DROP TABLE semantic_tag_edges;
      DROP TABLE semantic_tag_aliases;
      DROP TABLE semantic_tags;
      """
    )
    rawCatalog = nil

    let attached = try CardDatabase(
      userDatabaseURL: directory.appendingPathComponent("User.sqlite"),
      catalogURL: catalogURL
    )

    #expect(try attached.cardCount() == 1)
    #expect(try attached.semanticCatalogSnapshot() == .empty)
    #expect(
      try attached.semanticTagIDs(for: SemanticCardKey(oracleID: "legacy", printingID: "legacy"))
        == []
    )
    #expect(try attached.semanticCardKeys(tagID: "missing") == [])
  }
}

private func semanticSnapshot() -> SemanticCatalogSnapshot {
  SemanticCatalogSnapshot(
    tags: [
      SemanticTagRecord(
        id: "tag-card-advantage",
        namespace: "oracle",
        slug: "card-advantage",
        label: "Card Advantage",
        description: nil,
        similarityEnabled: true,
        source: "scryfall-oracle-tags"
      ),
      SemanticTagRecord(
        id: "tag-card-draw",
        namespace: "oracle",
        slug: "card-draw",
        label: "Card Draw",
        description: "Moves cards from a library into a hand.",
        similarityEnabled: true,
        source: "scryfall-oracle-tags"
      ),
    ],
    aliases: [
      SemanticTagAliasRecord(
        tagID: "tag-card-draw",
        alias: "Draw cards",
        aliasKey: SemanticTagAliasRecord.normalizedKey(for: "Draw cards")
      ),
    ],
    edges: [
      SemanticTagEdgeRecord(parentTagID: "tag-card-advantage", childTagID: "tag-card-draw"),
    ],
    cardTags: [
      SemanticCardTagRecord(
        cardKey: SemanticCardKey(oracleID: "oracle-card", printingID: "print-a"),
        tagID: "tag-card-draw",
        weightMillis: 1_500,
        annotation: "repeatable",
        source: "scryfall-oracle-tags"
      ),
    ],
    stats: [
      SemanticTagStatsRecord(
        tagID: "tag-card-advantage",
        directCardCount: 0,
        effectiveCardCount: 1,
        inverseFrequencyMillis: 700
      ),
      SemanticTagStatsRecord(
        tagID: "tag-card-draw",
        directCardCount: 1,
        effectiveCardCount: 1,
        inverseFrequencyMillis: 900
      ),
    ]
  )
}

private func semanticIndexNames(database: CardDatabase) throws -> Set<String> {
  let statement = try database.database.prepare(
    "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_semantic_%'"
  )
  var result: Set<String> = []
  while try statement.step() {
    if let name = statement.string(at: 0) {
      result.insert(name)
    }
  }
  return result
}

private func renameSemanticTablesToUppercase(_ database: SQLiteDatabase) throws {
  for table in [
    "semantic_tags",
    "semantic_tag_aliases",
    "semantic_tag_edges",
    "semantic_card_tags",
    "semantic_tag_stats",
  ] {
    try database.execute("ALTER TABLE \(table) RENAME TO \(table)_case_variant")
    try database.execute("ALTER TABLE \(table)_case_variant RENAME TO \(table.uppercased())")
  }
}

private func expectRejectedSemanticReplacement(
  _ invalid: SemanticCatalogSnapshot,
  preserving original: SemanticCatalogSnapshot
) throws {
  let database = try CardDatabase(storage: .inMemory)
  try database.replaceSemanticCatalog(with: original)

  #expect(throws: (any Error).self) {
    try database.replaceSemanticCatalog(with: invalid)
  }
  #expect(try database.semanticCatalogSnapshot() == original)
}

private func semanticTemporaryDirectory() -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("SemanticCatalogStorageTests-\(UUID().uuidString)", isDirectory: true)
  try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
