import Foundation

public protocol CloudSyncTransport: Sendable {
  func fetchRemoteState() async throws -> CloudRemoteState
  func save(snapshot: DeviceSyncSnapshot, requiredLibraryIdentity: LibraryIdentity) async throws
}

public actor DisabledCloudSyncTransport: CloudSyncTransport {
  public init() {}

  public func fetchRemoteState() async throws -> CloudRemoteState {
    CloudRemoteState()
  }

  public func save(snapshot: DeviceSyncSnapshot, requiredLibraryIdentity: LibraryIdentity) async throws {}
}

public actor MemoryCloudSyncTransport: CloudSyncTransport {
  private var state: CloudRemoteState

  public init(state: CloudRemoteState = CloudRemoteState()) {
    self.state = state
  }

  public func fetchRemoteState() async throws -> CloudRemoteState {
    state
  }

  public func save(snapshot: DeviceSyncSnapshot, requiredLibraryIdentity: LibraryIdentity) async throws {
    state.requiredLibraryIdentity = requiredLibraryIdentity
    state.snapshots.removeAll { $0.id == snapshot.id }
    state.snapshots.append(snapshot)
  }

  public func currentState() -> CloudRemoteState {
    state
  }
}

public actor CloudSyncCoordinator {
  private let database: CardDatabase
  private let transport: any CloudSyncTransport

  public init(database: CardDatabase, transport: any CloudSyncTransport) {
    self.database = database
    self.transport = transport
  }

  public static func disabled(database: CardDatabase) -> CloudSyncCoordinator {
    CloudSyncCoordinator(database: database, transport: DisabledCloudSyncTransport())
  }

  public func start(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings
  ) async -> CloudSyncStatus {
    do {
      let localIdentity = try database.libraryIdentity()
      let remoteState = try await transport.fetchRemoteState()
      if let requiredIdentity = remoteState.requiredLibraryIdentity {
        switch requiredIdentity.requirement(for: localIdentity) {
        case .satisfied:
          break
        case .needsDatabaseUpdate:
          return .waitingForDatabaseUpdate(requiredIdentity)
        case .needsAppUpdate(let requiredVersion):
          return .needsAppUpdate(requiredSyncSchemaVersion: requiredVersion)
        }
      }

      let localSnapshot = try database.deviceSyncSnapshot(
        deviceID: deviceID,
        deviceName: deviceName,
        searchSettings: searchSettings
      )

      if try shouldResolveBootstrapConflict(localSnapshot: localSnapshot, remoteState: remoteState) {
        return .resolving(resolutionSnapshots(localSnapshot: localSnapshot, remoteState: remoteState))
      }

      if let remoteSnapshot = try remoteSnapshotToApply(localSnapshot: localSnapshot, remoteState: remoteState) {
        try database.applyDeviceSyncSnapshot(remoteSnapshot)
        try database.markCloudSyncBootstrapResolved(true)
        let appliedSettings =
          remoteSnapshot.searchSettings.updatedAt >= searchSettings.updatedAt
          ? remoteSnapshot.searchSettings
          : searchSettings
        let refreshedSnapshot = try database.deviceSyncSnapshot(
          deviceID: deviceID,
          deviceName: deviceName,
          searchSettings: appliedSettings
        )
        try await transport.save(snapshot: refreshedSnapshot, requiredLibraryIdentity: refreshedSnapshot.libraryIdentity)
        try database.markSyncChangesSent(ids: try database.pendingSyncChanges().map(\.id))
        return .appliedRemoteSnapshot(remoteSnapshot)
      }

      try await transport.save(snapshot: localSnapshot, requiredLibraryIdentity: localIdentity)
      try database.markCloudSyncBootstrapResolved(true)
      try database.markSyncChangesSent(ids: try database.pendingSyncChanges().map(\.id))
      return .ready
    } catch {
      return .unavailable("iCloud sync is unavailable right now.")
    }
  }

  public func applyResolution(
    _ plan: SyncResolutionPlan,
    snapshots: [DeviceSyncSnapshot],
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings
  ) async -> CloudSyncStatus {
    do {
      let resolved = try database.applySyncResolutionPlan(plan, snapshots: snapshots)
      let refreshed = try database.deviceSyncSnapshot(
        deviceID: deviceID,
        deviceName: deviceName,
        searchSettings: resolved.searchSettings.updatedAt >= searchSettings.updatedAt
          ? resolved.searchSettings
          : searchSettings
      )
      try await transport.save(snapshot: refreshed, requiredLibraryIdentity: refreshed.libraryIdentity)
      try database.markCloudSyncBootstrapResolved(true)
      try database.markSyncChangesSent(ids: try database.pendingSyncChanges().map(\.id))
      return .ready
    } catch SyncResolutionError.sourceSnapshotNotFound {
      return .failed("The selected sync source was no longer available.")
    } catch {
      return .failed("Could not apply the sync choice.")
    }
  }

  public func pushLocalState(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings
  ) async -> CloudSyncStatus {
    do {
      let snapshot = try database.deviceSyncSnapshot(
        deviceID: deviceID,
        deviceName: deviceName,
        searchSettings: searchSettings
      )
      try await transport.save(snapshot: snapshot, requiredLibraryIdentity: snapshot.libraryIdentity)
      try database.markSyncChangesSent(ids: try database.pendingSyncChanges().map(\.id))
      return .ready
    } catch {
      return .failed("Sync failed. Grimora will try again later.")
    }
  }

  public func stop() async -> CloudSyncStatus {
    .disabled
  }

  public func recordStateSerialization(_ data: Data?) throws {
    try database.saveCloudSyncEngineStateSerialization(data)
  }

  private func shouldResolveBootstrapConflict(
    localSnapshot: DeviceSyncSnapshot,
    remoteState: CloudRemoteState
  ) throws -> Bool {
    guard try !database.isCloudSyncBootstrapResolved(),
      !remoteState.snapshots.isEmpty
    else {
      return false
    }

    if remoteState.snapshots.count > 1 {
      return true
    }

    guard let remoteSnapshot = remoteState.snapshots.first else {
      return false
    }

    return !localSnapshot.isEffectivelyEmpty && localSnapshot.listSnapshot != remoteSnapshot.listSnapshot
  }

  private func remoteSnapshotToApply(
    localSnapshot: DeviceSyncSnapshot,
    remoteState: CloudRemoteState
  ) throws -> DeviceSyncSnapshot? {
    let remoteSnapshots = remoteState.snapshots.filter { $0.id != localSnapshot.id }
    guard let latestSnapshot = remoteSnapshots.max(by: { $0.capturedAt < $1.capturedAt }) else {
      return nil
    }

    if try !database.isCloudSyncBootstrapResolved() {
      return latestSnapshot
    }

    guard try database.pendingSyncChanges().isEmpty else {
      return nil
    }

    if latestSnapshot.listSnapshot != localSnapshot.listSnapshot
      || latestSnapshot.searchSettings.updatedAt > localSnapshot.searchSettings.updatedAt
    {
      return latestSnapshot
    }

    return nil
  }

  private func resolutionSnapshots(
    localSnapshot: DeviceSyncSnapshot,
    remoteState: CloudRemoteState
  ) -> [DeviceSyncSnapshot] {
    var snapshots = remoteState.snapshots
    snapshots.removeAll { $0.id == localSnapshot.id }
    snapshots.append(localSnapshot)
    return snapshots.sorted {
      if $0.capturedAt != $1.capturedAt {
        return $0.capturedAt > $1.capturedAt
      }
      return $0.id < $1.id
    }
  }
}
