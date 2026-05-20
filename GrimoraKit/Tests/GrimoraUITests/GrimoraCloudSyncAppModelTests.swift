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

  func testRemoteRequiredDatabaseShowsUpdateRequiredState() async throws {
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

    XCTAssertEqual(model.requiredCloudLibraryIdentity, requiredIdentity)
    XCTAssertEqual(
      model.statusMessage,
      "A synced card database update is required before lists can sync."
    )
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

    XCTAssertEqual(appliedSnapshot.id, "iphone")
    XCTAssertEqual(model.cardLists.map(\.name), ["Favourites", "Remote Picks"])
    XCTAssertEqual(model.defaultSearchConfiguration.text, "type:creature")
    XCTAssertEqual(model.statusMessage, "iCloud sync is ready.")
  }

  func testSourceOfTruthResolutionCanImportSelectedLocalLists() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let localList = try database.createCardList(named: "Local Picks")
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

    XCTAssertEqual(Set(model.cloudSyncResolutionSnapshots.map(\.deviceName)), ["iPad", "Grimora Device"])

    let localSnapshot = try XCTUnwrap(
      model.cloudSyncResolutionSnapshots.first { $0.deviceName == "Grimora Device" }
    )
    await model.resolveCloudSync(
      sourceSnapshotID: remoteSnapshot.id,
      importedListIDsBySnapshotID: [localSnapshot.id: [localList.id]]
    )

    XCTAssertEqual(model.cloudSyncStatus, .ready)
    XCTAssertEqual(Set(model.cardLists.map(\.name)), ["Favourites", "Remote Picks", "Local Picks"])
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
      plainTextSearchTranspiler: UnavailablePlainTextSearchTranspiler(message: "Unavailable in tests."),
      searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration(
        textDebounceNanoseconds: 0,
        prefetchesNextPage: false
      ),
      temporaryDirectory: FileManager.default.temporaryDirectory,
      autoUpdateChecksEnabled: false,
      searchHistoryStore: isolatedSearchHistoryStore(),
      plainTextSearchHistoryStore: GrimoraSearchHistoryStore(
        userDefaults: isolatedUserDefaults(),
        key: GrimoraSearchPreferences.plainTextSearchHistoryKey
      ),
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
      listSnapshot: CardListLibrarySnapshot(
        lists: [
          CardListRecord(
            id: listID,
            name: listName,
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
