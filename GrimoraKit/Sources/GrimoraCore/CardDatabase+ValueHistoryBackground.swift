import Foundation

extension CardDatabase {
  public func valueHistoryCardDatabaseIdentity() throws -> String {
    try withDatabaseLock {
      try valueHistoryCardDatabaseIdentityUnlocked()
    }
  }

  func valueHistoryCardDatabaseIdentityUnlocked() throws -> String {
    let updatedAt = try metadataValue(forKey: MetadataKey.defaultCardsUpdatedAt.rawValue) ?? "unknown"
    let statement = try database.prepare("SELECT id FROM cards ORDER BY id")
    var count = 0
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    while try statement.step() {
      guard let id = statement.string(at: 0) else {
        continue
      }
      count += 1
      for byte in id.utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x0000_0100_0000_01b3
      }
      hash ^= 0xff
      hash &*= 0x0000_0100_0000_01b3
    }
    return "v1:\(updatedAt):\(count):\(String(hash, radix: 16))"
  }

  public func latestValueHistoryBackgroundJob() throws -> ValueHistoryBackgroundJob? {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT id, mtgjson_date, mtgjson_version, card_database_identity, stage, status,
               downloaded_bytes, total_download_bytes, scanned_bytes, total_scan_bytes,
               imported_price_points, created_at, updated_at, completed_at, last_error
        FROM value_history_background_jobs
        ORDER BY updated_at DESC
        LIMIT 1
        """)
      guard try statement.step() else {
        return nil
      }
      return valueHistoryBackgroundJob(from: statement)
    }
  }

  public func incompleteValueHistoryBackgroundJob() throws -> ValueHistoryBackgroundJob? {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT id, mtgjson_date, mtgjson_version, card_database_identity, stage, status,
               downloaded_bytes, total_download_bytes, scanned_bytes, total_scan_bytes,
               imported_price_points, created_at, updated_at, completed_at, last_error
        FROM value_history_background_jobs
        WHERE status IN ('pending', 'running')
        ORDER BY updated_at DESC
        LIMIT 1
        """)
      guard try statement.step() else {
        return nil
      }
      return valueHistoryBackgroundJob(from: statement)
    }
  }

  public func valueHistoryBackgroundJob(id: String) throws -> ValueHistoryBackgroundJob? {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT id, mtgjson_date, mtgjson_version, card_database_identity, stage, status,
               downloaded_bytes, total_download_bytes, scanned_bytes, total_scan_bytes,
               imported_price_points, created_at, updated_at, completed_at, last_error
        FROM value_history_background_jobs
        WHERE id = ?
        """)
      try statement.bind(id, at: 1)
      guard try statement.step() else {
        return nil
      }
      return valueHistoryBackgroundJob(from: statement)
    }
  }

  public func prepareValueHistoryBackgroundJob(
    meta: MTGJSONPriceHistoryMeta,
    cardDatabaseIdentity: String
  ) throws -> ValueHistoryBackgroundJob {
    try withDatabaseLock {
      if let existing = try incompleteValueHistoryBackgroundJob(),
        existing.mtgjsonDate == meta.date,
        existing.mtgjsonVersion == meta.version,
        existing.cardDatabaseIdentity == cardDatabaseIdentity
      {
        return existing
      }

      let now = Self.valueHistoryTimestamp()
      let job = ValueHistoryBackgroundJob(
        mtgjsonDate: meta.date,
        mtgjsonVersion: meta.version,
        cardDatabaseIdentity: cardDatabaseIdentity,
        createdAt: now,
        updatedAt: now
      )
      try database.transaction {
        try database.execute(
          "DELETE FROM value_history_background_jobs WHERE status IN ('pending', 'running', 'failed')"
        )
        try saveValueHistoryBackgroundJobUnlocked(job)
      }
      return job
    }
  }

  public func discardValueHistoryBackgroundJob(id: String) throws {
    try withDatabaseLock {
      let statement = try database.prepare("DELETE FROM value_history_background_jobs WHERE id = ?")
      try statement.bind(id, at: 1)
      try statement.step()
    }
  }

  public func updateValueHistoryBackgroundJob(
    id: String,
    stage: ValueHistoryBackgroundStage,
    status: ValueHistoryBackgroundStatus,
    downloadedBytes: Int64? = nil,
    totalDownloadBytes: Int64? = nil,
    scannedBytes: Int64? = nil,
    totalScanBytes: Int64? = nil,
    importedPricePoints: Int? = nil,
    lastError: String? = nil
  ) throws -> ValueHistoryBackgroundJob? {
    try withDatabaseLock {
      guard var job = try valueHistoryBackgroundJob(id: id) else {
        return nil
      }
      job.stage = stage
      job.status = status
      if let downloadedBytes {
        job.downloadedBytes = downloadedBytes
      }
      if totalDownloadBytes != nil {
        job.totalDownloadBytes = totalDownloadBytes
      }
      if let scannedBytes {
        job.scannedBytes = scannedBytes
      }
      if totalScanBytes != nil {
        job.totalScanBytes = totalScanBytes
      }
      if let importedPricePoints {
        job.importedPricePoints = importedPricePoints
      }
      job.updatedAt = Self.valueHistoryTimestamp()
      job.lastError = lastError
      if status == .succeeded {
        job.completedAt = job.updatedAt
      }
      if status == .failed {
        job.completedAt = nil
      }
      try saveValueHistoryBackgroundJobUnlocked(job)
      return job
    }
  }

  func prepareValueHistoryStaging(jobID: String) throws {
    try withDatabaseLock {
      let deletePrices = try database.prepare("DELETE FROM staging_card_price_points WHERE job_id = ?")
      try deletePrices.bind(jobID, at: 1)
      try deletePrices.step()

      let deleteMappings = try database.prepare("DELETE FROM staging_card_value_mappings WHERE job_id = ?")
      try deleteMappings.bind(jobID, at: 1)
      try deleteMappings.step()
    }
  }

  func stageCardValueHistory(
    jobID: String,
    mappingsByMTGJSONUUID: [String: CardRecord.ID],
    importPricePoints: (StagingCardPricePointWriter) throws -> Int
  ) throws -> MTGJSONPriceImportSummary {
    try withDatabaseLock {
      var summary = MTGJSONPriceImportSummary(mappedCards: 0, importedPricePoints: 0)
      try database.transaction {
        try prepareValueHistoryStaging(jobID: jobID)
        let mappingInsert = try database.prepare(
          """
          INSERT OR REPLACE INTO staging_card_value_mappings (job_id, card_id, mtgjson_uuid)
          VALUES (?, ?, ?)
          """)
        for (uuid, cardID) in mappingsByMTGJSONUUID {
          try mappingInsert.bind(jobID, at: 1)
          try mappingInsert.bind(cardID, at: 2)
          try mappingInsert.bind(uuid, at: 3)
          try mappingInsert.step()
          try mappingInsert.reset()
        }

        let priceInsert = try database.prepare(
          """
          INSERT OR REPLACE INTO staging_card_price_points (job_id, card_id, provider, finish, date, price)
          VALUES (?, ?, ?, ?, ?, ?)
          """)
        let writer = StagingCardPricePointWriter(jobID: jobID, statement: priceInsert)
        let importedPricePoints = try importPricePoints(writer)
        summary = MTGJSONPriceImportSummary(
          mappedCards: mappingsByMTGJSONUUID.count,
          importedPricePoints: importedPricePoints
        )
      }
      return summary
    }
  }

  public func commitStagedValueHistory(jobID: String, meta: MTGJSONPriceHistoryMeta) throws
    -> MTGJSONPriceImportSummary
  {
    try withDatabaseLock {
      var summary = MTGJSONPriceImportSummary(mappedCards: 0, importedPricePoints: 0)
      try database.transaction {
        let mappedCardsStatement = try database.prepare(
          "SELECT COUNT(*) FROM staging_card_value_mappings WHERE job_id = ?"
        )
        try mappedCardsStatement.bind(jobID, at: 1)
        _ = try mappedCardsStatement.step()
        let mappedCards = mappedCardsStatement.int(at: 0) ?? 0

        let pricePointsStatement = try database.prepare(
          "SELECT COUNT(*) FROM staging_card_price_points WHERE job_id = ?"
        )
        try pricePointsStatement.bind(jobID, at: 1)
        _ = try pricePointsStatement.step()
        let importedPricePoints = pricePointsStatement.int(at: 0) ?? 0

        try database.execute("DELETE FROM card_value_summaries")
        try database.execute("DELETE FROM card_price_points")
        try database.execute("DELETE FROM card_value_mappings")
        try database.execute(
          """
          INSERT INTO card_value_mappings (card_id, mtgjson_uuid)
          SELECT card_id, mtgjson_uuid
          FROM staging_card_value_mappings
          WHERE job_id = '\(jobID.sqlEscaped)'
          """)
        try database.execute(
          """
          INSERT INTO card_price_points (card_id, provider, finish, date, price)
          SELECT card_id, provider, finish, date, price
          FROM staging_card_price_points
          WHERE job_id = '\(jobID.sqlEscaped)'
          """)
        try rebuildCardValueSummariesUnlocked()
        try saveMetadataValue(meta.date, forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue)
        try saveMetadataValue(meta.version, forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue)
        try saveMetadataValue(
          try valueHistoryCardDatabaseIdentityUnlocked(),
          forKey: MetadataKey.mtgjsonPriceHistoryCardDatabaseIdentity.rawValue
        )
        try saveMetadataValue(meta.date, forKey: MetadataKey.mtgjsonCurrentPricesDate.rawValue)
        try saveMetadataValue(meta.version, forKey: MetadataKey.mtgjsonCurrentPricesVersion.rawValue)
        try saveMetadataValue(
          try valueHistoryCardDatabaseIdentityUnlocked(),
          forKey: MetadataKey.mtgjsonCurrentPricesCardDatabaseIdentity.rawValue
        )
        summary = MTGJSONPriceImportSummary(mappedCards: mappedCards, importedPricePoints: importedPricePoints)
      }
      return summary
    }
  }

  private func valueHistoryBackgroundJob(from statement: SQLiteStatement) -> ValueHistoryBackgroundJob {
    ValueHistoryBackgroundJob(
      id: statement.string(at: 0) ?? "",
      mtgjsonDate: statement.string(at: 1) ?? "",
      mtgjsonVersion: statement.string(at: 2) ?? "",
      cardDatabaseIdentity: statement.string(at: 3) ?? "",
      stage: statement.string(at: 4).flatMap(ValueHistoryBackgroundStage.init(rawValue:)) ?? .pending,
      status: statement.string(at: 5).flatMap(ValueHistoryBackgroundStatus.init(rawValue:)) ?? .pending,
      downloadedBytes: Int64(statement.int(at: 6) ?? 0),
      totalDownloadBytes: statement.int(at: 7).map(Int64.init),
      scannedBytes: Int64(statement.int(at: 8) ?? 0),
      totalScanBytes: statement.int(at: 9).map(Int64.init),
      importedPricePoints: statement.int(at: 10) ?? 0,
      createdAt: statement.string(at: 11) ?? "",
      updatedAt: statement.string(at: 12) ?? "",
      completedAt: statement.string(at: 13),
      lastError: statement.string(at: 14)
    )
  }

  private func saveValueHistoryBackgroundJobUnlocked(_ job: ValueHistoryBackgroundJob) throws {
    let statement = try database.prepare(
      """
      INSERT INTO value_history_background_jobs (
          id, mtgjson_date, mtgjson_version, card_database_identity, stage, status,
          downloaded_bytes, total_download_bytes, scanned_bytes, total_scan_bytes,
          imported_price_points, created_at, updated_at, completed_at, last_error
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
          mtgjson_date = excluded.mtgjson_date,
          mtgjson_version = excluded.mtgjson_version,
          card_database_identity = excluded.card_database_identity,
          stage = excluded.stage,
          status = excluded.status,
          downloaded_bytes = excluded.downloaded_bytes,
          total_download_bytes = excluded.total_download_bytes,
          scanned_bytes = excluded.scanned_bytes,
          total_scan_bytes = excluded.total_scan_bytes,
          imported_price_points = excluded.imported_price_points,
          updated_at = excluded.updated_at,
          completed_at = excluded.completed_at,
          last_error = excluded.last_error
      """)
    try statement.bind(job.id, at: 1)
    try statement.bind(job.mtgjsonDate, at: 2)
    try statement.bind(job.mtgjsonVersion, at: 3)
    try statement.bind(job.cardDatabaseIdentity, at: 4)
    try statement.bind(job.stage.rawValue, at: 5)
    try statement.bind(job.status.rawValue, at: 6)
    try statement.bind(Int(job.downloadedBytes), at: 7)
    try statement.bind(job.totalDownloadBytes.map(Int.init), at: 8)
    try statement.bind(Int(job.scannedBytes), at: 9)
    try statement.bind(job.totalScanBytes.map(Int.init), at: 10)
    try statement.bind(job.importedPricePoints, at: 11)
    try statement.bind(job.createdAt, at: 12)
    try statement.bind(job.updatedAt, at: 13)
    try statement.bind(job.completedAt, at: 14)
    try statement.bind(job.lastError, at: 15)
    try statement.step()
  }

  private static func valueHistoryTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
  }
}

final class StagingCardPricePointWriter {
  private let jobID: String
  private let statement: SQLiteStatement

  init(jobID: String, statement: SQLiteStatement) {
    self.jobID = jobID
    self.statement = statement
  }

  func insert(
    cardID: CardRecord.ID,
    provider: CardValueProvider,
    finish: CardValueFinish,
    date: String,
    price: Double
  ) throws {
    try statement.bind(jobID, at: 1)
    try statement.bind(cardID, at: 2)
    try statement.bind(provider.rawValue, at: 3)
    try statement.bind(finish.rawValue, at: 4)
    try statement.bind(date, at: 5)
    try statement.bind(price, at: 6)
    try statement.step()
    try statement.reset()
  }
}

private extension String {
  var sqlEscaped: String {
    replacingOccurrences(of: "'", with: "''")
  }
}
