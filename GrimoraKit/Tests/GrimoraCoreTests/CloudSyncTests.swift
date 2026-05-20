@testable import GrimoraCore
import XCTest

final class CloudSyncTests: XCTestCase {
    func testLibraryIdentityRequirementComparesDatabaseAndSchemaVersions() {
        let local = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")

        XCTAssertEqual(local.requirement(for: local), .satisfied)

        let newerDatabase = libraryIdentity(updatedAt: "2026-05-01T00:00:00.000+00:00")
        XCTAssertEqual(newerDatabase.requirement(for: local), .needsDatabaseUpdate(newerDatabase))

        let newerSearchSchema = libraryIdentity(
            updatedAt: "2026-04-25T09:09:59.477+00:00",
            searchSchemaVersion: "\((Int(CardDatabase.currentSearchSchemaVersion) ?? 0) + 1)"
        )
        XCTAssertEqual(newerSearchSchema.requirement(for: local), .needsDatabaseUpdate(newerSearchSchema))

        let newerApp = libraryIdentity(
            updatedAt: "2026-04-25T09:09:59.477+00:00",
            syncSchemaVersion: GrimoraCloudSyncConstants.currentSyncSchemaVersion + 1
        )
        XCTAssertEqual(
            newerApp.requirement(for: local),
            .needsAppUpdate(requiredSyncSchemaVersion: GrimoraCloudSyncConstants.currentSyncSchemaVersion + 1)
        )
    }

    func testDatabaseExportsAndAppliesDeviceSnapshots() throws {
        let source = try Fixtures.database()
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        try source.saveLibraryIdentity(identity)

        let list = try source.createCardList(named: "Drafts", now: Date(timeIntervalSince1970: 10))
        let category = try source.createCardListCategory(
            inList: list.id,
            named: "Ramp",
            now: Date(timeIntervalSince1970: 11)
        )
        try source.setCardListDisplaySort(id: list.id, mode: .edhrecRank, direction: .descending)
        try source.setCardListViewMode(id: list.id, viewMode: .list)
        try source.appendCard("alpha", toList: list.id, categoryID: category.id, quantity: 2)

        let snapshot = try source.deviceSyncSnapshot(
            deviceID: "iphone",
            deviceName: "iPhone",
            searchSettings: SyncSearchSettings(defaultSearchText: "t:creature")
        )

        let target = try Fixtures.database()
        try target.applyDeviceSyncSnapshot(snapshot)

        XCTAssertEqual(try target.libraryIdentity(), identity)
        XCTAssertEqual(try target.cardLists().map(\.name), ["Drafts"])
        XCTAssertEqual(try target.cardList(id: list.id)?.displaySortMode, .edhrecRank)
        XCTAssertEqual(try target.cardList(id: list.id)?.displaySortDirection, .descending)
        XCTAssertEqual(try target.cardList(id: list.id)?.viewMode, .list)
        XCTAssertEqual(try target.cardListCategories(forListID: list.id).map(\.name), ["Ramp"])
        XCTAssertEqual(try target.cardListEntries(forListID: list.id).map(\.cardID), ["alpha"])
        XCTAssertEqual(try target.cardListEntries(forListID: list.id).map(\.quantity), [2])
    }

    func testOutboxAndTombstonesTrackSyncableLocalChanges() throws {
        let database = try Fixtures.database()
        let list = try database.createCardList(named: "Keepers")
        let entry = try database.appendCard("alpha", toList: list.id)

        try database.recordLocalSyncSnapshotChange(reason: "unit-test")
        let pending = try database.pendingSyncChanges()
        XCTAssertEqual(pending.map(\.entityType), [.snapshot])
        XCTAssertEqual(pending.map(\.operation), [.snapshot])

        try database.removeCardListEntryCompletely(id: entry.id)
        let entryTombstone = try XCTUnwrap(try database.syncTombstones().first)
        XCTAssertEqual(entryTombstone.entityType, .cardListEntry)
        XCTAssertEqual(entryTombstone.recordID, entry.id)

        try database.deleteCardList(id: list.id)
        let tombstones = try database.syncTombstones()
        XCTAssertTrue(tombstones.contains { $0.entityType == .cardList && $0.recordID == list.id })

        try database.markSyncChangesSent(ids: pending.map(\.id))
        XCTAssertTrue(try database.pendingSyncChanges().isEmpty)
    }

    func testCoordinatorPausesSyncUntilRequiredDatabaseMatches() async throws {
        let database = try Fixtures.database()
        try database.saveLibraryIdentity(libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00"))

        let requiredIdentity = libraryIdentity(updatedAt: "2026-05-01T00:00:00.000+00:00")
        let transport = MemoryCloudSyncTransport(
            state: CloudRemoteState(requiredLibraryIdentity: requiredIdentity)
        )
        let coordinator = CloudSyncCoordinator(database: database, transport: transport)

        let status = await coordinator.start(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings()
        )

        guard case .waitingForDatabaseUpdate(let identity) = status else {
            return XCTFail("Expected database update gate, got \(status)")
        }

        XCTAssertEqual(identity, requiredIdentity)
    }

    func testCoordinatorOffersBootstrapResolutionForDifferentDeviceData() async throws {
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        let remoteDatabase = try Fixtures.database()
        try remoteDatabase.saveLibraryIdentity(identity)
        _ = try remoteDatabase.createCardList(named: "Remote Picks")
        let remoteSnapshot = try remoteDatabase.deviceSyncSnapshot(
            deviceID: "ipad",
            deviceName: "iPad",
            searchSettings: SyncSearchSettings(),
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        let localDatabase = try Fixtures.database()
        try localDatabase.saveLibraryIdentity(identity)
        _ = try localDatabase.createCardList(named: "Local Picks")

        let transport = MemoryCloudSyncTransport(
            state: CloudRemoteState(requiredLibraryIdentity: identity, snapshots: [remoteSnapshot])
        )
        let coordinator = CloudSyncCoordinator(database: localDatabase, transport: transport)

        let status = await coordinator.start(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings()
        )

        guard case .resolving(let snapshots) = status else {
            return XCTFail("Expected bootstrap resolution, got \(status)")
        }

        XCTAssertEqual(Set(snapshots.map(\.deviceName)), ["iPad", "Mac"])
        XCTAssertTrue(snapshots.contains { $0.listSnapshot.lists.map(\.name) == ["Remote Picks"] })
        XCTAssertTrue(snapshots.contains { $0.listSnapshot.lists.map(\.name) == ["Local Picks"] })
    }

    func testCoordinatorAppliesRemoteSnapshotForEmptyNewDevice() async throws {
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        let remoteDatabase = try Fixtures.database()
        try remoteDatabase.saveLibraryIdentity(identity)
        _ = try remoteDatabase.createCardList(named: "Remote Picks")
        let remoteSnapshot = try remoteDatabase.deviceSyncSnapshot(
            deviceID: "ipad",
            deviceName: "iPad",
            searchSettings: SyncSearchSettings(defaultSearchText: "t:creature"),
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        let localDatabase = try Fixtures.database()
        try localDatabase.saveLibraryIdentity(identity)
        let transport = MemoryCloudSyncTransport(
            state: CloudRemoteState(requiredLibraryIdentity: identity, snapshots: [remoteSnapshot])
        )
        let coordinator = CloudSyncCoordinator(database: localDatabase, transport: transport)

        let status = await coordinator.start(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings(updatedAt: Date(timeIntervalSince1970: 1))
        )

        guard case .appliedRemoteSnapshot(let appliedSnapshot) = status else {
            return XCTFail("Expected remote snapshot application, got \(status)")
        }

        XCTAssertEqual(appliedSnapshot.id, "ipad")
        XCTAssertEqual(try localDatabase.cardLists().map(\.name), ["Remote Picks"])

        let remoteState = await transport.currentState()
        let macSnapshot = try XCTUnwrap(remoteState.snapshots.first { $0.id == "mac" })
        XCTAssertEqual(macSnapshot.listSnapshot.lists.map(\.name), ["Remote Picks"])
        XCTAssertEqual(macSnapshot.searchSettings.defaultSearchText, "t:creature")
    }

    func testCoordinatorPushesOutgoingChangesAndPersistsStateSerialization() async throws {
        let database = try Fixtures.database()
        try database.saveLibraryIdentity(libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00"))
        _ = try database.createCardList(named: "Local Picks")
        try database.recordLocalSyncSnapshotChange(reason: "unit-test")

        let transport = MemoryCloudSyncTransport()
        let coordinator = CloudSyncCoordinator(database: database, transport: transport)
        let status = await coordinator.pushLocalState(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings(defaultSearchText: "o:draw")
        )

        XCTAssertEqual(status, .ready)
        XCTAssertTrue(try database.pendingSyncChanges().isEmpty)
        let remoteState = await transport.currentState()
        XCTAssertEqual(remoteState.requiredLibraryIdentity, try database.libraryIdentity())
        XCTAssertEqual(remoteState.snapshots.first?.listSnapshot.lists.map(\.name), ["Local Picks"])

        let stateData = Data([1, 2, 3])
        try await coordinator.recordStateSerialization(stateData)
        XCTAssertEqual(try database.cloudSyncEngineStateSerialization(), stateData)
        try await coordinator.recordStateSerialization(nil)
        XCTAssertNil(try database.cloudSyncEngineStateSerialization())
    }

    func testResolutionPlanPreservesSelectedImportedListsWithCollidingIDs() throws {
        let source = snapshot(deviceID: "mac", listID: "shared-list", listName: "Mac Source")
        let imported = snapshot(deviceID: "ipad", listID: "shared-list", listName: "iPad Picks")

        let resolved = try SyncResolutionPlan(
            sourceSnapshotID: source.id,
            importedListIDsBySnapshotID: [imported.id: ["shared-list"]]
        )
        .resolvedSnapshot(from: [source, imported])

        XCTAssertEqual(resolved.listSnapshot.lists.count, 2)
        XCTAssertTrue(resolved.listSnapshot.lists.contains { $0.id == "shared-list" && $0.name == "Mac Source" })

        let importedList = try XCTUnwrap(
            resolved.listSnapshot.lists.first { $0.id != "shared-list" && $0.name == "iPad Picks (Imported)" }
        )
        XCTAssertEqual(resolved.listSnapshot.entries.filter { $0.listID == importedList.id }.map(\.cardID), ["beta"])
    }

    private func libraryIdentity(
        updatedAt: String?,
        searchSchemaVersion: String = CardDatabase.currentSearchSchemaVersion,
        syncSchemaVersion: Int = GrimoraCloudSyncConstants.currentSyncSchemaVersion
    ) -> LibraryIdentity {
        LibraryIdentity(
            defaultCardsUpdatedAt: updatedAt,
            defaultCardsDownloadURI: URL(string: "https://example.test/default-cards.json")!,
            defaultCardsName: "Default Cards",
            defaultCardsSize: 123,
            searchSchemaVersion: searchSchemaVersion,
            syncSchemaVersion: syncSchemaVersion
        )
    }

    private func snapshot(deviceID: String, listID: String, listName: String) -> DeviceSyncSnapshot {
        let date = Date(timeIntervalSince1970: deviceID == "mac" ? 10 : 20)
        let cardID = deviceID == "mac" ? "alpha" : "beta"
        return DeviceSyncSnapshot(
            id: deviceID,
            deviceName: deviceID,
            capturedAt: date,
            libraryIdentity: libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00"),
            searchSettings: SyncSearchSettings(updatedAt: date),
            listSnapshot: CardListLibrarySnapshot(
                lists: [
                    CardListRecord(
                        id: listID,
                        name: listName,
                        createdAt: date,
                        updatedAt: date,
                        entryCount: 1
                    )
                ],
                categories: [],
                entries: [
                    CardListEntryRecord(
                        id: "\(deviceID)-entry",
                        listID: listID,
                        cardID: cardID,
                        position: 0,
                        createdAt: date
                    )
                ]
            )
        )
    }
}
