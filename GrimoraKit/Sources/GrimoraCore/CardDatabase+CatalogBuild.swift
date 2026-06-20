import Foundation

public struct CatalogBuildProgress: Equatable, Sendable {
  public enum Stage: String, Equatable, Sendable {
    case preparing
    case writingCards
    case derivingMetadata
    case finalizingIndexes
    case validating
    case compacting
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

extension CardDatabase {
  public func resetForStreamingCatalogBuild() throws {
    guard !usesExternalCatalog else {
      throw CatalogStorageError.invalidCatalog("Cannot build into an attached catalog")
    }
    try deleteAllCardsPreservingLists()
  }

  public func appendCatalogCards(_ cards: [CardRecord]) throws {
    guard !usesExternalCatalog else {
      throw CatalogStorageError.invalidCatalog("Cannot build into an attached catalog")
    }
    guard !cards.isEmpty else {
      return
    }

    try withDatabaseLock {
      try database.transaction {
        let placeholders = Array(repeating: "?", count: Self.insertCardColumns.count)
          .joined(separator: ", ")
        let cardInsert = try database.prepare(
          """
          INSERT INTO cards (\(Self.insertCardColumns.joined(separator: ", ")))
          VALUES (\(placeholders))
          """)
        let faceInsert = try database.prepare(
          """
          INSERT INTO card_faces (
              card_id, face_index, name, type_line, oracle_text,
              small_image_path, normal_image_path, large_image_path,
              art_crop_image_path, small_image_url, normal_image_url, large_image_url,
              art_crop_image_url
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """)
        let ftsInsert = try database.prepare(
          "INSERT INTO cards_fts (card_id, search_text) VALUES (?, ?)"
        )
        let nameFTSInsert = try database.prepare(
          "INSERT INTO cards_name_fts (card_id, name_text) VALUES (?, ?)"
        )

        for card in cards {
          try bind(card, to: cardInsert)
          try cardInsert.step()
          try cardInsert.reset()

          for face in card.faces {
            try faceInsert.bind(face.cardID, at: 1)
            try faceInsert.bind(face.faceIndex, at: 2)
            try faceInsert.bind(face.name, at: 3)
            try faceInsert.bind(face.typeLine, at: 4)
            try faceInsert.bind(face.oracleText, at: 5)
            try faceInsert.bind(face.smallImagePath, at: 6)
            try faceInsert.bind(face.normalImagePath, at: 7)
            try faceInsert.bind(face.largeImagePath, at: 8)
            try faceInsert.bind(face.artCropImagePath, at: 9)
            try faceInsert.bind(face.smallImageURL, at: 10)
            try faceInsert.bind(face.normalImageURL, at: 11)
            try faceInsert.bind(face.largeImageURL, at: 12)
            try faceInsert.bind(face.artCropImageURL, at: 13)
            try faceInsert.step()
            try faceInsert.reset()
          }

          try ftsInsert.bind(card.id, at: 1)
          try ftsInsert.bind(card.searchText, at: 2)
          try ftsInsert.step()
          try ftsInsert.reset()

          try nameFTSInsert.bind(card.id, at: 1)
          try nameFTSInsert.bind(card.name, at: 2)
          try nameFTSInsert.step()
          try nameFTSInsert.reset()
        }
      }
    }
  }

  public func finalizeStreamingCatalogBuild(
    sources: CatalogSourceVersions,
    progress: ((CatalogBuildProgress) -> Void)? = nil
  ) throws {
    guard !usesExternalCatalog else {
      throw CatalogStorageError.invalidCatalog("Cannot finalize an attached catalog")
    }

    try withDatabaseLock {
      progress?(CatalogBuildProgress(stage: .derivingMetadata))
      try deriveCatalogMetadata()

      progress?(CatalogBuildProgress(stage: .finalizingIndexes))
      try database.execute("INSERT INTO cards_fts(cards_fts) VALUES('optimize')")
      try database.execute("INSERT INTO cards_name_fts(cards_name_fts) VALUES('optimize')")
      try saveMetadataValue(sources.scryfallUpdatedAt, forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
      try saveMetadataValue("Grimora Catalog", forKey: MetadataKey.defaultCardsName.rawValue)
      try saveMetadataValue(Self.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
      try saveMetadataValue("\(CatalogManifest.currentSchemaVersion)", forKey: MetadataKey.catalogSchemaVersion.rawValue)
      try saveMetadataValue(sources.mtgjsonDate, forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue)
      try saveMetadataValue(sources.mtgjsonVersion, forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue)

      progress?(CatalogBuildProgress(stage: .validating))
      guard try database.quickCheck() == "ok" else {
        throw CatalogStorageError.invalidCatalog("SQLite quick_check failed before compaction")
      }
      let cardCount = try Self.catalogRowCount(in: "cards", database: database)
      let ftsCount = try Self.catalogRowCount(in: "cards_fts", database: database)
      let nameFTSCount = try Self.catalogRowCount(in: "cards_name_fts", database: database)
      guard cardCount > 0, ftsCount == cardCount, nameFTSCount == cardCount else {
        throw CatalogStorageError.invalidCatalog(
          "Card and search index counts differ: cards=\(cardCount), fts=\(ftsCount), nameFTS=\(nameFTSCount)"
        )
      }

      progress?(CatalogBuildProgress(stage: .compacting))
      try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
      try database.execute("VACUUM")
      guard try database.quickCheck() == "ok" else {
        throw CatalogStorageError.invalidCatalog("SQLite quick_check failed after compaction")
      }
    }
  }

  private func deriveCatalogMetadata() throws {
    try database.transaction {
      try database.execute("DROP TABLE IF EXISTS temp.catalog_card_groups")
      try database.execute(
        """
        CREATE TEMP TABLE catalog_card_groups AS
        SELECT
            COALESCE(oracle_id, name_key) AS group_key,
            COUNT(*) AS print_count,
            COUNT(DISTINCT lower(set_code)) AS set_count,
            SUM(CASE WHEN games_key LIKE '%|paper|%' THEN 1 ELSE 0 END) AS paper_print_count,
            COUNT(DISTINCT CASE WHEN games_key LIKE '%|paper|%' THEN lower(set_code) END) AS paper_set_count,
            COUNT(DISTINCT NULLIF(artist_key, '')) AS artist_count,
            COUNT(DISTINCT NULLIF(illustration_id, '')) AS illustration_count
        FROM cards
        GROUP BY COALESCE(oracle_id, name_key)
        """)
      try database.execute(
        "CREATE UNIQUE INDEX temp.idx_catalog_card_groups_key ON catalog_card_groups(group_key)"
      )
      try database.execute(
        """
        UPDATE cards
        SET
            print_count = (
                SELECT print_count FROM temp.catalog_card_groups
                WHERE group_key = COALESCE(cards.oracle_id, cards.name_key)
            ),
            set_count = (
                SELECT set_count FROM temp.catalog_card_groups
                WHERE group_key = COALESCE(cards.oracle_id, cards.name_key)
            ),
            paper_print_count = (
                SELECT paper_print_count FROM temp.catalog_card_groups
                WHERE group_key = COALESCE(cards.oracle_id, cards.name_key)
            ),
            paper_set_count = (
                SELECT paper_set_count FROM temp.catalog_card_groups
                WHERE group_key = COALESCE(cards.oracle_id, cards.name_key)
            ),
            artist_count = (
                SELECT artist_count FROM temp.catalog_card_groups
                WHERE group_key = COALESCE(cards.oracle_id, cards.name_key)
            ),
            illustration_count = (
                SELECT illustration_count FROM temp.catalog_card_groups
                WHERE group_key = COALESCE(cards.oracle_id, cards.name_key)
            )
        """)

      for (valueColumn, flagColumn) in [
        ("illustration_id", "is_new_art"),
        ("artist_key", "is_new_artist"),
        ("flavor_text_key", "is_new_flavor"),
        ("rarity", "is_new_rarity"),
        ("frame", "is_new_frame"),
        ("lang", "is_new_language"),
      ] {
        try deriveFirstOccurrenceFlag(valueColumn: valueColumn, flagColumn: flagColumn)
      }
      try database.execute("DROP TABLE IF EXISTS temp.catalog_card_groups")
    }
  }

  private func deriveFirstOccurrenceFlag(
    valueColumn: String,
    flagColumn: String
  ) throws {
    try database.execute(
      """
      WITH ranked AS (
          SELECT
              id,
              ROW_NUMBER() OVER (
                  PARTITION BY COALESCE(oracle_id, name_key), \(valueColumn)
                  ORDER BY
                      released_at IS NOT NULL ASC,
                      released_at ASC,
                      set_code ASC,
                      collector_number_number IS NULL ASC,
                      collector_number_number ASC,
                      collector_number ASC,
                      id ASC
              ) AS occurrence
          FROM cards
          WHERE \(valueColumn) IS NOT NULL AND \(valueColumn) <> ''
      )
      UPDATE cards
      SET \(flagColumn) = CASE
          WHEN id IN (SELECT id FROM ranked WHERE occurrence = 1) THEN 1
          ELSE 0
      END
      """)
  }

  private static func catalogRowCount(
    in table: String,
    database: SQLiteDatabase
  ) throws -> Int {
    let statement = try database.prepare("SELECT COUNT(*) FROM \(table)")
    _ = try statement.step()
    return statement.int(at: 0) ?? 0
  }
}
