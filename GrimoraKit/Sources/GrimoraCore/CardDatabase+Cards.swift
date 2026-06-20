import Foundation

private struct CardValueHistoryClearTable {
  var name: String
  var chunkSize: Int
}

public enum CardDatabaseWritePhase: Equatable, Sendable {
  case preparingMetadata
  case preservingValueHistory
  case clearingValueHistoryCache
  case resettingCachedLibrary
  case resettingSearchIndex
  case clearingExistingLibrary
  case writingCards
  case restoringValueHistory
}

public enum CardDatabaseMaintenanceError: Error, Equatable, Sendable {
  case clearValueHistoryCacheStalled(table: String, remainingRows: Int)
  case clearValueHistoryCacheTimedOut(table: String, remainingRows: Int, seconds: Int)
  case clearExistingLibraryStalled(table: String, remainingRows: Int)
  case clearExistingLibraryTimedOut(table: String, remainingRows: Int, seconds: Int)
  case resetSearchIndexTimedOut(seconds: Int)
}

public struct CardDatabaseWriteProgress: Equatable, Sendable {
  public var phase: CardDatabaseWritePhase
  public var completedUnitCount: Int
  public var totalUnitCount: Int?

  public var writtenCards: Int {
    phase == .writingCards ? completedUnitCount : 0
  }

  public var totalCards: Int {
    phase == .writingCards ? totalUnitCount ?? 0 : 0
  }

  public var progressFraction: Double? {
    guard let totalUnitCount else {
      return nil
    }
    guard totalUnitCount > 0 else {
      return 1
    }
    return Double(completedUnitCount) / Double(totalUnitCount)
  }

  public var fraction: Double {
    progressFraction ?? 0
  }

  public init(
    phase: CardDatabaseWritePhase,
    completedUnitCount: Int = 0,
    totalUnitCount: Int? = nil
  ) {
    self.phase = phase
    if let totalUnitCount {
      let clampedTotal = max(totalUnitCount, 0)
      self.totalUnitCount = clampedTotal
      self.completedUnitCount = min(max(completedUnitCount, 0), clampedTotal)
    } else {
      self.totalUnitCount = nil
      self.completedUnitCount = max(completedUnitCount, 0)
    }
  }

  public init(writtenCards: Int, totalCards: Int) {
    self.init(
      phase: .writingCards,
      completedUnitCount: writtenCards,
      totalUnitCount: totalCards
    )
  }
}

extension CardDatabase {
  public func replaceAllCards(
    _ cards: [CardRecord],
    preservesCardValueHistory: Bool = false,
    progress: ((CardDatabaseWriteProgress) -> Void)? = nil
  ) throws {
    guard !usesExternalCatalog else {
      throw CatalogStorageError.invalidCatalog("Attached catalogs are replaced as files")
    }
    let cards = Self.cardsByAddingDerivedMetadata(cards, progress: progress)
    let totalCards = cards.count

    try withDatabaseLock {
      if preservesCardValueHistory {
        progress?(CardDatabaseWriteProgress(phase: .preservingValueHistory))
        try database.execute("DROP TABLE IF EXISTS temp.preserved_card_value_mappings")
        try database.execute("DROP TABLE IF EXISTS temp.preserved_card_price_points")
        try database.execute("DROP TABLE IF EXISTS temp.preserved_card_value_summaries")
        try database.execute("DROP TABLE IF EXISTS temp.preserved_value_history_background_jobs")
        try database.execute(
          "CREATE TEMP TABLE preserved_card_value_mappings AS SELECT * FROM card_value_mappings"
        )
        try database.execute(
          "CREATE TEMP TABLE preserved_card_price_points AS SELECT * FROM card_price_points"
        )
        try database.execute(
          "CREATE TEMP TABLE preserved_card_value_summaries AS SELECT * FROM card_value_summaries"
        )
        try database.execute(
          "CREATE TEMP TABLE preserved_value_history_background_jobs AS SELECT * FROM value_history_background_jobs"
        )
      }

      try resetDisposableLibraryTables(progress: progress)

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
          """
          INSERT INTO cards_fts (card_id, search_text) VALUES (?, ?)
          """)

        let nameFTSInsert = try database.prepare(
          """
          INSERT INTO cards_name_fts (card_id, name_text) VALUES (?, ?)
          """)

        var writtenCards = 0
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

          writtenCards += 1
          if Self.shouldReportCardWriteProgress(writtenCards: writtenCards, totalCards: totalCards) {
            progress?(CardDatabaseWriteProgress(writtenCards: writtenCards, totalCards: totalCards))
          }
        }

        if preservesCardValueHistory {
          progress?(CardDatabaseWriteProgress(phase: .restoringValueHistory))
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
          try database.execute(
            """
            INSERT INTO value_history_background_jobs (
                id, mtgjson_date, mtgjson_version, card_database_identity, stage, status,
                downloaded_bytes, total_download_bytes, scanned_bytes, total_scan_bytes,
                imported_price_points, created_at, updated_at, completed_at, last_error
            )
            SELECT
                id, mtgjson_date, mtgjson_version, card_database_identity, stage, status,
                downloaded_bytes, total_download_bytes, scanned_bytes, total_scan_bytes,
                imported_price_points, created_at, updated_at, completed_at, last_error
            FROM preserved_value_history_background_jobs
            """)
          try database.execute("DROP TABLE IF EXISTS temp.preserved_card_value_mappings")
          try database.execute("DROP TABLE IF EXISTS temp.preserved_card_price_points")
          try database.execute("DROP TABLE IF EXISTS temp.preserved_card_value_summaries")
          try database.execute("DROP TABLE IF EXISTS temp.preserved_value_history_background_jobs")
        }
      }
    }
  }

  static func shouldReportCardWriteProgress(writtenCards: Int, totalCards: Int) -> Bool {
    totalCards > 0
      && (writtenCards == 1 || writtenCards == totalCards || writtenCards.isMultiple(of: 1_000))
  }

  private func resetDisposableLibraryTables(progress: ((CardDatabaseWriteProgress) -> Void)?) throws {
    progress?(
      CardDatabaseWriteProgress(
        phase: .resettingCachedLibrary,
        completedUnitCount: 0,
        totalUnitCount: Self.resetCachedLibraryStepCount
      ))

    let tableGroups = Self.disposableLibraryTableGroups
    for (index, tableGroup) in tableGroups.enumerated() {
      try dropTables(tableGroup)
      progress?(
        CardDatabaseWriteProgress(
          phase: .resettingCachedLibrary,
          completedUnitCount: index + 1,
          totalUnitCount: Self.resetCachedLibraryStepCount
        ))
    }

    try clearLibraryImportMetadata()
    try migrate()
    progress?(
      CardDatabaseWriteProgress(
        phase: .resettingCachedLibrary,
        completedUnitCount: Self.resetCachedLibraryStepCount,
        totalUnitCount: Self.resetCachedLibraryStepCount
      ))
  }

  private func dropTables(_ tableNames: [String]) throws {
    for tableName in tableNames {
      do {
        try database.execute(
          "DROP TABLE IF EXISTS \(tableName)",
          interruptingAfter: Self.clearExistingLibraryStatementTimeout
        )
      } catch SQLiteError.executionFailed(let message) where Self.isSQLiteInterruptMessage(message) {
        throw CardDatabaseMaintenanceError.clearValueHistoryCacheTimedOut(
          table: tableName,
          remainingRows: 0,
          seconds: Self.clearExistingLibraryStatementTimeoutSeconds
        )
      }
    }
  }

  private func clearLibraryImportMetadata() throws {
    try saveMetadataValue(nil, forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.defaultCardsDownloadURI.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.defaultCardsName.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.defaultCardsSize.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.searchSchemaVersion.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.requiredImagesCached.rawValue)
    try clearCardValueHistoryMetadata()
  }

  private func clearExistingCardData(progress: ((CardDatabaseWriteProgress) -> Void)?) throws {
    let totalRows = try rowCount(in: "card_faces") + rowCount(in: "cards")
    var clearedRows = 0
    progress?(
      CardDatabaseWriteProgress(
        phase: .clearingExistingLibrary,
        completedUnitCount: clearedRows,
        totalUnitCount: totalRows
      ))

    progress?(CardDatabaseWriteProgress(phase: .resettingSearchIndex))
    try recreateSearchIndexTables()
    let timeoutError: (String, Int) -> CardDatabaseMaintenanceError = { tableName, remainingRows in
      CardDatabaseMaintenanceError.clearExistingLibraryTimedOut(
        table: tableName,
        remainingRows: remainingRows,
        seconds: Self.clearExistingLibraryStatementTimeoutSeconds
      )
    }
    let stalledError: (String, Int) -> CardDatabaseMaintenanceError = { tableName, remainingRows in
      CardDatabaseMaintenanceError.clearExistingLibraryStalled(
        table: tableName,
        remainingRows: remainingRows
      )
    }

    clearedRows += try deleteRowsInChunks(
      from: "card_faces",
      completedRows: clearedRows,
      totalRows: totalRows,
      phase: .clearingExistingLibrary,
      chunkSize: Self.clearExistingLibraryChunkSize,
      timeoutError: timeoutError,
      stalledError: stalledError,
      progress: progress
    )
    _ = try deleteRowsInChunks(
      from: "cards",
      completedRows: clearedRows,
      totalRows: totalRows,
      phase: .clearingExistingLibrary,
      chunkSize: Self.clearExistingLibraryChunkSize,
      timeoutError: timeoutError,
      stalledError: stalledError,
      progress: progress
    )
  }

  func clearCardValueHistoryRowsUnlocked(
    includingBackgroundJobs: Bool,
    clearsMetadata: Bool
  ) throws {
    try clearCardValueHistoryRows(
      includingBackgroundJobs: includingBackgroundJobs,
      clearsMetadata: clearsMetadata,
      progress: nil
    )
  }

  private func clearCardValueHistoryRows(
    includingBackgroundJobs: Bool,
    clearsMetadata: Bool,
    progress: ((CardDatabaseWriteProgress) -> Void)?
  ) throws {
    let tables = cardValueHistoryTablesToClear(includingBackgroundJobs: includingBackgroundJobs)
    progress?(CardDatabaseWriteProgress(phase: .clearingValueHistoryCache))
    let totalRows = try tables.reduce(0) { try $0 + rowCount(in: $1.name) }
    guard totalRows > 0 else {
      if clearsMetadata {
        try clearCardValueHistoryMetadata()
      }
      return
    }

    var clearedRows = 0
    progress?(
      CardDatabaseWriteProgress(
        phase: .clearingValueHistoryCache,
        completedUnitCount: clearedRows,
        totalUnitCount: totalRows
      ))
    for table in tables {
      clearedRows += try deleteRowsInChunks(
        from: table.name,
        completedRows: clearedRows,
        totalRows: totalRows,
        phase: .clearingValueHistoryCache,
        chunkSize: table.chunkSize,
        timeoutError: { tableName, remainingRows in
          CardDatabaseMaintenanceError.clearValueHistoryCacheTimedOut(
            table: tableName,
            remainingRows: remainingRows,
            seconds: Self.clearExistingLibraryStatementTimeoutSeconds
          )
        },
        stalledError: { tableName, remainingRows in
          CardDatabaseMaintenanceError.clearValueHistoryCacheStalled(
            table: tableName,
            remainingRows: remainingRows
          )
        },
        progress: progress
      )
    }

    if clearsMetadata {
      try clearCardValueHistoryMetadata()
    }
  }

  private func cardValueHistoryTablesToClear(
    includingBackgroundJobs: Bool
  ) -> [CardValueHistoryClearTable] {
    var tables = [
      CardValueHistoryClearTable(name: "staging_card_price_points", chunkSize: Self.clearValueHistoryCacheChunkSize),
      CardValueHistoryClearTable(name: "staging_card_value_mappings", chunkSize: Self.clearValueHistoryCacheChunkSize),
      CardValueHistoryClearTable(name: "card_value_series", chunkSize: Self.clearValueHistoryCacheChunkSize),
      CardValueHistoryClearTable(name: "card_value_summaries", chunkSize: Self.clearValueHistoryCacheChunkSize),
      CardValueHistoryClearTable(name: "card_price_points", chunkSize: Self.clearValueHistoryCacheChunkSize),
      CardValueHistoryClearTable(name: "card_value_mappings", chunkSize: Self.clearValueHistoryCacheChunkSize),
    ]

    if includingBackgroundJobs {
      tables.append(
        CardValueHistoryClearTable(name: "value_history_background_jobs", chunkSize: Self.clearExistingLibraryChunkSize)
      )
    }

    return tables
  }

  private func clearCardValueHistoryMetadata() throws {
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonCurrentPricesDate.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonCurrentPricesVersion.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonCurrentPricesCardDatabaseIdentity.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue)
    try saveMetadataValue(nil, forKey: MetadataKey.mtgjsonPriceHistoryCardDatabaseIdentity.rawValue)
  }

  private func rowCount(in tableName: String) throws -> Int {
    let statement = try database.prepare("SELECT COUNT(*) FROM \(tableName)")
    _ = try statement.step()
    return statement.int(at: 0) ?? 0
  }

  private func deleteRowsInChunks(
    from tableName: String,
    completedRows: Int,
    totalRows: Int,
    phase: CardDatabaseWritePhase,
    chunkSize: Int,
    timeoutError: (String, Int) -> CardDatabaseMaintenanceError,
    stalledError: (String, Int) -> CardDatabaseMaintenanceError,
    progress: ((CardDatabaseWriteProgress) -> Void)?
  ) throws -> Int {
    var deletedRows = 0
    while true {
      let remainingRows = try rowCount(in: tableName)
      guard remainingRows > 0 else {
        return deletedRows
      }

      do {
        try database.execute(
          """
          DELETE FROM \(tableName)
          WHERE rowid IN (
              SELECT rowid
              FROM \(tableName)
              LIMIT \(chunkSize)
          )
          """,
          interruptingAfter: Self.clearExistingLibraryStatementTimeout
        )
      } catch SQLiteError.executionFailed(let message) where Self.isSQLiteInterruptMessage(message) {
        throw timeoutError(tableName, remainingRows)
      }
      let chunkDeletedRows = database.changedRowCount
      guard chunkDeletedRows > 0 else {
        throw stalledError(tableName, remainingRows)
      }

      deletedRows += chunkDeletedRows
      progress?(
        CardDatabaseWriteProgress(
          phase: phase,
          completedUnitCount: completedRows + deletedRows,
          totalUnitCount: totalRows
        ))
    }
  }

  private func recreateSearchIndexTables() throws {
    do {
      try database.execute("DROP TABLE IF EXISTS cards_name_fts", interruptingAfter: Self.clearExistingLibraryStatementTimeout)
      try database.execute("DROP TABLE IF EXISTS cards_fts", interruptingAfter: Self.clearExistingLibraryStatementTimeout)
      try database.execute(
        """
        CREATE VIRTUAL TABLE cards_fts
        USING fts5(card_id UNINDEXED, search_text, tokenize = 'unicode61 remove_diacritics 2')
        """,
        interruptingAfter: Self.clearExistingLibraryStatementTimeout
      )
      try database.execute(
        """
        CREATE VIRTUAL TABLE cards_name_fts
        USING fts5(card_id UNINDEXED, name_text, tokenize = 'unicode61 remove_diacritics 2')
        """,
        interruptingAfter: Self.clearExistingLibraryStatementTimeout
      )
    } catch SQLiteError.executionFailed(let message) where Self.isSQLiteInterruptMessage(message) {
      throw CardDatabaseMaintenanceError.resetSearchIndexTimedOut(
        seconds: Self.clearExistingLibraryStatementTimeoutSeconds
      )
    }
  }

  private static func isSQLiteInterruptMessage(_ message: String) -> Bool {
    message.localizedCaseInsensitiveContains("interrupted")
  }

  static let clearExistingLibraryChunkSize = 5_000
  static let clearValueHistoryCacheChunkSize = 50_000
  static let clearExistingLibraryStatementTimeout: TimeInterval = 20
  static let clearExistingLibraryStatementTimeoutSeconds = Int(clearExistingLibraryStatementTimeout.rounded())
  private static let resetCachedLibraryStepCount = 4
  private static let disposableLibraryTableGroups = [
    [
      "staging_card_price_points",
      "staging_card_value_mappings",
      "card_value_series",
      "card_value_summaries",
      "card_price_points",
      "card_value_mappings",
      "value_history_background_jobs",
    ],
    [
      "cards_name_fts",
      "cards_fts",
    ],
    [
      "card_faces",
      "cards",
    ],
  ]

  public func deleteAllCardsPreservingLists() throws {
    guard !usesExternalCatalog else {
      throw CatalogStorageError.invalidCatalog("Attached catalogs are replaced as files")
    }
    try withDatabaseLock {
      try resetDisposableLibraryTables(progress: nil)
    }
  }

  public func clearStoredImagePaths() throws {
    try withDatabaseLock {
      try database.transaction {
        if usesExternalCatalog {
          try database.execute("DELETE FROM main.card_image_paths")
          try saveMetadataValue("false", forKey: MetadataKey.requiredImagesCached.rawValue)
          return
        }
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
        if usesExternalCatalog {
          try upsertExternalImagePaths(
            cardID: card.id,
            faceIndex: -1,
            small: card.smallImagePath,
            normal: card.normalImagePath,
            large: card.largeImagePath,
            artCrop: card.artCropImagePath,
            mergesExistingValues: false
          )
          for face in card.faces {
            try upsertExternalImagePaths(
              cardID: face.cardID,
              faceIndex: face.faceIndex,
              small: face.smallImagePath,
              normal: face.normalImagePath,
              large: face.largeImagePath,
              artCrop: face.artCropImagePath,
              mergesExistingValues: false
            )
          }
          return
        }
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
        if usesExternalCatalog {
          try upsertExternalImagePaths(
            cardID: card.id,
            faceIndex: -1,
            small: card.smallImagePath,
            normal: card.normalImagePath,
            large: card.largeImagePath,
            artCrop: card.artCropImagePath,
            mergesExistingValues: true
          )
          for face in card.faces {
            try upsertExternalImagePaths(
              cardID: face.cardID,
              faceIndex: face.faceIndex,
              small: face.smallImagePath,
              normal: face.normalImagePath,
              large: face.largeImagePath,
              artCrop: face.artCropImagePath,
              mergesExistingValues: true
            )
          }
          return
        }
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

  private func upsertExternalImagePaths(
    cardID: String,
    faceIndex: Int,
    small: String?,
    normal: String?,
    large: String?,
    artCrop: String?,
    mergesExistingValues: Bool
  ) throws {
    let assignments = Self.catalogImagePathColumns.map { column in
      if mergesExistingValues {
        return "\(column) = COALESCE(excluded.\(column), card_image_paths.\(column))"
      }
      return "\(column) = excluded.\(column)"
    }
    .joined(separator: ", ")
    let statement = try database.prepare(
      """
      INSERT INTO main.card_image_paths (
          card_id, face_index, small_image_path, normal_image_path,
          large_image_path, art_crop_image_path
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(card_id, face_index) DO UPDATE SET \(assignments)
      """)
    try statement.bind(cardID, at: 1)
    try statement.bind(faceIndex, at: 2)
    try statement.bind(small, at: 3)
    try statement.bind(normal, at: 4)
    try statement.bind(large, at: 5)
    try statement.bind(artCrop, at: 6)
    try statement.step()
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
