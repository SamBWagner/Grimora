#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation
import OSLog

@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public final class CloudKitSyncTransport: NSObject, @unchecked Sendable, CloudSyncTransport,
  CKSyncEngineDelegate
{
  private typealias RecordType = GrimoraCloudKitSchema.RecordType
  private typealias Field = GrimoraCloudKitSchema.Field

  private enum RecordName {
    static let requiredLibraryIdentity = "required-library-identity"
  }

  private let container: CKContainer
  private let database: CKDatabase
  private let zoneID: CKRecordZone.ID
  private let stateSerializationHandler: @Sendable (Data?) -> Void
  private let systemFieldsProvider: @Sendable (_ recordType: String, _ recordID: String) -> Data?
  private let systemFieldsHandler:
    @Sendable (_ data: Data?, _ recordType: String, _ recordID: String) -> Void
  private let logger = Logger(
    subsystem: "com.samwagner.Grimora",
    category: "CloudSync"
  )
  private let lock = NSLock()
  private var syncEngine: CKSyncEngine?
  private var eventContinuations: [UUID: AsyncStream<CloudSyncTransportEvent>.Continuation] = [:]
  private var cachedRecords: [CKRecord.ID: CKRecord] = [:]
  private var pendingRecords: [CKRecord.ID: CKRecord] = [:]
  private var sendFailures: [CKRecord.ID: CKError] = [:]
  private var initialRecordsLoaded = false

  public init(
    containerIdentifier: String = GrimoraCloudSyncConstants.containerIdentifier,
    stateSerialization: Data? = nil,
    stateSerializationHandler: @escaping @Sendable (Data?) -> Void = { _ in },
    systemFieldsProvider: @escaping @Sendable (String, String) -> Data? = { _, _ in nil },
    systemFieldsHandler: @escaping @Sendable (Data?, String, String) -> Void = { _, _, _ in }
  ) {
    container = CKContainer(identifier: containerIdentifier)
    database = container.privateCloudDatabase
    zoneID = CKRecordZone.ID(
      zoneName: GrimoraCloudKitSchema.zoneName,
      ownerName: CKCurrentUserDefaultName
    )
    self.stateSerializationHandler = stateSerializationHandler
    self.systemFieldsProvider = systemFieldsProvider
    self.systemFieldsHandler = systemFieldsHandler
    super.init()
    initializeSyncEngine(stateSerialization: stateSerialization)
  }

  public func accountIdentifier() async throws -> String? {
    do {
      let recordName = try await container.userRecordID().recordName
      // Before CloudKit finishes warming up, `userRecordID()` hands back the
      // `__defaultOwner__` placeholder instead of the real user record name.
      // Persisting that placeholder makes the next launch (once the real name is
      // available) look like an account change, so treat it as "not yet known".
      guard recordName != CKCurrentUserDefaultName else {
        return nil
      }
      return recordName
    } catch let error as CKError where error.code == .notAuthenticated {
      return nil
    }
  }

  public func fetchRemoteState() async throws -> CloudRemoteState {
    try await ensureZoneExists()
    try await loadInitialRecordsIfNeeded()
    return try remoteStateFromCache()
  }

  public func eventStream() async -> AsyncStream<CloudSyncTransportEvent> {
    let id = UUID()
    return AsyncStream { continuation in
      lock.withLock {
        eventContinuations[id] = continuation
      }
      continuation.onTermination = { [weak self] _ in
        self?.removeEventContinuation(id: id)
      }
    }
  }

  public func refresh() async throws {
    guard let syncEngine = syncEngineLocked() else {
      throw CloudKitSyncTransportError.syncEngineUnavailable
    }
    try await syncEngine.fetchChanges(
      CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([zoneID]))
    )
  }

  public func save(
    snapshot: DeviceSyncSnapshot,
    requiredLibraryIdentity: LibraryIdentity
  ) async throws {
    try await ensureZoneExists()
    guard let syncEngine = syncEngineLocked() else {
      throw CloudKitSyncTransportError.syncEngineUnavailable
    }

    var v4Snapshot = snapshot
    var v4Identity = requiredLibraryIdentity
    v4Identity.syncSchemaVersion = GrimoraCloudSyncConstants.currentSyncSchemaVersion
    v4Snapshot.libraryIdentity = v4Identity

    let entities = try CloudSyncEntityCodec.records(from: v4Snapshot)
    var records = try entities.map(record(from:))
    records.append(
      try legacyRecord(
        recordType: RecordType.legacyLibraryIdentity,
        recordName: RecordName.requiredLibraryIdentity,
        payload: v4Identity,
        capturedAt: .now
      )
    )
    records.append(
      try legacyRecord(
        recordType: RecordType.legacyDeviceSnapshot,
        recordName: v4Snapshot.id,
        payload: v4Snapshot,
        capturedAt: v4Snapshot.capturedAt
      )
    )

    try await send(records: records, deleting: [], using: syncEngine)
  }

  public func save(recoverySnapshots: [CloudSyncRecoverySnapshot]) async throws {
    try await ensureZoneExists()
    guard let syncEngine = syncEngineLocked() else {
      throw CloudKitSyncTransportError.syncEngineUnavailable
    }

    let retained = CloudSyncRecoveryPolicy.retained(recoverySnapshots)
    let records = try retained.map { snapshot in
      try legacyRecord(
        recordType: RecordType.recoveryRevision,
        recordName: "recovery-\(snapshot.id)",
        payload: snapshot,
        capturedAt: snapshot.createdAt
      )
    }
    let retainedIDs = Set(records.map(\.recordID))
    let deletedIDs = lock.withLock {
      cachedRecords.values
        .filter {
          $0.recordType == RecordType.recoveryRevision
            && !retainedIDs.contains($0.recordID)
        }
        .map(\.recordID)
    }
    try await send(records: records, deleting: deletedIDs, using: syncEngine)
  }

  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    switch event {
    case .stateUpdate(let update):
      let data = try? JSONEncoder().encode(update.stateSerialization)
      stateSerializationHandler(data)

    case .accountChange(let accountChange):
      let change: CloudSyncAccountChange
      switch accountChange.changeType {
      case .signIn(let currentUser):
        change = CloudSyncAccountChange(
          previousAccountIdentifier: nil,
          currentAccountIdentifier: currentUser.recordName
        )
      case .signOut(let previousUser):
        change = CloudSyncAccountChange(
          previousAccountIdentifier: previousUser.recordName,
          currentAccountIdentifier: nil
        )
      case .switchAccounts(let previousUser, let currentUser):
        change = CloudSyncAccountChange(
          previousAccountIdentifier: previousUser.recordName,
          currentAccountIdentifier: currentUser.recordName
        )
      @unknown default:
        change = CloudSyncAccountChange(
          previousAccountIdentifier: nil,
          currentAccountIdentifier: nil
        )
      }
      lock.withLock {
        cachedRecords.removeAll()
        initialRecordsLoaded = false
      }
      publish(.accountChanged(change))

    case .fetchedDatabaseChanges(let changes):
      if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
        lock.withLock {
          cachedRecords.removeAll()
          initialRecordsLoaded = false
        }
        publish(.failed("The iCloud sync zone was reset. Local data remains safe and will be uploaded again."))
      }

    case .fetchedRecordZoneChanges(let changes):
      guard !changes.modifications.isEmpty || !changes.deletions.isEmpty else {
        break
      }
      for modification in changes.modifications {
        cache(modification.record)
      }
      for deletion in changes.deletions {
        removeCachedRecord(deletion.recordID)
      }
      let fetchedAt = Date.now
      logger.info(
        "Fetched \(changes.modifications.count, privacy: .public) CloudKit records and \(changes.deletions.count, privacy: .public) deletions"
      )
      publish(.didDownload(fetchedAt))
      publish(.remoteChangesAvailable)

    case .sentDatabaseChanges(let changes):
      for failure in changes.failedZoneSaves where failure.zone.zoneID == zoneID {
        logger.error(
          "CloudKit zone save failed with code \(failure.error.code.rawValue, privacy: .public)"
        )
        publish(.failed("iCloud could not prepare Grimora's private sync zone."))
      }

    case .sentRecordZoneChanges(let changes):
      for record in changes.savedRecords {
        cache(record)
        lock.withLock {
          pendingRecords[record.recordID] = nil
          sendFailures[record.recordID] = nil
        }
      }
      for recordID in changes.deletedRecordIDs {
        removeCachedRecord(recordID)
        lock.withLock {
          pendingRecords[recordID] = nil
          sendFailures[recordID] = nil
        }
      }
      for failure in changes.failedRecordSaves {
        handleFailedSave(failure)
      }
      for (recordID, error) in changes.failedRecordDeletes {
        lock.withLock {
          sendFailures[recordID] = error
        }
        logger.error(
          "CloudKit record delete failed with code \(error.code.rawValue, privacy: .public)"
        )
      }
      if !changes.savedRecords.isEmpty || !changes.deletedRecordIDs.isEmpty {
        publish(.didUpload(.now))
      }

    case .didFetchRecordZoneChanges(let result):
      if let error = result.error {
        logger.error(
          "CloudKit fetch failed with code \(error.code.rawValue, privacy: .public)"
        )
        publish(.failed(Self.userMessage(for: error, operation: "fetch")))
      }

    case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchChanges, .willSendChanges,
      .didSendChanges:
      break

    @unknown default:
      break
    }
  }

  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    let changes = syncEngine.state.pendingRecordZoneChanges.filter {
      context.options.scope.contains($0)
    }
    guard !changes.isEmpty else {
      return nil
    }

    return await CKSyncEngine.RecordZoneChangeBatch(
      pendingChanges: changes
    ) { [weak self] recordID in
      self?.lock.withLock {
        self?.pendingRecords[recordID]
      }
    }
  }

  private func initializeSyncEngine(stateSerialization data: Data?) {
    let stateSerialization = data.flatMap {
      try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
    }
    var configuration = CKSyncEngine.Configuration(
      database: database,
      stateSerialization: stateSerialization,
      delegate: self
    )
    configuration.automaticallySync = true

    lock.withLock {
      syncEngine = CKSyncEngine(configuration)
    }
  }

  private func syncEngineLocked() -> CKSyncEngine? {
    lock.withLock { syncEngine }
  }

  private func publish(_ event: CloudSyncTransportEvent) {
    let continuations = lock.withLock { Array(eventContinuations.values) }
    for continuation in continuations {
      continuation.yield(event)
    }
  }

  private func removeEventContinuation(id: UUID) {
    lock.withLock {
      eventContinuations[id] = nil
    }
  }

  private func ensureZoneExists() async throws {
    do {
      let zones = try await database.recordZones(for: [zoneID])
      if case .success? = zones[zoneID] {
        return
      }
    } catch let error as CKError
      where error.code != .unknownItem && error.code != .zoneNotFound
    {
      throw error
    }

    do {
      _ = try await database.save(CKRecordZone(zoneID: zoneID))
    } catch let error as CKError where error.code == .serverRejectedRequest {
      // Saving an existing custom zone can race another device. A follow-up fetch verifies it.
      let zones = try await database.recordZones(for: [zoneID])
      guard case .success? = zones[zoneID] else {
        throw error
      }
    }
  }

  private func loadInitialRecordsIfNeeded() async throws {
    let shouldLoad = lock.withLock { !initialRecordsLoaded }
    guard shouldLoad else {
      return
    }
    guard let syncEngine = syncEngineLocked() else {
      throw CloudKitSyncTransportError.syncEngineUnavailable
    }
    try await syncEngine.fetchChanges(
      CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([zoneID]))
    )
    lock.withLock {
      initialRecordsLoaded = true
    }
    let recordCount = lock.withLock { cachedRecords.count }
    logger.info("Loaded \(recordCount, privacy: .public) initial CloudKit records")
  }

  private func remoteStateFromCache() throws -> CloudRemoteState {
    let records = lock.withLock { Array(cachedRecords.values) }
    let legacyIdentity = try records.first {
      $0.recordType == RecordType.legacyLibraryIdentity
        && $0.recordID.recordName == RecordName.requiredLibraryIdentity
    }.map { try decode(LibraryIdentity.self, from: $0) }
    let legacySnapshots = try records
      .filter { $0.recordType == RecordType.legacyDeviceSnapshot }
      .map { record in
        let snapshot = try decode(DeviceSyncSnapshot.self, from: record)
        try snapshot.validateForApplication()
        return snapshot
      }

    let entityRecords = try records.compactMap(entityRecord(from:))
    let entitySnapshot = try CloudSyncEntityCodec.snapshot(
      from: entityRecords,
      fallbackIdentity: legacyIdentity
    )
    if let entitySnapshot {
      try entitySnapshot.validateForApplication()
    }
    let recoverySnapshots = try records
      .filter { $0.recordType == RecordType.recoveryRevision }
      .map { try decode(CloudSyncRecoverySnapshot.self, from: $0) }

    return CloudRemoteState(
      requiredLibraryIdentity: entitySnapshot?.libraryIdentity ?? legacyIdentity,
      snapshots: CloudSyncSnapshotSelection.authoritativeSnapshots(
        legacySnapshots: legacySnapshots,
        entitySnapshot: entitySnapshot
      ),
      recoverySnapshots: CloudSyncRecoveryPolicy.retained(recoverySnapshots)
    )
  }

  private func send(
    records: [CKRecord],
    deleting deletedRecordIDs: [CKRecord.ID],
    using syncEngine: CKSyncEngine
  ) async throws {
    let recordIDs = Set(records.map(\.recordID)).union(deletedRecordIDs)
    guard !recordIDs.isEmpty else {
      return
    }

    lock.withLock {
      for record in records {
        pendingRecords[record.recordID] = record
        sendFailures[record.recordID] = nil
      }
      for recordID in deletedRecordIDs {
        sendFailures[recordID] = nil
      }
    }

    let pendingChanges =
      records.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0.recordID) }
      + deletedRecordIDs.map(CKSyncEngine.PendingRecordZoneChange.deleteRecord)
    syncEngine.state.add(pendingRecordZoneChanges: pendingChanges)
    logger.info(
      "Queued \(records.count, privacy: .public) CloudKit saves and \(deletedRecordIDs.count, privacy: .public) deletes"
    )

    try await syncEngine.sendChanges(
      CKSyncEngine.SendChangesOptions(scope: .recordIDs(Array(recordIDs)))
    )

    if let failure = lock.withLock({
      recordIDs.compactMap { sendFailures[$0] }.first
    }) {
      throw CloudKitSyncTransportError.recordSaveFailed(
        code: failure.code.rawValue,
        message: failure.localizedDescription
      )
    }
  }

  private func record(from entity: CloudSyncEntityRecord) throws -> CKRecord {
    let recordType = recordType(for: entity.entityType)
    let recordName = recordName(for: entity)
    let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
    let record = restoredRecord(recordType: recordType, recordID: recordID)
      ?? lock.withLock { cachedRecords[recordID] }
      ?? CKRecord(recordType: recordType, recordID: recordID)

    record[Field.entityID] = entity.recordID as NSString
    record[Field.updatedAt] = entity.updatedAt as NSDate
    record[Field.sourceDeviceID] = entity.sourceDeviceID as NSString
    if let payload = entity.payload {
      record.encryptedValues[Field.payload] = payload as NSData
    } else {
      record.encryptedValues[Field.payload] = nil
    }
    if let deletedAt = entity.deletedAt {
      record[Field.deletedAt] = deletedAt as NSDate
    } else {
      record[Field.deletedAt] = nil
    }
    return record
  }

  private func entityRecord(from record: CKRecord) throws -> CloudSyncEntityRecord? {
    guard let entityType = entityType(for: record.recordType),
      let entityID = record[Field.entityID] as? String,
      let updatedAt = record[Field.updatedAt] as? Date,
      let sourceDeviceID = record[Field.sourceDeviceID] as? String
    else {
      return nil
    }
    return CloudSyncEntityRecord(
      entityType: entityType,
      recordID: entityID,
      payload: record.encryptedValues[Field.payload] as? Data,
      updatedAt: updatedAt,
      deletedAt: record[Field.deletedAt] as? Date,
      sourceDeviceID: sourceDeviceID
    )
  }

  private func legacyRecord<T: Encodable>(
    recordType: String,
    recordName: String,
    payload: T,
    capturedAt: Date
  ) throws -> CKRecord {
    let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
    let record = restoredRecord(recordType: recordType, recordID: recordID)
      ?? lock.withLock { cachedRecords[recordID] }
      ?? CKRecord(recordType: recordType, recordID: recordID)
    record.encryptedValues[Field.payload] = try CardDatabase.syncJSONData(payload) as NSData
    record[Field.capturedAt] = capturedAt as NSDate
    return record
  }

  private func decode<T: Decodable>(_ type: T.Type, from record: CKRecord) throws -> T {
    guard let data = record.encryptedValues[Field.payload] as? Data else {
      throw CloudKitSyncTransportError.missingPayload
    }
    return try CardDatabase.syncJSONValue(type, from: data)
  }

  private func recordType(for entityType: SyncEntityType) -> String {
    switch entityType {
    case .library:
      RecordType.metadata
    case .searchSettings:
      RecordType.preferences
    case .cardCollection:
      RecordType.cardCollection
    case .cardCollectionCategory:
      RecordType.cardCollectionCategory
    case .cardCollectionEntry:
      RecordType.cardCollectionEntry
    case .snapshot:
      RecordType.legacyDeviceSnapshot
    }
  }

  private func entityType(for recordType: String) -> SyncEntityType? {
    switch recordType {
    case RecordType.metadata:
      .library
    case RecordType.preferences:
      .searchSettings
    case RecordType.cardCollection:
      .cardCollection
    case RecordType.cardCollectionCategory:
      .cardCollectionCategory
    case RecordType.cardCollectionEntry:
      .cardCollectionEntry
    default:
      nil
    }
  }

  private func recordName(for entity: CloudSyncEntityRecord) -> String {
    switch entity.entityType {
    case .library:
      CloudSyncEntityCodec.metadataRecordID
    case .searchSettings:
      CloudSyncEntityCodec.preferencesRecordID
    case .cardCollection:
      "list-\(entity.recordID)"
    case .cardCollectionCategory:
      "category-\(entity.recordID)"
    case .cardCollectionEntry:
      "entry-\(entity.recordID)"
    case .snapshot:
      "snapshot-\(entity.recordID)"
    }
  }

  private func cache(_ record: CKRecord) {
    lock.withLock {
      cachedRecords[record.recordID] = record
    }
    systemFieldsHandler(
      archivedRecord(record),
      record.recordType,
      record.recordID.recordName
    )
  }

  private func removeCachedRecord(_ recordID: CKRecord.ID) {
    let recordType = lock.withLock {
      cachedRecords.removeValue(forKey: recordID)?.recordType
    }
    if let recordType {
      systemFieldsHandler(nil, recordType, recordID.recordName)
    }
  }

  private func restoredRecord(
    recordType: String,
    recordID: CKRecord.ID
  ) -> CKRecord? {
    guard let data = systemFieldsProvider(recordType, recordID.recordName),
      let record = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: data),
      record.recordID == recordID
    else {
      return nil
    }
    return record
  }

  private func archivedRecord(_ record: CKRecord) -> Data? {
    try? NSKeyedArchiver.archivedData(
      withRootObject: record,
      requiringSecureCoding: true
    )
  }

  private func handleFailedSave(
    _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave
  ) {
    let error = failure.error
    lock.withLock {
      sendFailures[failure.record.recordID] = error
    }

    if error.code == .serverRecordChanged, let serverRecord = error.serverRecord {
      cache(serverRecord)
      if let pending = lock.withLock({ pendingRecords[failure.record.recordID] }) {
        copyGrimoraFields(from: pending, to: serverRecord)
        lock.withLock {
          pendingRecords[failure.record.recordID] = serverRecord
        }
      }
      publish(
        .failed(
          "iCloud found simultaneous changes. Both versions remain preserved while Grimora retries."
        )
      )
    } else {
      logger.error(
        "CloudKit record save failed with code \(error.code.rawValue, privacy: .public)"
      )
      publish(.failed(Self.userMessage(for: error, operation: "save")))
    }
  }

  private func copyGrimoraFields(from source: CKRecord, to destination: CKRecord) {
    for key in [
      Field.capturedAt,
      Field.updatedAt,
      Field.deletedAt,
      Field.entityID,
      Field.sourceDeviceID,
    ] {
      destination[key] = source[key]
    }
    destination.encryptedValues[Field.payload] = source.encryptedValues[Field.payload]
  }

  private static func userMessage(for error: CKError, operation: String) -> String {
    switch error.code {
    case .notAuthenticated:
      "Sign in to iCloud to sync Grimora."
    case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited:
      "iCloud sync is temporarily unavailable. Local changes remain queued."
    case .quotaExceeded:
      "iCloud storage is full. Local changes remain queued."
    case .zoneNotFound:
      "Grimora's iCloud sync zone is missing and will be recreated."
    default:
      "iCloud could not \(operation) Grimora data. Local changes remain queued."
    }
  }
}

public enum CloudKitSyncTransportError: Error, Equatable, Sendable {
  case missingPayload
  case syncEngineUnavailable
  case recordSaveFailed(code: Int, message: String)
}
#endif
