import Foundation

extension CardDatabase {
  private enum SyncMetadataKey {
    static let bootstrapResolved = "bootstrapResolved"
    static let cloudSyncEngineState = "cloudSyncEngineState"
  }

  public func libraryIdentity() throws -> LibraryIdentity {
    try withDatabaseLock {
      let downloadURI = try metadataValue(forKey: MetadataKey.defaultCardsDownloadURI.rawValue)
        .flatMap(URL.init(string:))
      let size = try metadataValue(forKey: MetadataKey.defaultCardsSize.rawValue).flatMap(Int.init) ?? 0
      return LibraryIdentity(
        defaultCardsUpdatedAt: try metadataValue(forKey: MetadataKey.defaultCardsUpdatedAt.rawValue),
        defaultCardsDownloadURI: downloadURI,
        defaultCardsName: try metadataValue(forKey: MetadataKey.defaultCardsName.rawValue) ?? "Default Cards",
        defaultCardsSize: size,
        searchSchemaVersion: try metadataValue(forKey: MetadataKey.searchSchemaVersion.rawValue)
          ?? Self.currentSearchSchemaVersion,
        syncSchemaVersion: GrimoraCloudSyncConstants.currentSyncSchemaVersion
      )
    }
  }

  public func saveLibraryIdentity(_ identity: LibraryIdentity) throws {
    try withDatabaseLock {
      try database.transaction {
        try saveMetadataValue(identity.defaultCardsUpdatedAt, forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        try saveMetadataValue(
          identity.defaultCardsDownloadURI?.absoluteString,
          forKey: MetadataKey.defaultCardsDownloadURI.rawValue
        )
        try saveMetadataValue(identity.defaultCardsName, forKey: MetadataKey.defaultCardsName.rawValue)
        try saveMetadataValue("\(identity.defaultCardsSize)", forKey: MetadataKey.defaultCardsSize.rawValue)
        try saveMetadataValue(identity.searchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
      }
    }
  }

  public func deviceSyncSnapshot(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings,
    capturedAt: Date = Date()
  ) throws -> DeviceSyncSnapshot {
    try DeviceSyncSnapshot(
      id: deviceID,
      deviceName: deviceName,
      capturedAt: capturedAt,
      libraryIdentity: libraryIdentity(),
      searchSettings: searchSettings,
      listSnapshot: cardListLibrarySnapshot()
    )
  }

  public func applyDeviceSyncSnapshot(_ snapshot: DeviceSyncSnapshot) throws {
    try restoreCardListLibrarySnapshot(snapshot.listSnapshot)
    try saveLibraryIdentity(snapshot.libraryIdentity)
  }

  public func applySyncResolutionPlan(
    _ plan: SyncResolutionPlan,
    snapshots: [DeviceSyncSnapshot]
  ) throws -> DeviceSyncSnapshot {
    let resolved = try plan.resolvedSnapshot(from: snapshots)
    try applyDeviceSyncSnapshot(resolved)
    try markCloudSyncBootstrapResolved(true)
    try recordLocalSyncChange(
      entityType: .snapshot,
      recordID: resolved.id,
      operation: .snapshot,
      payload: Self.syncJSONData(resolved)
    )
    return resolved
  }

  public func isCloudSyncBootstrapResolved() throws -> Bool {
    try syncMetadataString(forKey: SyncMetadataKey.bootstrapResolved) == "true"
  }

  public func markCloudSyncBootstrapResolved(_ isResolved: Bool) throws {
    try saveSyncMetadataString(isResolved ? "true" : "false", forKey: SyncMetadataKey.bootstrapResolved)
  }

  public func cloudSyncEngineStateSerialization() throws -> Data? {
    try syncMetadataData(forKey: SyncMetadataKey.cloudSyncEngineState)
  }

  public func saveCloudSyncEngineStateSerialization(_ data: Data?) throws {
    try saveSyncMetadataData(data, forKey: SyncMetadataKey.cloudSyncEngineState)
  }

  public func recordLocalSyncSnapshotChange(reason: String) throws {
    try recordLocalSyncChange(
      entityType: .snapshot,
      recordID: "local-library",
      operation: .snapshot,
      payload: reason.data(using: .utf8)
    )
  }

  public func recordLocalSyncChange(
    entityType: SyncEntityType,
    recordID: String,
    operation: SyncOutboxOperation,
    payload: Data? = nil,
    createdAt: Date = Date()
  ) throws {
    try withDatabaseLock {
      try insertSyncOutboxChangeUnlocked(
        SyncOutboxChange(
          entityType: entityType,
          recordID: recordID,
          operation: operation,
          payload: payload,
          createdAt: createdAt
        )
      )
    }
  }

  public func pendingSyncChanges() throws -> [SyncOutboxChange] {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT id, entity_type, record_id, operation, payload, created_at
        FROM sync_outbox
        ORDER BY created_at ASC, id ASC
        """)

      var changes: [SyncOutboxChange] = []
      while try statement.step() {
        changes.append(
          SyncOutboxChange(
            id: statement.string(at: 0) ?? UUID().uuidString.lowercased(),
            entityType: SyncEntityType(rawValue: statement.string(at: 1) ?? "") ?? .snapshot,
            recordID: statement.string(at: 2) ?? "",
            operation: SyncOutboxOperation(rawValue: statement.string(at: 3) ?? "") ?? .snapshot,
            payload: statement.data(at: 4),
            createdAt: Self.parseListDate(statement.string(at: 5))
          )
        )
      }
      return changes
    }
  }

  public func markSyncChangesSent(ids: [SyncOutboxChange.ID]) throws {
    try withDatabaseLock {
      let statement = try database.prepare("DELETE FROM sync_outbox WHERE id = ?")
      for id in ids {
        try statement.bind(id, at: 1)
        try statement.step()
        try statement.reset()
      }
    }
  }

  public func syncTombstones() throws -> [SyncTombstone] {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT id, entity_type, record_id, deleted_at
        FROM sync_tombstones
        ORDER BY deleted_at ASC, id ASC
        """)

      var tombstones: [SyncTombstone] = []
      while try statement.step() {
        tombstones.append(
          SyncTombstone(
            id: statement.string(at: 0) ?? UUID().uuidString.lowercased(),
            entityType: SyncEntityType(rawValue: statement.string(at: 1) ?? "") ?? .snapshot,
            recordID: statement.string(at: 2) ?? "",
            deletedAt: Self.parseListDate(statement.string(at: 3))
          )
        )
      }
      return tombstones
    }
  }

  func insertSyncTombstoneUnlocked(
    entityType: SyncEntityType,
    recordID: String,
    deletedAt: Date = Date()
  ) throws {
    let tombstone = SyncTombstone(entityType: entityType, recordID: recordID, deletedAt: deletedAt)
    let statement = try database.prepare(
      """
      INSERT INTO sync_tombstones (id, entity_type, record_id, deleted_at)
      VALUES (?, ?, ?, ?)
      """)
    try statement.bind(tombstone.id, at: 1)
    try statement.bind(tombstone.entityType.rawValue, at: 2)
    try statement.bind(tombstone.recordID, at: 3)
    try statement.bind(Self.formattedListDate(tombstone.deletedAt), at: 4)
    try statement.step()
  }

  private func insertSyncOutboxChangeUnlocked(_ change: SyncOutboxChange) throws {
    let statement = try database.prepare(
      """
      INSERT INTO sync_outbox (id, entity_type, record_id, operation, payload, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
      """)
    try statement.bind(change.id, at: 1)
    try statement.bind(change.entityType.rawValue, at: 2)
    try statement.bind(change.recordID, at: 3)
    try statement.bind(change.operation.rawValue, at: 4)
    try statement.bind(change.payload, at: 5)
    try statement.bind(Self.formattedListDate(change.createdAt), at: 6)
    try statement.step()
  }

  private func syncMetadataString(forKey key: String) throws -> String? {
    try withDatabaseLock {
      let statement = try database.prepare("SELECT value_text FROM sync_metadata WHERE key = ?")
      try statement.bind(key, at: 1)
      guard try statement.step() else {
        return nil
      }
      return statement.string(at: 0)
    }
  }

  private func syncMetadataData(forKey key: String) throws -> Data? {
    try withDatabaseLock {
      let statement = try database.prepare("SELECT value_data FROM sync_metadata WHERE key = ?")
      try statement.bind(key, at: 1)
      guard try statement.step() else {
        return nil
      }
      return statement.data(at: 0)
    }
  }

  private func saveSyncMetadataString(_ value: String?, forKey key: String) throws {
    try withDatabaseLock {
      if let value {
        let statement = try database.prepare(
          """
          INSERT INTO sync_metadata (key, value_text, value_data) VALUES (?, ?, NULL)
          ON CONFLICT(key) DO UPDATE SET value_text = excluded.value_text, value_data = NULL
          """)
        try statement.bind(key, at: 1)
        try statement.bind(value, at: 2)
        try statement.step()
      } else {
        let statement = try database.prepare("DELETE FROM sync_metadata WHERE key = ?")
        try statement.bind(key, at: 1)
        try statement.step()
      }
    }
  }

  private func saveSyncMetadataData(_ value: Data?, forKey key: String) throws {
    try withDatabaseLock {
      if let value {
        let statement = try database.prepare(
          """
          INSERT INTO sync_metadata (key, value_text, value_data) VALUES (?, NULL, ?)
          ON CONFLICT(key) DO UPDATE SET value_text = NULL, value_data = excluded.value_data
          """)
        try statement.bind(key, at: 1)
        try statement.bind(value, at: 2)
        try statement.step()
      } else {
        let statement = try database.prepare("DELETE FROM sync_metadata WHERE key = ?")
        try statement.bind(key, at: 1)
        try statement.step()
      }
    }
  }

  static func syncJSONData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  static func syncJSONValue<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: data)
  }
}
