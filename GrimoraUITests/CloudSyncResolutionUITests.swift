import XCTest

@MainActor
final class CloudSyncResolutionUITests: XCTestCase {
  // The interactive iCloud conflict-resolution screen this exercised ("Review iCloud Data",
  // "Combine and Continue") was removed when CloudKit became the single source of truth
  // (commits 236b2bc and 2bc52fa). The app no longer reads GRIMORA_SYNC_TEST_CONFLICT_FIXTURE,
  // so the fixture launch can never reach that UI. Convergence is now covered by the
  // deterministic LWW unit-test harness in GrimoraKit, not by this UI flow.
  //
  // This test is obsolete; delete CloudSyncResolutionUITests.swift via Xcode (so the project
  // file reference is removed too) when convenient.
  func testConflictFixtureShowsCombinedCloudAndCurrentMac() throws {
    throw XCTSkip(
      "Interactive iCloud conflict-resolution UI was removed (CloudKit is now the single source "
        + "of truth). Covered by the LWW convergence unit tests instead.")
  }
}
