import Foundation

public struct CompactCardValueSeries: Equatable, Sendable {
  public static let missingPrice = Int32.min

  public var cardID: CardRecord.ID
  public var finish: CardValueFinish
  public var startDate: String
  public var endDate: String
  public var pricesInCents: [Int32]

  public init(
    cardID: CardRecord.ID,
    finish: CardValueFinish,
    startDate: String,
    endDate: String,
    pricesInCents: [Int32]
  ) {
    self.cardID = cardID
    self.finish = finish
    self.startDate = startDate
    self.endDate = endDate
    self.pricesInCents = pricesInCents
  }

  public var encodedPrices: Data {
    pricesInCents.reduce(into: Data(capacity: pricesInCents.count * 4)) { data, value in
      var littleEndian = value.littleEndian
      withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
  }

  public static func decodePrices(_ data: Data, expectedCount: Int) throws -> [Int32] {
    guard expectedCount >= 0, data.count == expectedCount * 4 else {
      throw CatalogStorageError.invalidCatalog("Compact price series has an invalid byte count")
    }
    return data.withUnsafeBytes { rawBuffer in
      (0..<expectedCount).map { index in
        let value = rawBuffer.loadUnaligned(fromByteOffset: index * 4, as: Int32.self)
        return Int32(littleEndian: value)
      }
    }
  }
}

extension CardDatabase {
  public func replaceCompactCardValueHistory(
    meta: MTGJSONPriceHistoryMeta,
    mappingsByMTGJSONUUID: [String: CardRecord.ID],
    series: [CompactCardValueSeries]
  ) throws -> MTGJSONPriceImportSummary {
    try replaceCompactCardValueHistory(
      meta: meta,
      importMappings: { insert in
        for (uuid, cardID) in mappingsByMTGJSONUUID.sorted(by: { $0.key < $1.key }) {
          try insert(uuid, cardID)
        }
      },
      importSeries: { _, insert in
        for valueSeries in series {
          try insert(valueSeries)
        }
      }
    )
  }

  public func replaceCompactCardValueHistory(
    meta: MTGJSONPriceHistoryMeta,
    importMappings: (
      _ insert: (_ mtgjsonUUID: String, _ cardID: CardRecord.ID) throws -> Void
    ) throws -> Void,
    importSeries: (
      _ cardIDForMTGJSONUUID: (String) throws -> CardRecord.ID?,
      _ insert: (CompactCardValueSeries) throws -> Void
    ) throws -> Void
  ) throws -> MTGJSONPriceImportSummary {
    try withDatabaseLock {
      var importedPricePoints = 0
      var mappedCards = 0
      try database.transaction {
        try clearCardValueHistoryUnlocked()

        let mappingInsert = try database.prepare(
          """
          INSERT INTO card_value_mappings (card_id, mtgjson_uuid)
          SELECT ?, ?
          WHERE EXISTS (SELECT 1 FROM cards WHERE id = ?)
          ON CONFLICT(mtgjson_uuid) DO UPDATE SET card_id = excluded.card_id
          """
        )
        try importMappings { uuid, cardID in
          try mappingInsert.bind(cardID, at: 1)
          try mappingInsert.bind(uuid, at: 2)
          try mappingInsert.bind(cardID, at: 3)
          try mappingInsert.step()
          try mappingInsert.reset()
        }
        let mappingCount = try database.prepare("SELECT COUNT(*) FROM card_value_mappings")
        _ = try mappingCount.step()
        mappedCards = mappingCount.int(at: 0) ?? 0

        let mappingLookup = try database.prepare(
          "SELECT card_id FROM card_value_mappings WHERE mtgjson_uuid = ?"
        )

        let existingSeries = try database.prepare(
          """
          SELECT start_date, end_date, day_count, prices_cents
          FROM card_value_series
          WHERE card_id = ? AND provider = ? AND finish = ?
          """)
        let seriesUpsert = try database.prepare(
          """
          INSERT INTO card_value_series (
              card_id, provider, finish, start_date, end_date, day_count, prices_cents
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(card_id, provider, finish) DO UPDATE SET
              start_date = excluded.start_date,
              end_date = excluded.end_date,
              day_count = excluded.day_count,
              prices_cents = excluded.prices_cents
          """)

        try importSeries({ uuid in
          try mappingLookup.bind(uuid, at: 1)
          defer { try? mappingLookup.reset() }
          guard try mappingLookup.step() else {
            return nil
          }
          return mappingLookup.string(at: 0)
        }) { valueSeries in
          try existingSeries.bind(valueSeries.cardID, at: 1)
          try existingSeries.bind(CardValueProvider.tcgplayer.rawValue, at: 2)
          try existingSeries.bind(valueSeries.finish.rawValue, at: 3)

          var prices = valueSeries.pricesInCents
          if try existingSeries.step() {
            guard existingSeries.string(at: 0) == valueSeries.startDate,
              existingSeries.string(at: 1) == valueSeries.endDate,
              existingSeries.int(at: 2) == prices.count,
              let encoded = existingSeries.data(at: 3)
            else {
              throw CatalogStorageError.invalidCatalog(
                "Compact aliases for \(valueSeries.cardID) use incompatible date ranges"
              )
            }
            let existingPrices = try CompactCardValueSeries.decodePrices(
              encoded,
              expectedCount: prices.count
            )
            for index in prices.indices
            where prices[index] == CompactCardValueSeries.missingPrice {
              prices[index] = existingPrices[index]
            }
          }
          try existingSeries.reset()

          try seriesUpsert.bind(valueSeries.cardID, at: 1)
          try seriesUpsert.bind(CardValueProvider.tcgplayer.rawValue, at: 2)
          try seriesUpsert.bind(valueSeries.finish.rawValue, at: 3)
          try seriesUpsert.bind(valueSeries.startDate, at: 4)
          try seriesUpsert.bind(valueSeries.endDate, at: 5)
          try seriesUpsert.bind(prices.count, at: 6)
          try seriesUpsert.bind(CompactCardValueSeries(
            cardID: valueSeries.cardID,
            finish: valueSeries.finish,
            startDate: valueSeries.startDate,
            endDate: valueSeries.endDate,
            pricesInCents: prices
          ).encodedPrices, at: 7)
          try seriesUpsert.step()
          try seriesUpsert.reset()
        }

        importedPricePoints = try finalizeCompactCardValueSeriesUnlocked()
        try saveMetadataValue(meta.date, forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue)
        try saveMetadataValue(meta.version, forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue)
      }
      return MTGJSONPriceImportSummary(
        mappedCards: mappedCards,
        importedPricePoints: importedPricePoints
      )
    }
  }

  private func finalizeCompactCardValueSeriesUnlocked() throws -> Int {
    try database.execute(
      """
      CREATE TEMP TABLE normalized_card_value_series (
          card_id TEXT NOT NULL,
          provider TEXT NOT NULL,
          finish TEXT NOT NULL,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL,
          day_count INTEGER NOT NULL,
          prices_cents BLOB NOT NULL,
          PRIMARY KEY (card_id, provider, finish)
      ) WITHOUT ROWID
      """)
    defer { try? database.execute("DROP TABLE IF EXISTS normalized_card_value_series") }

    let source = try database.prepare(
      """
      SELECT card_id, provider, finish, start_date, end_date, day_count, prices_cents
      FROM card_value_series
      ORDER BY card_id, provider, finish
      """)
    let normalizedInsert = try database.prepare(
      """
      INSERT INTO normalized_card_value_series (
          card_id, provider, finish, start_date, end_date, day_count, prices_cents
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      """)
    let summaryInsert = try database.prepare(
      """
      INSERT INTO card_value_summaries (
          card_id, provider, finish, current_price, "current_date",
          price_1d, price_7d, price_30d, price_90d
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      """)

    var importedPricePoints = 0
    while try source.step() {
      guard let cardID = source.string(at: 0),
        let provider = source.string(at: 1),
        let finish = source.string(at: 2),
        let startDate = source.string(at: 3),
        let endDate = source.string(at: 4),
        let dayCount = source.int(at: 5),
        let encoded = source.data(at: 6)
      else {
        throw CatalogStorageError.invalidCatalog("Compact price series contains a null value")
      }

      var prices = try CompactCardValueSeries.decodePrices(encoded, expectedCount: dayCount)
      var lastValue: Int32?
      for index in prices.indices {
        if prices[index] == CompactCardValueSeries.missingPrice {
          if let lastValue {
            prices[index] = lastValue
          }
        } else {
          lastValue = prices[index]
        }
      }
      importedPricePoints += prices.filter {
        $0 != CompactCardValueSeries.missingPrice
      }.count

      let finishValue = CardValueFinish(rawValue: finish)
      guard let finishValue else {
        throw CatalogStorageError.invalidCatalog("Compact price series has an unknown finish")
      }
      let normalizedSeries = CompactCardValueSeries(
        cardID: cardID,
        finish: finishValue,
        startDate: startDate,
        endDate: endDate,
        pricesInCents: prices
      )

      try normalizedInsert.bind(cardID, at: 1)
      try normalizedInsert.bind(provider, at: 2)
      try normalizedInsert.bind(finish, at: 3)
      try normalizedInsert.bind(startDate, at: 4)
      try normalizedInsert.bind(endDate, at: 5)
      try normalizedInsert.bind(dayCount, at: 6)
      try normalizedInsert.bind(normalizedSeries.encodedPrices, at: 7)
      try normalizedInsert.step()
      try normalizedInsert.reset()

      guard let summary = CardDatabase.recomputeValueSummary(
        pricesInCents: prices,
        endDate: endDate
      ) else {
        continue
      }
      try summaryInsert.bind(cardID, at: 1)
      try summaryInsert.bind(provider, at: 2)
      try summaryInsert.bind(finish, at: 3)
      try summaryInsert.bind(summary.currentPrice, at: 4)
      try summaryInsert.bind(summary.currentDate, at: 5)
      try summaryInsert.bind(summary.price1d, at: 6)
      try summaryInsert.bind(summary.price7d, at: 7)
      try summaryInsert.bind(summary.price30d, at: 8)
      try summaryInsert.bind(summary.price90d, at: 9)
      try summaryInsert.step()
      try summaryInsert.reset()
    }

    try database.execute("DELETE FROM card_value_series")
    try database.execute(
      """
      INSERT INTO card_value_series (
          card_id, provider, finish, start_date, end_date, day_count, prices_cents
      )
      SELECT card_id, provider, finish, start_date, end_date, day_count, prices_cents
      FROM normalized_card_value_series
      ORDER BY card_id, provider, finish
      """)
    return importedPricePoints
  }

  /// A recomputed `card_value_summaries` row, derived purely from a stored compact price series.
  public struct ValueSummaryComputation: Equatable, Sendable {
    public var currentPrice: Double
    public var currentDate: String
    public var price1d: Double?
    public var price7d: Double?
    public var price30d: Double?
    public var price90d: Double?
  }

  /// Recomputes the summary for one series from its stored (already forward-filled) compact price
  /// array, using the exact arithmetic of `finalizeCompactCardValueSeriesUnlocked`. This is the
  /// single source of truth for value summaries: the engine build calls it, and an on-device delta
  /// apply calls it too, so summaries are never shipped in a delta yet stay bit-identical to a full
  /// build. Returns `nil` when the series has no real (non-missing) price — matching the engine,
  /// which then writes no summary row for that series.
  public static func recomputeValueSummary(
    pricesInCents prices: [Int32],
    endDate: String
  ) -> ValueSummaryComputation? {
    guard let currentCents = prices.last(where: {
      $0 != CompactCardValueSeries.missingPrice
    }) else {
      return nil
    }
    return ValueSummaryComputation(
      currentPrice: Double(currentCents) / 100,
      currentDate: endDate,
      price1d: compactPreviousPrice(prices, days: 1),
      price7d: compactPreviousPrice(prices, days: 7),
      price30d: compactPreviousPrice(prices, days: 30),
      price90d: compactPreviousPrice(prices, days: 90)
    )
  }

  private static func compactPreviousPrice(_ prices: [Int32], days: Int) -> Double? {
    guard let currentIndex = prices.lastIndex(where: {
      $0 != CompactCardValueSeries.missingPrice
    }) else {
      return nil
    }
    let target = currentIndex - days
    guard target >= 0 else {
      return nil
    }
    for index in stride(from: target, through: 0, by: -1) {
      let cents = prices[index]
      if cents != CompactCardValueSeries.missingPrice {
        return Double(cents) / 100
      }
    }
    return nil
  }
}
