import Foundation

enum CloudSyncBootstrapDecision: Equatable, Sendable {
  case apply(DeviceSyncSnapshot)
  case resolve(CloudSyncResolutionContext)
}

enum CloudSyncBootstrapAnalyzer {
  static func analyze(
    localSnapshot: DeviceSyncSnapshot,
    remoteSnapshots: [DeviceSyncSnapshot]
  ) throws -> CloudSyncBootstrapDecision {
    precondition(!remoteSnapshots.isEmpty)

    let remoteSnapshot = normalizedRemoteSnapshot(
      remoteSnapshots,
      localIdentity: localSnapshot.libraryIdentity
    )
    let snapshots = [remoteSnapshot, localSnapshot]
    let conflictingIDs = conflictingListIDs(in: snapshots)

    guard conflictingIDs.values.contains(where: { !$0.isEmpty }) else {
      return .apply(
        safelyMergedSnapshot(
          snapshots,
          deviceID: localSnapshot.id,
          deviceName: localSnapshot.deviceName,
          libraryIdentity: localSnapshot.libraryIdentity
        )
      )
    }

    // Lists are identified by their stable ID, so any snapshot can serve as the
    // source of truth. The combined iCloud snapshot is offered by default.
    let eligibleSourceIDs = Set(snapshots.map(\.id))
    let defaultSourceID = remoteSnapshot.id

    return .resolve(
      CloudSyncResolutionContext(
        snapshots: snapshots,
        defaultSourceSnapshotID: defaultSourceID,
        eligibleSourceSnapshotIDs: eligibleSourceIDs,
        safeImportedListIDsBySourceSnapshotID: safeImports(
          snapshots: snapshots,
          conflicts: conflictingIDs,
          eligibleSourceIDs: eligibleSourceIDs
        ),
        conflictingListIDsBySnapshotID: conflictingIDs
      )
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

  private static func conflictingListIDs(
    in snapshots: [DeviceSyncSnapshot]
  ) -> [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>] {
    var conflicts = Dictionary(
      uniqueKeysWithValues: snapshots.map { ($0.id, Set<CardListRecord.ID>()) }
    )

    // A genuine conflict only exists when the *same* list (matching ID) has been
    // changed in incompatible ways across snapshots, or one side edited a list
    // the other side deleted. Lists that merely share a name are independent
    // lists and are kept side by side without asking the user to resolve them.
    for leftIndex in snapshots.indices {
      for rightIndex in snapshots.indices where rightIndex > leftIndex {
        let left = snapshots[leftIndex]
        let right = snapshots[rightIndex]
        for leftList in left.listSnapshot.lists where !isFavourites(leftList) {
          guard
            let rightList = right.listSnapshot.lists.first(where: { $0.id == leftList.id }),
            !isFavourites(rightList)
          else {
            continue
          }
          let leftIdentity = CloudSyncListSemanticIdentity(
            listID: leftList.id,
            snapshot: left.listSnapshot
          )
          let rightIdentity = CloudSyncListSemanticIdentity(
            listID: rightList.id,
            snapshot: right.listSnapshot
          )
          if leftIdentity != rightIdentity {
            conflicts[left.id, default: []].insert(leftList.id)
            conflicts[right.id, default: []].insert(rightList.id)
          }
        }

        let leftDeletedIDs = Set(left.deletedLists.map(\.id))
        let rightDeletedIDs = Set(right.deletedLists.map(\.id))
        let leftListIDs = Set(left.listSnapshot.lists.map(\.id))
        let rightListIDs = Set(right.listSnapshot.lists.map(\.id))
        conflicts[left.id, default: []].formUnion(leftListIDs.intersection(rightDeletedIDs))
        conflicts[right.id, default: []].formUnion(rightListIDs.intersection(leftDeletedIDs))
      }
    }
    return conflicts
  }

  private static func safeImports(
    snapshots: [DeviceSyncSnapshot],
    conflicts: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>],
    eligibleSourceIDs: Set<DeviceSyncSnapshot.ID>
  ) -> [DeviceSyncSnapshot.ID: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>]] {
    var result:
      [DeviceSyncSnapshot.ID: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>]] = [:]

    for source in snapshots where eligibleSourceIDs.contains(source.id) {
      for candidate in snapshots where candidate.id != source.id {
        for list in candidate.listSnapshot.lists {
          guard !conflicts[candidate.id, default: []].contains(list.id) else {
            continue
          }
          if isFavourites(list) {
            result[source.id, default: [:]][candidate.id, default: []].insert(list.id)
            continue
          }
          let identity = CloudSyncListSemanticIdentity(
            listID: list.id,
            snapshot: candidate.listSnapshot
          )
          let alreadyRepresented = source.listSnapshot.lists.contains { sourceList in
            guard !isFavourites(sourceList) else {
              return false
            }
            return CloudSyncListSemanticIdentity(
              listID: sourceList.id,
              snapshot: source.listSnapshot
            ) == identity
          }
          if !alreadyRepresented {
            result[source.id, default: [:]][candidate.id, default: []].insert(list.id)
          }
        }
      }
    }
    return result
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
