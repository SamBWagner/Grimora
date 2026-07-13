import Foundation

public enum CatalogDeltaApplierError: Error, Equatable, Sendable {
  case missingMetadata
  case unsupportedFormatVersion(Int)
  case seriesAppendMissingBase(cardID: String, finish: String)
  case invalidAppendedBytes(cardID: String, finish: String)
}

/// Replays a patch database (see ``CatalogDeltaSchema``) onto a **writable working copy** of the
/// on-device catalog, turning a catalog at `base_version` into the catalog at `target_version`.
///
/// It deliberately opens the working catalog as a raw ``SQLiteDatabase`` rather than a
/// `CardDatabase`, so no migration/overlay logic runs against the pristine catalog. Everything
/// happens inside a single transaction; on any error the transaction rolls back and the caller
/// falls back to a full download. Value summaries are recomputed from the patched series rather
/// than shipped, using the same arithmetic as a fresh engine build
/// (`CardDatabase.recomputeValueSummary`).
public struct CatalogDeltaApplier {
  public init() {}

  public func apply(deltaURL: URL, toWorkingCatalog workingURL: URL) throws {
    let database = try SQLiteDatabase(storage: .file(workingURL))
    try database.attachReadOnlyDatabase(at: deltaURL, as: "delta")
    defer { try? database.detachDatabase(named: "delta") }

    try verifyFormatVersion(database)
    let cardColumns = try columnNames(database, schema: "main", table: "cards")
    let faceColumns = try columnNames(database, schema: "main", table: "card_faces")
      .filter { $0 != "id" }

    try database.transaction {
      try applyCardDeletes(database)
      try applyFieldChanges(database, cardColumns: cardColumns)
      try applyCardUpserts(database, cardColumns: cardColumns)
      try applyFaceReplacements(database, faceColumns: faceColumns)
      try applySeriesReplacements(database)
      try applySeriesSlides(database)
      try applySeriesDeletes(database)
      try applyMappings(database)
      try applyMetadata(database)
    }

    try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    try database.execute("PRAGMA journal_mode = DELETE")
  }

  // MARK: - Sections

  private func verifyFormatVersion(_ database: SQLiteDatabase) throws {
    let statement = try database.prepare(
      "SELECT format_version FROM delta.\(CatalogDeltaSchema.meta) LIMIT 1"
    )
    guard try statement.step(), let version = statement.int(at: 0) else {
      throw CatalogDeltaApplierError.missingMetadata
    }
    guard version == CatalogDelta.currentFormatVersion else {
      throw CatalogDeltaApplierError.unsupportedFormatVersion(version)
    }
  }

  private func applyCardDeletes(_ database: SQLiteDatabase) throws {
    // Foreign keys are ON, so deleting a card cascades to faces / series / summaries / mappings.
    // FTS tables aren't foreign-keyed, so their rows (for both deletes and upserts) are cleared
    // here and rebuilt in `applyCardUpserts`.
    try database.execute(
      """
      DELETE FROM cards_fts WHERE card_id IN (
          SELECT id FROM delta.\(CatalogDeltaSchema.cardsDelete)
          UNION SELECT id FROM delta.\(CatalogDeltaSchema.cardsUpsert)
      )
      """
    )
    try database.execute(
      """
      DELETE FROM cards_name_fts WHERE card_id IN (
          SELECT id FROM delta.\(CatalogDeltaSchema.cardsDelete)
          UNION SELECT id FROM delta.\(CatalogDeltaSchema.cardsUpsert)
      )
      """
    )
    try database.execute(
      "DELETE FROM cards WHERE id IN (SELECT id FROM delta.\(CatalogDeltaSchema.cardsDelete))"
    )
  }

  /// Narrow per-field updates (prices / ranks / image URLs). One UPDATE per whitelisted column,
  /// touching only the cards that changed it — no FTS rebuild, since these columns don't feed search.
  /// Iterates the local whitelist (not fields from the delta) so a malformed/newer delta can't drive
  /// an arbitrary column write; any field the applier doesn't recognize is simply left unapplied,
  /// which the post-apply digest check catches (→ full-download fallback).
  private func applyFieldChanges(_ database: SQLiteDatabase, cardColumns: [String]) throws {
    let known = Set(cardColumns)
    for column in CatalogDeltaSchema.narrowUpdateColumns where known.contains(column) {
      try database.execute(
        """
        UPDATE cards SET \(Self.quoted(column)) = (
            SELECT value FROM delta.\(CatalogDeltaSchema.cardFieldChange) c
            WHERE c.id = cards.id AND c.field = '\(column)'
        )
        WHERE id IN (
            SELECT id FROM delta.\(CatalogDeltaSchema.cardFieldChange) WHERE field = '\(column)'
        )
        """
      )
    }
  }

  private func applyCardUpserts(_ database: SQLiteDatabase, cardColumns: [String]) throws {
    let nonIDColumns = cardColumns.filter { $0 != "id" }
    guard !nonIDColumns.isEmpty else { return }
    let assignList = nonIDColumns.map(Self.quoted).joined(separator: ", ")
    let selectList = nonIDColumns.map { "d.\(Self.quoted($0))" }.joined(separator: ", ")

    // Update existing rows without INSERT OR REPLACE — a REPLACE would cascade-delete the card's
    // faces/series via the FK, wiping data we mean to keep.
    try database.execute(
      """
      UPDATE cards SET (\(assignList)) = (
          SELECT \(selectList) FROM delta.\(CatalogDeltaSchema.cardsUpsert) d WHERE d.id = cards.id
      )
      WHERE id IN (SELECT id FROM delta.\(CatalogDeltaSchema.cardsUpsert))
      """
    )
    // Insert brand-new cards.
    let insertColumns = (["id"] + nonIDColumns).map(Self.quoted).joined(separator: ", ")
    try database.execute(
      """
      INSERT INTO cards (\(insertColumns))
      SELECT \(insertColumns) FROM delta.\(CatalogDeltaSchema.cardsUpsert)
      WHERE id NOT IN (SELECT id FROM cards)
      """
    )

    // Rebuild the FTS rows for every upserted card (their old rows were cleared above).
    try database.execute(
      """
      INSERT INTO cards_fts (card_id, search_text)
      SELECT id, \(CatalogDeltaSchema.cardsUpsertSearchTextColumn)
      FROM delta.\(CatalogDeltaSchema.cardsUpsert)
      """
    )
    try database.execute(
      """
      INSERT INTO cards_name_fts (card_id, name_text)
      SELECT id, name FROM delta.\(CatalogDeltaSchema.cardsUpsert)
      """
    )
  }

  private func applyFaceReplacements(_ database: SQLiteDatabase, faceColumns: [String]) throws {
    try database.execute(
      """
      DELETE FROM card_faces WHERE card_id IN (
          SELECT card_id FROM delta.\(CatalogDeltaSchema.cardFacesReplaceCards)
      )
      """
    )
    guard !faceColumns.isEmpty else { return }
    let list = faceColumns.map(Self.quoted).joined(separator: ", ")
    try database.execute(
      """
      INSERT INTO card_faces (\(list))
      SELECT \(list) FROM delta.\(CatalogDeltaSchema.cardFacesReplace)
      """
    )
  }

  private func applySeriesReplacements(_ database: SQLiteDatabase) throws {
    try database.execute(
      """
      INSERT OR REPLACE INTO card_value_series
          (card_id, provider, finish, start_date, end_date, day_count, prices_cents)
      SELECT card_id, provider, finish, start_date, end_date, day_count, prices_cents
      FROM delta.\(CatalogDeltaSchema.seriesReplace)
      """
    )
    // Recompute summaries for the replaced series directly from the shipped blobs.
    let source = try database.prepare(
      """
      SELECT card_id, provider, finish, end_date, day_count, prices_cents
      FROM delta.\(CatalogDeltaSchema.seriesReplace)
      """
    )
    let summaryUpsert = try prepareSummaryUpsert(database)
    let summaryDelete = try prepareSummaryDelete(database)
    while try source.step() {
      try recomputeSummary(
        cardID: source.string(at: 0) ?? "",
        provider: source.string(at: 1) ?? "",
        finish: source.string(at: 2) ?? "",
        endDate: source.string(at: 3) ?? "",
        dayCount: source.int(at: 4) ?? 0,
        encodedPrices: source.data(at: 5) ?? Data(),
        upsert: summaryUpsert,
        delete: summaryDelete
      )
    }
  }

  private func applySeriesSlides(_ database: SQLiteDatabase) throws {
    let source = try database.prepare(
      """
      SELECT card_id, provider, finish, drop_bytes, new_start_date, new_end_date, new_day_count, appended_cents
      FROM delta.\(CatalogDeltaSchema.seriesSlide)
      """
    )
    let existing = try database.prepare(
      "SELECT prices_cents FROM card_value_series WHERE card_id = ? AND provider = ? AND finish = ?"
    )
    let update = try database.prepare(
      """
      UPDATE card_value_series
      SET start_date = ?, end_date = ?, day_count = ?, prices_cents = ?
      WHERE card_id = ? AND provider = ? AND finish = ?
      """
    )
    let summaryUpsert = try prepareSummaryUpsert(database)
    let summaryDelete = try prepareSummaryDelete(database)

    while try source.step() {
      let cardID = source.string(at: 0) ?? ""
      let provider = source.string(at: 1) ?? ""
      let finish = source.string(at: 2) ?? ""
      let dropBytes = source.int(at: 3) ?? 0
      let newStartDate = source.string(at: 4) ?? ""
      let newEndDate = source.string(at: 5) ?? ""
      let newDayCount = source.int(at: 6) ?? 0
      let appended = source.data(at: 7) ?? Data()
      guard appended.count % 4 == 0, dropBytes >= 0, dropBytes % 4 == 0 else {
        throw CatalogDeltaApplierError.invalidAppendedBytes(cardID: cardID, finish: finish)
      }

      try existing.bind(cardID, at: 1)
      try existing.bind(provider, at: 2)
      try existing.bind(finish, at: 3)
      guard try existing.step(), let base = existing.data(at: 0), dropBytes <= base.count else {
        try existing.reset()
        throw CatalogDeltaApplierError.seriesAppendMissingBase(cardID: cardID, finish: finish)
      }
      try existing.reset()

      var combined = Data(base.dropFirst(dropBytes))
      combined.append(appended)

      try update.bind(newStartDate, at: 1)
      try update.bind(newEndDate, at: 2)
      try update.bind(newDayCount, at: 3)
      try update.bind(combined, at: 4)
      try update.bind(cardID, at: 5)
      try update.bind(provider, at: 6)
      try update.bind(finish, at: 7)
      try update.step()
      try update.reset()

      try recomputeSummary(
        cardID: cardID,
        provider: provider,
        finish: finish,
        endDate: newEndDate,
        dayCount: newDayCount,
        encodedPrices: combined,
        upsert: summaryUpsert,
        delete: summaryDelete
      )
    }
  }

  private func applySeriesDeletes(_ database: SQLiteDatabase) throws {
    for table in ["card_value_series", "card_value_summaries"] {
      try database.execute(
        """
        DELETE FROM \(table) WHERE (card_id, provider, finish) IN (
            SELECT card_id, provider, finish FROM delta.\(CatalogDeltaSchema.seriesDelete)
        )
        """
      )
    }
  }

  private func applyMappings(_ database: SQLiteDatabase) throws {
    try database.execute(
      """
      INSERT OR REPLACE INTO card_value_mappings (card_id, mtgjson_uuid)
      SELECT card_id, mtgjson_uuid FROM delta.\(CatalogDeltaSchema.mappingsUpsert)
      """
    )
    try database.execute(
      """
      DELETE FROM card_value_mappings WHERE mtgjson_uuid IN (
          SELECT mtgjson_uuid FROM delta.\(CatalogDeltaSchema.mappingsDelete)
      )
      """
    )
  }

  private func applyMetadata(_ database: SQLiteDatabase) throws {
    try database.execute(
      """
      INSERT OR REPLACE INTO metadata (key, value)
      SELECT key, value FROM delta.\(CatalogDeltaSchema.metadataSet)
      """
    )
  }

  // MARK: - Summary recompute

  private func recomputeSummary(
    cardID: String,
    provider: String,
    finish: String,
    endDate: String,
    dayCount: Int,
    encodedPrices: Data,
    upsert: SQLiteStatement,
    delete: SQLiteStatement
  ) throws {
    let prices = try CompactCardValueSeries.decodePrices(encodedPrices, expectedCount: dayCount)
    guard let summary = CardDatabase.recomputeValueSummary(pricesInCents: prices, endDate: endDate)
    else {
      try delete.bind(cardID, at: 1)
      try delete.bind(provider, at: 2)
      try delete.bind(finish, at: 3)
      try delete.step()
      try delete.reset()
      return
    }
    try upsert.bind(cardID, at: 1)
    try upsert.bind(provider, at: 2)
    try upsert.bind(finish, at: 3)
    try upsert.bind(summary.currentPrice, at: 4)
    try upsert.bind(summary.currentDate, at: 5)
    try upsert.bind(summary.price1d, at: 6)
    try upsert.bind(summary.price7d, at: 7)
    try upsert.bind(summary.price30d, at: 8)
    try upsert.bind(summary.price90d, at: 9)
    try upsert.step()
    try upsert.reset()
  }

  private func prepareSummaryUpsert(_ database: SQLiteDatabase) throws -> SQLiteStatement {
    try database.prepare(
      """
      INSERT INTO card_value_summaries
          (card_id, provider, finish, current_price, "current_date", price_1d, price_7d, price_30d, price_90d)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(card_id, provider, finish) DO UPDATE SET
          current_price = excluded.current_price,
          "current_date" = excluded."current_date",
          price_1d = excluded.price_1d,
          price_7d = excluded.price_7d,
          price_30d = excluded.price_30d,
          price_90d = excluded.price_90d
      """
    )
  }

  private func prepareSummaryDelete(_ database: SQLiteDatabase) throws -> SQLiteStatement {
    try database.prepare(
      "DELETE FROM card_value_summaries WHERE card_id = ? AND provider = ? AND finish = ?"
    )
  }

  // MARK: - Helpers

  private func columnNames(
    _ database: SQLiteDatabase,
    schema: String,
    table: String
  ) throws -> [String] {
    let statement = try database.prepare("PRAGMA \(schema).table_info(\(table))")
    var names: [String] = []
    while try statement.step() {
      if let name = statement.string(at: 1) {
        names.append(name)
      }
    }
    return names
  }

  private static func quoted(_ identifier: String) -> String {
    "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}
