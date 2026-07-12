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

  private func makeDigestFixture(
    at url: URL,
    reversed: Bool,
    bumpFirstPrice: Bool = false
  ) throws -> CatalogContentDigests {
    let database = try SQLiteDatabase(storage: .file(url))
    try database.execute(
      """
      CREATE TABLE cards (id TEXT PRIMARY KEY, name TEXT NOT NULL, price_usd REAL, flavor_text TEXT);
      CREATE TABLE card_faces (id INTEGER PRIMARY KEY AUTOINCREMENT, card_id TEXT NOT NULL, face_index INTEGER NOT NULL, name TEXT NOT NULL);
      CREATE TABLE card_value_series (card_id TEXT NOT NULL, provider TEXT NOT NULL, finish TEXT NOT NULL, start_date TEXT NOT NULL, end_date TEXT NOT NULL, day_count INTEGER NOT NULL, prices_cents BLOB NOT NULL, PRIMARY KEY (card_id, provider, finish));
      CREATE TABLE card_value_summaries (card_id TEXT NOT NULL, provider TEXT NOT NULL, finish TEXT NOT NULL, current_price REAL NOT NULL, PRIMARY KEY (card_id, provider, finish));
      CREATE TABLE card_value_mappings (card_id TEXT NOT NULL, mtgjson_uuid TEXT PRIMARY KEY);
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

    // Only the reversed fixture gets VACUUMed, to prove page layout doesn't affect the digest.
    if reversed {
      try database.execute("VACUUM")
    }
    return try CatalogContentDigest.compute(database)
  }
}
