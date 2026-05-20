import Foundation

extension CardDatabase {
  public func valueGuide(forCardID cardID: CardRecord.ID) throws -> CardValueGuide {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT finish, current_price, "current_date", price_1d, price_7d, price_30d, price_90d
        FROM card_value_summaries
        WHERE card_id = ?
            AND provider = ?
        ORDER BY
            CASE finish
                WHEN 'normal' THEN 0
                WHEN 'foil' THEN 1
                WHEN 'etched' THEN 2
                ELSE 3
            END ASC
        """)
      try statement.bind(cardID, at: 1)
      try statement.bind(CardValueProvider.tcgplayer.rawValue, at: 2)

      var entries: [CardValueGuideEntry] = []
      while try statement.step() {
        guard let finishRaw = statement.string(at: 0),
          let finish = CardValueFinish(rawValue: finishRaw),
          let currentPrice = statement.double(at: 1),
          let currentDate = statement.string(at: 2)
        else {
          continue
        }

        entries.append(
          CardValueGuideEntry(
            finish: finish,
            currentPrice: currentPrice,
            currentDate: currentDate,
            oneDay: statement.double(at: 3).map {
              CardValueMovement(days: 1, currentPrice: currentPrice, previousPrice: $0)
            },
            sevenDay: statement.double(at: 4).map {
              CardValueMovement(days: 7, currentPrice: currentPrice, previousPrice: $0)
            },
            thirtyDay: statement.double(at: 5).map {
              CardValueMovement(days: 30, currentPrice: currentPrice, previousPrice: $0)
            },
            ninetyDay: statement.double(at: 6).map {
              CardValueMovement(days: 90, currentPrice: currentPrice, previousPrice: $0)
            },
            history: try valueHistoryPointsUnlocked(
              forCardID: cardID,
              provider: .tcgplayer,
              finish: finish,
              currentDate: currentDate
            )
          ))
      }

      if entries.isEmpty {
        return try scryfallSnapshotValueGuideUnlocked(forCardID: cardID)
      }

      return CardValueGuide(cardID: cardID, entries: entries)
    }
  }

  public func valueSummaryCount() throws -> Int {
    try withDatabaseLock {
      let statement = try database.prepare("SELECT COUNT(*) FROM card_value_summaries")
      _ = try statement.step()
      return statement.int(at: 0) ?? 0
    }
  }

  private func valueHistoryPointsUnlocked(
    forCardID cardID: CardRecord.ID,
    provider: CardValueProvider,
    finish: CardValueFinish,
    currentDate: String
  ) throws -> [CardValueHistoryPoint] {
    let statement = try database.prepare(
      """
      SELECT "date", price
      FROM card_price_points
      WHERE card_id = ?
          AND provider = ?
          AND finish = ?
          AND "date" >= date(?, '-90 day')
          AND "date" <= ?
      ORDER BY "date" ASC
      """)
    try statement.bind(cardID, at: 1)
    try statement.bind(provider.rawValue, at: 2)
    try statement.bind(finish.rawValue, at: 3)
    try statement.bind(currentDate, at: 4)
    try statement.bind(currentDate, at: 5)

    var points: [CardValueHistoryPoint] = []
    while try statement.step() {
      guard let date = statement.string(at: 0),
        let price = statement.double(at: 1)
      else {
        continue
      }
      points.append(CardValueHistoryPoint(date: date, price: price))
    }
    return points
  }

  func hasUsableValueSummaryCoverage() throws -> Bool {
    try withDatabaseLock {
      let cardCountStatement = try database.prepare("SELECT COUNT(*) FROM cards")
      _ = try cardCountStatement.step()
      let cardCount = cardCountStatement.int(at: 0) ?? 0
      guard cardCount > 0 else {
        return false
      }

      let summaryCardStatement = try database.prepare(
        "SELECT COUNT(DISTINCT card_id) FROM card_value_summaries"
      )
      _ = try summaryCardStatement.step()
      let summaryCardCount = summaryCardStatement.int(at: 0) ?? 0
      guard summaryCardCount > 0 else {
        return false
      }

      if cardCount < 100 {
        return true
      }

      let minimumExpectedCoverage = min(10_000, max(100, cardCount / 5))
      return summaryCardCount >= minimumExpectedCoverage
    }
  }

  func localCardIDSet() throws -> Set<CardRecord.ID> {
    try withDatabaseLock {
      let statement = try database.prepare("SELECT id FROM cards")
      var cardIDs: Set<CardRecord.ID> = []
      while try statement.step() {
        if let cardID = statement.string(at: 0) {
          cardIDs.insert(cardID)
        }
      }
      return cardIDs
    }
  }

  func clearCardValueHistory() throws {
    try withDatabaseLock {
      try database.transaction {
        try clearCardValueHistoryUnlocked()
      }
    }
  }

  func replaceCardValueHistory(
    meta: MTGJSONPriceHistoryMeta,
    mappingsByMTGJSONUUID: [String: CardRecord.ID],
    importPricePoints: (CardPricePointWriter) throws -> Int
  ) throws -> MTGJSONPriceImportSummary {
    try withDatabaseLock {
      var summary = MTGJSONPriceImportSummary(mappedCards: 0, importedPricePoints: 0)
      try database.transaction {
        try clearCardValueHistoryUnlocked()

        let mappingInsert = try database.prepare(
          """
          INSERT INTO card_value_mappings (card_id, mtgjson_uuid)
          VALUES (?, ?)
          """)
        for (uuid, cardID) in mappingsByMTGJSONUUID {
          try mappingInsert.bind(cardID, at: 1)
          try mappingInsert.bind(uuid, at: 2)
          try mappingInsert.step()
          try mappingInsert.reset()
        }

        let priceInsert = try database.prepare(
          """
          INSERT OR REPLACE INTO card_price_points (card_id, provider, finish, date, price)
          VALUES (?, ?, ?, ?, ?)
          """)
        let writer = CardPricePointWriter(statement: priceInsert)
        let importedPricePoints = try importPricePoints(writer)
        try rebuildCardValueSummariesUnlocked()
        try saveMetadataValue(meta.date, forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue)
        try saveMetadataValue(meta.version, forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue)
        try saveMetadataValue(
          try valueHistoryCardDatabaseIdentityUnlocked(),
          forKey: MetadataKey.mtgjsonPriceHistoryCardDatabaseIdentity.rawValue
        )
        summary = MTGJSONPriceImportSummary(
          mappedCards: mappingsByMTGJSONUUID.count,
          importedPricePoints: importedPricePoints
        )
      }
      return summary
    }
  }

  func upsertCurrentCardValues(
    meta: MTGJSONPriceHistoryMeta,
    mappingsByMTGJSONUUID: [String: CardRecord.ID],
    importPricePoints: (CardPricePointWriter) throws -> Int
  ) throws -> MTGJSONPriceImportSummary {
    try withDatabaseLock {
      var summary = MTGJSONPriceImportSummary(mappedCards: 0, importedPricePoints: 0)
      try database.transaction {
        let mappingInsert = try database.prepare(
          """
          INSERT OR REPLACE INTO card_value_mappings (card_id, mtgjson_uuid)
          VALUES (?, ?)
          """)
        for (uuid, cardID) in mappingsByMTGJSONUUID {
          try mappingInsert.bind(cardID, at: 1)
          try mappingInsert.bind(uuid, at: 2)
          try mappingInsert.step()
          try mappingInsert.reset()
        }

        let priceInsert = try database.prepare(
          """
          INSERT OR REPLACE INTO card_price_points (card_id, provider, finish, date, price)
          VALUES (?, ?, ?, ?, ?)
          """)
        let writer = CardPricePointWriter(statement: priceInsert)
        let importedPricePoints = try importPricePoints(writer)
        try rebuildCardValueSummariesUnlocked()
        try saveMetadataValue(meta.date, forKey: MetadataKey.mtgjsonCurrentPricesDate.rawValue)
        try saveMetadataValue(meta.version, forKey: MetadataKey.mtgjsonCurrentPricesVersion.rawValue)
        try saveMetadataValue(
          try valueHistoryCardDatabaseIdentityUnlocked(),
          forKey: MetadataKey.mtgjsonCurrentPricesCardDatabaseIdentity.rawValue
        )
        summary = MTGJSONPriceImportSummary(
          mappedCards: mappingsByMTGJSONUUID.count,
          importedPricePoints: importedPricePoints
        )
      }
      return summary
    }
  }

  func clearCardValueHistoryUnlocked() throws {
    try database.execute("DELETE FROM card_value_summaries")
    try database.execute("DELETE FROM card_price_points")
    try database.execute("DELETE FROM card_value_mappings")
    try database.execute("DELETE FROM staging_card_price_points")
    try database.execute("DELETE FROM staging_card_value_mappings")
    try database.execute("DELETE FROM value_history_background_jobs")
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonCurrentPricesDate.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonCurrentPricesVersion.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonCurrentPricesCardDatabaseIdentity.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonPriceHistoryCardDatabaseIdentity.rawValue)
  }

  func rebuildCardValueSummariesUnlocked() throws {
    try database.execute("DELETE FROM card_value_summaries")
    try database.execute(
      """
      INSERT OR REPLACE INTO card_value_summaries (
          card_id, provider, finish, current_price, "current_date",
          price_1d, price_7d, price_30d, price_90d
      )
      WITH latest AS (
          SELECT card_id, provider, finish, MAX(card_price_points."date") AS latest_price_date
          FROM card_price_points
          GROUP BY card_id, provider, finish
      )
      SELECT
          latest.card_id,
          latest.provider,
          latest.finish,
          current.price,
          latest.latest_price_date,
          (
              SELECT previous.price
              FROM card_price_points previous
              WHERE previous.card_id = latest.card_id
                  AND previous.provider = latest.provider
                  AND previous.finish = latest.finish
                  AND previous."date" <= date(latest.latest_price_date, '-1 day')
              ORDER BY previous."date" DESC
              LIMIT 1
          ) AS price_1d,
          (
              SELECT previous.price
              FROM card_price_points previous
              WHERE previous.card_id = latest.card_id
                  AND previous.provider = latest.provider
                  AND previous.finish = latest.finish
                  AND previous."date" <= date(latest.latest_price_date, '-7 day')
              ORDER BY previous."date" DESC
              LIMIT 1
          ) AS price_7d,
          (
              SELECT previous.price
              FROM card_price_points previous
              WHERE previous.card_id = latest.card_id
                  AND previous.provider = latest.provider
                  AND previous.finish = latest.finish
                  AND previous."date" <= date(latest.latest_price_date, '-30 day')
              ORDER BY previous."date" DESC
              LIMIT 1
          ) AS price_30d,
          (
              SELECT previous.price
              FROM card_price_points previous
              WHERE previous.card_id = latest.card_id
                  AND previous.provider = latest.provider
                  AND previous.finish = latest.finish
                  AND previous."date" <= date(latest.latest_price_date, '-90 day')
              ORDER BY previous."date" DESC
              LIMIT 1
          ) AS price_90d
      FROM latest
      JOIN card_price_points current
          ON current.card_id = latest.card_id
          AND current.provider = latest.provider
          AND current.finish = latest.finish
          AND current."date" = latest.latest_price_date
      """)
  }

  private func scryfallSnapshotValueGuideUnlocked(forCardID cardID: CardRecord.ID) throws -> CardValueGuide {
    let statement = try database.prepare("SELECT price_usd FROM cards WHERE id = ?")
    try statement.bind(cardID, at: 1)
    guard try statement.step(), let priceUSD = statement.double(at: 0) else {
      return CardValueGuide(cardID: cardID)
    }

    let snapshotDate = try metadataValue(forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
      .map(Self.valueSnapshotDisplayDate)
      ?? "local snapshot"
    return CardValueGuide(
      cardID: cardID,
      sourceName: "Scryfall local price snapshot",
      entries: [
        CardValueGuideEntry(
          finish: .normal,
          currentPrice: priceUSD,
          currentDate: snapshotDate
        )
      ]
    )
  }

  private static func valueSnapshotDisplayDate(_ value: String) -> String {
    guard let separator = value.firstIndex(of: "T") else {
      return value
    }
    return String(value[..<separator])
  }
}

enum CardValueProvider: String, Sendable {
  case tcgplayer
}

final class CardPricePointWriter {
  private let statement: SQLiteStatement

  init(statement: SQLiteStatement) {
    self.statement = statement
  }

  func insert(
    cardID: CardRecord.ID,
    provider: CardValueProvider,
    finish: CardValueFinish,
    date: String,
    price: Double
  ) throws {
    try statement.bind(cardID, at: 1)
    try statement.bind(provider.rawValue, at: 2)
    try statement.bind(finish.rawValue, at: 3)
    try statement.bind(date, at: 4)
    try statement.bind(price, at: 5)
    try statement.step()
    try statement.reset()
  }
}
