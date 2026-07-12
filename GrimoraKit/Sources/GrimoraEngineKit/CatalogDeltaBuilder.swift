import Foundation
import GrimoraCore

/// Row counts for each section of a generated patch database — handy for logging and tests.
public struct CatalogDeltaStats: Equatable, Sendable {
  public var cardsPriceUpdated: Int
  public var cardsUpserted: Int
  public var cardsDeleted: Int
  public var cardFacesReplacedCards: Int
  public var seriesSlid: Int
  public var seriesReplaced: Int
  public var seriesDeleted: Int
  public var mappingsUpserted: Int
  public var mappingsDeleted: Int
  public var metadataSet: Int

  public var isEmpty: Bool {
    cardsPriceUpdated == 0 && cardsUpserted == 0 && cardsDeleted == 0
      && cardFacesReplacedCards == 0 && seriesSlid == 0 && seriesReplaced == 0
      && seriesDeleted == 0 && mappingsUpserted == 0 && mappingsDeleted == 0 && metadataSet == 0
  }
}

public enum CatalogDeltaBuilderError: Error, Equatable, Sendable {
  case missingColumns(String)
}

/// Diffs two built catalogs (`base` → `target`) into a patch database that ``CatalogDeltaApplier``
/// can replay on a device sitting on `base` to reach `target`. Everything is expressed as
/// set-difference SQL between the two attached databases; no per-row Swift marshaling.
public struct CatalogDeltaBuilder {
  public init() {}

  /// Builds an **uncompressed** patch database at `deltaURL`. Callers gzip it for transport.
  @discardableResult
  public func buildDelta(
    baseCatalogURL: URL,
    targetCatalogURL: URL,
    baseVersion: String,
    targetVersion: String,
    into deltaURL: URL,
    fileManager: FileManager = .default
  ) throws -> CatalogDeltaStats {
    if fileManager.fileExists(atPath: deltaURL.path) {
      try fileManager.removeItem(at: deltaURL)
    }

    let patch = try SQLiteDatabase(storage: .file(deltaURL))
    try patch.attachReadOnlyDatabase(at: baseCatalogURL, as: "base")
    try patch.attachReadOnlyDatabase(at: targetCatalogURL, as: "target")

    let cardColumns = try columnNames(patch, schema: "target", table: "cards")
    let faceColumns = try columnNames(patch, schema: "target", table: "card_faces")
      .filter { $0 != "id" }
    guard !cardColumns.isEmpty, !faceColumns.isEmpty else {
      throw CatalogDeltaBuilderError.missingColumns("cards/card_faces columns unavailable")
    }
    let priceColumns = Set(CatalogDeltaSchema.cardsPriceColumns)
    let nonPriceCardColumns = cardColumns.filter { $0 != "id" && !priceColumns.contains($0) }

    try patch.execute(CatalogDeltaSchema.fixedTableDDL)
    try createDynamicPatchTables(patch, cardColumns: cardColumns, faceColumns: faceColumns)

    try patch.transaction {
      try populate(
        patch,
        cardColumns: cardColumns,
        nonPriceCardColumns: nonPriceCardColumns,
        faceColumns: faceColumns
      )
    }

    let metaInsert = try patch.prepare(
      """
      INSERT INTO \(CatalogDeltaSchema.meta) (base_version, target_version, format_version, created_at)
      VALUES (?, ?, ?, ?)
      """
    )
    try metaInsert.bind(baseVersion, at: 1)
    try metaInsert.bind(targetVersion, at: 2)
    try metaInsert.bind(CatalogDelta.currentFormatVersion, at: 3)
    let iso8601 = ISO8601DateFormatter()
    iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    try metaInsert.bind(iso8601.string(from: Date()), at: 4)
    try metaInsert.step()

    let stats = try collectStats(patch)

    try patch.detachDatabase(named: "base")
    try patch.detachDatabase(named: "target")
    try patch.execute("PRAGMA journal_mode = DELETE")
    try patch.execute("VACUUM")

    return stats
  }

  // MARK: - Table creation

  private func createDynamicPatchTables(
    _ patch: SQLiteDatabase,
    cardColumns: [String],
    faceColumns: [String]
  ) throws {
    let cardList = cardColumns.map(Self.quoted).joined(separator: ", ")
    try patch.execute(
      """
      CREATE TABLE \(CatalogDeltaSchema.cardsUpsert) AS
      SELECT \(cardList), CAST(NULL AS TEXT) AS \(CatalogDeltaSchema.cardsUpsertSearchTextColumn)
      FROM target.cards WHERE 0
      """
    )
    let faceList = faceColumns.map(Self.quoted).joined(separator: ", ")
    try patch.execute(
      """
      CREATE TABLE \(CatalogDeltaSchema.cardFacesReplace) AS
      SELECT \(faceList) FROM target.card_faces WHERE 0
      """
    )
  }

  // MARK: - Population

  private func populate(
    _ patch: SQLiteDatabase,
    cardColumns: [String],
    nonPriceCardColumns: [String],
    faceColumns: [String]
  ) throws {
    let nonPriceChanged = orDiffers(nonPriceCardColumns)
    let priceChanged = orDiffers(CatalogDeltaSchema.cardsPriceColumns)

    // Deleted cards (dependents cascade on apply).
    try patch.execute(
      """
      INSERT INTO \(CatalogDeltaSchema.cardsDelete) (id)
      SELECT id FROM base.cards WHERE id NOT IN (SELECT id FROM target.cards)
      """
    )

    // Price-only changes: present in both, every non-price column equal, some price column differs.
    try patch.execute(
      """
      INSERT INTO \(CatalogDeltaSchema.cardsPriceUpdate) (id, price_usd, price_tix, price_eur)
      SELECT t.id, t.price_usd, t.price_tix, t.price_eur
      FROM target.cards t JOIN base.cards b ON b.id = t.id
      WHERE NOT (\(nonPriceChanged)) AND (\(priceChanged))
      """
    )

    // Full-row upserts: new cards, or cards whose non-price columns changed.
    let cardList = cardColumns.map(Self.quoted).joined(separator: ", ")
    let targetCardList = cardColumns.map { "t.\(Self.quoted($0))" }.joined(separator: ", ")
    try patch.execute(
      """
      INSERT INTO \(CatalogDeltaSchema.cardsUpsert)
          (\(cardList), \(CatalogDeltaSchema.cardsUpsertSearchTextColumn))
      SELECT \(targetCardList),
          (SELECT f.search_text FROM target.cards_fts f WHERE f.card_id = t.id)
      FROM target.cards t LEFT JOIN base.cards b ON b.id = t.id
      WHERE b.id IS NULL OR (\(nonPriceChanged))
      """
    )

    // Cards whose face set changed (symmetric difference), limited to cards that still exist.
    let faceList = faceColumns.map(Self.quoted).joined(separator: ", ")
    for (minuend, subtrahend) in [("base", "target"), ("target", "base")] {
      try patch.execute(
        """
        INSERT OR IGNORE INTO \(CatalogDeltaSchema.cardFacesReplaceCards) (card_id)
        SELECT DISTINCT card_id FROM (
            SELECT \(faceList) FROM \(minuend).card_faces
            EXCEPT
            SELECT \(faceList) FROM \(subtrahend).card_faces
        )
        WHERE card_id IN (SELECT id FROM target.cards)
        """
      )
    }
    try patch.execute(
      """
      INSERT INTO \(CatalogDeltaSchema.cardFacesReplace) (\(faceList))
      SELECT \(faceList) FROM target.card_faces
      WHERE card_id IN (SELECT card_id FROM \(CatalogDeltaSchema.cardFacesReplaceCards))
      """
    )

    // Value series — a sliding fixed-width daily window. Emit a compact slide (drop N bytes off the
    // front, append a suffix) where the overlap is byte-identical, else a full replace; plus deletes.
    try populateSeries(patch)

    // MTGJSON UUID → card_id mappings.
    try patch.execute(
      """
      INSERT INTO \(CatalogDeltaSchema.mappingsUpsert) (card_id, mtgjson_uuid)
      SELECT t.card_id, t.mtgjson_uuid FROM target.card_value_mappings t
      LEFT JOIN base.card_value_mappings b ON b.mtgjson_uuid = t.mtgjson_uuid
      WHERE b.mtgjson_uuid IS NULL OR b.card_id IS NOT t.card_id
      """
    )
    try patch.execute(
      """
      INSERT INTO \(CatalogDeltaSchema.mappingsDelete) (mtgjson_uuid)
      SELECT b.mtgjson_uuid FROM base.card_value_mappings b
      WHERE b.mtgjson_uuid NOT IN (SELECT mtgjson_uuid FROM target.card_value_mappings)
      """
    )

    // Catalog metadata rows that changed (value summaries are recomputed on device, not shipped).
    try patch.execute(
      """
      INSERT INTO \(CatalogDeltaSchema.metadataSet) (key, value)
      SELECT key, value FROM target.metadata
      WHERE (key, value) NOT IN (SELECT key, value FROM base.metadata)
      """
    )
  }

  /// Classifies every value series as slide / replace / delete. All series in a build share the
  /// same window `start_date`, so the day-shift is computed once and memoized. Runs in Swift because
  /// the slide test (drop-front + overlap-equality) is awkward and error-prone in pure SQL.
  private func populateSeries(_ patch: SQLiteDatabase) throws {
    try patch.execute(
      """
      INSERT INTO \(CatalogDeltaSchema.seriesDelete) (card_id, provider, finish)
      SELECT b.card_id, b.provider, b.finish
      FROM base.card_value_series b
      LEFT JOIN target.card_value_series t USING (card_id, provider, finish)
      WHERE t.card_id IS NULL
      """
    )

    let targetSeries = try patch.prepare(
      """
      SELECT card_id, provider, finish, start_date, end_date, day_count, prices_cents
      FROM target.card_value_series ORDER BY card_id, provider, finish
      """
    )
    let baseLookup = try patch.prepare(
      """
      SELECT start_date, prices_cents FROM base.card_value_series
      WHERE card_id = ? AND provider = ? AND finish = ?
      """
    )
    let slideInsert = try patch.prepare(
      """
      INSERT INTO \(CatalogDeltaSchema.seriesSlide)
          (card_id, provider, finish, drop_bytes, new_start_date, new_end_date, new_day_count, appended_cents)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    let replaceInsert = try patch.prepare(
      """
      INSERT INTO \(CatalogDeltaSchema.seriesReplace)
          (card_id, provider, finish, start_date, end_date, day_count, prices_cents)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """
    )

    let formatter = Self.makeDateFormatter()
    var dayDiffCache: [String: Int?] = [:]

    while try targetSeries.step() {
      let cardID = targetSeries.string(at: 0) ?? ""
      let provider = targetSeries.string(at: 1) ?? ""
      let finish = targetSeries.string(at: 2) ?? ""
      let startDate = targetSeries.string(at: 3) ?? ""
      let endDate = targetSeries.string(at: 4) ?? ""
      let dayCount = targetSeries.int(at: 5) ?? 0
      let targetBlob = targetSeries.data(at: 6) ?? Data()

      try baseLookup.bind(cardID, at: 1)
      try baseLookup.bind(provider, at: 2)
      try baseLookup.bind(finish, at: 3)
      var baseStart: String?
      var baseBlob: Data?
      if try baseLookup.step() {
        baseStart = baseLookup.string(at: 0)
        baseBlob = baseLookup.data(at: 1)
      }
      try baseLookup.reset()

      if let baseStart, let baseBlob {
        if baseStart == startDate, baseBlob == targetBlob {
          continue // unchanged
        }
        if let drop = slideDropBytes(
          baseStart: baseStart,
          targetStart: startDate,
          baseBlob: baseBlob,
          targetBlob: targetBlob,
          formatter: formatter,
          cache: &dayDiffCache
        ) {
          let appended = Data(targetBlob.suffix(targetBlob.count - (baseBlob.count - drop)))
          try slideInsert.bind(cardID, at: 1)
          try slideInsert.bind(provider, at: 2)
          try slideInsert.bind(finish, at: 3)
          try slideInsert.bind(drop, at: 4)
          try slideInsert.bind(startDate, at: 5)
          try slideInsert.bind(endDate, at: 6)
          try slideInsert.bind(dayCount, at: 7)
          try slideInsert.bind(appended, at: 8)
          try slideInsert.step()
          try slideInsert.reset()
          continue
        }
      }

      try replaceInsert.bind(cardID, at: 1)
      try replaceInsert.bind(provider, at: 2)
      try replaceInsert.bind(finish, at: 3)
      try replaceInsert.bind(startDate, at: 4)
      try replaceInsert.bind(endDate, at: 5)
      try replaceInsert.bind(dayCount, at: 6)
      try replaceInsert.bind(targetBlob, at: 7)
      try replaceInsert.step()
      try replaceInsert.reset()
    }
  }

  /// Returns the number of leading bytes to drop from `baseBlob` such that the remaining bytes are a
  /// prefix of `targetBlob` (the window slid forward by that many days), or `nil` if no such clean
  /// slide exists and the series must be shipped in full.
  private func slideDropBytes(
    baseStart: String,
    targetStart: String,
    baseBlob: Data,
    targetBlob: Data,
    formatter: DateFormatter,
    cache: inout [String: Int?]
  ) -> Int? {
    let key = "\(baseStart)|\(targetStart)"
    let slideDays: Int?
    if let cached = cache[key] {
      slideDays = cached
    } else {
      slideDays = Self.dayDifference(from: baseStart, to: targetStart, formatter: formatter)
      cache[key] = slideDays
    }
    guard let slideDays, slideDays >= 0 else { return nil }
    let drop = slideDays * 4
    guard drop <= baseBlob.count else { return nil }
    let overlapLength = baseBlob.count - drop
    guard targetBlob.count >= overlapLength else { return nil }
    guard baseBlob.suffix(overlapLength).elementsEqual(targetBlob.prefix(overlapLength)) else {
      return nil
    }
    return drop
  }

  private static func dayDifference(from: String, to: String, formatter: DateFormatter) -> Int? {
    guard let start = formatter.date(from: from), let end = formatter.date(from: to) else {
      return nil
    }
    return Int((end.timeIntervalSince(start) / 86400).rounded())
  }

  private static func makeDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }

  // MARK: - Helpers

  private func collectStats(_ patch: SQLiteDatabase) throws -> CatalogDeltaStats {
    CatalogDeltaStats(
      cardsPriceUpdated: try count(patch, CatalogDeltaSchema.cardsPriceUpdate),
      cardsUpserted: try count(patch, CatalogDeltaSchema.cardsUpsert),
      cardsDeleted: try count(patch, CatalogDeltaSchema.cardsDelete),
      cardFacesReplacedCards: try count(patch, CatalogDeltaSchema.cardFacesReplaceCards),
      seriesSlid: try count(patch, CatalogDeltaSchema.seriesSlide),
      seriesReplaced: try count(patch, CatalogDeltaSchema.seriesReplace),
      seriesDeleted: try count(patch, CatalogDeltaSchema.seriesDelete),
      mappingsUpserted: try count(patch, CatalogDeltaSchema.mappingsUpsert),
      mappingsDeleted: try count(patch, CatalogDeltaSchema.mappingsDelete),
      metadataSet: try count(patch, CatalogDeltaSchema.metadataSet)
    )
  }

  private func count(_ database: SQLiteDatabase, _ table: String) throws -> Int {
    let statement = try database.prepare("SELECT COUNT(*) FROM \(table)")
    _ = try statement.step()
    return statement.int(at: 0) ?? 0
  }

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

  private func orDiffers(_ columns: [String]) -> String {
    guard !columns.isEmpty else { return "0" }
    return columns.map { "b.\(Self.quoted($0)) IS NOT t.\(Self.quoted($0))" }
      .joined(separator: " OR ")
  }

  private static func quoted(_ identifier: String) -> String {
    "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}
