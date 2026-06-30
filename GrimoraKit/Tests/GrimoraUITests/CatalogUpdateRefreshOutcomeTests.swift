import XCTest

@testable import GrimoraCore
@testable import GrimoraUI

final class CatalogUpdateRefreshOutcomeTests: XCTestCase {
  private func manifest() -> BulkDataManifest {
    BulkDataManifest(
      id: "default_cards",
      type: "default_cards",
      updatedAt: "2026-06-30T00:00:00.000+00:00",
      name: "Default Cards",
      size: 123_456,
      downloadURI: URL(string: "https://example.test/default.json")!
    )
  }

  func testSkipsWhenAnotherLibraryOperationWasRunning() {
    XCTAssertEqual(
      catalogUpdateRefreshOutcome(wasWorking: true, updateManifest: nil),
      .skipped
    )
    // Even with a pending manifest, a refresh that couldn't run surfaces nothing.
    XCTAssertEqual(
      catalogUpdateRefreshOutcome(wasWorking: true, updateManifest: manifest()),
      .skipped
    )
  }

  func testOffersDownloadWhenManifestIsAvailable() {
    XCTAssertEqual(
      catalogUpdateRefreshOutcome(wasWorking: false, updateManifest: manifest()),
      .updateAvailable(manifest())
    )
  }

  func testReportsUpToDateWhenNoManifest() {
    XCTAssertEqual(
      catalogUpdateRefreshOutcome(wasWorking: false, updateManifest: nil),
      .upToDate
    )
  }
}
