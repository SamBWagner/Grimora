#if DEBUG
  import Foundation
  import GrimoraCore

  enum CloudSyncConflictFixture {
    @MainActor
    static func context() -> CloudSyncResolutionContext {
      let remote = snapshot(
        id: CloudSyncEntityCodec.entitySnapshotID,
        deviceName: "iCloud (combined)",
        capturedAt: Date(timeIntervalSince1970: 1_781_992_800),
        lists: [
          fixtureList(id: "remote-shared", name: "Weekend Commander", cardID: "remote-card"),
          fixtureList(id: "remote-unique", name: "Trade Binder", cardID: "trade-card"),
        ]
      )
      let local = snapshot(
        id: "fixture-current-device",
        deviceName: GrimoraDeviceLabel.current,
        capturedAt: Date(timeIntervalSince1970: 1_781_989_200),
        lists: [
          fixtureList(id: "local-shared", name: "Weekend Commander", cardID: "local-card"),
          fixtureList(id: "local-unique", name: "Draft Ideas", cardID: "draft-card"),
        ]
      )

      return CloudSyncResolutionContext(
        snapshots: [remote, local],
        defaultSourceSnapshotID: remote.id,
        eligibleSourceSnapshotIDs: [remote.id, local.id],
        safeImportedListIDsBySourceSnapshotID: [
          remote.id: [local.id: ["local-unique"]],
          local.id: [remote.id: ["remote-unique"]],
        ],
        conflictingListIDsBySnapshotID: [
          remote.id: ["remote-shared"],
          local.id: ["local-shared"],
        ]
      )
    }

    private static func snapshot(
      id: String,
      deviceName: String,
      capturedAt: Date,
      lists: [(list: CardListRecord, entry: CardListEntryRecord)]
    ) -> DeviceSyncSnapshot {
      DeviceSyncSnapshot(
        id: id,
        deviceName: deviceName,
        capturedAt: capturedAt,
        libraryIdentity: LibraryIdentity(),
        searchSettings: SyncSearchSettings(updatedAt: capturedAt),
        listSnapshot: CardListLibrarySnapshot(
          lists: lists.map(\.list),
          categories: [],
          entries: lists.map(\.entry)
        )
      )
    }

    private static func fixtureList(
      id: String,
      name: String,
      cardID: String
    ) -> (list: CardListRecord, entry: CardListEntryRecord) {
      let timestamp = Date(timeIntervalSince1970: 1_781_989_200)
      return (
        CardListRecord(
          id: id,
          name: name,
          createdAt: timestamp,
          updatedAt: timestamp,
          entryCount: 1
        ),
        CardListEntryRecord(
          id: "\(id)-entry",
          listID: id,
          cardID: cardID,
          position: 0,
          createdAt: timestamp
        )
      )
    }
  }
#endif
