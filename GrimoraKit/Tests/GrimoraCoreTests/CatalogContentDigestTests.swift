import Foundation
import Testing
@testable import GrimoraCore

/// Guards the invariant the whole incremental-update integrity model rests on: the content digest is
/// a function of logical row *values*, not file byte layout. Two catalogs with identical rows must
/// digest identically regardless of insert order, `VACUUM`, or the `card_faces` surrogate rowid.
struct CatalogContentDigestTests {
  @Test
  func digestIsStableAcrossInsertOrderVacuumAndSurrogateKeys() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DigestTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let forward = try makeDigestFixture(at: root.appendingPathComponent("a.sqlite"), reversed: false)
    let reversed = try makeDigestFixture(at: root.appendingPathComponent("b.sqlite"), reversed: true)

    #expect(forward == reversed)
    // Every per-table digest matches, not just the roll-up.
    #expect(forward.cards == reversed.cards)
    #expect(forward.cardFaces == reversed.cardFaces)
    #expect(forward.series == reversed.series)
    #expect(forward.summaries == reversed.summaries)
    #expect(forward.mappings == reversed.mappings)
  }

  @Test
  func digestChangesWhenAValueChanges() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DigestTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let baseline = try makeDigestFixture(at: root.appendingPathComponent("a.sqlite"), reversed: false)
    let mutated = try makeDigestFixture(
      at: root.appendingPathComponent("c.sqlite"),
      reversed: false,
      bumpFirstPrice: true
    )
    #expect(baseline.cards != mutated.cards)
    #expect(baseline.overall != mutated.overall)
  }

  @Test
  func digestChangesWhenSemanticCatalogChanges() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DigestTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let baseline = try makeDigestFixture(at: root.appendingPathComponent("a.sqlite"), reversed: false)
    let mutated = try makeDigestFixture(
      at: root.appendingPathComponent("semantic.sqlite"),
      reversed: false,
      semanticLabel: "Changed Draw Engine"
    )

    #expect(baseline.overall != mutated.overall)
  }

  @Test
  func digestIsStableAcrossCaseVariantSemanticTableNames() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DigestTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let canonical = try makeDigestFixture(
      at: root.appendingPathComponent("canonical.sqlite"),
      reversed: false
    )
    let caseVariant = try makeDigestFixture(
      at: root.appendingPathComponent("case-variant.sqlite"),
      reversed: false,
      caseVariantSemanticTables: true
    )

    #expect(caseVariant == canonical)
  }

  private func makeDigestFixture(
    at url: URL,
    reversed: Bool,
    bumpFirstPrice: Bool = false,
    semanticLabel: String = "Draw Engine",
    caseVariantSemanticTables: Bool = false
  ) throws -> CatalogContentDigests {
    let database = try SQLiteDatabase(storage: .file(url))
    try database.execute(
      """
      CREATE TABLE cards (id TEXT PRIMARY KEY, name TEXT NOT NULL, price_usd REAL, flavor_text TEXT);
      CREATE TABLE card_faces (id INTEGER PRIMARY KEY AUTOINCREMENT, card_id TEXT NOT NULL, face_index INTEGER NOT NULL, name TEXT NOT NULL);
      CREATE TABLE card_value_series (card_id TEXT NOT NULL, provider TEXT NOT NULL, finish TEXT NOT NULL, start_date TEXT NOT NULL, end_date TEXT NOT NULL, day_count INTEGER NOT NULL, prices_cents BLOB NOT NULL, PRIMARY KEY (card_id, provider, finish));
      CREATE TABLE card_value_summaries (card_id TEXT NOT NULL, provider TEXT NOT NULL, finish TEXT NOT NULL, current_price REAL NOT NULL, PRIMARY KEY (card_id, provider, finish));
      CREATE TABLE card_value_mappings (card_id TEXT NOT NULL, mtgjson_uuid TEXT PRIMARY KEY);
      CREATE TABLE semantic_tags (id TEXT PRIMARY KEY, namespace TEXT NOT NULL, slug TEXT NOT NULL, label TEXT NOT NULL, description TEXT, similarity_enabled INTEGER NOT NULL, source TEXT NOT NULL);
      CREATE TABLE semantic_tag_aliases (tag_id TEXT NOT NULL, alias TEXT NOT NULL, alias_key TEXT NOT NULL, PRIMARY KEY (tag_id, alias_key));
      CREATE TABLE semantic_tag_edges (parent_tag_id TEXT NOT NULL, child_tag_id TEXT NOT NULL, PRIMARY KEY (parent_tag_id, child_tag_id));
      CREATE TABLE semantic_card_tags (card_key TEXT NOT NULL, tag_id TEXT NOT NULL, weight_millis INTEGER NOT NULL, annotation TEXT, source TEXT NOT NULL, PRIMARY KEY (card_key, tag_id, source));
      CREATE TABLE semantic_tag_stats (tag_id TEXT PRIMARY KEY, direct_card_count INTEGER NOT NULL, effective_card_count INTEGER NOT NULL, idf_millis INTEGER NOT NULL);
      """
    )

    var cardRows: [(String, String, Double?, String?)] = [
      ("aaa", "Alpha", bumpFirstPrice ? 9.99 : 0.50, "flavor"),
      ("bbb", "Beta", nil, nil),
      ("ccc", "Gamma", 1.25, "quote"),
    ]
    if reversed { cardRows.reverse() }
    let cardInsert = try database.prepare(
      "INSERT INTO cards (id, name, price_usd, flavor_text) VALUES (?, ?, ?, ?)"
    )
    for row in cardRows {
      try cardInsert.bind(row.0, at: 1)
      try cardInsert.bind(row.1, at: 2)
      try cardInsert.bind(row.2, at: 3)
      try cardInsert.bind(row.3, at: 4)
      try cardInsert.step()
      try cardInsert.reset()
    }

    // Two faces on "aaa"; inserting them in different orders yields different surrogate `id`s.
    var faceRows = [("aaa", 0, "Front"), ("aaa", 1, "Back")]
    if reversed { faceRows.reverse() }
    let faceInsert = try database.prepare(
      "INSERT INTO card_faces (card_id, face_index, name) VALUES (?, ?, ?)"
    )
    for row in faceRows {
      try faceInsert.bind(row.0, at: 1)
      try faceInsert.bind(row.1, at: 2)
      try faceInsert.bind(row.2, at: 3)
      try faceInsert.step()
      try faceInsert.reset()
    }

    let seriesInsert = try database.prepare(
      "INSERT INTO card_value_series (card_id, provider, finish, start_date, end_date, day_count, prices_cents) VALUES (?, ?, ?, ?, ?, ?, ?)"
    )
    try seriesInsert.bind("aaa", at: 1)
    try seriesInsert.bind("tcgplayer", at: 2)
    try seriesInsert.bind("nonfoil", at: 3)
    try seriesInsert.bind("2026-01-01", at: 4)
    try seriesInsert.bind("2026-01-02", at: 5)
    try seriesInsert.bind(2, at: 6)
    try seriesInsert.bind(Data([48, 0, 0, 0, 50, 0, 0, 0]), at: 7)
    try seriesInsert.step()

    let summaryInsert = try database.prepare(
      "INSERT INTO card_value_summaries (card_id, provider, finish, current_price) VALUES (?, ?, ?, ?)"
    )
    try summaryInsert.bind("aaa", at: 1)
    try summaryInsert.bind("tcgplayer", at: 2)
    try summaryInsert.bind("nonfoil", at: 3)
    try summaryInsert.bind(0.50, at: 4)
    try summaryInsert.step()

    var mappingRows = [("aaa", "uuid-1"), ("ccc", "uuid-2")]
    if reversed { mappingRows.reverse() }
    let mappingInsert = try database.prepare(
      "INSERT INTO card_value_mappings (card_id, mtgjson_uuid) VALUES (?, ?)"
    )
    for row in mappingRows {
      try mappingInsert.bind(row.0, at: 1)
      try mappingInsert.bind(row.1, at: 2)
      try mappingInsert.step()
      try mappingInsert.reset()
    }

    let semanticTag = try database.prepare(
      "INSERT INTO semantic_tags (id, namespace, slug, label, description, similarity_enabled, source) VALUES (?, ?, ?, ?, ?, ?, ?)"
    )
    try semanticTag.bind("tag-draw-engine", at: 1)
    try semanticTag.bind("oracle", at: 2)
    try semanticTag.bind("draw-engine", at: 3)
    try semanticTag.bind(semanticLabel, at: 4)
    try semanticTag.bind("Repeatable card draw.", at: 5)
    try semanticTag.bind(true, at: 6)
    try semanticTag.bind("scryfall-oracle-tags@fixture", at: 7)
    try semanticTag.step()
    try database.execute(
      """
      INSERT INTO semantic_tag_aliases VALUES ('tag-draw-engine', 'Card Draw Engine', 'card draw engine');
      INSERT INTO semantic_card_tags VALUES ('o:oracle-aaa', 'tag-draw-engine', 1000, 'fixture', 'scryfall-oracle-tags@fixture');
      INSERT INTO semantic_tag_stats VALUES ('tag-draw-engine', 1, 1, 1000);
      """
    )

    if caseVariantSemanticTables {
      try renameSemanticTablesToUppercase(database)
    }

    // Only the reversed fixture gets VACUUMed, to prove page layout doesn't affect the digest.
    if reversed {
      try database.execute("VACUUM")
    }
    return try CatalogContentDigest.compute(database)
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
      try database.execute(
        "ALTER TABLE \(table)_case_variant RENAME TO \(table.uppercased())"
      )
    }
  }
}
