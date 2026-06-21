import Foundation

public struct CloudSyncResolutionContext: Equatable, Sendable {
  public var snapshots: [DeviceSyncSnapshot]
  public var defaultSourceSnapshotID: DeviceSyncSnapshot.ID
  public var eligibleSourceSnapshotIDs: Set<DeviceSyncSnapshot.ID>
  public var safeImportedListIDsBySourceSnapshotID:
    [DeviceSyncSnapshot.ID: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>]]
  public var conflictingListIDsBySnapshotID:
    [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>]

  public init(
    snapshots: [DeviceSyncSnapshot],
    defaultSourceSnapshotID: DeviceSyncSnapshot.ID,
    eligibleSourceSnapshotIDs: Set<DeviceSyncSnapshot.ID>,
    safeImportedListIDsBySourceSnapshotID:
      [DeviceSyncSnapshot.ID: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>]],
    conflictingListIDsBySnapshotID:
      [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>]
  ) {
    self.snapshots = snapshots
    self.defaultSourceSnapshotID = defaultSourceSnapshotID
    self.eligibleSourceSnapshotIDs = eligibleSourceSnapshotIDs
    self.safeImportedListIDsBySourceSnapshotID = safeImportedListIDsBySourceSnapshotID
    self.conflictingListIDsBySnapshotID = conflictingListIDsBySnapshotID
  }

  public func safeImportedListIDs(
    for sourceSnapshotID: DeviceSyncSnapshot.ID
  ) -> [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>] {
    safeImportedListIDsBySourceSnapshotID[sourceSnapshotID] ?? [:]
  }

  public func conflictingListIDs(
    for snapshotID: DeviceSyncSnapshot.ID
  ) -> Set<CardListRecord.ID> {
    conflictingListIDsBySnapshotID[snapshotID] ?? []
  }
}
