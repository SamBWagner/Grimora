import Foundation

enum CloudSyncSnapshotSelection {
  static func authoritativeSnapshots(
    legacySnapshots: [DeviceSyncSnapshot],
    entitySnapshot: DeviceSyncSnapshot?
  ) -> [DeviceSyncSnapshot] {
    if let entitySnapshot {
      return [entitySnapshot]
    }
    return legacySnapshots.sorted {
      if $0.capturedAt != $1.capturedAt {
        return $0.capturedAt > $1.capturedAt
      }
      return $0.id < $1.id
    }
  }
}
