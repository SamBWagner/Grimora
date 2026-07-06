import Foundation

/// Pure, CloudKit-free decision logic for "does this record need re-uploading?", extracted from
/// `CloudKitSyncTransport` so the rules can be unit-tested without a live CloudKit container.
///
/// The transport re-derives a full snapshot of the library on every sync; this decides which of
/// those records actually differ from what CloudKit already holds, so we upload only genuine
/// changes instead of the whole library each time.
public enum CloudSyncUploadDiff {
  /// The copy of a record CloudKit has already confirmed (via a prior save or fetch). `nil`
  /// timestamps mean the field is absent on that copy.
  public struct KnownRecord: Equatable, Sendable {
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(updatedAt: Date?, deletedAt: Date?) {
      self.updatedAt = updatedAt
      self.deletedAt = deletedAt
    }
  }

  /// Whether an entity with the given timestamps needs uploading.
  ///
  /// Returns `true` when CloudKit has no confirmed copy (`known == nil`), or when the record's
  /// `updatedAt` or deletion state differs from that copy. It intentionally does NOT consider
  /// provenance (`sourceDeviceID`): the encoder stamps every entity with the *current* device's
  /// id on re-encode, so comparing it would flag every record that originated on another device
  /// (e.g. imported collections) as changed and re-upload the entire library each sync.
  public static func needsUpload(
    updatedAt: Date,
    deletedAt: Date?,
    known: KnownRecord?
  ) -> Bool {
    guard let known else {
      return true
    }
    return !sameInstant(known.updatedAt, updatedAt)
      || !sameInstant(known.deletedAt, deletedAt)
  }

  /// Millisecond-tolerant date equality — CloudKit can round-trip `Date`s with slightly different
  /// sub-millisecond precision, and a false "changed" would only cost a needless re-upload, so we
  /// treat instants within ~1ms as equal. Two absent dates are equal; one absent is not.
  public static func sameInstant(_ lhs: Date?, _ rhs: Date?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
      return true
    case let (lhs?, rhs?):
      return abs(lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate) < 0.001
    default:
      return false
    }
  }
}
