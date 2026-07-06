import XCTest

@testable import GrimoraCore

/// Unit coverage for the "only upload genuine changes" diff that replaced re-uploading the whole
/// library on every sync. These lock in the rules (and the two bugs found during live debugging:
/// re-encoded `sourceDeviceID` and CloudKit date-precision) without needing a live CloudKit zone.
final class CloudSyncUploadDiffTests: XCTestCase {
  private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

  // MARK: needsUpload

  func testRecordCloudKitHasNeverSeenIsUploaded() {
    XCTAssertTrue(
      CloudSyncUploadDiff.needsUpload(updatedAt: t0, deletedAt: nil, known: nil),
      "A record with no confirmed server copy must upload (new record / prior failure)."
    )
  }

  func testUnchangedRecordIsSkipped() {
    let known = CloudSyncUploadDiff.KnownRecord(updatedAt: t0, deletedAt: nil)
    XCTAssertFalse(
      CloudSyncUploadDiff.needsUpload(updatedAt: t0, deletedAt: nil, known: known),
      "A record whose updatedAt and deletion match the server copy must not re-upload."
    )
  }

  func testNewerUpdatedAtIsUploaded() {
    let known = CloudSyncUploadDiff.KnownRecord(updatedAt: t0, deletedAt: nil)
    XCTAssertTrue(
      CloudSyncUploadDiff.needsUpload(
        updatedAt: t0.addingTimeInterval(5),
        deletedAt: nil,
        known: known
      ),
      "A genuine local edit (bumped updatedAt) must upload."
    )
  }

  /// The regression that made the first fix upload 1496/1716 records: an entity that originated on
  /// another device (imported collection) is re-encoded with THIS device's sourceDeviceID, but its
  /// content is unchanged. The diff ignores provenance, so it must still be skipped.
  func testImportedRecordWithUnchangedContentIsSkipped() {
    let known = CloudSyncUploadDiff.KnownRecord(updatedAt: t0, deletedAt: nil)
    // Same updatedAt/deletion as the server copy; only provenance would differ, which is not an
    // input here precisely because it must not drive the decision.
    XCTAssertFalse(
      CloudSyncUploadDiff.needsUpload(updatedAt: t0, deletedAt: nil, known: known),
      "A record differing only by re-stamped provenance must not re-upload."
    )
  }

  func testBecomingDeletedIsUploaded() {
    let known = CloudSyncUploadDiff.KnownRecord(updatedAt: t0, deletedAt: nil)
    XCTAssertTrue(
      CloudSyncUploadDiff.needsUpload(updatedAt: t0, deletedAt: t0, known: known),
      "A record that is now tombstoned must upload the deletion."
    )
  }

  func testUnchangedDeletionIsSkipped() {
    let known = CloudSyncUploadDiff.KnownRecord(updatedAt: t0, deletedAt: t0)
    XCTAssertFalse(
      CloudSyncUploadDiff.needsUpload(updatedAt: t0, deletedAt: t0, known: known),
      "An already-synced tombstone must not re-upload."
    )
  }

  func testDifferentDeletionInstantIsUploaded() {
    let known = CloudSyncUploadDiff.KnownRecord(updatedAt: t0, deletedAt: t0)
    XCTAssertTrue(
      CloudSyncUploadDiff.needsUpload(
        updatedAt: t0,
        deletedAt: t0.addingTimeInterval(5),
        known: known
      )
    )
  }

  func testResurrectedRecordIsUploaded() {
    // Server has a tombstone; locally it's live again (deletedAt cleared).
    let known = CloudSyncUploadDiff.KnownRecord(updatedAt: t0, deletedAt: t0)
    XCTAssertTrue(
      CloudSyncUploadDiff.needsUpload(updatedAt: t0, deletedAt: nil, known: known)
    )
  }

  /// CloudKit can hand a Date back with slightly different sub-millisecond precision than we
  /// stored; that must not count as a change (it would resurrect the whole-library churn).
  func testSubMillisecondPrecisionDriftIsSkipped() {
    let known = CloudSyncUploadDiff.KnownRecord(
      updatedAt: t0.addingTimeInterval(0.0004),
      deletedAt: nil
    )
    XCTAssertFalse(
      CloudSyncUploadDiff.needsUpload(updatedAt: t0, deletedAt: nil, known: known),
      "A <1ms timestamp drift must be treated as unchanged."
    )
  }

  func testChangeJustBeyondToleranceIsUploaded() {
    let known = CloudSyncUploadDiff.KnownRecord(
      updatedAt: t0.addingTimeInterval(0.002),
      deletedAt: nil
    )
    XCTAssertTrue(
      CloudSyncUploadDiff.needsUpload(updatedAt: t0, deletedAt: nil, known: known)
    )
  }

  // MARK: sameInstant

  func testSameInstantHandlesNilAndTolerance() {
    XCTAssertTrue(CloudSyncUploadDiff.sameInstant(nil, nil))
    XCTAssertFalse(CloudSyncUploadDiff.sameInstant(t0, nil))
    XCTAssertFalse(CloudSyncUploadDiff.sameInstant(nil, t0))
    XCTAssertTrue(CloudSyncUploadDiff.sameInstant(t0, t0))
    XCTAssertTrue(CloudSyncUploadDiff.sameInstant(t0, t0.addingTimeInterval(0.0009)))
    XCTAssertFalse(CloudSyncUploadDiff.sameInstant(t0, t0.addingTimeInterval(0.05)))
  }
}
