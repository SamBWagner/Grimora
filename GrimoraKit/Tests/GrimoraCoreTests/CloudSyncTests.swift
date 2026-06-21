@testable import GrimoraCore
import XCTest

private struct CloudSyncSaveTestError: Error {}

private actor FailingSaveCloudSyncTransport: CloudSyncTransport {
    var state: CloudRemoteState

    init(state: CloudRemoteState = CloudRemoteState()) {
        self.state = state
    }

    func fetchRemoteState() async throws -> CloudRemoteState {
        state
    }

    func save(snapshot: DeviceSyncSnapshot, requiredLibraryIdentity: LibraryIdentity) async throws {
        throw CloudSyncSaveTestError()
    }
}

final class CloudSyncTests: XCTestCase {
    func testCloudKitSchemaContractContainsEveryRequiredRecordType() {
        XCTAssertEqual(
            Set(GrimoraCloudKitSchema.allRecordTypes),
            [
                "LibraryIdentity",
                "DeviceSnapshot",
                "GrimoraSyncMetadata",
                "GrimoraUserPreferences",
                "GrimoraCardList",
                "GrimoraCardListCategory",
                "GrimoraCardListEntry",
                "GrimoraRecoveryRevision",
            ]
        )
        XCTAssertEqual(GrimoraCloudKitSchema.zoneName, "GrimoraSync")
        XCTAssertEqual(
            Set(GrimoraCloudKitSchema.allFieldNames),
            [
                "payload",
                "capturedAt",
                "updatedAt",
                "deletedAt",
                "entityID",
                "sourceDeviceID",
            ]
        )
        for recordType in GrimoraCloudKitSchema.entityRecordTypes {
            XCTAssertEqual(
                GrimoraCloudKitSchema.requiredFields(for: recordType),
                GrimoraCloudKitSchema.entityFields
            )
        }
        for recordType in GrimoraCloudKitSchema.legacyRecordTypes {
            XCTAssertEqual(
                GrimoraCloudKitSchema.requiredFields(for: recordType),
                GrimoraCloudKitSchema.historicalFields
            )
        }
        XCTAssertTrue(GrimoraCloudKitSchema.requiredFields(for: "Unknown").isEmpty)
    }

    func testLibraryIdentityRequirementOnlyGatesNewerSyncSchema() {
        let local = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")

        XCTAssertEqual(local.requirement(for: local), .satisfied)

        let newerDatabase = libraryIdentity(updatedAt: "2026-05-01T00:00:00.000+00:00")
        XCTAssertEqual(newerDatabase.requirement(for: local), .satisfied)

        let newerSearchSchema = libraryIdentity(
            updatedAt: "2026-04-25T09:09:59.477+00:00",
            searchSchemaVersion: "\((Int(CardDatabase.currentSearchSchemaVersion) ?? 0) + 1)"
        )
        XCTAssertEqual(newerSearchSchema.requirement(for: local), .satisfied)

        let newerApp = libraryIdentity(
            updatedAt: "2026-04-25T09:09:59.477+00:00",
            syncSchemaVersion: GrimoraCloudSyncConstants.currentSyncSchemaVersion + 1
        )
        XCTAssertEqual(
            newerApp.requirement(for: local),
            .needsAppUpdate(requiredSyncSchemaVersion: GrimoraCloudSyncConstants.currentSyncSchemaVersion + 1)
        )
    }

    func testManagedCatalogIdentityIgnoresArtifactVersionWhenSchemasMatch() {
        let local = libraryIdentity(
            updatedAt: "v1-local",
            catalogSchemaVersion: CatalogManifest.currentSchemaVersion
        )
        let remote = libraryIdentity(
            updatedAt: "v1-remote",
            catalogSchemaVersion: CatalogManifest.currentSchemaVersion
        )

        XCTAssertEqual(remote.requirement(for: local), .satisfied)
    }

    func testManagedCatalogIdentityAcceptsLegacyRequiredIdentityDuringTransition() {
        let local = libraryIdentity(
            updatedAt: "v1-managed",
            catalogSchemaVersion: CatalogManifest.currentSchemaVersion
        )
        let legacyRemote = libraryIdentity(updatedAt: "2026-06-01")

        XCTAssertEqual(legacyRemote.requirement(for: local), .satisfied)
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

    func testCoordinatorSyncsUserDataAcrossDifferentCatalogVersions() async throws {
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

        XCTAssertEqual(status, .ready)
        let savedState = await transport.currentState()
        XCTAssertEqual(
            savedState.requiredLibraryIdentity,
            try database.libraryIdentity()
        )
    }

    func testCoordinatorAutomaticallyCombinesNonOverlappingDeviceData() async throws {
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        let remoteDatabase = try Fixtures.database()
        try remoteDatabase.saveLibraryIdentity(identity)
        let remotePicks = try remoteDatabase.createCardList(named: "Remote Picks")
        try remoteDatabase.appendCard("beta", toList: remotePicks.id)
        let remoteSnapshot = try remoteDatabase.deviceSyncSnapshot(
            deviceID: "ipad",
            deviceName: "iPad",
            searchSettings: SyncSearchSettings(),
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        let localDatabase = try Fixtures.database()
        try localDatabase.saveLibraryIdentity(identity)
        let localPicks = try localDatabase.createCardList(named: "Local Picks")
        try localDatabase.appendCard("alpha", toList: localPicks.id)

        let transport = MemoryCloudSyncTransport(
            state: CloudRemoteState(requiredLibraryIdentity: identity, snapshots: [remoteSnapshot])
        )
        let coordinator = CloudSyncCoordinator(database: localDatabase, transport: transport)

        let status = await coordinator.start(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings()
        )

        guard case .appliedRemoteSnapshot(let appliedSnapshot) = status else {
            return XCTFail("Expected automatic bootstrap merge, got \(status)")
        }

        XCTAssertEqual(appliedSnapshot.deviceName, "Mac")
        XCTAssertEqual(
            Set(try localDatabase.cardLists().map(\.name)),
            ["Remote Picks", "Local Picks"]
        )
        XCTAssertFalse(try localDatabase.cloudSyncRecoverySnapshots().isEmpty)
    }

    func testCoordinatorAppliesRemoteSnapshotForEmptyNewDevice() async throws {
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        let remoteDatabase = try Fixtures.database()
        try remoteDatabase.saveLibraryIdentity(identity)
        let remotePicks = try remoteDatabase.createCardList(named: "Remote Picks")
        try remoteDatabase.appendCard("beta", toList: remotePicks.id)
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

        XCTAssertEqual(appliedSnapshot.id, "mac")
        XCTAssertEqual(try localDatabase.cardLists().map(\.name), ["Remote Picks"])

        let remoteState = await transport.currentState()
        let entitySnapshot = try XCTUnwrap(remoteState.snapshots.first)
        XCTAssertEqual(entitySnapshot.id, CloudSyncEntityCodec.entitySnapshotID)
        XCTAssertEqual(entitySnapshot.listSnapshot.lists.map(\.name), ["Remote Picks"])
        XCTAssertEqual(entitySnapshot.searchSettings.defaultSearchText, "t:creature")
    }

    func testEmptyReplacementDatabaseRecoversCloudSnapshotWithSameDeviceID() async throws {
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        let remoteSnapshot = snapshot(
            deviceID: "stable-device-id",
            listID: "existing-list",
            listName: "Existing User Data"
        )
        let transport = MemoryCloudSyncTransport(
            state: CloudRemoteState(
                requiredLibraryIdentity: identity,
                snapshots: [remoteSnapshot]
            )
        )
        let replacementDatabase = try Fixtures.database()
        try replacementDatabase.saveLibraryIdentity(identity)
        let coordinator = CloudSyncCoordinator(database: replacementDatabase, transport: transport)

        let status = await coordinator.start(
            deviceID: "stable-device-id",
            deviceName: "Replacement Device",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )

        guard case .appliedRemoteSnapshot = status else {
            return XCTFail("Expected the retained same-device cloud snapshot, got \(status).")
        }
        XCTAssertEqual(try replacementDatabase.cardLists().map(\.name), ["Existing User Data"])
        let savedState = await transport.currentState()
        XCTAssertEqual(savedState.snapshots.first?.listSnapshot.lists.map(\.name), ["Existing User Data"])
    }

    func testSameDeviceBootstrapAutomaticallyCombinesUniqueCloudAndLocalLists() async throws {
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        let remoteSnapshot = snapshot(
            deviceID: "stable-device-id",
            listID: "remote-list",
            listName: "Cloud Copy"
        )
        let localDatabase = try Fixtures.database()
        try localDatabase.saveLibraryIdentity(identity)
        let localCopy = try localDatabase.createCardList(named: "Local Copy")
        try localDatabase.appendCard("alpha", toList: localCopy.id)
        let coordinator = CloudSyncCoordinator(
            database: localDatabase,
            transport: MemoryCloudSyncTransport(
                state: CloudRemoteState(
                    requiredLibraryIdentity: identity,
                    snapshots: [remoteSnapshot]
                )
            )
        )

        let status = await coordinator.start(
            deviceID: "stable-device-id",
            deviceName: "Current Device",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )

        guard case .appliedRemoteSnapshot = status else {
            return XCTFail("Expected unique lists to combine automatically, got \(status).")
        }
        XCTAssertEqual(
            Set(try localDatabase.cardLists().map(\.name)),
            ["Cloud Copy", "Local Copy"]
        )
    }

    func testCoordinatorKeepsDivergentListsSharingANameWithoutResolution() async throws {
        // Two different lists (distinct IDs) that merely share a name are kept
        // side by side; a name collision is not a conflict to resolve.
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        let remoteSnapshot = snapshot(
            deviceID: "ipad",
            listID: "remote-shared",
            listName: "Shared Deck"
        )
        let localDatabase = try Fixtures.database()
        try localDatabase.saveLibraryIdentity(identity)
        let localList = try localDatabase.createCardList(named: "Shared Deck")
        try localDatabase.appendCard("alpha", toList: localList.id)
        let coordinator = CloudSyncCoordinator(
            database: localDatabase,
            transport: MemoryCloudSyncTransport(
                state: CloudRemoteState(
                    requiredLibraryIdentity: identity,
                    snapshots: [remoteSnapshot]
                )
            )
        )

        let status = await coordinator.start(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )

        guard case .appliedRemoteSnapshot(let applied) = status else {
            return XCTFail("Expected an automatic merge without resolution, got \(status).")
        }
        XCTAssertEqual(
            try localDatabase.cardLists().filter { $0.name == "Shared Deck" }.count,
            2
        )

        // A follow-up sync (carrying the applied settings, as the app does) must
        // settle to a quiet `.ready` rather than re-opening resolution or churning.
        let settled = await coordinator.reconcileRemoteState(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: applied.searchSettings
        )
        guard case .ready = settled else {
            return XCTFail("Expected the state to settle to ready, got \(settled).")
        }
    }

    func testPruningEmptyContentlessListsKeepsOnlyMeaningfulLists() throws {
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = DeviceSyncSnapshot(
            id: "device",
            deviceName: "Device",
            capturedAt: now,
            libraryIdentity: libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00"),
            searchSettings: SyncSearchSettings(updatedAt: now),
            listSnapshot: CardListLibrarySnapshot(
                lists: [
                    CardListRecord(id: "empty", name: "Empty Scratch", createdAt: now, updatedAt: now),
                    CardListRecord(
                        id: "described",
                        name: "Has Notes",
                        descriptionPlainText: "deck idea",
                        createdAt: now,
                        updatedAt: now
                    ),
                    CardListRecord(
                        id: "real",
                        name: "Real Deck",
                        createdAt: now,
                        updatedAt: now,
                        entryCount: 1
                    ),
                    CardListRecord(id: "fav", name: "Favourites", createdAt: now, updatedAt: now),
                ],
                categories: [],
                entries: [
                    CardListEntryRecord(
                        id: "real-entry",
                        listID: "real",
                        cardID: "alpha",
                        position: 0,
                        createdAt: now
                    )
                ]
            )
        )

        let pruned = CloudSyncEntityCodec.pruningEmptyContentlessLists(snapshot)

        XCTAssertEqual(
            Set(pruned.listSnapshot.lists.map(\.name)),
            ["Has Notes", "Real Deck", "Favourites"]
        )
        XCTAssertTrue(pruned.deletedLists.contains { $0.id == "empty" })
        XCTAssertTrue(
            pruned.deletedEntities.contains { $0.entityType == .cardList && $0.recordID == "empty" }
        )
    }

    func testBootstrapCombineErasesEmptyContentlessLists() async throws {
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        let remoteSnapshot = snapshot(deviceID: "ipad", listID: "cloud-list", listName: "Cloud Deck")
        let localDatabase = try Fixtures.database()
        try localDatabase.saveLibraryIdentity(identity)
        let keeper = try localDatabase.createCardList(named: "Keeper")
        try localDatabase.appendCard("alpha", toList: keeper.id)
        _ = try localDatabase.createCardList(named: "Empty Scratch")
        let transport = MemoryCloudSyncTransport(
            state: CloudRemoteState(requiredLibraryIdentity: identity, snapshots: [remoteSnapshot])
        )
        let coordinator = CloudSyncCoordinator(database: localDatabase, transport: transport)

        guard case .appliedRemoteSnapshot = await coordinator.start(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        ) else {
            return XCTFail("Expected an automatic bootstrap combine.")
        }

        XCTAssertEqual(
            Set(try localDatabase.cardLists().map(\.name)),
            ["Keeper", "Cloud Deck"]
        )
        let remoteState = await transport.currentState()
        XCTAssertFalse(
            remoteState.snapshots.flatMap(\.listSnapshot.lists).contains { $0.name == "Empty Scratch" }
        )
    }

    func testCoordinatorPushesOutgoingChangesAndPersistsStateSerialization() async throws {
        let database = try Fixtures.database()
        try database.saveLibraryIdentity(libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00"))
        _ = try database.createCardList(named: "Local Picks")
        try database.recordLocalSyncSnapshotChange(reason: "unit-test")

        let transport = MemoryCloudSyncTransport()
        let coordinator = CloudSyncCoordinator(database: database, transport: transport)
        let searchSettings = SyncSearchSettings(defaultSearchText: "o:draw")
        let localBeforePush = try database.deviceSyncSnapshot(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: searchSettings
        )
        let roundTrippedBeforePush = try XCTUnwrap(
            CloudSyncEntityCodec.snapshot(
                from: CloudSyncEntityCodec.records(from: localBeforePush),
                fallbackIdentity: localBeforePush.libraryIdentity
            )
        )
        XCTAssertEqual(
            try CardDatabase.syncJSONData(roundTrippedBeforePush.listSnapshot),
            try CardDatabase.syncJSONData(localBeforePush.listSnapshot)
        )
        XCTAssertEqual(
            try CardDatabase.syncJSONData(roundTrippedBeforePush.searchSettings),
            try CardDatabase.syncJSONData(localBeforePush.searchSettings)
        )
        let status = await coordinator.pushLocalState(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: searchSettings
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
            resolved.listSnapshot.lists.first { $0.id != "shared-list" && $0.name == "iPad Picks" }
        )
        XCTAssertEqual(resolved.listSnapshot.entries.filter { $0.listID == importedList.id }.map(\.cardID), ["beta"])
    }

    func testResolutionMergesEveryDevicesFavouritesIntoOne() throws {
        let source = snapshot(deviceID: "mac", listID: "fav-mac", listName: "Favourites")
        let imported = snapshot(deviceID: "ipad", listID: "fav-ipad", listName: "Favourites")

        let resolved = try SyncResolutionPlan(
            sourceSnapshotID: source.id,
            importedListIDsBySnapshotID: [imported.id: ["fav-ipad"]]
        )
        .resolvedSnapshot(from: [source, imported])

        XCTAssertEqual(resolved.listSnapshot.lists.count, 1)
        let favourites = try XCTUnwrap(resolved.listSnapshot.lists.first)
        XCTAssertEqual(favourites.id, CloudSyncEntityCodec.favouritesListID)
        XCTAssertEqual(favourites.name, "Favourites")
        XCTAssertEqual(
            resolved.listSnapshot.entries
                .filter { $0.listID == CloudSyncEntityCodec.favouritesListID }
                .map(\.cardID)
                .sorted(),
            ["alpha", "beta"]
        )
    }

    func testResolutionNumbersGenuinelyDifferentListsSharingAName() throws {
        let source = snapshot(deviceID: "mac", listID: "aggro-mac", listName: "Aggro")
        let imported = snapshot(deviceID: "ipad", listID: "aggro-ipad", listName: "Aggro")

        let resolved = try SyncResolutionPlan(
            sourceSnapshotID: source.id,
            importedListIDsBySnapshotID: [imported.id: ["aggro-ipad"]]
        )
        .resolvedSnapshot(from: [source, imported])

        XCTAssertEqual(resolved.listSnapshot.lists.count, 2)
        XCTAssertTrue(resolved.listSnapshot.lists.contains { $0.id == "aggro-mac" && $0.name == "Aggro" })
        let renamed = try XCTUnwrap(resolved.listSnapshot.lists.first { $0.name == "Aggro 2" })
        XCTAssertEqual(
            resolved.listSnapshot.entries.filter { $0.listID == renamed.id }.map(\.cardID),
            ["beta"]
        )
        XCTAssertFalse(resolved.listSnapshot.lists.contains { $0.name.contains("(Imported)") })
    }

    func testResolutionNumbersDivergentNamesCaseInsensitively() throws {
        let source = snapshot(deviceID: "mac", listID: "aggro-mac", listName: "Aggro")
        let imported = snapshot(deviceID: "ipad", listID: "aggro-ipad", listName: "AGGRO")

        let resolved = try SyncResolutionPlan(
            sourceSnapshotID: source.id,
            importedListIDsBySnapshotID: [imported.id: ["aggro-ipad"]]
        )
        .resolvedSnapshot(from: [source, imported])

        XCTAssertEqual(
            Set(resolved.listSnapshot.lists.map(\.name)),
            ["Aggro", "AGGRO 2"]
        )
    }

    func testManualResolutionAlwaysCreatesARecoverySnapshot() throws {
        let database = try Fixtures.database()
        let identity = libraryIdentity(updatedAt: "2026-06-21")
        try database.saveLibraryIdentity(identity)
        let local = try database.deviceSyncSnapshot(
            deviceID: "mac",
            deviceName: "This Mac",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )

        _ = try database.applySyncResolutionPlan(
            SyncResolutionPlan(sourceSnapshotID: local.id),
            snapshots: [local]
        )

        let recovery = try XCTUnwrap(try database.cloudSyncRecoverySnapshots().first)
        XCTAssertEqual(recovery.reason, "Before manually combining iCloud data")
    }

    func testBootstrapAnalyzerCollapsesSemanticallyIdenticalNamedLists() throws {
        let source = snapshot(deviceID: "mac", listID: "mac-list", listName: "Shared")
        var duplicate = source
        duplicate.id = "ipad"
        duplicate.deviceName = "iPad"
        duplicate.capturedAt = Date(timeIntervalSince1970: 30)
        duplicate.listSnapshot.lists[0].id = "ipad-list"
        duplicate.listSnapshot.entries[0].id = "ipad-entry"
        duplicate.listSnapshot.entries[0].listID = "ipad-list"

        let decision = try CloudSyncBootstrapAnalyzer.analyze(
            localSnapshot: source,
            remoteSnapshots: [duplicate]
        )

        guard case .apply(let merged) = decision else {
            return XCTFail("Expected identical lists to merge automatically.")
        }
        XCTAssertEqual(merged.listSnapshot.lists.map(\.name), ["Shared"])
        XCTAssertEqual(merged.listSnapshot.entries.count, 1)
    }

    func testBootstrapAnalyzerErasesEmptyContentlessListsWhenCombining() throws {
        let timestamp = Date(timeIntervalSince1970: 20)
        let local = emptySnapshot(
            deviceID: "mac",
            listID: "local-empty",
            listName: "Future Deck",
            timestamp: timestamp
        )
        let remote = emptySnapshot(
            deviceID: "ipad",
            listID: "remote-empty",
            listName: "Other Empty",
            timestamp: timestamp
        )

        let decision = try CloudSyncBootstrapAnalyzer.analyze(
            localSnapshot: local,
            remoteSnapshots: [remote]
        )

        guard case .apply(let merged) = decision else {
            return XCTFail("Expected empty lists to combine automatically.")
        }
        XCTAssertTrue(merged.listSnapshot.lists.isEmpty)
        XCTAssertTrue(merged.deletedLists.contains { $0.id == "local-empty" })
        XCTAssertTrue(merged.deletedLists.contains { $0.id == "remote-empty" })
    }

    func testBootstrapAnalyzerMergesFavouritesAndSearchHistories() throws {
        var local = snapshot(deviceID: "mac", listID: "fav-mac", listName: "Favourites")
        local.searchSettings = SyncSearchSettings(
            defaultSearchText: "type:artifact",
            searchHistory: ["type:artifact"],
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        var remote = snapshot(deviceID: "ipad", listID: "fav-ipad", listName: "Favourites")
        remote.searchSettings = SyncSearchSettings(
            defaultSearchText: "type:creature",
            searchHistory: ["type:creature"],
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        let decision = try CloudSyncBootstrapAnalyzer.analyze(
            localSnapshot: local,
            remoteSnapshots: [remote]
        )

        guard case .apply(let merged) = decision else {
            return XCTFail("Expected favourites and settings to merge automatically.")
        }
        XCTAssertEqual(merged.listSnapshot.lists.map(\.name), ["Favourites"])
        XCTAssertEqual(
            Set(merged.listSnapshot.entries.map(\.cardID)),
            ["alpha", "beta"]
        )
        XCTAssertEqual(merged.searchSettings.defaultSearchText, "type:creature")
        XCTAssertEqual(
            merged.searchSettings.searchHistory,
            ["type:creature", "type:artifact"]
        )
    }

    func testBootstrapAnalyzerRequiresResolutionForDeleteVersusEdit() throws {
        let local = snapshot(deviceID: "mac", listID: "shared-list", listName: "Shared")
        let remote = DeviceSyncSnapshot(
            id: "ipad",
            deviceName: "iPad",
            capturedAt: Date(timeIntervalSince1970: 30),
            libraryIdentity: local.libraryIdentity,
            searchSettings: SyncSearchSettings(updatedAt: Date(timeIntervalSince1970: 30)),
            listSnapshot: CardListLibrarySnapshot(lists: [], categories: [], entries: []),
            deletedLists: [
                SyncListDeletion(id: "shared-list", deletedAt: Date(timeIntervalSince1970: 30))
            ],
            deletedEntities: [
                SyncTombstone(
                    entityType: .cardList,
                    recordID: "shared-list",
                    deletedAt: Date(timeIntervalSince1970: 30)
                )
            ]
        )

        let decision = try CloudSyncBootstrapAnalyzer.analyze(
            localSnapshot: local,
            remoteSnapshots: [remote]
        )

        guard case .resolve(let context) = decision else {
            return XCTFail("Expected delete-versus-edit resolution.")
        }
        XCTAssertEqual(context.conflictingListIDs(for: local.id), ["shared-list"])
    }

    func testBootstrapResolutionDefaultsIncludeOnlySafeUniqueLists() throws {
        // The same list (matching ID) was edited differently on each device, which
        // is a genuine conflict. Each device's unique lists remain safe to import.
        var local = snapshot(deviceID: "mac", listID: "shared-list", listName: "Shared")
        let localUnique = snapshot(
            deviceID: "mac-unique",
            listID: "local-unique",
            listName: "Local Only"
        )
        local.listSnapshot.lists.append(contentsOf: localUnique.listSnapshot.lists)
        local.listSnapshot.entries.append(contentsOf: localUnique.listSnapshot.entries)

        var remote = snapshot(deviceID: "ipad", listID: "shared-list", listName: "Shared")
        let remoteUnique = snapshot(
            deviceID: "ipad-unique",
            listID: "remote-unique",
            listName: "Cloud Only"
        )
        remote.listSnapshot.lists.append(contentsOf: remoteUnique.listSnapshot.lists)
        remote.listSnapshot.entries.append(contentsOf: remoteUnique.listSnapshot.entries)

        let decision = try CloudSyncBootstrapAnalyzer.analyze(
            localSnapshot: local,
            remoteSnapshots: [remote]
        )

        guard case .resolve(let context) = decision else {
            return XCTFail("Expected a genuine same-list edit conflict.")
        }
        XCTAssertEqual(context.defaultSourceSnapshotID, CloudSyncEntityCodec.entitySnapshotID)
        XCTAssertEqual(
            context.safeImportedListIDs(for: context.defaultSourceSnapshotID)[local.id],
            ["local-unique"]
        )
        XCTAssertFalse(
            context.safeImportedListIDs(for: context.defaultSourceSnapshotID)[local.id, default: []]
                .contains("shared-list")
        )
    }

    func testConsolidatedEntitySnapshotOverridesLegacyDeviceSnapshots() {
        let legacyA = snapshot(deviceID: "mac", listID: "mac-list", listName: "Mac")
        let legacyB = snapshot(deviceID: "ipad", listID: "ipad-list", listName: "iPad")
        let entity = snapshot(
            deviceID: CloudSyncEntityCodec.entitySnapshotID,
            listID: "entity-list",
            listName: "Combined"
        )

        XCTAssertEqual(
            CloudSyncSnapshotSelection.authoritativeSnapshots(
                legacySnapshots: [legacyA, legacyB],
                entitySnapshot: entity
            ),
            [entity]
        )
    }

    func testLegacySnapshotsRemainAvailableWithoutEntitySnapshot() {
        let older = snapshot(
            deviceID: "mac",
            listID: "mac-list",
            listName: "Mac",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = snapshot(
            deviceID: "ipad",
            listID: "ipad-list",
            listName: "iPad",
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(
            CloudSyncSnapshotSelection.authoritativeSnapshots(
                legacySnapshots: [older, newer],
                entitySnapshot: nil
            ).map(\.id),
            ["ipad", "mac"]
        )
    }

    func testLegacySnapshotDecodesWithoutDeletedLists() throws {
        let original = snapshot(deviceID: "mac", listID: "legacy-list", listName: "Legacy")
        let encoded = try CardDatabase.syncJSONData(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["deletedLists"] = nil
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let decoded = try CardDatabase.syncJSONValue(DeviceSyncSnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.listSnapshot, original.listSnapshot)
        XCTAssertEqual(decoded.deletedLists, [])
    }

    func testLegacySearchSettingsDecodeWithoutNewPreferences() throws {
        let settings = SyncSearchSettings(
            defaultSearchText: "type:artifact",
            updatedAt: Date(timeIntervalSince1970: 42)
        )
        let encoded = try CardDatabase.syncJSONData(settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["displayCurrencyRawValue"] = nil
        object["searchHistory"] = nil
        object["plainTextSearchHistory"] = nil

        let decoded = try CardDatabase.syncJSONValue(
            SyncSearchSettings.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.defaultSearchText, "type:artifact")
        XCTAssertEqual(decoded.displayCurrencyRawValue, "USD")
        XCTAssertEqual(decoded.searchHistory, [])
        XCTAssertEqual(decoded.plainTextSearchHistory, [])
    }

    func testSearchSettingsMergePreservesHistoriesFromBothDevices() {
        let older = SyncSearchSettings(
            defaultSearchText: "type:creature",
            searchHistory: ["one", "shared"],
            plainTextSearchHistory: ["old plain"],
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = SyncSearchSettings(
            defaultSearchText: "type:artifact",
            displayCurrencyRawValue: "AUD",
            searchHistory: ["two", "shared"],
            plainTextSearchHistory: ["new plain"],
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        let merged = SyncSearchSettings.merged([older, newer])

        XCTAssertEqual(merged.defaultSearchText, "type:artifact")
        XCTAssertEqual(merged.displayCurrencyRawValue, "AUD")
        XCTAssertEqual(merged.searchHistory, ["two", "shared", "one"])
        XCTAssertEqual(merged.plainTextSearchHistory, ["new plain", "old plain"])
    }

    func testEntityCodecCanonicalizesFavouritesAndDeletionWins() throws {
        let oldDate = Date(timeIntervalSince1970: 10)
        let newDate = Date(timeIntervalSince1970: 20)
        let first = snapshot(
            deviceID: "iphone",
            listID: "iphone-favourites",
            listName: "Favorites",
            updatedAt: oldDate
        )
        let second = snapshot(
            deviceID: "ipad",
            listID: "ipad-favourites",
            listName: "Favourites",
            updatedAt: newDate
        )

        let activeRecords = CloudSyncEntityCodec.mergedRecords(
            try [first, second].map(CloudSyncEntityCodec.records)
        )
        let active = try XCTUnwrap(
            CloudSyncEntityCodec.snapshot(from: activeRecords)
        )
        XCTAssertEqual(active.listSnapshot.lists.map(\.id), [CloudSyncEntityCodec.favouritesListID])
        XCTAssertEqual(active.listSnapshot.entries.count, 1)
        XCTAssertEqual(
            active.listSnapshot.entries.first?.id,
            CloudSyncEntityCodec.favouriteEntryID(cardID: "beta")
        )

        var deletion = second
        deletion.listSnapshot.entries = []
        deletion.deletedEntities = [
            SyncTombstone(
                entityType: .cardListEntry,
                recordID: CloudSyncEntityCodec.favouriteEntryID(cardID: "beta"),
                deletedAt: Date(timeIntervalSince1970: 30)
            )
        ]
        let deletedRecords = CloudSyncEntityCodec.mergedRecords([
            activeRecords,
            try CloudSyncEntityCodec.records(from: deletion),
        ])
        let deleted = try XCTUnwrap(
            CloudSyncEntityCodec.snapshot(from: deletedRecords)
        )

        XCTAssertTrue(deleted.listSnapshot.entries.isEmpty)
        XCTAssertTrue(
            deleted.deletedEntities.contains {
                $0.recordID == CloudSyncEntityCodec.favouriteEntryID(cardID: "beta")
            }
        )
    }

    func testAccountChangeBlocksUploadsUntilAccepted() async throws {
        let database = try Fixtures.database()
        let transport = MemoryCloudSyncTransport(accountIdentifier: "account-a")
        let coordinator = CloudSyncCoordinator(database: database, transport: transport)

        let initial = await coordinator.start(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )
        XCTAssertEqual(initial, .ready)
        await transport.changeAccount(to: "account-b")

        let blocked = await coordinator.start(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )
        XCTAssertEqual(
            blocked,
            .accountChangeRequiresResolution(
                CloudSyncAccountChange(
                    previousAccountIdentifier: "account-a",
                    currentAccountIdentifier: "account-b"
                )
            )
        )

        let accepted = await coordinator.acceptCurrentAccount(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )
        XCTAssertTrue(accepted == .ready || {
            if case .appliedRemoteSnapshot = accepted { return true }
            return false
        }())
        XCTAssertEqual(try database.cloudSyncAccountIdentifier(), "account-b")
    }

    func testCloudRecoveryRetentionKeepsThirtyDaysOrLatestTwenty() throws {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let recent = (0..<25).map { index in
            recoverySnapshot(
                id: "recent-\(index)",
                createdAt: now.addingTimeInterval(TimeInterval(-index * 60))
            )
        }
        XCTAssertEqual(
            CloudSyncRecoveryPolicy.retained(recent, now: now).count,
            25
        )

        let old = (0..<25).map { index in
            recoverySnapshot(
                id: "old-\(index)",
                createdAt: now.addingTimeInterval(
                    -CloudSyncRecoveryPolicy.retentionDuration - TimeInterval(index * 60)
                )
            )
        }
        XCTAssertEqual(
            CloudSyncRecoveryPolicy.retained(old, now: now).count,
            CloudSyncRecoveryPolicy.minimumRevisionCount
        )
    }

    func testReplacementInstallImportsCloudRecoveryHistory() async throws {
        let remoteSnapshot = snapshot(
            deviceID: "iphone",
            listID: "cloud-list",
            listName: "Cloud Deck"
        )
        let recovery = recoverySnapshot(
            id: "cloud-recovery",
            createdAt: Date(timeIntervalSince1970: 30)
        )
        let transport = MemoryCloudSyncTransport(
            state: CloudRemoteState(
                snapshots: [remoteSnapshot],
                recoverySnapshots: [recovery]
            )
        )
        let replacement = try Fixtures.database()
        let coordinator = CloudSyncCoordinator(database: replacement, transport: transport)

        guard case .appliedRemoteSnapshot = await coordinator.start(
            deviceID: "replacement",
            deviceName: "Replacement",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        ) else {
            return XCTFail("Expected a replacement install to restore the cloud snapshot.")
        }

        XCTAssertEqual(try replacement.cardLists().map(\.name), ["Cloud Deck"])
        XCTAssertTrue(
            try replacement.cloudSyncRecoverySnapshots(limit: 100)
                .contains { $0.id == "cloud-recovery" }
        )
    }

    func testResolvedDeviceMergesLegacyRemoteSnapshotWithoutLosingLocalLists() async throws {
        var legacyRemote = snapshot(
            deviceID: "legacy-device",
            listID: "legacy-list",
            listName: "Legacy Cloud List"
        )
        legacyRemote.libraryIdentity.syncSchemaVersion = 1
        let encoded = try CardDatabase.syncJSONData(legacyRemote)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["deletedLists"] = nil
        let decodedLegacy = try CardDatabase.syncJSONValue(
            DeviceSyncSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        let database = try Fixtures.database()
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        try database.saveLibraryIdentity(identity)
        _ = try database.createCardList(
            named: "Current Local List",
            now: Date(timeIntervalSince1970: 30)
        )
        try database.markCloudSyncBootstrapResolved(true)
        let coordinator = CloudSyncCoordinator(
            database: database,
            transport: MemoryCloudSyncTransport(
                state: CloudRemoteState(
                    requiredLibraryIdentity: identity,
                    snapshots: [decodedLegacy]
                )
            )
        )

        let status = await coordinator.start(
            deviceID: "current-device",
            deviceName: "Current Device",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )

        guard case .appliedRemoteSnapshot = status else {
            return XCTFail("Expected a backward-compatible merge, got \(status).")
        }
        XCTAssertEqual(
            Set(try database.cardLists().map(\.name)),
            ["Current Local List", "Legacy Cloud List"]
        )
    }

    func testMalformedRemoteSnapshotFailsClosedWithoutChangingLocalData() async throws {
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        var malformed = snapshot(
            deviceID: "remote",
            listID: "remote-list",
            listName: "Remote"
        )
        malformed.listSnapshot.entries[0].listID = "missing-list"

        let database = try Fixtures.database()
        try database.saveLibraryIdentity(identity)
        _ = try database.createCardList(named: "Keep Local Data")
        try database.markCloudSyncBootstrapResolved(true)
        let before = try database.cardListLibrarySnapshot()
        let coordinator = CloudSyncCoordinator(
            database: database,
            transport: MemoryCloudSyncTransport(
                state: CloudRemoteState(
                    requiredLibraryIdentity: identity,
                    snapshots: [malformed]
                )
            )
        )

        let status = await coordinator.reconcileRemoteState(
            deviceID: "local",
            deviceName: "Local",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )

        XCTAssertEqual(
            status,
            .failed("iCloud sync data could not be validated. Local data was not changed.")
        )
        XCTAssertEqual(try database.cardListLibrarySnapshot(), before)
        XCTAssertTrue(try database.cloudSyncRecoverySnapshots().isEmpty)
    }

    func testSnapshotMergeCombinesDifferentListsAndUsesDeterministicSameListWinner() {
        let older = snapshot(
            deviceID: "a-device",
            listID: "shared-list",
            listName: "Older Name",
            updatedAt: Date(timeIntervalSince1970: 10),
            capturedAt: Date(timeIntervalSince1970: 30)
        )
        let newer = snapshot(
            deviceID: "z-device",
            listID: "shared-list",
            listName: "Newer Name",
            updatedAt: Date(timeIntervalSince1970: 20),
            capturedAt: Date(timeIntervalSince1970: 20)
        )
        let other = snapshot(
            deviceID: "b-device",
            listID: "other-list",
            listName: "Other",
            updatedAt: Date(timeIntervalSince1970: 15),
            capturedAt: Date(timeIntervalSince1970: 15)
        )

        let merged = DeviceSyncSnapshot.merged(
            snapshots: [older, newer, other],
            deviceID: "local",
            deviceName: "Local",
            libraryIdentity: newer.libraryIdentity,
            capturedAt: Date(timeIntervalSince1970: 40)
        )

        XCTAssertEqual(Set(merged.listSnapshot.lists.map(\.name)), ["Newer Name", "Other"])
        XCTAssertEqual(
            merged.listSnapshot.entries.first { $0.listID == "shared-list" }?.cardID,
            "beta"
        )
    }

    func testDeletionTombstonePreventsStaleSnapshotResurrection() {
        let stale = snapshot(
            deviceID: "stale-device",
            listID: "deleted-list",
            listName: "Stale",
            updatedAt: Date(timeIntervalSince1970: 10),
            capturedAt: Date(timeIntervalSince1970: 30)
        )
        let deleted = DeviceSyncSnapshot(
            id: "deleting-device",
            deviceName: "Deleting Device",
            capturedAt: Date(timeIntervalSince1970: 20),
            libraryIdentity: stale.libraryIdentity,
            searchSettings: SyncSearchSettings(updatedAt: Date(timeIntervalSince1970: 1)),
            listSnapshot: CardListLibrarySnapshot(lists: [], categories: [], entries: []),
            deletedLists: [
                SyncListDeletion(id: "deleted-list", deletedAt: Date(timeIntervalSince1970: 20))
            ]
        )

        let merged = DeviceSyncSnapshot.merged(
            snapshots: [deleted, stale],
            deviceID: "local",
            deviceName: "Local",
            libraryIdentity: stale.libraryIdentity
        )

        XCTAssertTrue(merged.listSnapshot.lists.isEmpty)
        XCTAssertEqual(merged.deletedLists.map(\.id), ["deleted-list"])
    }

    func testCoordinatorRetainsOutboxWhenSaveFails() async throws {
        let database = try Fixtures.database()
        try database.saveLibraryIdentity(libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00"))
        _ = try database.createCardList(named: "Unsaved")
        try database.recordLocalSyncSnapshotChange(reason: "unit-test")
        let coordinator = CloudSyncCoordinator(
            database: database,
            transport: FailingSaveCloudSyncTransport()
        )

        let status = await coordinator.pushLocalState(
            deviceID: "mac",
            deviceName: "Mac",
            searchSettings: SyncSearchSettings()
        )

        XCTAssertEqual(status, .failed("Sync failed. Grimora will try again later."))
        XCTAssertEqual(try database.pendingSyncChanges().count, 1)
    }

    func testTwoCoordinatorsPropagateListsFavouritesAndDeletions() async throws {
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        let transport = MemoryCloudSyncTransport()
        let databaseA = try Fixtures.database()
        let databaseB = try Fixtures.database()
        try databaseA.saveLibraryIdentity(identity)
        try databaseB.saveLibraryIdentity(identity)
        try databaseA.markCloudSyncBootstrapResolved(true)
        try databaseB.markCloudSyncBootstrapResolved(true)
        let coordinatorA = CloudSyncCoordinator(database: databaseA, transport: transport)
        let coordinatorB = CloudSyncCoordinator(database: databaseB, transport: transport)

        let list = try databaseA.createCardList(named: "Shared", now: Date(timeIntervalSince1970: 10))
        let favourites = try databaseA.createCardList(named: "Favourites", now: Date(timeIntervalSince1970: 11))
        let favouriteEntry = try databaseA.appendCard(
            "alpha",
            toList: favourites.id,
            now: Date(timeIntervalSince1970: 12)
        )
        try databaseA.recordLocalSyncSnapshotChange(reason: "device-a")

        let firstPushStatus = await coordinatorA.pushLocalState(
            deviceID: "device-a",
            deviceName: "Device A",
            searchSettings: SyncSearchSettings(updatedAt: Date(timeIntervalSince1970: 1))
        )
        XCTAssertEqual(firstPushStatus, .ready)
        guard case .appliedRemoteSnapshot = await coordinatorB.reconcileRemoteState(
            deviceID: "device-b",
            deviceName: "Device B",
            searchSettings: SyncSearchSettings(updatedAt: Date(timeIntervalSince1970: 1))
        ) else {
            return XCTFail("Expected Device B to apply Device A's snapshot.")
        }
        XCTAssertEqual(Set(try databaseB.cardLists().map(\.name)), ["Shared", "Favourites"])
        let syncedFavourites = try XCTUnwrap(
            try databaseB.cardLists().first {
                CloudSyncEntityCodec.isFavouritesListName($0.name)
            }
        )
        XCTAssertEqual(
            try databaseB.cardListEntries(forListID: syncedFavourites.id).map(\.cardID),
            ["alpha"]
        )

        try databaseA.deleteCardList(id: list.id)
        try databaseA.removeCardListEntryCompletely(
            id: favouriteEntry.id,
            now: Date(timeIntervalSince1970: 30)
        )
        try databaseA.recordLocalSyncSnapshotChange(reason: "device-a-delete")
        let deletionPushStatus = await coordinatorA.pushLocalState(
            deviceID: "device-a",
            deviceName: "Device A",
            searchSettings: SyncSearchSettings(updatedAt: Date(timeIntervalSince1970: 1))
        )
        switch deletionPushStatus {
        case .ready, .appliedRemoteSnapshot:
            break
        default:
            XCTFail("Expected a successful deletion push, got \(deletionPushStatus).")
        }
        guard case .appliedRemoteSnapshot = await coordinatorB.reconcileRemoteState(
            deviceID: "device-b",
            deviceName: "Device B",
            searchSettings: SyncSearchSettings(updatedAt: Date(timeIntervalSince1970: 1))
        ) else {
            return XCTFail("Expected Device B to apply Device A's deletion.")
        }

        XCTAssertEqual(try databaseB.cardLists().map(\.name), ["Favourites"])
        XCTAssertTrue(try databaseB.cardListEntries(forListID: syncedFavourites.id).isEmpty)
        XCTAssertTrue(try databaseB.latestListDeletionTombstones().contains { $0.id == list.id })
    }

    func testRemoteApplyRetainsDurableRecoveryAndCanRestoreIt() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncRecovery-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = temporaryDirectory.appendingPathComponent("Grimora.sqlite")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        var recoveryID: CloudSyncRecoverySnapshot.ID?
        do {
            let database = try CardDatabase(storage: .file(databaseURL))
            try database.replaceAllCards(Fixtures.records())
            let localList = try database.createCardList(
                named: "Existing Deck",
                now: Date(timeIntervalSince1970: 10)
            )
            try database.appendCard(
                "alpha",
                toList: localList.id,
                now: Date(timeIntervalSince1970: 11)
            )

            try database.applyDeviceSyncSnapshot(
                snapshot(
                    deviceID: "remote",
                    listID: "remote-list",
                    listName: "Remote Deck"
                )
            )

            let recovery = try XCTUnwrap(try database.cloudSyncRecoverySnapshots().first)
            recoveryID = recovery.id
            XCTAssertEqual(recovery.listSnapshot.lists.map(\.name), ["Existing Deck"])
            XCTAssertEqual(recovery.listSnapshot.entries.map(\.cardID), ["alpha"])
        }

        let reopened = try CardDatabase(storage: .file(databaseURL))
        let persistedRecovery = try XCTUnwrap(
            try reopened.cloudSyncRecoverySnapshots().first { $0.id == recoveryID }
        )
        try reopened.restoreCloudSyncRecoverySnapshot(
            id: persistedRecovery.id,
            now: Date(timeIntervalSince1970: 100)
        )

        let restoredList = try XCTUnwrap(try reopened.cardLists().first)
        XCTAssertEqual(restoredList.name, "Existing Deck")
        XCTAssertEqual(
            try reopened.cardListEntries(forListID: restoredList.id).map(\.cardID),
            ["alpha"]
        )
        XCTAssertFalse(try reopened.pendingSyncChanges().isEmpty)
    }

    func testFailedSaveAfterRemoteDeletionLeavesRecoverableLocalData() async throws {
        let identity = libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00")
        let database = try Fixtures.database()
        try database.saveLibraryIdentity(identity)
        let localList = try database.createCardList(
            named: "Recoverable Deck",
            now: Date(timeIntervalSince1970: 10)
        )
        try database.markCloudSyncBootstrapResolved(true)
        let remoteDeletion = DeviceSyncSnapshot(
            id: "remote",
            deviceName: "Remote",
            capturedAt: Date(timeIntervalSince1970: 20),
            libraryIdentity: identity,
            searchSettings: SyncSearchSettings(updatedAt: .distantPast),
            listSnapshot: CardListLibrarySnapshot(lists: [], categories: [], entries: []),
            deletedLists: [
                SyncListDeletion(id: localList.id, deletedAt: Date(timeIntervalSince1970: 20))
            ]
        )
        let coordinator = CloudSyncCoordinator(
            database: database,
            transport: FailingSaveCloudSyncTransport(
                state: CloudRemoteState(
                    requiredLibraryIdentity: identity,
                    snapshots: [remoteDeletion]
                )
            )
        )

        let status = await coordinator.reconcileRemoteState(
            deviceID: "local",
            deviceName: "Local",
            searchSettings: SyncSearchSettings(updatedAt: .distantPast)
        )

        XCTAssertEqual(status, .failed("Sync failed. Grimora will try again later."))
        XCTAssertNil(try database.cardList(id: localList.id))
        let recovery = try XCTUnwrap(try database.cloudSyncRecoverySnapshots().first)
        XCTAssertEqual(recovery.listSnapshot.lists.map(\.name), ["Recoverable Deck"])

        try database.restoreCloudSyncRecoverySnapshot(
            id: recovery.id,
            now: Date(timeIntervalSince1970: 30)
        )
        XCTAssertEqual(try database.cardList(id: localList.id)?.name, "Recoverable Deck")
        XCTAssertFalse(try database.pendingSyncChanges().isEmpty)
    }

    func testExistingDatabaseMigrationAddsRecoveryStorageWithoutChangingLists() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncMigration-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = temporaryDirectory.appendingPathComponent("Grimora.sqlite")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        do {
            let database = try CardDatabase(storage: .file(databaseURL))
            _ = try database.createCardList(named: "Pre-Upgrade Deck")
        }
        do {
            let legacyDatabase = try SQLiteDatabase(storage: .file(databaseURL))
            try legacyDatabase.execute("DROP TABLE cloud_sync_recovery_snapshots")
        }

        let migrated = try CardDatabase(storage: .file(databaseURL))

        XCTAssertEqual(try migrated.cardLists().map(\.name), ["Pre-Upgrade Deck"])
        XCTAssertTrue(try migrated.cloudSyncRecoverySnapshots().isEmpty)
    }

    private func libraryIdentity(
        updatedAt: String?,
        searchSchemaVersion: String = CardDatabase.currentSearchSchemaVersion,
        syncSchemaVersion: Int = GrimoraCloudSyncConstants.currentSyncSchemaVersion,
        catalogSchemaVersion: Int? = nil
    ) -> LibraryIdentity {
        LibraryIdentity(
            defaultCardsUpdatedAt: updatedAt,
            defaultCardsDownloadURI: URL(string: "https://example.test/default-cards.json")!,
            defaultCardsName: "Default Cards",
            defaultCardsSize: 123,
            searchSchemaVersion: searchSchemaVersion,
            syncSchemaVersion: syncSchemaVersion,
            catalogSchemaVersion: catalogSchemaVersion
        )
    }

    private func snapshot(
        deviceID: String,
        listID: String,
        listName: String,
        updatedAt: Date? = nil,
        capturedAt: Date? = nil
    ) -> DeviceSyncSnapshot {
        let date = updatedAt ?? Date(timeIntervalSince1970: deviceID == "mac" ? 10 : 20)
        let capturedAt = capturedAt ?? date
        let cardID = deviceID == "mac" ? "alpha" : "beta"
        return DeviceSyncSnapshot(
            id: deviceID,
            deviceName: deviceID,
            capturedAt: capturedAt,
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

    private func emptySnapshot(
        deviceID: String,
        listID: String,
        listName: String,
        timestamp: Date
    ) -> DeviceSyncSnapshot {
        DeviceSyncSnapshot(
            id: deviceID,
            deviceName: deviceID,
            capturedAt: timestamp,
            libraryIdentity: libraryIdentity(updatedAt: "2026-04-25T09:09:59.477+00:00"),
            searchSettings: SyncSearchSettings(updatedAt: timestamp),
            listSnapshot: CardListLibrarySnapshot(
                lists: [
                    CardListRecord(
                        id: listID,
                        name: listName,
                        createdAt: timestamp,
                        updatedAt: timestamp
                    )
                ],
                categories: [],
                entries: []
            )
        )
    }

    private func recoverySnapshot(
        id: String,
        createdAt: Date
    ) -> CloudSyncRecoverySnapshot {
        CloudSyncRecoverySnapshot(
            id: id,
            createdAt: createdAt,
            reason: "Test recovery",
            libraryIdentity: LibraryIdentity(),
            listSnapshot: CardListLibrarySnapshot(
                lists: [
                    CardListRecord(
                        id: "\(id)-list",
                        name: "Recovered \(id)",
                        createdAt: createdAt,
                        updatedAt: createdAt
                    )
                ],
                categories: [],
                entries: []
            ),
            deletedLists: []
        )
    }
}
