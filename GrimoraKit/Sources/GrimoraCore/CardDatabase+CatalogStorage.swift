import Foundation

public struct UserDataMigrationReport: Equatable, Sendable {
  public var sourceCounts: [String: Int]
  public var destinationCounts: [String: Int]
  public var listSnapshotMatches: Bool

  public init(
    sourceCounts: [String: Int],
    destinationCounts: [String: Int],
    listSnapshotMatches: Bool
  ) {
    self.sourceCounts = sourceCounts
    self.destinationCounts = destinationCounts
    self.listSnapshotMatches = listSnapshotMatches
  }

  public var isVerified: Bool {
    sourceCounts == destinationCounts && listSnapshotMatches
  }
}

public enum CatalogStorageError: Error, Equatable, Sendable {
  case invalidCatalog(String)
  case userMigrationVerificationFailed
}

extension CardDatabase {
  static let catalogSchemaName = "catalog"
  static let catalogImagePathColumns = [
    "small_image_path",
    "normal_image_path",
    "large_image_path",
    "art_crop_image_path",
  ]

  public static func migrateLegacyUserDatabaseIfNeeded(
    legacyURL: URL,
    userDatabaseURL: URL,
    temporaryDirectory: URL,
    fileManager: FileManager = .default
  ) throws -> UserDataMigrationReport? {
    guard !fileManager.fileExists(atPath: userDatabaseURL.path),
      fileManager.fileExists(atPath: legacyURL.path)
    else {
      return nil
    }

    try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let snapshotURL = temporaryDirectory
      .appendingPathComponent("Grimora-user-migration-\(UUID().uuidString).sqlite")
    defer {
      try? fileManager.removeItem(at: snapshotURL)
      try? fileManager.removeItem(at: URL(fileURLWithPath: snapshotURL.path + "-wal"))
      try? fileManager.removeItem(at: URL(fileURLWithPath: snapshotURL.path + "-shm"))
    }

    try SQLiteDatabase.backup(from: legacyURL, to: snapshotURL)
    return try migrateLegacyUserDatabase(
      legacyURL: snapshotURL,
      userDatabaseURL: userDatabaseURL
    )
  }

  public static func migrateLegacyUserDatabase(
    legacyURL: URL,
    userDatabaseURL: URL
  ) throws -> UserDataMigrationReport {
    let sourceSnapshot: CardListLibrarySnapshot
    let sourceCounts: [String: Int]
    do {
      let source = try CardDatabase(storage: .file(legacyURL))
      sourceSnapshot = try source.cardListLibrarySnapshot()
      sourceCounts = try source.userOwnedTableCounts()
    }

    let destination = try CardDatabase(storage: .file(userDatabaseURL))
    try destination.copyUserOwnedTables(from: legacyURL)
    let destinationSnapshot = try destination.cardListLibrarySnapshot()
    let destinationCounts = try destination.userOwnedTableCounts()
    let report = UserDataMigrationReport(
      sourceCounts: sourceCounts,
      destinationCounts: destinationCounts,
      listSnapshotMatches: sourceSnapshot == destinationSnapshot
    )
    guard report.isVerified else {
      throw CatalogStorageError.userMigrationVerificationFailed
    }
    try destination.dropMainCatalogTables()
    try destination.database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    return report
  }

  public func recordInstalledCatalogManifest(_ manifest: CatalogManifest) throws {
    try saveCatalogManifestMetadata(manifest)
  }

  public func installCatalog(
    from stagedURL: URL,
    expectedManifest: CatalogManifest,
    fileManager: FileManager = .default
  ) throws {
    guard let destinationURL = attachedCatalogURL else {
      throw CatalogStorageError.invalidCatalog("Database is not using an attached catalog")
    }
    _ = try Self.validateCatalog(at: stagedURL, expectedManifest: expectedManifest)

    try withDatabaseLock {
      let backupURL = destinationURL.deletingLastPathComponent()
        .appendingPathComponent("Catalog.previous.sqlite")
      try dropCatalogOverlayViews()
      try database.detachDatabase(named: Self.catalogSchemaName)

      do {
        if fileManager.fileExists(atPath: backupURL.path) {
          try fileManager.removeItem(at: backupURL)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
          try fileManager.moveItem(at: destinationURL, to: backupURL)
        }
        try fileManager.moveItem(at: stagedURL, to: destinationURL)
        try database.attachReadOnlyDatabase(at: destinationURL, as: Self.catalogSchemaName)
        try createCatalogOverlayViews()
        try saveCatalogManifestMetadata(expectedManifest)
        try? fileManager.removeItem(at: backupURL)
      } catch {
        try? dropCatalogOverlayViews()
        try? database.detachDatabase(named: Self.catalogSchemaName)
        if fileManager.fileExists(atPath: destinationURL.path) {
          try? fileManager.removeItem(at: destinationURL)
        }
        if fileManager.fileExists(atPath: backupURL.path) {
          try? fileManager.moveItem(at: backupURL, to: destinationURL)
        }
        try? database.attachReadOnlyDatabase(at: destinationURL, as: Self.catalogSchemaName)
        try? createCatalogOverlayViews()
        throw error
      }
    }
  }

  public static func validateCatalog(
    at url: URL,
    expectedManifest: CatalogManifest? = nil
  ) throws -> CatalogCounts {
    let database = try SQLiteDatabase(storage: .readOnlyFile(url))
    guard try database.quickCheck() == "ok" else {
      throw CatalogStorageError.invalidCatalog("SQLite quick_check failed")
    }

    for table in ["cards", "card_faces", "cards_fts", "cards_name_fts", "card_value_summaries", "card_value_series"] {
      let statement = try database.prepare(
        "SELECT 1 FROM sqlite_master WHERE name = ? LIMIT 1"
      )
      try statement.bind(table, at: 1)
      guard try statement.step() else {
        throw CatalogStorageError.invalidCatalog("Missing table \(table)")
      }
    }

    let cardCount = try rowCount(in: "cards", database: database)
    let priceSeriesCount = try rowCount(in: "card_value_series", database: database)
    guard cardCount > 0 else {
      throw CatalogStorageError.invalidCatalog("Catalog contains no cards")
    }

    let counts = CatalogCounts(cards: cardCount, priceSeries: priceSeriesCount)
    if let expectedManifest, counts != expectedManifest.counts {
      throw CatalogStorageError.invalidCatalog(
        "Manifest counts \(expectedManifest.counts) do not match catalog counts \(counts)"
      )
    }
    return counts
  }

  public func prepareForCatalogDistribution() throws {
    try withDatabaseLock {
      try dropCatalogOverlayViews()
      for table in Self.userContentTables.reversed() {
        try database.execute("DROP TABLE IF EXISTS \(table)")
      }
      for table in Self.transientCatalogTables {
        try database.execute("DROP TABLE IF EXISTS \(table)")
      }
      try database.execute("PRAGMA foreign_keys = ON")
      try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
      try database.execute("PRAGMA journal_mode = DELETE")
    }
  }

  public func catalogCounts() throws -> CatalogCounts {
    try withDatabaseLock {
      CatalogCounts(
        cards: try Self.rowCount(in: "cards", database: database),
        priceSeries: try Self.rowCount(in: "card_value_series", database: database)
      )
    }
  }

  func prepareMainDatabaseForAttachedCatalog() throws {
    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS card_image_paths (
          card_id TEXT NOT NULL,
          face_index INTEGER NOT NULL,
          small_image_path TEXT,
          normal_image_path TEXT,
          large_image_path TEXT,
          art_crop_image_path TEXT,
          PRIMARY KEY (card_id, face_index)
      )
      """)
    try dropMainCatalogTables()
  }

  func createCatalogOverlayViews() throws {
    guard attachedCatalogURL != nil else {
      return
    }
    try dropCatalogOverlayViews()
    try createImageOverlayView(table: "cards", faceIndexExpression: "-1")
    try createImageOverlayView(table: "card_faces", faceIndexExpression: "source.face_index")
  }

  func dropCatalogOverlayViews() throws {
    try database.execute("DROP VIEW IF EXISTS temp.cards")
    try database.execute("DROP VIEW IF EXISTS temp.card_faces")
  }

  private func createImageOverlayView(
    table: String,
    faceIndexExpression: String
  ) throws {
    let columnsStatement = try database.prepare("PRAGMA \(Self.catalogSchemaName).table_info(\(table))")
    var columns: [String] = []
    while try columnsStatement.step() {
      if let name = columnsStatement.string(at: 1) {
        columns.append(name)
      }
    }
    guard !columns.isEmpty else {
      throw CatalogStorageError.invalidCatalog("Catalog table \(table) has no columns")
    }

    let selections = columns.map { column -> String in
      guard Self.catalogImagePathColumns.contains(column) else {
        return "source.\(Self.quotedIdentifier(column)) AS \(Self.quotedIdentifier(column))"
      }
      return """
      COALESCE(
          (
              SELECT paths.\(Self.quotedIdentifier(column))
              FROM main.card_image_paths paths
              WHERE paths.card_id = source.card_id_for_paths
                  AND paths.face_index = \(faceIndexExpression)
          ),
          source.\(Self.quotedIdentifier(column))
      ) AS \(Self.quotedIdentifier(column))
      """
    }

    let sourceProjection: String
    if table == "cards" {
      sourceProjection = "SELECT catalog_source.*, catalog_source.id AS card_id_for_paths FROM \(Self.catalogSchemaName).cards catalog_source"
    } else {
      sourceProjection = "SELECT catalog_source.*, catalog_source.card_id AS card_id_for_paths FROM \(Self.catalogSchemaName).card_faces catalog_source"
    }
    try database.execute(
      """
      CREATE TEMP VIEW \(table) AS
      SELECT \(selections.joined(separator: ",\n"))
      FROM (\(sourceProjection)) source
      """)
  }

  private func saveCatalogManifestMetadata(_ manifest: CatalogManifest) throws {
    try saveMetadataValue(manifest.version, forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
    try saveMetadataValue(
      manifest.artifact.downloadURL.absoluteString,
      forKey: MetadataKey.defaultCardsDownloadURI.rawValue
    )
    try saveMetadataValue("Grimora Catalog", forKey: MetadataKey.defaultCardsName.rawValue)
    try saveMetadataValue(
      "\(manifest.artifact.compressedBytes)",
      forKey: MetadataKey.defaultCardsSize.rawValue
    )
    try saveMetadataValue(Self.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
    try saveMetadataValue("\(manifest.catalogSchemaVersion)", forKey: MetadataKey.catalogSchemaVersion.rawValue)
    try saveMetadataValue(manifest.artifact.sha256, forKey: MetadataKey.catalogArtifactSHA256.rawValue)
  }

  private func copyUserOwnedTables(from sourceURL: URL) throws {
    try database.attachReadOnlyDatabase(at: sourceURL, as: "legacy")
    defer { try? database.detachDatabase(named: "legacy") }

    try database.transaction {
      for table in Self.userOwnedTables {
        try database.execute("DELETE FROM main.\(table)")
        let sourceColumns = Set(try tableColumnNames(schema: "legacy", table: table))
        let columns = try tableColumnNames(schema: "main", table: table)
          .filter { sourceColumns.contains($0) }
        guard !columns.isEmpty else {
          continue
        }
        let columnList = columns.map(Self.quotedIdentifier).joined(separator: ", ")
        try database.execute(
          """
          INSERT INTO main.\(Self.quotedIdentifier(table)) (\(columnList))
          SELECT \(columnList) FROM legacy.\(Self.quotedIdentifier(table))
          """
        )
      }
    }
  }

  private func tableColumnNames(schema: String, table: String) throws -> [String] {
    let statement = try database.prepare(
      "PRAGMA \(schema).table_info(\(Self.quotedIdentifier(table)))"
    )
    var names: [String] = []
    while try statement.step() {
      if let name = statement.string(at: 1) {
        names.append(name)
      }
    }
    return names
  }

  private func userOwnedTableCounts() throws -> [String: Int] {
    try withDatabaseLock {
      var counts: [String: Int] = [:]
      for table in Self.userOwnedTables {
        counts[table] = try Self.rowCount(in: table, database: database)
      }
      return counts
    }
  }

  private func dropMainCatalogTables() throws {
    for table in Self.catalogTablesToDropFromMain {
      try database.execute("DROP TABLE IF EXISTS main.\(table)")
    }
  }

  static func createEmptyCatalogIfNeeded(
    at url: URL,
    fileManager: FileManager = .default
  ) throws {
    guard !fileManager.fileExists(atPath: url.path) else {
      return
    }
    let catalog = try CardDatabase(storage: .file(url))
    try catalog.prepareForCatalogDistribution()
    try catalog.database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
  }

  private static func rowCount(
    in table: String,
    database: SQLiteDatabase
  ) throws -> Int {
    let statement = try database.prepare("SELECT COUNT(*) FROM \(table)")
    _ = try statement.step()
    return statement.int(at: 0) ?? 0
  }

  private static func quotedIdentifier(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }

  private static let userOwnedTables = [
    "metadata",
  ] + userContentTables

  private static let userContentTables = [
    "sync_metadata",
    "sync_outbox",
    "sync_tombstones",
    "cloud_sync_recovery_snapshots",
    "card_lists",
    "card_list_categories",
    "card_list_entries",
  ]

  private static let transientCatalogTables = [
    "staging_card_price_points",
    "staging_card_value_mappings",
    "value_history_background_jobs",
  ]

  private static let catalogTablesToDropFromMain =
    transientCatalogTables
    + [
      "card_value_series",
      "card_value_summaries",
      "card_price_points",
      "card_value_mappings",
      "cards_name_fts",
      "cards_fts",
      "card_faces",
      "cards",
    ]
}
