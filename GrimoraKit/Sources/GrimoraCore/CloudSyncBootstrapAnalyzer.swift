import Foundation

enum CloudSyncBootstrapAnalyzer {
  /// Deterministically merges the local library with every remote snapshot using
  /// per-entity last-writer-wins. CloudKit is the single source of truth, so first
  /// launch never asks the user to resolve a conflict: divergent lists that share an
  /// id collapse to the most recently edited copy (the overwritten copy is retained
  /// as a recovery snapshot so it can be undone), lists that are semantically
  /// identical are de-duplicated, and lists that merely share a name are kept side by
  /// side ("Name", "Name 2", ...).
  static func mergedBootstrapSnapshot(
    localSnapshot: DeviceSyncSnapshot,
    remoteSnapshots: [DeviceSyncSnapshot]
  ) throws -> DeviceSyncSnapshot {
    precondition(!remoteSnapshots.isEmpty)

    let remoteSnapshot = normalizedRemoteSnapshot(
      remoteSnapshots,
      localIdentity: localSnapshot.libraryIdentity
    )
    return safelyMergedSnapshot(
      [remoteSnapshot, localSnapshot],
      deviceID: localSnapshot.id,
      deviceName: localSnapshot.deviceName,
      libraryIdentity: localSnapshot.libraryIdentity
    )
  }

  private static func normalizedRemoteSnapshot(
    _ snapshots: [DeviceSyncSnapshot],
    localIdentity: LibraryIdentity
  ) -> DeviceSyncSnapshot {
    let merged = DeviceSyncSnapshot.merged(
      snapshots: snapshots,
      deviceID: CloudSyncEntityCodec.entitySnapshotID,
      deviceName: "iCloud (combined)",
      libraryIdentity: localIdentity
    )
    return collapsedIdenticalNamedLists(
      CloudSyncEntityCodec.canonicalizedSnapshot(merged),
      tombstoneRemovedDuplicates: false
    )
  }

  private static func safelyMergedSnapshot(
    _ snapshots: [DeviceSyncSnapshot],
    deviceID: DeviceSyncSnapshot.ID,
    deviceName: String,
    libraryIdentity: LibraryIdentity
  ) -> DeviceSyncSnapshot {
    let merged = DeviceSyncSnapshot.merged(
      snapshots: snapshots,
      deviceID: deviceID,
      deviceName: deviceName,
      libraryIdentity: libraryIdentity
    )
    return CloudSyncEntityCodec.pruningEmptyContentlessLists(
      collapsedIdenticalNamedLists(
        CloudSyncEntityCodec.canonicalizedSnapshot(merged),
        tombstoneRemovedDuplicates: true
      )
    )
  }

  private static func collapsedIdenticalNamedLists(
    _ snapshot: DeviceSyncSnapshot,
    tombstoneRemovedDuplicates: Bool
  ) -> DeviceSyncSnapshot {
    var snapshot = snapshot
    let groups = Dictionary(
      grouping: snapshot.listSnapshot.lists.filter { !isFavourites($0) },
      by: { CloudSyncListSemanticIdentity.normalizedName($0.name) }
    )
    var removedListIDs: Set<CardListRecord.ID> = []

    for lists in groups.values where lists.count > 1 {
      let identityGroups = Dictionary(
        grouping: lists,
        by: {
          CloudSyncListSemanticIdentity(listID: $0.id, snapshot: snapshot.listSnapshot)
        }
      )
      for identicalLists in identityGroups.values where identicalLists.count > 1 {
        let survivor = identicalLists.max {
          if $0.updatedAt != $1.updatedAt {
            return $0.updatedAt < $1.updatedAt
          }
          return $0.id < $1.id
        }
        removedListIDs.formUnion(
          identicalLists.compactMap { $0.id == survivor?.id ? nil : $0.id }
        )
      }
    }

    guard !removedListIDs.isEmpty else {
      return snapshot
    }

    snapshot.listSnapshot.lists.removeAll { removedListIDs.contains($0.id) }
    snapshot.listSnapshot.categories.removeAll { removedListIDs.contains($0.listID) }
    snapshot.listSnapshot.entries.removeAll { removedListIDs.contains($0.listID) }
    if tombstoneRemovedDuplicates {
      let deletedAt = snapshot.capturedAt
      for listID in removedListIDs {
        snapshot.deletedLists.append(SyncListDeletion(id: listID, deletedAt: deletedAt))
        snapshot.deletedEntities.append(
          SyncTombstone(entityType: .cardList, recordID: listID, deletedAt: deletedAt)
        )
      }
    }
    return snapshot
  }

  private static func isFavourites(_ list: CardListRecord) -> Bool {
    list.id == CloudSyncEntityCodec.favouritesListID
      || CloudSyncEntityCodec.isFavouritesListName(list.name)
  }
}
