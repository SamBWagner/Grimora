import Foundation

extension CardDatabase {
  private enum SyncMetadataKey {
    static let bootstrapResolved = "bootstrapResolved"
    static let cloudSyncEngineState = "cloudSyncEngineState"
    static let cloudSyncAccountIdentifier = "cloudSyncAccountIdentifier"
    static let cloudSyncBaseSnapshot = "cloudSyncBaseSnapshot"
    static let cloudSyncLastDownloadAt = "cloudSyncLastDownloadAt"
    static let cloudSyncLastUploadAt = "cloudSyncLastUploadAt"
  }

  public func libraryIdentity() throws -> LibraryIdentity {
    try withDatabaseLock {
      try libraryIdentityUnlocked()
    }
  }

  public func saveLibraryIdentity(_ identity: LibraryIdentity) throws {
    try withDatabaseLock {
      try database.transaction {
        try saveLibraryIdentityUnlocked(identity)
      }
    }
  }

  public func deviceSyncSnapshot(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings,
    capturedAt: Date = Date()
  ) throws -> DeviceSyncSnapshot {
    try deviceSyncSnapshotWithRevision(
      deviceID: deviceID,
      deviceName: deviceName,
      searchSettings: searchSettings,
      capturedAt: capturedAt
    ).snapshot
  }

  func deviceSyncSnapshotWithRevision(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings,
    capturedAt: Date = Date()
  ) throws -> (snapshot: DeviceSyncSnapshot, revision: Int) {
    try withDatabaseLock {
      let revision = try listRevisionUnlocked()
      let deletedEntities = try syncTombstones()
      let deletedLists = Self.listDeletions(from: deletedEntities)
      var listSnapshot = try cardListLibrarySnapshotUnlocked()
      listSnapshot.entries = listSnapshot.entries.map { entry in
        var entry = entry
        entry.card = nil
        return entry
      }
      let snapshot = DeviceSyncSnapshot(
          id: deviceID,
          deviceName: deviceName,
          capturedAt: capturedAt,
          libraryIdentity: try libraryIdentityUnlocked(),
          searchSettings: searchSettings,
          listSnapshot: listSnapshot,
          deletedLists: deletedLists,
          deletedEntities: deletedEntities
        )
      return (
        CloudSyncEntityCodec.canonicalizedSnapshot(snapshot),
        revision
      )
    }
  }

  public func applyDeviceSyncSnapshot(
    _ snapshot: DeviceSyncSnapshot,
    recoveryReason: String = "Before applying iCloud changes",
    expectedLocalRevision: Int? = nil,
    alwaysCreateRecoverySnapshot: Bool = false
  ) throws {
    try snapshot.validateForApplication()

    try withDatabaseLock {
      if let expectedLocalRevision,
        try listRevisionUnlocked() != expectedLocalRevision
      {
        throw CloudSyncLocalDataChangedError()
      }
      let recoverySnapshot = try makeCloudSyncRecoverySnapshotUnlocked(reason: recoveryReason)
      let preservesChangedListData =
        recoverySnapshot.listSnapshot != snapshot.listSnapshot
        || recoverySnapshot.deletedLists != snapshot.deletedLists
      let recoveryPayload =
        preservesChangedListData || alwaysCreateRecoverySnapshot
        ? try Self.syncJSONData(recoverySnapshot)
        : nil

      try database.transaction {
        if let recoveryPayload {
          try insertCloudSyncRecoverySnapshotUnlocked(
            recoverySnapshot,
            payload: recoveryPayload
          )
        }
        try restoreCardListLibrarySnapshotUnlocked(snapshot.listSnapshot)
        try mergeSyncTombstonesUnlocked(
          snapshot.deletedEntities
            + snapshot.deletedLists.map {
              SyncTombstone(
                entityType: .cardList,
                recordID: $0.id,
                deletedAt: $0.deletedAt
              )
            }
        )
        try saveLibraryIdentityUnlocked(snapshot.libraryIdentity)
        try pruneCloudSyncRecoverySnapshotsUnlocked()
      }
    }
  }

  public func applySyncResolutionPlan(
    _ plan: SyncResolutionPlan,
    snapshots: [DeviceSyncSnapshot]
  ) throws -> DeviceSyncSnapshot {
    let resolved = try plan.resolvedSnapshot(from: snapshots)
    try applyDeviceSyncSnapshot(
      resolved,
      recoveryReason: "Before manually combining iCloud data",
      alwaysCreateRecoverySnapshot: true
    )
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

  public func cloudSyncAccountIdentifier() throws -> String? {
    try syncMetadataString(forKey: SyncMetadataKey.cloudSyncAccountIdentifier)
  }

  public func saveCloudSyncAccountIdentifier(_ identifier: String?) throws {
    try saveSyncMetadataString(identifier, forKey: SyncMetadataKey.cloudSyncAccountIdentifier)
  }

  public func cloudSyncBaseSnapshot() throws -> DeviceSyncSnapshot? {
    guard let data = try syncMetadataData(forKey: SyncMetadataKey.cloudSyncBaseSnapshot) else {
      return nil
    }
    return try Self.syncJSONValue(DeviceSyncSnapshot.self, from: data)
  }

  public func saveCloudSyncBaseSnapshot(_ snapshot: DeviceSyncSnapshot?) throws {
    try saveSyncMetadataData(
      snapshot.map(Self.syncJSONData),
      forKey: SyncMetadataKey.cloudSyncBaseSnapshot
    )
  }

  public func cloudSyncLastDownloadAt() throws -> Date? {
    try syncMetadataString(forKey: SyncMetadataKey.cloudSyncLastDownloadAt)
      .map(Self.parseListDate)
  }

  public func saveCloudSyncLastDownloadAt(_ date: Date?) throws {
    try saveSyncMetadataString(
      date.map(Self.formattedListDate),
      forKey: SyncMetadataKey.cloudSyncLastDownloadAt
    )
  }

  public func cloudSyncLastUploadAt() throws -> Date? {
    try syncMetadataString(forKey: SyncMetadataKey.cloudSyncLastUploadAt)
      .map(Self.parseListDate)
  }

  public func saveCloudSyncLastUploadAt(_ date: Date?) throws {
    try saveSyncMetadataString(
      date.map(Self.formattedListDate),
      forKey: SyncMetadataKey.cloudSyncLastUploadAt
    )
  }

  public func cloudSyncRecordSystemFields(
    recordType: String,
    recordID: String
  ) throws -> Data? {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT system_fields
        FROM cloud_sync_records
        WHERE record_type = ? AND record_id = ?
        """)
      try statement.bind(recordType, at: 1)
      try statement.bind(recordID, at: 2)
      guard try statement.step() else {
        return nil
      }
      return statement.data(at: 0)
    }
  }

  public func saveCloudSyncRecordSystemFields(
    _ data: Data?,
    recordType: String,
    recordID: String,
    updatedAt: Date = .now
  ) throws {
    try withDatabaseLock {
      if let data {
        let statement = try database.prepare(
          """
          INSERT INTO cloud_sync_records (
              record_type, record_id, system_fields, updated_at
          )
          VALUES (?, ?, ?, ?)
          ON CONFLICT(record_type, record_id) DO UPDATE SET
              system_fields = excluded.system_fields,
              updated_at = excluded.updated_at
          """)
        try statement.bind(recordType, at: 1)
        try statement.bind(recordID, at: 2)
        try statement.bind(data, at: 3)
        try statement.bind(Self.formattedListDate(updatedAt), at: 4)
        try statement.step()
      } else {
        let statement = try database.prepare(
          "DELETE FROM cloud_sync_records WHERE record_type = ? AND record_id = ?"
        )
        try statement.bind(recordType, at: 1)
        try statement.bind(recordID, at: 2)
        try statement.step()
      }
    }
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

  public func latestListDeletionTombstones() throws -> [SyncListDeletion] {
    Self.listDeletions(from: try syncTombstones())
  }

  public func mergeListDeletionTombstones(_ deletions: [SyncListDeletion]) throws {
    guard !deletions.isEmpty else {
      return
    }

    try withDatabaseLock {
      try database.transaction {
        try mergeListDeletionTombstonesUnlocked(deletions)
      }
    }
  }

  public func cloudSyncRecoverySnapshots(limit: Int = 20) throws
    -> [CloudSyncRecoverySnapshot]
  {
    try withDatabaseLock {
      let statement = try database.prepare(
        """
        SELECT payload
        FROM cloud_sync_recovery_snapshots
        ORDER BY created_at DESC, id DESC
        LIMIT ?
        """)
      try statement.bind(max(0, limit), at: 1)

      var snapshots: [CloudSyncRecoverySnapshot] = []
      while try statement.step() {
        guard let payload = statement.data(at: 0) else {
          continue
        }
        snapshots.append(try Self.syncJSONValue(CloudSyncRecoverySnapshot.self, from: payload))
      }
      return snapshots
    }
  }

  public func mergeCloudSyncRecoverySnapshots(
    _ snapshots: [CloudSyncRecoverySnapshot]
  ) throws {
    guard !snapshots.isEmpty else {
      return
    }

    try withDatabaseLock {
      try database.transaction {
        let insert = try database.prepare(
          """
          INSERT OR IGNORE INTO cloud_sync_recovery_snapshots (id, created_at, reason, payload)
          VALUES (?, ?, ?, ?)
          """)
        for snapshot in CloudSyncRecoveryPolicy.retained(snapshots) {
          try snapshot.listSnapshot.validateForApplication()
          try insert.bind(snapshot.id, at: 1)
          try insert.bind(Self.formattedListDate(snapshot.createdAt), at: 2)
          try insert.bind(snapshot.reason, at: 3)
          try insert.bind(Self.syncJSONData(snapshot), at: 4)
          try insert.step()
          try insert.reset()
        }
        try pruneCloudSyncRecoverySnapshotsUnlocked()
      }
    }
  }

  public func restoreCloudSyncRecoverySnapshot(
    id: CloudSyncRecoverySnapshot.ID,
    now: Date = Date()
  ) throws {
    try withDatabaseLock {
      guard var recoverySnapshot = try cloudSyncRecoverySnapshotUnlocked(id: id) else {
        throw CloudSyncRecoveryError.snapshotNotFound
      }
      try recoverySnapshot.listSnapshot.validateForApplication()

      let currentSnapshot = try makeCloudSyncRecoverySnapshotUnlocked(
        reason: "Before restoring iCloud recovery data"
      )
      let currentPayload = try Self.syncJSONData(currentSnapshot)
      recoverySnapshot.listSnapshot.lists = recoverySnapshot.listSnapshot.lists.map { list in
        var list = list
        list.updatedAt = now
        return list
      }
      recoverySnapshot.listSnapshot.categories = recoverySnapshot.listSnapshot.categories.map {
        category in
        var category = category
        category.updatedAt = now
        return category
      }

      try database.transaction {
        try insertCloudSyncRecoverySnapshotUnlocked(currentSnapshot, payload: currentPayload)
        try restoreCardListLibrarySnapshotUnlocked(recoverySnapshot.listSnapshot)

        let deleteTombstone = try database.prepare(
          "DELETE FROM sync_tombstones WHERE entity_type = ? AND record_id = ?"
        )
        for list in recoverySnapshot.listSnapshot.lists {
          try deleteTombstone.bind(SyncEntityType.cardList.rawValue, at: 1)
          try deleteTombstone.bind(list.id, at: 2)
          try deleteTombstone.step()
          try deleteTombstone.reset()
        }

        try insertSyncOutboxChangeUnlocked(
          SyncOutboxChange(
            entityType: .snapshot,
            recordID: "local-library",
            operation: .snapshot,
            payload: "cloud-sync-recovery".data(using: .utf8),
            createdAt: now
          )
        )
        try pruneCloudSyncRecoverySnapshotsUnlocked()
      }
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

  private func latestSyncTombstoneDateUnlocked(
    entityType: SyncEntityType,
    recordID: String
  ) throws -> Date? {
    let statement = try database.prepare(
      """
      SELECT deleted_at
      FROM sync_tombstones
      WHERE entity_type = ? AND record_id = ?
      ORDER BY deleted_at DESC
      LIMIT 1
      """)
    try statement.bind(entityType.rawValue, at: 1)
    try statement.bind(recordID, at: 2)
    guard try statement.step() else {
      return nil
    }
    return Self.parseListDate(statement.string(at: 0))
  }

  private func libraryIdentityUnlocked() throws -> LibraryIdentity {
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
      syncSchemaVersion: GrimoraCloudSyncConstants.currentSyncSchemaVersion,
      catalogSchemaVersion: try metadataValue(
        forKey: MetadataKey.catalogSchemaVersion.rawValue
      ).flatMap(Int.init)
    )
  }

  private func saveLibraryIdentityUnlocked(_ identity: LibraryIdentity) throws {
    try saveMetadataValue(identity.defaultCardsUpdatedAt, forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
    try saveMetadataValue(
      identity.defaultCardsDownloadURI?.absoluteString,
      forKey: MetadataKey.defaultCardsDownloadURI.rawValue
    )
    try saveMetadataValue(identity.defaultCardsName, forKey: MetadataKey.defaultCardsName.rawValue)
    try saveMetadataValue("\(identity.defaultCardsSize)", forKey: MetadataKey.defaultCardsSize.rawValue)
    try saveMetadataValue(identity.searchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
    try saveMetadataValue(
      identity.catalogSchemaVersion.map(String.init),
      forKey: MetadataKey.catalogSchemaVersion.rawValue
    )
  }

  private func mergeListDeletionTombstonesUnlocked(_ deletions: [SyncListDeletion]) throws {
    try mergeSyncTombstonesUnlocked(
      deletions.map {
        SyncTombstone(entityType: .cardList, recordID: $0.id, deletedAt: $0.deletedAt)
      }
    )
  }

  private func mergeSyncTombstonesUnlocked(_ tombstones: [SyncTombstone]) throws {
    for tombstone in tombstones {
      let current = try latestSyncTombstoneDateUnlocked(
        entityType: tombstone.entityType,
        recordID: tombstone.recordID
      )
      if let current, tombstone.deletedAt <= current {
        continue
      }
      try insertSyncTombstoneUnlocked(
        entityType: tombstone.entityType,
        recordID: tombstone.recordID,
        deletedAt: tombstone.deletedAt
      )
    }
  }

  private static func listDeletions(from tombstones: [SyncTombstone]) -> [SyncListDeletion] {
    var latestByListID: [CardListRecord.ID: Date] = [:]
    for tombstone in tombstones where tombstone.entityType == .cardList {
      latestByListID[tombstone.recordID] = max(
        latestByListID[tombstone.recordID] ?? .distantPast,
        tombstone.deletedAt
      )
    }
    return latestByListID
      .map { SyncListDeletion(id: $0.key, deletedAt: $0.value) }
      .sorted {
        if $0.deletedAt != $1.deletedAt {
          return $0.deletedAt < $1.deletedAt
        }
        return $0.id < $1.id
      }
  }

  private func makeCloudSyncRecoverySnapshotUnlocked(reason: String) throws
    -> CloudSyncRecoverySnapshot
  {
    CloudSyncRecoverySnapshot(
      reason: reason,
      libraryIdentity: try libraryIdentityUnlocked(),
      listSnapshot: try cardListLibrarySnapshotUnlocked(),
      deletedLists: try latestListDeletionTombstonesUnlocked()
    )
  }

  private func latestListDeletionTombstonesUnlocked() throws -> [SyncListDeletion] {
    let statement = try database.prepare(
      """
      SELECT record_id, MAX(deleted_at)
      FROM sync_tombstones
      WHERE entity_type = ?
      GROUP BY record_id
      ORDER BY MAX(deleted_at) ASC, record_id ASC
      """)
    try statement.bind(SyncEntityType.cardList.rawValue, at: 1)

    var deletions: [SyncListDeletion] = []
    while try statement.step() {
      deletions.append(
        SyncListDeletion(
          id: statement.string(at: 0) ?? "",
          deletedAt: Self.parseListDate(statement.string(at: 1))
        )
      )
    }
    return deletions
  }

  private func insertCloudSyncRecoverySnapshotUnlocked(
    _ snapshot: CloudSyncRecoverySnapshot,
    payload: Data
  ) throws {
    let statement = try database.prepare(
      """
      INSERT INTO cloud_sync_recovery_snapshots (id, created_at, reason, payload)
      VALUES (?, ?, ?, ?)
      """)
    try statement.bind(snapshot.id, at: 1)
    try statement.bind(Self.formattedListDate(snapshot.createdAt), at: 2)
    try statement.bind(snapshot.reason, at: 3)
    try statement.bind(payload, at: 4)
    try statement.step()
  }

  private func cloudSyncRecoverySnapshotUnlocked(id: CloudSyncRecoverySnapshot.ID) throws
    -> CloudSyncRecoverySnapshot?
  {
    let statement = try database.prepare(
      "SELECT payload FROM cloud_sync_recovery_snapshots WHERE id = ?"
    )
    try statement.bind(id, at: 1)
    guard try statement.step(), let payload = statement.data(at: 0) else {
      return nil
    }
    return try Self.syncJSONValue(CloudSyncRecoverySnapshot.self, from: payload)
  }

  private func pruneCloudSyncRecoverySnapshotsUnlocked() throws {
    let cutoff = Self.formattedListDate(
      Date().addingTimeInterval(-CloudSyncRecoveryPolicy.retentionDuration)
    )
    let statement = try database.prepare(
      """
      DELETE FROM cloud_sync_recovery_snapshots
      WHERE created_at < ?
        AND id NOT IN (
            SELECT id
            FROM cloud_sync_recovery_snapshots
            ORDER BY created_at DESC, id DESC
            LIMIT \(CloudSyncRecoveryPolicy.minimumRevisionCount)
        )
      """)
    try statement.bind(cutoff, at: 1)
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

  private func listRevisionUnlocked() throws -> Int {
    let statement = try database.prepare(
      "SELECT revision FROM sync_list_revision WHERE singleton = 1"
    )
    guard try statement.step() else {
      return 0
    }
    return statement.int(at: 0) ?? 0
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

public enum CloudSyncRecoveryError: Error, Equatable, Sendable {
  case snapshotNotFound
}

struct CloudSyncLocalDataChangedError: Error {}
