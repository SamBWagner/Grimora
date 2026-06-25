import Foundation

public protocol CloudSyncTransport: Sendable {
  func accountIdentifier() async throws -> String?
  func eventStream() async -> AsyncStream<CloudSyncTransportEvent>
  func fetchRemoteState() async throws -> CloudRemoteState
  func refresh() async throws
  func save(snapshot: DeviceSyncSnapshot, requiredLibraryIdentity: LibraryIdentity) async throws
  func save(recoverySnapshots: [CloudSyncRecoverySnapshot]) async throws
}

extension CloudSyncTransport {
  public func accountIdentifier() async throws -> String? {
    nil
  }

  public func eventStream() async -> AsyncStream<CloudSyncTransportEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }

  public func refresh() async throws {}

  public func save(recoverySnapshots: [CloudSyncRecoverySnapshot]) async throws {}
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
  private var entityRecords: [CloudSyncEntityRecord]
  private var savedSnapshots: [DeviceSyncSnapshot] = []
  private var currentAccountIdentifier: String?
  private var eventContinuations: [UUID: AsyncStream<CloudSyncTransportEvent>.Continuation] = [:]

  public init(
    state: CloudRemoteState = CloudRemoteState(),
    accountIdentifier: String? = "memory-account"
  ) {
    self.state = state
    entityRecords =
      (try? state.snapshots.flatMap(CloudSyncEntityCodec.records)) ?? []
    self.currentAccountIdentifier = accountIdentifier
  }

  public func accountIdentifier() async throws -> String? {
    currentAccountIdentifier
  }

  public func eventStream() -> AsyncStream<CloudSyncTransportEvent> {
    let id = UUID()
    return AsyncStream { continuation in
      eventContinuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeEventContinuation(id: id) }
      }
    }
  }

  public func fetchRemoteState() async throws -> CloudRemoteState {
    state
  }

  public func save(snapshot: DeviceSyncSnapshot, requiredLibraryIdentity: LibraryIdentity) async throws {
    savedSnapshots.append(snapshot)
    state.requiredLibraryIdentity = requiredLibraryIdentity
    entityRecords = CloudSyncEntityCodec.mergedRecords([
      entityRecords,
      try CloudSyncEntityCodec.records(from: snapshot),
    ])
    state.snapshots = try CloudSyncEntityCodec.snapshot(
      from: entityRecords,
      fallbackIdentity: requiredLibraryIdentity
    ).map { [$0] } ?? []
    publish(.remoteChangesAvailable)
  }

  public func save(recoverySnapshots: [CloudSyncRecoverySnapshot]) async throws {
    state.recoverySnapshots = CloudSyncRecoveryPolicy.retained(
      state.recoverySnapshots + recoverySnapshots
    )
    publish(.remoteChangesAvailable)
  }

  public func currentState() -> CloudRemoteState {
    state
  }

  public func saveHistory() -> [DeviceSyncSnapshot] {
    savedSnapshots
  }

  public func publish(_ event: CloudSyncTransportEvent) {
    for continuation in eventContinuations.values {
      continuation.yield(event)
    }
  }

  public func changeAccount(to identifier: String?) {
    let change = CloudSyncAccountChange(
      previousAccountIdentifier: currentAccountIdentifier,
      currentAccountIdentifier: identifier
    )
    currentAccountIdentifier = identifier
    publish(.accountChanged(change))
  }

  private func removeEventContinuation(id: UUID) {
    eventContinuations[id] = nil
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

  public func eventStream() async -> AsyncStream<CloudSyncTransportEvent> {
    await transport.eventStream()
  }

  public func start(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings
  ) async -> CloudSyncStatus {
    await start(
      deviceID: deviceID,
      deviceName: deviceName,
      searchSettings: searchSettings,
      localRaceRetryCount: 0
    )
  }

  private func start(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings,
    localRaceRetryCount: Int
  ) async -> CloudSyncStatus {
    do {
      if let accountStatus = try await accountBindingStatus() {
        return accountStatus
      }
      let remoteState = try await transport.fetchRemoteState()
      try database.mergeCloudSyncRecoverySnapshots(remoteState.recoverySnapshots)
      let localIdentity = try database.libraryIdentity()
      if let blockedStatus = blockedStatus(remoteState: remoteState, localIdentity: localIdentity) {
        return blockedStatus
      }
      try validate(remoteState: remoteState)

      let localRead = try database.deviceSyncSnapshotWithRevision(
        deviceID: deviceID,
        deviceName: deviceName,
        searchSettings: searchSettings
      )
      let localSnapshot = localRead.snapshot

      if try !database.isCloudSyncBootstrapResolved(), !remoteState.snapshots.isEmpty {
        // CloudKit is the single source of truth. On first join we deterministically
        // merge the remote and local libraries (per-entity last-writer-wins) rather
        // than ever prompting the user to pick a side. The pre-merge state is kept as
        // a recovery snapshot so an unexpected overwrite can still be undone.
        var mergedSnapshot = try CloudSyncBootstrapAnalyzer.mergedBootstrapSnapshot(
          localSnapshot: localSnapshot,
          remoteSnapshots: remoteState.snapshots
        )
        try Task.checkCancellation()
        let appliedSettings =
          mergedSnapshot.searchSettings.updatedAt >= searchSettings.updatedAt
          ? mergedSnapshot.searchSettings
          : searchSettings
        mergedSnapshot.searchSettings = appliedSettings
        try database.applyDeviceSyncSnapshot(
          mergedSnapshot,
          recoveryReason: "Before automatically combining initial iCloud data",
          expectedLocalRevision: localRead.revision,
          alwaysCreateRecoverySnapshot: true
        )
        try database.markCloudSyncBootstrapResolved(true)
        let refreshedSnapshot = try database.deviceSyncSnapshot(
          deviceID: deviceID,
          deviceName: deviceName,
          searchSettings: appliedSettings
        )
        try await save(refreshedSnapshot)
        try database.saveCloudSyncBaseSnapshot(refreshedSnapshot)
        return .appliedRemoteSnapshot(mergedSnapshot)
      }

      if try !database.isCloudSyncBootstrapResolved() {
        try await save(localSnapshot)
        try database.markCloudSyncBootstrapResolved(true)
        try database.saveCloudSyncBaseSnapshot(localSnapshot)
        return .ready
      }

      return try await reconcile(
        remoteState: remoteState,
        localSnapshot: localSnapshot,
        localRevision: localRead.revision,
        forceSave: true
      )
    } catch is CloudSyncLocalDataChangedError where localRaceRetryCount < 3 {
      return await start(
        deviceID: deviceID,
        deviceName: deviceName,
        searchSettings: searchSettings,
        localRaceRetryCount: localRaceRetryCount + 1
      )
    } catch is CloudSyncSnapshotValidationError {
      return .failed("iCloud sync data could not be validated. Local data was not changed.")
    } catch {
      return .unavailable("iCloud sync is unavailable right now.")
    }
  }

  public func pushLocalState(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings
  ) async -> CloudSyncStatus {
    await reconcileCurrentState(
      deviceID: deviceID,
      deviceName: deviceName,
      searchSettings: searchSettings,
      refreshTransport: false,
      forceSave: true
    )
  }

  public func reconcileRemoteState(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings
  ) async -> CloudSyncStatus {
    await reconcileCurrentState(
      deviceID: deviceID,
      deviceName: deviceName,
      searchSettings: searchSettings,
      refreshTransport: false,
      forceSave: false
    )
  }

  public func refreshRemoteState(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings
  ) async -> CloudSyncStatus {
    await reconcileCurrentState(
      deviceID: deviceID,
      deviceName: deviceName,
      searchSettings: searchSettings,
      refreshTransport: true,
      forceSave: false
    )
  }

  public func accountDidChange(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings
  ) async -> CloudSyncStatus {
    do {
      let change = CloudSyncAccountChange(
        previousAccountIdentifier: try database.cloudSyncAccountIdentifier(),
        currentAccountIdentifier: try await transport.accountIdentifier()
      )
      return .accountChangeRequiresResolution(change)
    } catch {
      return .failed("iCloud account changes could not be prepared.")
    }
  }

  public func acceptCurrentAccount(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings
  ) async -> CloudSyncStatus {
    do {
      let currentAccount = try await transport.accountIdentifier()
      try database.saveCloudSyncAccountIdentifier(currentAccount)
      try database.markCloudSyncBootstrapResolved(false)
      try database.saveCloudSyncBaseSnapshot(nil)
    } catch {
      return .failed("The new iCloud account could not be prepared.")
    }
    return await start(
      deviceID: deviceID,
      deviceName: deviceName,
      searchSettings: searchSettings
    )
  }

  public func stop() async -> CloudSyncStatus {
    .disabled
  }

  public func recordStateSerialization(_ data: Data?) throws {
    try database.saveCloudSyncEngineStateSerialization(data)
  }

  private func reconcileCurrentState(
    deviceID: String,
    deviceName: String,
    searchSettings: SyncSearchSettings,
    refreshTransport: Bool,
    forceSave: Bool,
    localRaceRetryCount: Int = 0
  ) async -> CloudSyncStatus {
    do {
      if refreshTransport {
        try await transport.refresh()
      }
      let remoteState = try await transport.fetchRemoteState()
      try database.mergeCloudSyncRecoverySnapshots(remoteState.recoverySnapshots)
      let localIdentity = try database.libraryIdentity()
      if let blockedStatus = blockedStatus(remoteState: remoteState, localIdentity: localIdentity) {
        return blockedStatus
      }
      try validate(remoteState: remoteState)
      let localRead = try database.deviceSyncSnapshotWithRevision(
        deviceID: deviceID,
        deviceName: deviceName,
        searchSettings: searchSettings
      )
      return try await reconcile(
        remoteState: remoteState,
        localSnapshot: localRead.snapshot,
        localRevision: localRead.revision,
        forceSave: forceSave
      )
    } catch is CloudSyncLocalDataChangedError where localRaceRetryCount < 3 {
      return await reconcileCurrentState(
        deviceID: deviceID,
        deviceName: deviceName,
        searchSettings: searchSettings,
        refreshTransport: false,
        forceSave: forceSave,
        localRaceRetryCount: localRaceRetryCount + 1
      )
    } catch is CloudSyncSnapshotValidationError {
      return .failed("iCloud sync data could not be validated. Local data was not changed.")
    } catch {
      return .failed("Sync failed. Grimora will try again later.")
    }
  }

  private func reconcile(
    remoteState: CloudRemoteState,
    localSnapshot: DeviceSyncSnapshot,
    localRevision: Int,
    forceSave: Bool
  ) async throws -> CloudSyncStatus {
    // CloudKit is the single source of truth. Reconciliation is always an automatic
    // per-entity last-writer-wins merge of the remote and local state — concurrent
    // edits converge deterministically and never surface an interactive prompt.
    let mergedSnapshot = try mergedEntitySnapshot(
      snapshots: remoteState.snapshots.filter { $0.id != localSnapshot.id } + [localSnapshot],
      deviceID: localSnapshot.id,
      deviceName: localSnapshot.deviceName,
      libraryIdentity: localSnapshot.libraryIdentity
    )
    let changed = syncContentDiffers(mergedSnapshot, localSnapshot)
    let pendingChanges = try database.pendingSyncChanges()
    let remoteHasCurrentData = remoteState.snapshots.contains {
      $0.id == localSnapshot.id || $0.id == CloudSyncEntityCodec.entitySnapshotID
    }

    if changed {
      try Task.checkCancellation()
      try database.applyDeviceSyncSnapshot(
        mergedSnapshot,
        recoveryReason: "Before reconciling iCloud changes",
        expectedLocalRevision: localRevision
      )
    }

    if forceSave || changed || !pendingChanges.isEmpty || !remoteHasCurrentData {
      let snapshotToSave = changed
        ? try database.deviceSyncSnapshot(
          deviceID: mergedSnapshot.id,
          deviceName: mergedSnapshot.deviceName,
          searchSettings: mergedSnapshot.searchSettings
        )
        : localSnapshot
      try await transport.save(
        snapshot: snapshotToSave,
        requiredLibraryIdentity: snapshotToSave.libraryIdentity
      )
      try await transport.save(
        recoverySnapshots: try database.cloudSyncRecoverySnapshots(limit: 200)
      )
      try database.markSyncChangesSent(ids: pendingChanges.map(\.id))
      try database.saveCloudSyncLastUploadAt(.now)
      try database.saveCloudSyncBaseSnapshot(snapshotToSave)
    } else {
      try database.saveCloudSyncBaseSnapshot(localSnapshot)
    }

    if changed {
      try database.saveCloudSyncLastDownloadAt(.now)
    }
    return changed ? .appliedRemoteSnapshot(mergedSnapshot) : .ready
  }

  private func save(_ snapshot: DeviceSyncSnapshot) async throws {
    let pendingChanges = try database.pendingSyncChanges()
    try await transport.save(
      snapshot: snapshot,
      requiredLibraryIdentity: snapshot.libraryIdentity
    )
    try await transport.save(
      recoverySnapshots: try database.cloudSyncRecoverySnapshots(limit: 200)
    )
    try database.markSyncChangesSent(ids: pendingChanges.map(\.id))
    try database.saveCloudSyncLastUploadAt(.now)
  }

  private func accountBindingStatus() async throws -> CloudSyncStatus? {
    let currentAccount = try await transport.accountIdentifier()
    let storedAccount = try database.cloudSyncAccountIdentifier()
    guard let storedAccount else {
      try database.saveCloudSyncAccountIdentifier(currentAccount)
      return nil
    }
    guard storedAccount == currentAccount else {
      return .accountChangeRequiresResolution(
        CloudSyncAccountChange(
          previousAccountIdentifier: storedAccount,
          currentAccountIdentifier: currentAccount
        )
      )
    }
    return nil
  }

  private func blockedStatus(
    remoteState: CloudRemoteState,
    localIdentity: LibraryIdentity
  ) -> CloudSyncStatus? {
    if let requiredVersion = remoteState.snapshots
      .map(\.libraryIdentity.syncSchemaVersion)
      .max(),
      requiredVersion > GrimoraCloudSyncConstants.currentSyncSchemaVersion
    {
      return .needsAppUpdate(requiredSyncSchemaVersion: requiredVersion)
    }

    guard let requiredIdentity = remoteState.requiredLibraryIdentity else {
      return nil
    }

    switch requiredIdentity.requirement(for: localIdentity) {
    case .satisfied:
      return nil
    case .needsAppUpdate(let requiredVersion):
      return .needsAppUpdate(requiredSyncSchemaVersion: requiredVersion)
    }
  }

  private func validate(remoteState: CloudRemoteState) throws {
    for snapshot in remoteState.snapshots {
      try snapshot.validateForApplication()
    }
  }

  private func mergedEntitySnapshot(
    snapshots: [DeviceSyncSnapshot],
    deviceID: String,
    deviceName: String,
    libraryIdentity: LibraryIdentity
  ) throws -> DeviceSyncSnapshot {
    let records = CloudSyncEntityCodec.mergedRecords(
      try snapshots.map(CloudSyncEntityCodec.records)
    )
    var merged = try CloudSyncEntityCodec.snapshot(
      from: records,
      fallbackIdentity: libraryIdentity
    ) ?? DeviceSyncSnapshot(
      id: deviceID,
      deviceName: deviceName,
      libraryIdentity: libraryIdentity,
      searchSettings: SyncSearchSettings(updatedAt: .distantPast),
      listSnapshot: CardListLibrarySnapshot(lists: [], categories: [], entries: [])
    )
    merged.id = deviceID
    merged.deviceName = deviceName
    merged.capturedAt = .now
    merged.libraryIdentity = libraryIdentity
    merged.searchSettings = SyncSearchSettings.merged(snapshots.map(\.searchSettings))
    return merged
  }

  private func syncContentDiffers(
    _ lhs: DeviceSyncSnapshot,
    _ rhs: DeviceSyncSnapshot
  ) -> Bool {
    (try? CardDatabase.syncJSONData(lhs.searchSettings))
      != (try? CardDatabase.syncJSONData(rhs.searchSettings))
      || (try? CardDatabase.syncJSONData(canonicalListSnapshot(lhs.listSnapshot)))
        != (try? CardDatabase.syncJSONData(canonicalListSnapshot(rhs.listSnapshot)))
      || canonicalTombstones(lhs.deletedEntities) != canonicalTombstones(rhs.deletedEntities)
  }

  private func canonicalListSnapshot(
    _ snapshot: CardListLibrarySnapshot
  ) -> CardListLibrarySnapshot {
    CardListLibrarySnapshot(
      lists: snapshot.lists.sorted { $0.id < $1.id },
      categories: snapshot.categories.sorted { $0.id < $1.id },
      entries: snapshot.entries.map { entry in
        var entry = entry
        entry.card = nil
        return entry
      }.sorted { $0.id < $1.id }
    )
  }

  private func canonicalTombstones(_ tombstones: [SyncTombstone]) -> [String: Date] {
    var result: [String: Date] = [:]
    for tombstone in tombstones {
      let key = "\(tombstone.entityType.rawValue):\(tombstone.recordID)"
      if let current = result[key], current >= tombstone.deletedAt {
        continue
      }
      result[key] = tombstone.deletedAt
    }
    return result
  }
}
