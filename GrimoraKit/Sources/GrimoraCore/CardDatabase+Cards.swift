import Foundation

extension CardDatabase {
  public func replaceAllCards(
    _ cards: [CardRecord],
    preservesCardValueHistory: Bool = false
  ) throws {
    let cards = Self.cardsByAddingDerivedMetadata(cards)

    try withDatabaseLock {
      try database.transaction {
        if preservesCardValueHistory {
          try database.execute("DROP TABLE IF EXISTS temp.preserved_card_value_mappings")
          try database.execute("DROP TABLE IF EXISTS temp.preserved_card_price_points")
          try database.execute("DROP TABLE IF EXISTS temp.preserved_card_value_summaries")
          try database.execute(
            "CREATE TEMP TABLE preserved_card_value_mappings AS SELECT * FROM card_value_mappings"
          )
          try database.execute(
            "CREATE TEMP TABLE preserved_card_price_points AS SELECT * FROM card_price_points"
          )
          try database.execute(
            "CREATE TEMP TABLE preserved_card_value_summaries AS SELECT * FROM card_value_summaries"
          )
        } else {
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
        try database.execute("DELETE FROM card_faces")
        try database.execute("DELETE FROM cards_name_fts")
        try database.execute("DELETE FROM cards_fts")
        try database.execute("DELETE FROM cards")

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
          """
          INSERT INTO cards_fts (card_id, search_text) VALUES (?, ?)
          """)

        let nameFTSInsert = try database.prepare(
          """
          INSERT INTO cards_name_fts (card_id, name_text) VALUES (?, ?)
          """)

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

        if preservesCardValueHistory {
          try database.execute(
            """
            INSERT INTO card_value_mappings (card_id, mtgjson_uuid)
            SELECT preserved.card_id, preserved.mtgjson_uuid
            FROM preserved_card_value_mappings preserved
            JOIN cards ON cards.id = preserved.card_id
            """)
          try database.execute(
            """
            INSERT INTO card_price_points (card_id, provider, finish, date, price)
            SELECT preserved.card_id, preserved.provider, preserved.finish, preserved.date, preserved.price
            FROM preserved_card_price_points preserved
            JOIN cards ON cards.id = preserved.card_id
            """)
          try database.execute(
            """
            INSERT INTO card_value_summaries (
                card_id, provider, finish, current_price, current_date,
                price_1d, price_7d, price_30d, price_90d
            )
            SELECT
                preserved.card_id, preserved.provider, preserved.finish,
                preserved.current_price, preserved.current_date,
                preserved.price_1d, preserved.price_7d, preserved.price_30d, preserved.price_90d
            FROM preserved_card_value_summaries preserved
            JOIN cards ON cards.id = preserved.card_id
            """)
          try database.execute("DROP TABLE IF EXISTS temp.preserved_card_value_mappings")
          try database.execute("DROP TABLE IF EXISTS temp.preserved_card_price_points")
          try database.execute("DROP TABLE IF EXISTS temp.preserved_card_value_summaries")
        }
      }
    }
  }

  public func deleteAllCardsPreservingLists() throws {
    try withDatabaseLock {
      try database.transaction {
        try database.execute("DELETE FROM card_faces")
        try database.execute("DELETE FROM cards_name_fts")
        try database.execute("DELETE FROM cards_fts")
        try database.execute("DELETE FROM cards")

        try saveMetadataValue(nil, forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.defaultCardsDownloadURI.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.defaultCardsName.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.defaultCardsSize.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.searchSchemaVersion.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.requiredImagesCached.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonCurrentPricesDate.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonCurrentPricesVersion.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonCurrentPricesCardDatabaseIdentity.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue)
        try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonPriceHistoryCardDatabaseIdentity.rawValue)
        try database.execute("DELETE FROM staging_card_price_points")
        try database.execute("DELETE FROM staging_card_value_mappings")
        try database.execute("DELETE FROM value_history_background_jobs")
      }
    }
  }

  public func clearStoredImagePaths() throws {
    try withDatabaseLock {
      try database.transaction {
        try database.execute(
          """
          UPDATE cards
          SET small_image_path = NULL,
              normal_image_path = NULL,
              large_image_path = NULL,
              art_crop_image_path = NULL
          """)
        try database.execute(
          """
          UPDATE card_faces
          SET small_image_path = NULL,
              normal_image_path = NULL,
              large_image_path = NULL,
              art_crop_image_path = NULL
          """)
        try saveMetadataValue("false", forKey: MetadataKey.requiredImagesCached.rawValue)
      }
    }
  }

  public func cardCount() throws -> Int {
    try withDatabaseLock {
      let statement = try database.prepare("SELECT COUNT(*) FROM cards")
      _ = try statement.step()
      return statement.int(at: 0) ?? 0
    }
  }

  public func isLibraryReady(fileManager: FileManager = .default) throws -> Bool {
    try withDatabaseLock {
      guard try cardCount() > 0 else {
        return false
      }

      return try metadataValue(forKey: MetadataKey.defaultCardsUpdatedAt.rawValue) != nil
        && metadataValue(forKey: MetadataKey.searchSchemaVersion.rawValue) == Self.currentSearchSchemaVersion
    }
  }

  public func missingStoredImageCount(fileManager: FileManager = .default) throws -> Int {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT COALESCE(small_image_path, normal_image_path) AS display_image_path
        FROM cards
        WHERE small_image_path IS NOT NULL OR normal_image_path IS NOT NULL
        UNION ALL
        SELECT COALESCE(small_image_path, normal_image_path) AS display_image_path
        FROM card_faces
        WHERE small_image_path IS NOT NULL OR normal_image_path IS NOT NULL
        UNION ALL
        SELECT art_crop_image_path AS display_image_path
        FROM cards
        WHERE art_crop_image_path IS NOT NULL
        UNION ALL
        SELECT art_crop_image_path AS display_image_path
        FROM card_faces
        WHERE art_crop_image_path IS NOT NULL
        """)

      var missingCount = 0
      while try statement.step() {
        guard let path = statement.string(at: 0) else {
          continue
        }

        if !fileManager.fileExists(atPath: path) {
          missingCount += 1
        }
      }

      return missingCount
    }
  }

  public func updateImagePaths(for card: CardRecord) throws {
    try withDatabaseLock {
      try database.transaction {
        let cardUpdate = try database.prepare(
          """
          UPDATE cards
          SET small_image_path = ?, normal_image_path = ?, large_image_path = ?, art_crop_image_path = ?
          WHERE id = ?
          """)
        try cardUpdate.bind(card.smallImagePath, at: 1)
        try cardUpdate.bind(card.normalImagePath, at: 2)
        try cardUpdate.bind(card.largeImagePath, at: 3)
        try cardUpdate.bind(card.artCropImagePath, at: 4)
        try cardUpdate.bind(card.id, at: 5)
        try cardUpdate.step()

        let faceUpdate = try database.prepare(
          """
          UPDATE card_faces
          SET small_image_path = ?, normal_image_path = ?, large_image_path = ?, art_crop_image_path = ?
          WHERE card_id = ? AND face_index = ?
          """)
        for face in card.faces {
          try faceUpdate.bind(face.smallImagePath, at: 1)
          try faceUpdate.bind(face.normalImagePath, at: 2)
          try faceUpdate.bind(face.largeImagePath, at: 3)
          try faceUpdate.bind(face.artCropImagePath, at: 4)
          try faceUpdate.bind(face.cardID, at: 5)
          try faceUpdate.bind(face.faceIndex, at: 6)
          try faceUpdate.step()
          try faceUpdate.reset()
        }
      }
    }
  }

  func mergeImagePaths(for card: CardRecord) throws -> CardRecord? {
    try withDatabaseLock {
      try database.transaction {
        let cardUpdate = try database.prepare(
          """
          UPDATE cards
          SET
              small_image_path = COALESCE(?, small_image_path),
              normal_image_path = COALESCE(?, normal_image_path),
              large_image_path = COALESCE(?, large_image_path),
              art_crop_image_path = COALESCE(?, art_crop_image_path)
          WHERE id = ?
          """)
        try cardUpdate.bind(card.smallImagePath, at: 1)
        try cardUpdate.bind(card.normalImagePath, at: 2)
        try cardUpdate.bind(card.largeImagePath, at: 3)
        try cardUpdate.bind(card.artCropImagePath, at: 4)
        try cardUpdate.bind(card.id, at: 5)
        try cardUpdate.step()

        let faceUpdate = try database.prepare(
          """
          UPDATE card_faces
          SET
              small_image_path = COALESCE(?, small_image_path),
              normal_image_path = COALESCE(?, normal_image_path),
              large_image_path = COALESCE(?, large_image_path),
              art_crop_image_path = COALESCE(?, art_crop_image_path)
          WHERE card_id = ? AND face_index = ?
          """)
        for face in card.faces {
          try faceUpdate.bind(face.smallImagePath, at: 1)
          try faceUpdate.bind(face.normalImagePath, at: 2)
          try faceUpdate.bind(face.largeImagePath, at: 3)
          try faceUpdate.bind(face.artCropImagePath, at: 4)
          try faceUpdate.bind(face.cardID, at: 5)
          try faceUpdate.bind(face.faceIndex, at: 6)
          try faceUpdate.step()
          try faceUpdate.reset()
        }
      }

      return try self.card(id: card.id)
    }
  }

  public func card(id: String) throws -> CardRecord? {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT \(Self.cardColumns)
        FROM cards
        WHERE id = ?
        LIMIT 1
        """)
      try statement.bind(id, at: 1)

      guard try statement.step() else {
        return nil
      }

      var card = readCard(from: statement)
      card.faces = try fetchFaces(for: card.id)
      return card
    }
  }

  public func card(setCode: String, collectorNumber: String) throws -> CardRecord? {
    let normalizedSetCode = setCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedCollectorNumber = collectorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSetCode.isEmpty, !normalizedCollectorNumber.isEmpty else {
      return nil
    }

    return try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT \(Self.cardColumns)
        FROM cards
        WHERE set_code = ? COLLATE NOCASE
            AND collector_number = ? COLLATE NOCASE
        ORDER BY \(Self.preferredPrintingOrderClause(preferences: []))
        LIMIT 1
        """)
      try statement.bind(normalizedSetCode, at: 1)
      try statement.bind(normalizedCollectorNumber, at: 2)

      guard try statement.step() else {
        return nil
      }

      var card = readCard(from: statement)
      card.faces = try fetchFaces(for: card.id)
      return card
    }
  }
}
