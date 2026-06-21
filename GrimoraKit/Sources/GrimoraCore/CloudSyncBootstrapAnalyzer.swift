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

    let internallyConflictedSnapshotIDs = Set(
      snapshots.compactMap { snapshot in
        hasInternalNameConflict(snapshot) ? snapshot.id : nil
      }
    )
    var eligibleSourceIDs = Set(snapshots.map(\.id))
      .subtracting(internallyConflictedSnapshotIDs)
    if eligibleSourceIDs.isEmpty {
      eligibleSourceIDs = [localSnapshot.id]
    }
    let defaultSourceID =
      eligibleSourceIDs.contains(remoteSnapshot.id) ? remoteSnapshot.id : localSnapshot.id

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
    return collapsedIdenticalNamedLists(
      CloudSyncEntityCodec.canonicalizedSnapshot(merged),
      tombstoneRemovedDuplicates: true
    )
  }

  private static func conflictingListIDs(
    in snapshots: [DeviceSyncSnapshot]
  ) -> [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>] {
    var conflicts = Dictionary(
      uniqueKeysWithValues: snapshots.map { ($0.id, Set<CardListRecord.ID>()) }
    )

    for snapshot in snapshots {
      let groupedByName = Dictionary(
        grouping: snapshot.listSnapshot.lists.filter { !isFavourites($0) },
        by: { CloudSyncListSemanticIdentity.normalizedName($0.name) }
      )
      for lists in groupedByName.values where lists.count > 1 {
        let identities = Set(
          lists.map {
            CloudSyncListSemanticIdentity(listID: $0.id, snapshot: snapshot.listSnapshot)
          }
        )
        if identities.count > 1 {
          conflicts[snapshot.id, default: []].formUnion(lists.map(\.id))
        }
      }
    }

    for leftIndex in snapshots.indices {
      for rightIndex in snapshots.indices where rightIndex > leftIndex {
        let left = snapshots[leftIndex]
        let right = snapshots[rightIndex]
        for leftList in left.listSnapshot.lists where !isFavourites(leftList) {
          let leftIdentity = CloudSyncListSemanticIdentity(
            listID: leftList.id,
            snapshot: left.listSnapshot
          )
          for rightList in right.listSnapshot.lists where !isFavourites(rightList) {
            let matchesID = leftList.id == rightList.id
            let matchesName =
              CloudSyncListSemanticIdentity.normalizedName(leftList.name)
              == CloudSyncListSemanticIdentity.normalizedName(rightList.name)
            guard matchesID || matchesName else {
              continue
            }
            let rightIdentity = CloudSyncListSemanticIdentity(
              listID: rightList.id,
              snapshot: right.listSnapshot
            )
            if leftIdentity != rightIdentity {
              conflicts[left.id, default: []].insert(leftList.id)
              conflicts[right.id, default: []].insert(rightList.id)
            }
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

  private static func hasInternalNameConflict(_ snapshot: DeviceSyncSnapshot) -> Bool {
    let groupedByName = Dictionary(
      grouping: snapshot.listSnapshot.lists.filter { !isFavourites($0) },
      by: { CloudSyncListSemanticIdentity.normalizedName($0.name) }
    )
    return groupedByName.values.contains { lists in
      guard lists.count > 1 else {
        return false
      }
      return Set(
        lists.map {
          CloudSyncListSemanticIdentity(listID: $0.id, snapshot: snapshot.listSnapshot)
        }
      ).count > 1
    }
  }

  private static func isFavourites(_ list: CardListRecord) -> Bool {
    list.id == CloudSyncEntityCodec.favouritesListID
      || CloudSyncEntityCodec.isFavouritesListName(list.name)
  }
}
