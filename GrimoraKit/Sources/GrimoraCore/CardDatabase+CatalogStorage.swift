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
    let sourceSnapshot: CardCollectionLibrarySnapshot
    let sourceCounts: [String: Int]
    do {
      let source = try CardDatabase(storage: .file(legacyURL))
      sourceSnapshot = try source.cardCollectionLibrarySnapshot()
      sourceCounts = try source.userOwnedTableCounts()
    }

    let destination = try CardDatabase(storage: .file(userDatabaseURL))
    try destination.copyUserOwnedTables(from: legacyURL)
    let destinationSnapshot = try destination.cardCollectionLibrarySnapshot()
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

    var requiredTables = [
      "cards",
      "card_faces",
      "cards_fts",
      "cards_name_fts",
      "card_value_summaries",
      "card_value_series",
    ]
    let semanticTables = [
      "semantic_tags",
      "semantic_tag_aliases",
      "semantic_tag_edges",
      "semantic_card_tags",
      "semantic_tag_stats",
    ]
    let semanticRequiredColumns: [String: Set<String>] = [
      "semantic_tags": [
        "id", "namespace", "slug", "label", "description", "similarity_enabled", "source",
      ],
      "semantic_tag_aliases": ["tag_id", "alias", "alias_key"],
      "semantic_tag_edges": ["parent_tag_id", "child_tag_id"],
      "semantic_card_tags": ["card_key", "tag_id", "weight_millis", "annotation", "source"],
      "semantic_tag_stats": [
        "tag_id", "direct_card_count", "effective_card_count", "idf_millis",
      ],
    ]
    let semanticObjectCount = try semanticTables.reduce(into: 0) { count, table in
      let statement = try database.prepare(
        "SELECT 1 FROM sqlite_master WHERE name = ? COLLATE NOCASE LIMIT 1"
      )
      try statement.bind(table, at: 1)
      if try statement.step() {
        count += 1
      }
    }
    if semanticObjectCount > 0 {
      requiredTables.append(contentsOf: semanticTables)
    }

    for table in requiredTables {
      let statement = try database.prepare(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? COLLATE NOCASE LIMIT 1"
      )
      try statement.bind(table, at: 1)
      guard try statement.step() else {
        throw CatalogStorageError.invalidCatalog("Missing table \(table)")
      }
      if let requiredColumns = semanticRequiredColumns[table] {
        let columnsStatement = try database.prepare(
          "PRAGMA table_info(\(quotedIdentifier(table)))"
        )
        var columns: Set<String> = []
        while try columnsStatement.step() {
          if let name = columnsStatement.string(at: 1) {
            columns.insert(name.lowercased())
          }
        }
        guard columns.isSuperset(of: requiredColumns) else {
          let missing = requiredColumns.subtracting(columns).sorted().joined(separator: ", ")
          throw CatalogStorageError.invalidCatalog(
            "Table \(table) is missing required columns: \(missing)"
          )
        }
      }
    }

    let cardCount = try rowCount(in: "cards", database: database)
    let priceSeriesCount = try rowCount(in: "card_value_series", database: database)
    guard cardCount > 0 else {
      throw CatalogStorageError.invalidCatalog("Catalog contains no cards")
    }

    let semanticCounts: CatalogSemanticCounts? = semanticObjectCount == semanticTables.count
      ? CatalogSemanticCounts(
        tags: try rowCount(in: "semantic_tags", database: database),
        aliases: try rowCount(in: "semantic_tag_aliases", database: database),
        edges: try rowCount(in: "semantic_tag_edges", database: database),
        cardTags: try rowCount(in: "semantic_card_tags", database: database),
        tagStats: try rowCount(in: "semantic_tag_stats", database: database)
      )
      : nil
    var counts = CatalogCounts(
      cards: cardCount,
      priceSeries: priceSeriesCount,
      semantic: semanticCounts
    )
    if semanticCounts != nil {
      let oracleTagsVersions = expectedManifest?.enrichments
        .filter { $0.identifier == "scryfall-oracle-tags" }
        .map(\.version) ?? []
      let allowsUnresolvedCardKeys = oracleTagsVersions == [1]
      try validateSemanticCatalogRows(
        database,
        requiresResolvableCardKeys: !allowsUnresolvedCardKeys
      )
    }
    if let expectedManifest {
      guard expectedManifest.counts.cards == counts.cards,
        expectedManifest.counts.priceSeries == counts.priceSeries
      else {
        throw CatalogStorageError.invalidCatalog(
          "Manifest counts \(expectedManifest.counts) do not match catalog counts \(counts)"
        )
      }
      if let expectedSemanticCounts = expectedManifest.counts.semantic {
        guard expectedSemanticCounts == semanticCounts else {
          throw CatalogStorageError.invalidCatalog(
            "Manifest semantic counts \(expectedSemanticCounts) do not match catalog counts \(String(describing: semanticCounts))"
          )
        }
      } else {
        counts.semantic = nil
      }
      if expectedManifest.enrichments.contains(where: { $0.identifier == "scryfall-oracle-tags" }) {
        guard let semanticCounts, semanticCounts.tags > 0, semanticCounts.cardTags > 0 else {
          throw CatalogStorageError.invalidCatalog(
            "Oracle Tags enrichment produced no semantic tags or memberships"
          )
        }
      }
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
        priceSeries: try Self.rowCount(in: "card_value_series", database: database),
        semantic: try semanticCatalogAvailableUnlocked()
          ? CatalogSemanticCounts(
            tags: try Self.rowCount(in: "semantic_tags", database: database),
            aliases: try Self.rowCount(in: "semantic_tag_aliases", database: database),
            edges: try Self.rowCount(in: "semantic_tag_edges", database: database),
            cardTags: try Self.rowCount(in: "semantic_card_tags", database: database),
            tagStats: try Self.rowCount(in: "semantic_tag_stats", database: database)
          )
          : nil
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

  private static func validateSemanticCatalogRows(
    _ database: SQLiteDatabase,
    requiresResolvableCardKeys: Bool
  ) throws {
    let tags = try database.prepare(
      "SELECT id, namespace, slug, label, source FROM semantic_tags"
    )
    while try tags.step() {
      guard let id = tags.string(at: 0),
        let namespace = tags.string(at: 1),
        let slug = tags.string(at: 2),
        let label = tags.string(at: 3),
        let source = tags.string(at: 4),
        !id.isSemanticBlank,
        !namespace.isSemanticBlank,
        !slug.isSemanticBlank,
        !label.isSemanticBlank,
        !source.isSemanticBlank
      else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic tags contain invalid identity data"
        )
      }
    }

    let aliases = try database.prepare(
      "SELECT tag_id, alias, alias_key FROM semantic_tag_aliases"
    )
    while try aliases.step() {
      guard let tagID = aliases.string(at: 0),
        let alias = aliases.string(at: 1),
        let aliasKey = aliases.string(at: 2),
        !tagID.isSemanticBlank,
        !alias.isSemanticBlank,
        !aliasKey.isSemanticBlank,
        aliasKey == SemanticTagAliasRecord.normalizedKey(for: alias)
      else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic aliases must be normalized and contain valid identity data"
        )
      }
    }

    let edges = try database.prepare(
      "SELECT parent_tag_id, child_tag_id FROM semantic_tag_edges"
    )
    while try edges.step() {
      guard let parentTagID = edges.string(at: 0),
        let childTagID = edges.string(at: 1),
        !parentTagID.isSemanticBlank,
        !childTagID.isSemanticBlank,
        parentTagID != childTagID
      else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic hierarchy edges contain invalid identity data"
        )
      }
    }

    let memberships = try database.prepare(
      "SELECT card_key, tag_id, source FROM semantic_card_tags"
    )
    while try memberships.step() {
      guard let cardKey = memberships.string(at: 0),
        let tagID = memberships.string(at: 1),
        let source = memberships.string(at: 2),
        cardKey.hasValidSemanticCardIdentity,
        !tagID.isSemanticBlank,
        !source.isSemanticBlank
      else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic card memberships contain invalid identity data"
        )
      }
    }

    let statistics = try database.prepare(
      "SELECT tag_id FROM semantic_tag_stats"
    )
    while try statistics.step() {
      guard let tagID = statistics.string(at: 0), !tagID.isSemanticBlank else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic statistics contain invalid identity data"
        )
      }
    }

    var invalidQueries: [(String, String)] = [
      (
        "Semantic tags contain invalid identity data",
        """
        SELECT 1 FROM semantic_tags
        WHERE id IS NULL OR length(trim(id)) = 0
           OR namespace IS NULL OR length(trim(namespace)) = 0
           OR slug IS NULL OR length(trim(slug)) = 0
           OR label IS NULL OR length(trim(label)) = 0
           OR typeof(similarity_enabled) != 'integer'
           OR similarity_enabled IS NULL OR similarity_enabled NOT IN (0, 1)
           OR source IS NULL OR length(trim(source)) = 0
        LIMIT 1
        """
      ),
      (
        "Semantic aliases contain invalid identity data",
        """
        SELECT 1 FROM semantic_tag_aliases
        WHERE tag_id IS NULL OR length(trim(tag_id)) = 0
           OR alias IS NULL OR length(trim(alias)) = 0
           OR alias_key IS NULL OR length(trim(alias_key)) = 0
        LIMIT 1
        """
      ),
      (
        "Semantic hierarchy edges contain invalid identity data",
        """
        SELECT 1 FROM semantic_tag_edges
        WHERE parent_tag_id IS NULL OR length(trim(parent_tag_id)) = 0
           OR child_tag_id IS NULL OR length(trim(child_tag_id)) = 0
           OR parent_tag_id = child_tag_id
        LIMIT 1
        """
      ),
      (
        "Semantic card memberships contain invalid values",
        """
        SELECT 1 FROM semantic_card_tags
        WHERE card_key IS NULL
           OR substr(card_key, 1, 2) NOT IN ('o:', 'p:')
           OR length(trim(substr(card_key, 3))) = 0
           OR tag_id IS NULL OR length(trim(tag_id)) = 0
           OR typeof(weight_millis) != 'integer'
           OR weight_millis IS NULL OR weight_millis < 0
           OR source IS NULL OR length(trim(source)) = 0
        LIMIT 1
        """
      ),
      (
        "Semantic statistics contain invalid values",
        """
        SELECT 1 FROM semantic_tag_stats
        WHERE tag_id IS NULL OR length(trim(tag_id)) = 0
           OR typeof(direct_card_count) != 'integer'
           OR direct_card_count IS NULL OR direct_card_count < 0
           OR typeof(effective_card_count) != 'integer'
           OR effective_card_count IS NULL OR effective_card_count < direct_card_count
           OR typeof(idf_millis) != 'integer'
           OR idf_millis IS NULL OR idf_millis < 0
        LIMIT 1
        """
      ),
      (
        "Semantic tags contain duplicate identifiers",
        "SELECT 1 FROM semantic_tags GROUP BY id HAVING COUNT(*) > 1 LIMIT 1"
      ),
      (
        "Semantic tags contain duplicate source slugs",
        "SELECT 1 FROM semantic_tags GROUP BY source, slug HAVING COUNT(*) > 1 LIMIT 1"
      ),
      (
        "Semantic aliases contain duplicate identities",
        "SELECT 1 FROM semantic_tag_aliases GROUP BY tag_id, alias_key HAVING COUNT(*) > 1 LIMIT 1"
      ),
      (
        "Semantic hierarchy edges contain duplicate identities",
        "SELECT 1 FROM semantic_tag_edges GROUP BY parent_tag_id, child_tag_id HAVING COUNT(*) > 1 LIMIT 1"
      ),
      (
        "Semantic card memberships contain duplicate identities",
        "SELECT 1 FROM semantic_card_tags GROUP BY card_key, tag_id, source HAVING COUNT(*) > 1 LIMIT 1"
      ),
      (
        "Semantic statistics contain duplicate tag identities",
        "SELECT 1 FROM semantic_tag_stats GROUP BY tag_id HAVING COUNT(*) > 1 LIMIT 1"
      ),
      (
        "Semantic aliases contain orphan tag references",
        """
        SELECT 1 FROM semantic_tag_aliases aliases
        LEFT JOIN semantic_tags tags ON tags.id = aliases.tag_id
        WHERE tags.id IS NULL
        LIMIT 1
        """
      ),
      (
        "Semantic hierarchy edges contain orphan tag references",
        """
        SELECT 1 FROM semantic_tag_edges edges
        LEFT JOIN semantic_tags parents ON parents.id = edges.parent_tag_id
        LEFT JOIN semantic_tags children ON children.id = edges.child_tag_id
        WHERE parents.id IS NULL OR children.id IS NULL
        LIMIT 1
        """
      ),
      (
        "Semantic card memberships contain orphan tag references",
        """
        SELECT 1 FROM semantic_card_tags memberships
        LEFT JOIN semantic_tags tags ON tags.id = memberships.tag_id
        WHERE tags.id IS NULL
        LIMIT 1
        """
      ),
      (
        "Semantic statistics do not cover every tag exactly once",
        """
        SELECT 1 FROM semantic_tags tags
        LEFT JOIN semantic_tag_stats stats ON stats.tag_id = tags.id
        WHERE stats.tag_id IS NULL
        UNION ALL
        SELECT 1 FROM semantic_tag_stats stats
        LEFT JOIN semantic_tags tags ON tags.id = stats.tag_id
        WHERE tags.id IS NULL
        LIMIT 1
        """
      ),
      (
        "Semantic statistics do not match catalog relationships",
        """
        WITH RECURSIVE descendants(root_tag_id, tag_id) AS (
          SELECT id, id FROM semantic_tags
          UNION
          SELECT descendants.root_tag_id, edges.child_tag_id
          FROM descendants
          JOIN semantic_tag_edges edges ON edges.parent_tag_id = descendants.tag_id
        ),
        direct_counts(tag_id, expected_count) AS (
          SELECT tags.id, COUNT(DISTINCT memberships.card_key)
          FROM semantic_tags tags
          LEFT JOIN semantic_card_tags memberships ON memberships.tag_id = tags.id
          GROUP BY tags.id
        ),
        effective_counts(tag_id, expected_count) AS (
          SELECT descendants.root_tag_id, COUNT(DISTINCT memberships.card_key)
          FROM descendants
          LEFT JOIN semantic_card_tags memberships ON memberships.tag_id = descendants.tag_id
          GROUP BY descendants.root_tag_id
        )
        SELECT 1
        FROM semantic_tag_stats stats
        JOIN semantic_tags tags ON tags.id = stats.tag_id
        JOIN direct_counts direct ON direct.tag_id = stats.tag_id
        JOIN effective_counts effective ON effective.tag_id = stats.tag_id
        WHERE stats.direct_card_count != direct.expected_count
           OR stats.effective_card_count != effective.expected_count
           OR (tags.similarity_enabled = 0 AND stats.idf_millis != 0)
        LIMIT 1
        """
      ),
      (
        "Semantic hierarchy contains a cycle",
        """
        WITH RECURSIVE descendants(root_tag_id, tag_id) AS (
          SELECT parent_tag_id, child_tag_id FROM semantic_tag_edges
          UNION
          SELECT descendants.root_tag_id, edges.child_tag_id
          FROM descendants
          JOIN semantic_tag_edges edges ON edges.parent_tag_id = descendants.tag_id
        )
        SELECT 1 FROM descendants WHERE root_tag_id = tag_id LIMIT 1
        """
      ),
    ]

    if requiresResolvableCardKeys {
      invalidQueries.append(
        (
          "Semantic card memberships contain orphan card references",
          """
          SELECT 1
          FROM semantic_card_tags memberships
          WHERE (
            substr(memberships.card_key, 1, 2) = 'o:'
            AND NOT EXISTS (
              SELECT 1 FROM cards
              WHERE cards.oracle_id = substr(memberships.card_key, 3)
            )
          ) OR (
            substr(memberships.card_key, 1, 2) = 'p:'
            AND NOT EXISTS (
              SELECT 1 FROM cards
              WHERE cards.id = substr(memberships.card_key, 3)
            )
          )
          LIMIT 1
          """
        )
      )
    }

    for (message, query) in invalidQueries {
      let statement = try database.prepare(query)
      if try statement.step() {
        throw CatalogStorageError.invalidCatalog(message)
      }
    }

    let membershipCardCountStatement = try database.prepare(
      "SELECT COUNT(DISTINCT card_key) FROM semantic_card_tags"
    )
    _ = try membershipCardCountStatement.step()
    let allDistinctMembershipCards = membershipCardCountStatement.int(at: 0) ?? 0
    let inverseFrequencies = try database.prepare(
      """
      SELECT tags.similarity_enabled, stats.effective_card_count, stats.idf_millis
      FROM semantic_tag_stats stats
      JOIN semantic_tags tags ON tags.id = stats.tag_id
      """
    )
    while try inverseFrequencies.step() {
      guard let similarityEnabled = inverseFrequencies.int(at: 0),
        let effectiveCount = inverseFrequencies.int(at: 1),
        let actualIDFMillis = inverseFrequencies.int(at: 2)
      else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic statistics contain invalid values"
        )
      }
      let expectedIDFMillis: Int
      if similarityEnabled == 0 {
        expectedIDFMillis = 0
      } else {
        let numerator = Double(allDistinctMembershipCards + 1)
        let denominator = Double(effectiveCount + 1)
        expectedIDFMillis = max(
          0,
          Int(((log(numerator / denominator) + 1) * 1_000).rounded())
        )
      }
      guard actualIDFMillis == expectedIDFMillis else {
        throw CatalogStorageError.invalidCatalog(
          "Semantic inverse frequencies do not match catalog relationships"
        )
      }
    }
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
    "card_labels",
  ]

  private static let transientCatalogTables = [
    "staging_card_price_points",
    "staging_card_value_mappings",
    "value_history_background_jobs",
  ]

  private static let catalogTablesToDropFromMain =
    transientCatalogTables
    + [
      "semantic_tag_stats",
      "semantic_card_tags",
      "semantic_tag_edges",
      "semantic_tag_aliases",
      "semantic_tags",
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

private extension String {
  var isSemanticBlank: Bool {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var hasValidSemanticCardIdentity: Bool {
    guard hasPrefix("o:") || hasPrefix("p:") else {
      return false
    }
    return !String(dropFirst(2)).isSemanticBlank
  }
}
