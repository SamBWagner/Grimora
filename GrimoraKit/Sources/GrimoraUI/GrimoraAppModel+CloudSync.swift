import Foundation
import GrimoraCore

extension GrimoraAppModel {
  public var isCloudSyncEnabled: Bool {
    cloudSyncMode == .enabled
  }

  public var cloudSyncResolutionContext: CloudSyncResolutionContext? {
    if case .resolving(let context) = cloudSyncStatus {
      return context
    }
    return nil
  }

  public var cloudSyncResolutionSnapshots: [DeviceSyncSnapshot] {
    cloudSyncResolutionContext?.snapshots ?? []
  }

  public func applyCloudSyncModePreference(_ mode: GrimoraCloudSyncMode) {
    guard mode != cloudSyncMode else {
      return
    }

    cloudSyncMode = mode
    switch mode {
    case .enabled:
      GrimoraCloudSyncPreferences.persistAccountConsent()
      Task { await startCloudSync() }
    case .disabled, .undecided:
      cloudSyncTask?.cancel()
      cloudSyncMonitorTask?.cancel()
      cloudSyncPushTask?.cancel()
      publishCloudSyncStatus(.disabled)
      Task {
        let status = await cloudSyncCoordinator.stop()
        await MainActor.run {
          self.publishCloudSyncStatus(status)
        }
      }
    }
  }

  public func chooseCloudSync() {
    applyCloudSyncModePreference(.enabled)
  }

  public func keepDeviceSeparate() {
    applyCloudSyncModePreference(.disabled)
  }

  public func useCurrentICloudAccount() {
    cloudSyncStatus = .preparing
    Task { [weak self] in
      guard let self else {
        return
      }
      let status = await cloudSyncCoordinator.acceptCurrentAccount(
        deviceID: cloudSyncDeviceID,
        deviceName: cloudSyncDeviceName,
        searchSettings: currentSyncSearchSettings()
      )
      handleCloudSyncStatus(status)
      if case .ready = status {
        await startCloudSyncMonitoring()
      }
    }
  }

  public func reconsiderCloudSyncChoice() {
    applyCloudSyncModePreference(.undecided)
  }

  public func startCloudSync() async {
    guard cloudSyncMode == .enabled else {
      publishCloudSyncStatus(.disabled)
      return
    }

    cloudSyncTask?.cancel()
    cloudSyncMonitorTask?.cancel()
    cloudSyncStatus = .preparing
    let settings = currentSyncSearchSettings()
    let deviceID = cloudSyncDeviceID
    let deviceName = cloudSyncDeviceName
    let coordinator = cloudSyncCoordinator
    let task = Task { [weak self, coordinator, deviceID, deviceName, settings] in
      let status = await coordinator.start(
        deviceID: deviceID,
        deviceName: deviceName,
        searchSettings: settings
      )
      guard !Task.isCancelled else {
        return
      }

      guard let self, self.cloudSyncMode == .enabled else {
        return
      }
      self.handleCloudSyncStatus(status)
      switch status {
      case .ready, .appliedRemoteSnapshot:
        await self.startCloudSyncMonitoring()
        self.applyCloudSyncTestActionsIfNeeded()
      case .disabled, .unavailable, .preparing, .syncing, .needsAppUpdate, .resolving,
        .accountChangeRequiresResolution, .failed:
        break
      }
    }
    cloudSyncTask = task
    await task.value
  }

  public func pushCloudSyncChangesIfNeeded() {
    guard cloudSyncMode == .enabled else {
      return
    }

    cloudSyncPushTask?.cancel()
    cloudSyncPushTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else {
        return
      }
      await self?.pushCloudSyncChanges()
    }
  }

  public func pushCloudSyncChanges() async {
    guard cloudSyncMode == .enabled else {
      return
    }

    let settings = currentSyncSearchSettings()
    let status = await cloudSyncCoordinator.pushLocalState(
      deviceID: cloudSyncDeviceID,
      deviceName: cloudSyncDeviceName,
      searchSettings: settings
    )
    handleCloudSyncStatus(status)
  }

  public func refreshCloudSyncWhenActive() {
    guard cloudSyncMode == .enabled else {
      return
    }
    switch cloudSyncStatus {
    case .ready, .appliedRemoteSnapshot:
      break
    case .disabled, .unavailable, .preparing, .syncing, .needsAppUpdate, .resolving,
      .accountChangeRequiresResolution, .failed:
      return
    }

    Task { [weak self] in
      await self?.refreshCloudSync(requestTransportRefresh: true)
    }
  }

  public func resolveCloudSync(
    sourceSnapshotID: DeviceSyncSnapshot.ID,
    importedListIDsBySnapshotID: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>]
  ) async {
    guard let context = cloudSyncResolutionContext else {
      return
    }
    let snapshots = context.snapshots

    let selectedSearchSettings = snapshots.first { $0.id == sourceSnapshotID }?.searchSettings
    cloudSyncStatus = .syncing
    let status = await cloudSyncCoordinator.applyResolution(
      SyncResolutionPlan(
        sourceSnapshotID: sourceSnapshotID,
        importedListIDsBySnapshotID: importedListIDsBySnapshotID
      ),
      snapshots: snapshots,
      deviceID: cloudSyncDeviceID,
      deviceName: cloudSyncDeviceName,
      searchSettings: currentSyncSearchSettings()
    )
    handleCloudSyncStatus(status)
    if case .ready = status, let selectedSearchSettings {
      applySyncedSearchSettings(selectedSearchSettings)
      await startCloudSyncMonitoring()
    }
    reloadCardLists()
    if hasLibrary {
      reloadSearch()
    }
  }

  public func reloadCloudSyncRecoverySnapshots() {
    do {
      cloudSyncRecoverySnapshots = try database.cloudSyncRecoverySnapshots()
    } catch {
      cloudSyncRecoverySnapshots = []
    }
  }

  public func reloadCloudSyncDiagnostics() {
    cloudSyncPendingChangeCount = (try? database.pendingSyncChanges().count) ?? 0
    cloudSyncLastDownloadAt = try? database.cloudSyncLastDownloadAt()
    cloudSyncLastUploadAt = try? database.cloudSyncLastUploadAt()
  }

  public func restoreCloudSyncRecoverySnapshot(id: CloudSyncRecoverySnapshot.ID) {
    do {
      try database.restoreCloudSyncRecoverySnapshot(id: id)
      reloadCardLists()
      reloadCloudSyncRecoverySnapshots()
      statusMessage = "Restored lists from before iCloud sync."
      pushCloudSyncChangesIfNeeded()
    } catch {
      reloadCloudSyncRecoverySnapshots()
      statusMessage = "Could not restore the iCloud sync recovery copy."
    }
  }

  func currentSyncSearchSettings() -> SyncSearchSettings {
    SyncSearchSettings(
      defaultSearchText: defaultSearchConfiguration.text,
      alwaysIncludedSearchText: defaultSearchConfiguration.alwaysIncludedText,
      defaultSortModeRawValue: defaultSearchConfiguration.sortMode.rawValue,
      defaultSortDirectionRawValue: defaultSearchConfiguration.sortDirection.rawValue,
      searchInputModeRawValue: searchInputMode.rawValue,
      displayCurrencyRawValue: UserDefaults.standard.string(
        forKey: GrimoraValuePreferences.displayCurrencyKey
      ) ?? CardValueDisplayCurrency.usd.rawValue,
      searchHistory: searchHistory,
      plainTextSearchHistory: plainTextSearchHistory,
      updatedAt: cloudSyncSearchSettingsUpdatedAt
    )
  }

  func markCloudSyncSearchSettingsChanged(at date: Date = Date()) {
    guard !isApplyingCloudSyncState else {
      return
    }
    cloudSyncSearchSettingsUpdatedAt = date
    UserDefaults.standard.set(date, forKey: GrimoraCloudSyncPreferences.searchSettingsUpdatedAtKey)
  }

  private func applyCloudSyncTestActionsIfNeeded(
    processInfo: ProcessInfo = .processInfo
  ) {
    let environment = processInfo.environment
    let hasActions = [
      "GRIMORA_SYNC_TEST_DEFAULT_SEARCH",
      "GRIMORA_SYNC_TEST_CURRENCY",
      "GRIMORA_SYNC_TEST_CREATE_LIST",
      "GRIMORA_SYNC_TEST_DELETE_LIST",
    ].contains { environment[$0] != nil }
    guard hasActions, !didApplyCloudSyncTestActions else {
      return
    }
    didApplyCloudSyncTestActions = true

    if let defaultSearch = environment["GRIMORA_SYNC_TEST_DEFAULT_SEARCH"] {
      UserDefaults.standard.set(
        defaultSearch,
        forKey: GrimoraSearchPreferences.defaultSearchTextKey
      )
      var configuration = defaultSearchConfiguration
      configuration.text = defaultSearch
      applySearchPreferences(configuration)
    }

    if let currency = environment["GRIMORA_SYNC_TEST_CURRENCY"] {
      UserDefaults.standard.set(
        currency,
        forKey: GrimoraValuePreferences.displayCurrencyKey
      )
      durableCloudSyncPreferencesChanged()
    }

    if let listName = environment["GRIMORA_SYNC_TEST_CREATE_LIST"],
      !cardLists.contains(where: { $0.name == listName })
    {
      createCardList(named: listName)
    }

    if let listName = environment["GRIMORA_SYNC_TEST_DELETE_LIST"],
      let list = cardLists.first(where: { $0.name == listName })
    {
      deleteCardList(id: list.id)
    }
  }

  public func durableCloudSyncPreferencesChanged() {
    pauseCloudSyncMonitoringForLocalMutation()
    defer { resumeCloudSyncMonitoringAfterLocalMutation() }
    markCloudSyncSearchSettingsChanged()
    pushCloudSyncChangesIfNeeded()
  }

  func pauseCloudSyncMonitoringForLocalMutation() {
    cloudSyncMonitorTask?.cancel()
    cloudSyncMonitorTask = nil
    cloudSyncPushTask?.cancel()
    cloudSyncPushTask = nil
  }

  func resumeCloudSyncMonitoringAfterLocalMutation() {
    guard cloudSyncMode == .enabled else {
      return
    }
    Task { [weak self] in
      await self?.startCloudSyncMonitoring()
    }
  }

  func publishCloudSyncStatus(_ status: CloudSyncStatus) {
    cloudSyncStatus = status
    switch status {
    case .disabled:
      statusMessage = "iCloud sync is off."
    case .unavailable(let message), .failed(let message):
      statusMessage = message
    case .preparing:
      statusMessage = "Preparing iCloud sync..."
    case .ready, .appliedRemoteSnapshot:
      statusMessage = "iCloud sync is ready."
    case .syncing:
      statusMessage = "Syncing with iCloud..."
    case .needsAppUpdate:
      statusMessage = "Update Grimora to continue syncing across devices."
    case .resolving:
      statusMessage = "Choose which device data to sync."
    case .accountChangeRequiresResolution:
      statusMessage = "Choose how Grimora should handle the changed iCloud account."
    }
    reloadCloudSyncDiagnostics()
  }

  func applySyncedSearchSettings(_ settings: SyncSearchSettings) {
    isApplyingCloudSyncState = true
    defer { isApplyingCloudSyncState = false }
    cloudSyncSearchSettingsUpdatedAt = settings.updatedAt
    UserDefaults.standard.set(
      settings.updatedAt,
      forKey: GrimoraCloudSyncPreferences.searchSettingsUpdatedAtKey
    )
    UserDefaults.standard.set(settings.defaultSearchText, forKey: GrimoraSearchPreferences.defaultSearchTextKey)
    UserDefaults.standard.set(
      settings.alwaysIncludedSearchText,
      forKey: GrimoraSearchPreferences.alwaysIncludedSearchTextKey
    )
    UserDefaults.standard.set(
      settings.defaultSortModeRawValue,
      forKey: GrimoraSearchPreferences.defaultSearchSortModeKey
    )
    UserDefaults.standard.set(
      settings.defaultSortDirectionRawValue,
      forKey: GrimoraSearchPreferences.defaultSearchSortDirectionKey
    )
    UserDefaults.standard.set(settings.searchInputModeRawValue, forKey: GrimoraSearchPreferences.searchInputModeKey)
    UserDefaults.standard.set(
      settings.displayCurrencyRawValue,
      forKey: GrimoraValuePreferences.displayCurrencyKey
    )
    searchHistoryStore.save(settings.searchHistory)
    plainTextSearchHistoryStore.save(settings.plainTextSearchHistory)
    searchHistory = settings.searchHistory
    plainTextSearchHistory = settings.plainTextSearchHistory

    applySearchPreferences(
      GrimoraSearchPreferences.configuration(
        text: settings.defaultSearchText,
        alwaysIncludedText: settings.alwaysIncludedSearchText,
        sortModeRawValue: settings.defaultSortModeRawValue,
        sortDirectionRawValue: settings.defaultSortDirectionRawValue
      )
    )
    applySearchInputModePreference(
      GrimoraSearchPreferences.searchInputMode(from: settings.searchInputModeRawValue)
    )
  }

  func startCloudSyncMonitoring() async {
    cloudSyncMonitorTask?.cancel()
    let coordinator = cloudSyncCoordinator
    let events = await coordinator.eventStream()
    cloudSyncMonitorTask = Task { [weak self, coordinator, events] in
      for await event in events {
        guard !Task.isCancelled, let self, self.cloudSyncMode == .enabled else {
          return
        }

        switch event {
        case .remoteChangesAvailable:
          await self.refreshCloudSync(requestTransportRefresh: false)
        case .accountChanged:
          self.cloudSyncStatus = .preparing
          let status = await coordinator.accountDidChange(
            deviceID: self.cloudSyncDeviceID,
            deviceName: self.cloudSyncDeviceName,
            searchSettings: self.currentSyncSearchSettings()
          )
          self.handleCloudSyncStatus(status)
        case .didDownload(let date):
          try? self.database.saveCloudSyncLastDownloadAt(date)
          self.reloadCloudSyncDiagnostics()
        case .didUpload(let date):
          try? self.database.saveCloudSyncLastUploadAt(date)
          self.reloadCloudSyncDiagnostics()
        case .failed(let message):
          self.publishCloudSyncStatus(.failed(message))
        }
      }
    }
  }

  private func refreshCloudSync(requestTransportRefresh: Bool) async {
    guard cloudSyncMode == .enabled else {
      return
    }

    let settings = currentSyncSearchSettings()
    let status: CloudSyncStatus
    if requestTransportRefresh {
      status = await cloudSyncCoordinator.refreshRemoteState(
        deviceID: cloudSyncDeviceID,
        deviceName: cloudSyncDeviceName,
        searchSettings: settings
      )
    } else {
      status = await cloudSyncCoordinator.reconcileRemoteState(
        deviceID: cloudSyncDeviceID,
        deviceName: cloudSyncDeviceName,
        searchSettings: settings
      )
    }
    handleCloudSyncStatus(status)
  }

  private func handleCloudSyncStatus(_ status: CloudSyncStatus) {
    publishCloudSyncStatus(status)
    reloadCloudSyncRecoverySnapshots()
    guard case .appliedRemoteSnapshot(let snapshot) = status else {
      return
    }

    applySyncedSearchSettings(snapshot.searchSettings)
    reloadCardLists()
    if hasLibrary {
      reloadSearch()
    }
  }
}
