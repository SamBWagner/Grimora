import GrimoraCore
import XCTest

@testable import GrimoraUI

private struct CloudSyncModelTestError: Error {}

private actor FailingCloudSyncTransport: CloudSyncTransport {
  func fetchRemoteState() async throws -> CloudRemoteState {
    throw CloudSyncModelTestError()
  }

  func save(snapshot: DeviceSyncSnapshot, requiredLibraryIdentity: LibraryIdentity) async throws {
    throw CloudSyncModelTestError()
  }
}

@MainActor
final class GrimoraCloudSyncAppModelTests: XCTestCase {
  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: GrimoraCloudSyncPreferences.searchSettingsUpdatedAtKey)
  }

  func testFirstLaunchCanKeepDeviceSeparate() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let model = GrimoraAppModel(
      environment: environment(database: database),
      initialCloudSyncMode: .undecided
    )

    XCTAssertEqual(model.cloudSyncMode, .undecided)
    XCTAssertEqual(model.cloudSyncStatus, .disabled)

    model.keepDeviceSeparate()
    await Task.yield()

    XCTAssertEqual(model.cloudSyncMode, .disabled)
    XCTAssertEqual(model.cloudSyncStatus, .disabled)
    XCTAssertEqual(model.statusMessage, "iCloud sync is off.")
  }

  func testFirstLaunchCanReconsiderKeepDeviceSeparateBeforeDownload() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let model = GrimoraAppModel(
      environment: environment(database: database),
      initialCloudSyncMode: .undecided
    )

    model.keepDeviceSeparate()
    model.reconsiderCloudSyncChoice()
    await Task.yield()

    XCTAssertEqual(model.cloudSyncMode, .undecided)
    XCTAssertEqual(model.cloudSyncStatus, .disabled)
    XCTAssertEqual(model.statusMessage, "iCloud sync is off.")
  }

  func testFirstLaunchCanReconsiderCloudSyncBeforeDownload() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let model = GrimoraAppModel(
      environment: environment(database: database),
      initialCloudSyncMode: .undecided
    )
    model.cloudSyncMode = .enabled
    model.cloudSyncStatus = .preparing

    model.reconsiderCloudSyncChoice()
    await Task.yield()

    XCTAssertEqual(model.cloudSyncMode, .undecided)
    XCTAssertEqual(model.cloudSyncStatus, .disabled)
    XCTAssertEqual(model.statusMessage, "iCloud sync is off.")
  }

  func testICloudUnavailableFallsBackToLocalUse() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let coordinator = CloudSyncCoordinator(database: database, transport: FailingCloudSyncTransport())
    let model = GrimoraAppModel(
      environment: environment(database: database, cloudSyncCoordinator: coordinator)
    )

    model.cloudSyncMode = .enabled
    await model.startCloudSync()

    XCTAssertEqual(model.cloudSyncMode, .enabled)
    XCTAssertEqual(model.cloudSyncStatus, .unavailable("iCloud sync is unavailable right now."))
    XCTAssertEqual(model.statusMessage, "iCloud sync is unavailable right now.")
  }

  func testActivationDoesNotRaceInitialCloudSyncBootstrap() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let coordinator = CloudSyncCoordinator(database: database, transport: FailingCloudSyncTransport())
    let model = GrimoraAppModel(
      environment: environment(database: database, cloudSyncCoordinator: coordinator)
    )
    model.cloudSyncMode = .enabled
    model.cloudSyncStatus = .preparing

    model.refreshCloudSyncWhenActive()
    await Task.yield()

    XCTAssertEqual(model.cloudSyncStatus, .preparing)
  }

  func testRemoteCatalogVersionDoesNotBlockUserDataSync() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let requiredIdentity = LibraryIdentity(
      defaultCardsUpdatedAt: "2026-05-01T00:00:00.000+00:00",
      defaultCardsDownloadURI: URL(string: "https://example.test/default-cards.json")!,
      defaultCardsName: "Default Cards",
      defaultCardsSize: 123
    )
    let coordinator = CloudSyncCoordinator(
      database: database,
      transport: MemoryCloudSyncTransport(
        state: CloudRemoteState(requiredLibraryIdentity: requiredIdentity)
      )
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, cloudSyncCoordinator: coordinator)
    )

    model.cloudSyncMode = .enabled
    await model.startCloudSync()

    XCTAssertEqual(model.cloudSyncStatus, .ready)
    XCTAssertEqual(model.statusMessage, "iCloud sync is ready.")
  }

  func testRemoteNewerSyncSchemaShowsAppUpdateState() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let requiredIdentity = LibraryIdentity(
      defaultCardsUpdatedAt: nil,
      defaultCardsDownloadURI: nil,
      syncSchemaVersion: GrimoraCloudSyncConstants.currentSyncSchemaVersion + 1
    )
    let coordinator = CloudSyncCoordinator(
      database: database,
      transport: MemoryCloudSyncTransport(
        state: CloudRemoteState(requiredLibraryIdentity: requiredIdentity)
      )
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, cloudSyncCoordinator: coordinator)
    )

    model.cloudSyncMode = .enabled
    await model.startCloudSync()

    XCTAssertEqual(
      model.cloudSyncStatus,
      .needsAppUpdate(requiredSyncSchemaVersion: GrimoraCloudSyncConstants.currentSyncSchemaVersion + 1)
    )
    XCTAssertEqual(model.statusMessage, "Update Grimora to continue syncing across devices.")
  }

  func testEmptyDeviceAppliesRemoteSnapshotAndSearchSettings() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let remoteSnapshot = deviceSnapshot(
      id: "iphone",
      deviceName: "iPhone",
      listID: "remote-list",
      listName: "Remote Picks"
    )
    let coordinator = CloudSyncCoordinator(
      database: database,
      transport: MemoryCloudSyncTransport(state: CloudRemoteState(snapshots: [remoteSnapshot]))
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, cloudSyncCoordinator: coordinator),
      initialDefaultSearchConfiguration: GrimoraDefaultSearchConfiguration(text: "")
    )

    model.cloudSyncMode = .enabled
    await model.startCloudSync()

    guard case .appliedRemoteSnapshot(let appliedSnapshot) = model.cloudSyncStatus else {
      return XCTFail("Expected remote snapshot application, got \(model.cloudSyncStatus)")
    }

    XCTAssertEqual(appliedSnapshot.deviceName, "Grimora Device")
    XCTAssertEqual(model.cardCollections.map(\.name), ["Favourites", "Remote Picks"])
    XCTAssertEqual(model.defaultSearchConfiguration.text, "type:creature")
    XCTAssertEqual(model.statusMessage, "iCloud sync is ready.")
  }

  func testBootstrapCombineKeepsBothListsSharingANameWithoutResolution() async throws {
    // A name collision between two different lists is no longer a conflict: both
    // are kept side by side and the user is never asked to resolve.
    let database = try CardDatabase(storage: .inMemory)
    let card = testCard()
    try database.replaceAllCards([card])
    let localList = try database.createCardCollection(named: "Remote Picks")
    try database.appendCard(card.id, toList: localList.id)
    let remoteSnapshot = deviceSnapshot(
      id: "ipad",
      deviceName: "iPad",
      listID: "remote-list",
      listName: "Remote Picks"
    )
    let coordinator = CloudSyncCoordinator(
      database: database,
      transport: MemoryCloudSyncTransport(state: CloudRemoteState(snapshots: [remoteSnapshot]))
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, cloudSyncCoordinator: coordinator)
    )

    model.cloudSyncMode = .enabled
    await model.startCloudSync()

    // A name collision auto-merges (both kept side by side) — never a prompt.
    XCTAssertEqual(
      model.cardCollections.filter { $0.name == "Remote Picks" }.count,
      2
    )
  }

  func testRunningDevicesPropagateListsFavouritesAndSelectedListState() async throws {
    let transport = MemoryCloudSyncTransport()
    let databaseA = try CardDatabase(storage: .inMemory)
    let databaseB = try CardDatabase(storage: .inMemory)
    let card = testCard()
    try databaseA.replaceAllCards([card])
    try databaseB.replaceAllCards([card])

    let modelA = GrimoraAppModel(
      environment: environment(
        database: databaseA,
        cloudSyncCoordinator: CloudSyncCoordinator(database: databaseA, transport: transport)
      ),
      cloudSyncDeviceID: "device-a",
      cloudSyncDeviceName: "Device A",
      initialCloudSyncSearchSettingsUpdatedAt: .distantPast
    )
    modelA.cloudSyncMode = .enabled
    await modelA.startCloudSync()

    let modelB = GrimoraAppModel(
      environment: environment(
        database: databaseB,
        cloudSyncCoordinator: CloudSyncCoordinator(database: databaseB, transport: transport)
      ),
      cloudSyncDeviceID: "device-b",
      cloudSyncDeviceName: "Device B",
      initialCloudSyncSearchSettingsUpdatedAt: .distantPast
    )
    modelB.cloudSyncMode = .enabled
    await modelB.startCloudSync()

    modelA.addHiddenTerm(.forKeyword("Devoid"))
    let hiddenTermArrived = await waitUntil {
      modelB.hiddenSearchTerms == [.forKeyword("Devoid", intent: .exclude)]
    }
    XCTAssertTrue(hiddenTermArrived)

    let sharedList = try XCTUnwrap(
      modelA.createCardCollection(named: "Live Picks", selectAfterCreate: true)
    )
    let createdListArrived = await waitUntil {
      modelB.cardCollections.contains { $0.id == sharedList.id }
    }
    XCTAssertTrue(createdListArrived)

    modelB.selectCardCollection(id: sharedList.id)
    modelA.renameCardCollection(id: sharedList.id, to: "Renamed Live Picks")
    XCTAssertEqual(
      modelA.cardCollections.first { $0.id == sharedList.id }?.name,
      "Renamed Live Picks",
      "The local rename must commit before any remote reconciliation."
    )
    let immediateRenameTimestamp = try databaseA.cardCollection(id: sharedList.id)?.updatedAt
    let renamedListArrived = await waitUntil {
      modelB.selectedCollection?.name == "Renamed Live Picks"
        && modelB.sidebarSelection == .list(sharedList.id)
    }
    let renamedRemoteState = await transport.currentState()
    let saveHistory = await transport.saveHistory()
    XCTAssertTrue(
      renamedListArrived,
      """
      immediateRenameTimestamp=\(String(describing: immediateRenameTimestamp?.timeIntervalSince1970)), \
      aStatus=\(modelA.cloudSyncStatus), \
      aLists=\(modelA.cardCollections.map { "\($0.id):\($0.name):\($0.updatedAt.timeIntervalSince1970)" }), \
      bStatus=\(modelB.cloudSyncStatus), \
      bLists=\(modelB.cardCollections.map { "\($0.id):\($0.name):\($0.updatedAt.timeIntervalSince1970)" }), \
      remote=\(renamedRemoteState.snapshots.flatMap(\.listSnapshot.lists).map { "\($0.id):\($0.name):\($0.updatedAt.timeIntervalSince1970)" }), \
      saves=\(saveHistory.map { snapshot in
        "\(snapshot.id)[\(snapshot.listSnapshot.lists.map { "\($0.name):\($0.updatedAt.timeIntervalSince1970)" }.joined(separator: ","))]"
      })
      """
    )

    modelA.addCardToFavourites(card)
    let favouriteArrived = await waitUntil {
      guard let favouritesID = modelB.favouritesList?.id else {
        return false
      }
      modelB.selectCardCollection(id: favouritesID)
      return modelB.selectedCollectionEntries.map(\.cardID) == [card.id]
    }
    XCTAssertTrue(favouriteArrived)

    let favouriteEntry = try XCTUnwrap(modelA.favouritesList).id
    modelA.selectCardCollection(id: favouriteEntry)
    let favouriteEntryID = try XCTUnwrap(modelA.selectedCollectionEntries.first).id
    modelA.removeCardCollectionEntriesCompletely(ids: [favouriteEntryID])
    let favouriteRemovalArrived = await waitUntil {
      modelB.favouritesList.map { list in
        modelB.selectCardCollection(id: list.id)
        return modelB.selectedCollectionEntries.isEmpty
      } ?? false
    }
    XCTAssertTrue(favouriteRemovalArrived)

    modelA.deleteCardCollection(id: sharedList.id)
    let deletionArrived = await waitUntil {
      !modelB.cardCollections.contains { $0.id == sharedList.id }
        && modelB.selectedCollectionID != sharedList.id
    }
    XCTAssertTrue(deletionArrived)

    modelA.keepDeviceSeparate()
    modelB.keepDeviceSeparate()
  }

  func testTransportFailureEventIsVisibleWhileSyncIsRunning() async throws {
    let transport = MemoryCloudSyncTransport()
    let database = try CardDatabase(storage: .inMemory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        cloudSyncCoordinator: CloudSyncCoordinator(database: database, transport: transport)
      ),
      cloudSyncDeviceID: "device-a",
      initialCloudSyncSearchSettingsUpdatedAt: .distantPast
    )
    model.cloudSyncMode = .enabled
    await model.startCloudSync()

    await transport.publish(.failed("CloudKit fetch failed."))

    let failureArrived = await waitUntil {
      model.cloudSyncStatus == .failed("CloudKit fetch failed.")
        && model.statusMessage == "CloudKit fetch failed."
    }
    XCTAssertTrue(failureArrived)
    model.keepDeviceSeparate()
  }

  func testSearchSettingsModificationDateAdvancesWhileSyncIsDisabled() throws {
    let database = try CardDatabase(storage: .inMemory)
    let model = GrimoraAppModel(
      environment: environment(database: database),
      initialCloudSyncSearchSettingsUpdatedAt: .distantPast
    )

    model.applySearchPreferences(
      GrimoraDefaultSearchConfiguration(text: "type:artifact")
    )

    XCTAssertGreaterThan(model.currentSyncSearchSettings().updatedAt, Date.distantPast)
  }

  func testRecoveryCopyIsVisibleAndRestorableThroughAppModel() throws {
    let database = try CardDatabase(storage: .inMemory)
    let localList = try database.createCardCollection(
      named: "Existing Deck",
      now: Date(timeIntervalSince1970: 10)
    )
    try database.applyDeviceSyncSnapshot(
      deviceSnapshot(
        id: "remote",
        deviceName: "Remote",
        listID: "remote-list",
        listName: "Remote Deck"
      )
    )
    let model = GrimoraAppModel(environment: environment(database: database))

    let recovery = try XCTUnwrap(model.cloudSyncRecoverySnapshots.first)
    XCTAssertEqual(recovery.listSnapshot.lists.map(\.id), [localList.id])

    model.restoreCloudSyncRecoverySnapshot(id: recovery.id)

    XCTAssertEqual(Set(model.cardCollections.map(\.name)), ["Existing Deck", "Favourites"])
    XCTAssertEqual(model.statusMessage, "Restored collections from before iCloud sync.")
    XCTAssertFalse(try database.pendingSyncChanges().isEmpty)
    XCTAssertGreaterThan(model.cloudSyncRecoverySnapshots.count, 1)
  }

  func testIncomingRemoteChangeSurfacesUndoableMergeNotice() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([testCard()])
    let list = try database.createCardCollection(named: "Picks", now: Date(timeIntervalSince1970: 10))
    try database.markCloudSyncBootstrapResolved(true)

    // The server already holds a newer copy of the same list, edited on another device.
    let transport = MemoryCloudSyncTransport(
      state: CloudRemoteState(
        snapshots: [
          deviceSnapshot(
            id: "other-device",
            deviceName: "iPad",
            listID: list.id,
            listName: "Renamed remotely"
          )
        ]
      )
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        cloudSyncCoordinator: CloudSyncCoordinator(database: database, transport: transport)
      ),
      cloudSyncDeviceID: "device-a",
      cloudSyncDeviceName: "Device A",
      initialCloudSyncSearchSettingsUpdatedAt: .distantPast
    )
    model.cloudSyncMode = .enabled
    // Pretend the first-launch sync already finished so incoming changes are notified.
    model.hasCompletedInitialCloudSync = true

    // Pulling applies the newer remote copy (last-writer-wins), overwriting the local
    // name and surfacing a non-blocking, undoable notice — never a modal.
    await model.pushCloudSyncChanges()
    XCTAssertEqual(model.cardCollections.first { $0.id == list.id }?.name, "Renamed remotely")
    XCTAssertNotNil(model.cloudSyncMergeNotice, "An overwriting remote change should offer Undo.")

    // Undo restores the pre-merge local copy.
    model.undoCloudSyncMerge()
    XCTAssertNil(model.cloudSyncMergeNotice)
    XCTAssertEqual(model.cardCollections.first { $0.id == list.id }?.name, "Picks")
  }

  private func waitUntil(
    attempts: Int = 100,
    condition: () -> Bool
  ) async -> Bool {
    for _ in 0..<attempts {
      if condition() {
        return true
      }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
  }

  private func testCard() -> CardRecord {
    CardRecord(
      id: "alpha",
      name: "Alpha",
      setCode: "tst",
      setName: "Test",
      setType: "expansion",
      collectorNumber: "1",
      rarity: "common",
      colorSortKey: 0,
      layout: "normal",
      typeLine: "Creature",
      oracleText: ""
    )
  }

  func testAppliedRemoteSnapshotPopulatesSidebarEntryCount() async throws {
    // After an applied remote snapshot the cached `CardCollectionRecord.entryCount` that the
    // sidebar (and the list-detail header) read must match the entries that landed — the
    // regression where a populated list showed "0 cards" because the in-memory count was
    // never re-derived from the database.
    let database = try CardDatabase(storage: .inMemory)
    let date = Date(timeIntervalSince1970: 100)
    let remoteList = CardCollectionRecord(
      id: "remote-list",
      name: "Remote Picks",
      createdAt: date,
      updatedAt: date
    )
    let entries = [("alpha", 3), ("bravo", 2)].enumerated().map { index, pair in
      CardCollectionEntryRecord(
        id: "remote-entry-\(pair.0)",
        listID: remoteList.id,
        cardID: pair.0,
        position: index,
        quantity: pair.1,
        createdAt: date
      )
    }
    let remoteSnapshot = DeviceSyncSnapshot(
      id: "ipad",
      deviceName: "iPad",
      capturedAt: date,
      libraryIdentity: LibraryIdentity(),
      searchSettings: SyncSearchSettings(updatedAt: date),
      listSnapshot: CardCollectionLibrarySnapshot(
        lists: [remoteList],
        categories: [],
        entries: entries
      )
    )
    let coordinator = CloudSyncCoordinator(
      database: database,
      transport: MemoryCloudSyncTransport(state: CloudRemoteState(snapshots: [remoteSnapshot]))
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, cloudSyncCoordinator: coordinator)
    )

    model.cloudSyncMode = .enabled
    await model.startCloudSync()

    guard case .appliedRemoteSnapshot = model.cloudSyncStatus else {
      return XCTFail("Expected remote snapshot application, got \(model.cloudSyncStatus)")
    }
    let applied = try XCTUnwrap(model.cardCollections.first { $0.id == "remote-list" })
    XCTAssertEqual(applied.entryCount, 5, "Sidebar count must reflect the applied entry quantities (3 + 2).")
  }

  private func environment(
    database: CardDatabase,
    cloudSyncCoordinator: CloudSyncCoordinator? = nil
  ) -> GrimoraEnvironment {
    let imageStore = ImageStore(
      rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
      )
    )
    let bulkClient = BulkDataClient(network: BlockingNetworkClient())
    return GrimoraEnvironment(
      database: database,
      updateService: LibraryUpdateService(database: database, bulkDataClient: bulkClient),
      importer: LibraryImporter(database: database, imageResolver: NoImageResolver()),
      imageCache: CardImageCache(database: database, imageResolver: NoImageResolver()),
      imageStore: imageStore,
      searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration(
        textDebounceNanoseconds: 0,
        prefetchesNextPage: false
      ),
      temporaryDirectory: FileManager.default.temporaryDirectory,
      autoUpdateChecksEnabled: false,
      searchHistoryStore: isolatedSearchHistoryStore(),
      hiddenSearchTermsStore: HiddenSearchTermsStore(userDefaults: isolatedUserDefaults()),
      cloudSyncCoordinator: cloudSyncCoordinator
    )
  }

  private func isolatedSearchHistoryStore() -> GrimoraSearchHistoryStore {
    GrimoraSearchHistoryStore(userDefaults: isolatedUserDefaults())
  }

  private func isolatedUserDefaults() -> UserDefaults {
    let suiteName = "GrimoraCloudSyncAppModelTests-\(UUID().uuidString)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
      fatalError("Unable to create isolated user defaults suite.")
    }
    userDefaults.removePersistentDomain(forName: suiteName)
    return userDefaults
  }

  private func deviceSnapshot(
    id: String,
    deviceName: String,
    listID: String,
    listName: String
  ) -> DeviceSyncSnapshot {
    let date = Date(timeIntervalSince1970: 42)
    return DeviceSyncSnapshot(
      id: id,
      deviceName: deviceName,
      capturedAt: date,
      libraryIdentity: LibraryIdentity(),
      searchSettings: SyncSearchSettings(defaultSearchText: "type:creature", updatedAt: date),
      listSnapshot: CardCollectionLibrarySnapshot(
        lists: [
          CardCollectionRecord(
            id: listID,
            name: listName,
            descriptionPlainText: "synced notes",
            createdAt: date,
            updatedAt: date
          )
        ],
        categories: [],
        entries: []
      )
    )
  }
}
