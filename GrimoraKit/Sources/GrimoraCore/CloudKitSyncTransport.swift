#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation

@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public final class CloudKitSyncTransport: NSObject, @unchecked Sendable, CloudSyncTransport,
  CKSyncEngineDelegate
{
  private enum RecordType {
    static let libraryIdentity = "LibraryIdentity"
    static let deviceSnapshot = "DeviceSnapshot"
  }

  private enum RecordName {
    static let requiredLibraryIdentity = "required-library-identity"
  }

  private enum Field {
    static let payload = "payload"
    static let capturedAt = "capturedAt"
  }

  private let container: CKContainer
  private let database: CKDatabase
  private let zoneID: CKRecordZone.ID
  private let stateSerializationHandler: @Sendable (Data?) -> Void
  private let lock = NSLock()
  private var syncEngine: CKSyncEngine?

  public init(
    containerIdentifier: String = GrimoraCloudSyncConstants.containerIdentifier,
    stateSerialization: Data? = nil,
    stateSerializationHandler: @escaping @Sendable (Data?) -> Void = { _ in }
  ) {
    container = CKContainer(identifier: containerIdentifier)
    database = container.privateCloudDatabase
    zoneID = CKRecordZone.ID(zoneName: "GrimoraSync", ownerName: CKCurrentUserDefaultName)
    self.stateSerializationHandler = stateSerializationHandler
    super.init()
    initializeSyncEngine(stateSerialization: stateSerialization)
  }

  public func fetchRemoteState() async throws -> CloudRemoteState {
    try await ensureZoneExists()

    let requiredIdentity = try await fetchRequiredLibraryIdentity()
    let snapshots = try await fetchDeviceSnapshots()
    return CloudRemoteState(requiredLibraryIdentity: requiredIdentity, snapshots: snapshots)
  }

  public func save(
    snapshot: DeviceSyncSnapshot,
    requiredLibraryIdentity: LibraryIdentity
  ) async throws {
    try await ensureZoneExists()

    let records = try [
      record(
        recordType: RecordType.libraryIdentity,
        recordName: RecordName.requiredLibraryIdentity,
        payload: requiredLibraryIdentity,
        capturedAt: Date()
      ),
      record(
        recordType: RecordType.deviceSnapshot,
        recordName: snapshot.id,
        payload: snapshot,
        capturedAt: snapshot.capturedAt
      ),
    ]

    _ = try await database.modifyRecords(
      saving: records,
      deleting: [],
      savePolicy: .changedKeys,
      atomically: true
    )

    syncEngineLocked()?.state.add(
      pendingRecordZoneChanges: records.map { .saveRecord($0.recordID) }
    )
  }

  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    switch event {
    case .stateUpdate(let update):
      let data = try? JSONEncoder().encode(update.stateSerialization)
      stateSerializationHandler(data)
    case .accountChange, .fetchedDatabaseChanges, .fetchedRecordZoneChanges,
      .sentDatabaseChanges, .sentRecordZoneChanges, .willFetchChanges,
      .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .didFetchChanges,
      .willSendChanges, .didSendChanges:
      break
    @unknown default:
      break
    }
  }

  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    nil
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

    lock.lock()
    syncEngine = CKSyncEngine(configuration)
    lock.unlock()
  }

  private func syncEngineLocked() -> CKSyncEngine? {
    lock.lock()
    defer { lock.unlock() }
    return syncEngine
  }

  private func ensureZoneExists() async throws {
    let zone = CKRecordZone(zoneID: zoneID)
    _ = try? await database.save(zone)
  }

  private func fetchRequiredLibraryIdentity() async throws -> LibraryIdentity? {
    let recordID = CKRecord.ID(recordName: RecordName.requiredLibraryIdentity, zoneID: zoneID)
    do {
      let record = try await database.record(for: recordID)
      return try decode(LibraryIdentity.self, from: record)
    } catch let error as CKError where error.code == .unknownItem {
      return nil
    }
  }

  private func fetchDeviceSnapshots() async throws -> [DeviceSyncSnapshot] {
    let query = CKQuery(recordType: RecordType.deviceSnapshot, predicate: NSPredicate(value: true))
    let result = try await database.records(matching: query, inZoneWith: zoneID)
    var snapshots: [DeviceSyncSnapshot] = []

    for match in result.matchResults {
      guard case .success(let record) = match.1,
        let snapshot = try? decode(DeviceSyncSnapshot.self, from: record)
      else {
        continue
      }
      snapshots.append(snapshot)
    }

    return snapshots.sorted {
      if $0.capturedAt != $1.capturedAt {
        return $0.capturedAt > $1.capturedAt
      }
      return $0.id < $1.id
    }
  }

  private func record<T: Encodable>(
    recordType: String,
    recordName: String,
    payload: T,
    capturedAt: Date
  ) throws -> CKRecord {
    let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
    let record = CKRecord(recordType: recordType, recordID: recordID)
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
}

public enum CloudKitSyncTransportError: Error, Equatable, Sendable {
  case missingPayload
}
#endif
