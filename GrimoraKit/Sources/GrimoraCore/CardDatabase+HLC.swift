import Foundation

// MARK: - Cross-device sync clock (the "logical clock" half of the sync fix)
//
// The sync merge is a per-entity last-writer-wins on `updatedAt`. On its own that is a raw
// wall-clock comparison, which breaks the moment two devices' clocks disagree: a device whose
// clock runs even slightly behind can never produce a timestamp that beats what it just pulled,
// so its edits are reverted on every sync and the list is locked to the other device's version
// forever.
//
// The fix is to stop stamping local edits with the raw wall clock and instead issue timestamps
// from a strictly-monotonic clock that also advances past everything the device has *observed*
// from other devices. This is the local half of a hybrid logical clock:
//
//   * `issueSyncTimestampUnlocked` — called at every local mutation. Returns an instant that is
//     at least `now` and always strictly greater than the last timestamp this device issued.
//   * `advanceSyncClockUnlocked` — called when applying remote changes. Pushes the floor up to
//     the newest instant we've seen from any device, so the *next* local edit out-ranks it.
//
// Together these guarantee that once a device has seen a remote edit, its subsequent edits win
// the merge regardless of clock skew — which is exactly what stops the revert loop.
extension CardDatabase {
  private static let syncClockFloorMetadataKey = "cloudSyncClockFloor"

  /// One tick of the logical clock. 2ms sits safely above the `CloudSyncUploadDiff` ~1ms
  /// "same instant" tolerance and is exactly representable at the millisecond precision of
  /// `isoListDateFormatter`, so every issued stamp is a distinct, strictly-increasing instant
  /// that the upload diff still recognises as a real change.
  static let syncClockTick: TimeInterval = 0.002

  /// Issues a strictly-monotonic timestamp for a local mutation ("the point of interaction").
  ///
  /// The returned instant is `>= now` and strictly greater than any timestamp this device has
  /// previously issued or observed (via `advanceSyncClockUnlocked`). Must be called inside
  /// `withDatabaseLock`; the mutation then binds the returned value into the row's `updated_at`.
  func issueSyncTimestampUnlocked(now: Date = Date()) throws -> Date {
    let issued: Date
    if let floor = try syncClockFloorUnlocked(), now <= floor.addingTimeInterval(Self.syncClockTick) {
      issued = floor.addingTimeInterval(Self.syncClockTick)
    } else {
      issued = now
    }
    // Round-trip through the on-disk format so the stored floor is quantised to the exact
    // millisecond that lands on the row — otherwise a sub-millisecond floor could drift ahead of
    // the value actually written and start rejecting legitimately newer edits.
    let quantized = Self.parseListDate(Self.formattedListDate(issued))
    try saveSyncClockFloorUnlocked(quantized)
    return quantized
  }

  /// Pushes the clock floor forward to at least `date` (no tick added) so the next locally-issued
  /// timestamp out-ranks a value we've just observed from another device. Must be called inside
  /// `withDatabaseLock`.
  func advanceSyncClockUnlocked(toAtLeast date: Date) throws {
    if let floor = try syncClockFloorUnlocked(), date <= floor {
      return
    }
    try saveSyncClockFloorUnlocked(date)
  }

  /// Locked convenience for callers outside a database transaction (e.g. the sync coordinator
  /// advancing the clock past the newest instant in a freshly fetched remote snapshot).
  public func advanceSyncClock(toAtLeast date: Date) throws {
    try withDatabaseLock {
      try advanceSyncClockUnlocked(toAtLeast: date)
    }
  }

  /// The largest `updatedAt` / deletion instant anywhere in a snapshot — the value the clock must
  /// clear so local edits made after applying it are guaranteed to win the merge.
  static func newestInstant(in snapshot: DeviceSyncSnapshot) -> Date? {
    var newest: Date?
    func consider(_ date: Date) {
      if let current = newest {
        if date > current { newest = date }
      } else {
        newest = date
      }
    }
    snapshot.listSnapshot.lists.forEach { consider($0.updatedAt) }
    snapshot.listSnapshot.categories.forEach { consider($0.updatedAt) }
    snapshot.listSnapshot.entries.forEach { consider($0.updatedAt) }
    snapshot.deletedEntities.forEach { consider($0.deletedAt) }
    snapshot.deletedLists.forEach { consider($0.deletedAt) }
    consider(snapshot.searchSettings.updatedAt)
    return newest
  }

  private func syncClockFloorUnlocked() throws -> Date? {
    let statement = try database.prepare("SELECT value_text FROM sync_metadata WHERE key = ?")
    try statement.bind(Self.syncClockFloorMetadataKey, at: 1)
    guard try statement.step(), let text = statement.string(at: 0) else {
      return nil
    }
    return Self.isoListDateFormatter().date(from: text)
  }

  private func saveSyncClockFloorUnlocked(_ date: Date) throws {
    let statement = try database.prepare(
      """
      INSERT INTO sync_metadata (key, value_text, value_data) VALUES (?, ?, NULL)
      ON CONFLICT(key) DO UPDATE SET value_text = excluded.value_text, value_data = NULL
      """)
    try statement.bind(Self.syncClockFloorMetadataKey, at: 1)
    try statement.bind(Self.formattedListDate(date), at: 2)
    try statement.step()
  }
}
