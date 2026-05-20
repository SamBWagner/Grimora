import Foundation
import GrimoraCore

extension GrimoraAppModel {
  public var isCloudSyncEnabled: Bool {
    cloudSyncMode == .enabled
  }

  public var cloudSyncResolutionSnapshots: [DeviceSyncSnapshot] {
    if case .resolving(let snapshots) = cloudSyncStatus {
      return snapshots
    }
    return []
  }

  public var requiredCloudLibraryIdentity: LibraryIdentity? {
    if case .waitingForDatabaseUpdate(let identity) = cloudSyncStatus {
      return identity
    }
    return nil
  }

  public func applyCloudSyncModePreference(_ mode: GrimoraCloudSyncMode) {
    guard mode != cloudSyncMode else {
      return
    }

    cloudSyncMode = mode
    switch mode {
    case .enabled:
      Task { await startCloudSync() }
    case .disabled, .undecided:
      cloudSyncTask?.cancel()
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

  public func reconsiderCloudSyncChoice() {
    applyCloudSyncModePreference(.undecided)
  }

  public func startCloudSync() async {
    guard cloudSyncMode == .enabled else {
      publishCloudSyncStatus(.disabled)
      return
    }

    cloudSyncTask?.cancel()
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

      await MainActor.run {
        guard let self, self.cloudSyncMode == .enabled else {
          return
        }

        self.publishCloudSyncStatus(status)
        if case .appliedRemoteSnapshot(let snapshot) = status {
          self.applySyncedSearchSettings(snapshot.searchSettings)
          self.reloadCardLists()
          if self.hasLibrary {
            self.reloadSearch()
          }
        }
      }
    }
    cloudSyncTask = task
    await task.value
  }

  public func pushCloudSyncChangesIfNeeded() {
    guard cloudSyncMode == .enabled else {
      return
    }

    Task { await pushCloudSyncChanges() }
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
    publishCloudSyncStatus(status)
  }

  public func resolveCloudSync(
    sourceSnapshotID: DeviceSyncSnapshot.ID,
    importedListIDsBySnapshotID: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>]
  ) async {
    let snapshots = cloudSyncResolutionSnapshots
    guard !snapshots.isEmpty else {
      return
    }

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
    publishCloudSyncStatus(status)
    if case .ready = status, let selectedSearchSettings {
      applySyncedSearchSettings(selectedSearchSettings)
    }
    reloadCardLists()
    if hasLibrary {
      reloadSearch()
    }
  }

  public func importRequiredCloudDatabaseUpdate() async {
    guard let identity = requiredCloudLibraryIdentity,
      let manifest = identity.manifest
    else {
      statusMessage = "The required synced database is missing download information."
      return
    }

    await importSpecificCardDatabase(
      manifest: manifest,
      successMessage: { summary in
        "Updated to the synced card database with \(self.formatted(summary.importedCards)) cards."
      },
      failureMessage: "Could not update to the synced card database."
    )

    if hasLibrary {
      await startCloudSync()
    }
  }

  func currentSyncSearchSettings(now: Date = Date()) -> SyncSearchSettings {
    SyncSearchSettings(
      defaultSearchText: defaultSearchConfiguration.text,
      alwaysIncludedSearchText: defaultSearchConfiguration.alwaysIncludedText,
      defaultSortModeRawValue: defaultSearchConfiguration.sortMode.rawValue,
      defaultSortDirectionRawValue: defaultSearchConfiguration.sortDirection.rawValue,
      searchInputModeRawValue: searchInputMode.rawValue,
      updatedAt: now
    )
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
    case .waitingForDatabaseUpdate:
      statusMessage = "A synced card database update is required before lists can sync."
    case .needsAppUpdate:
      statusMessage = "Update Grimora to continue syncing across devices."
    case .resolving:
      statusMessage = "Choose which device data to sync."
    }
  }

  func applySyncedSearchSettings(_ settings: SyncSearchSettings) {
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
}
