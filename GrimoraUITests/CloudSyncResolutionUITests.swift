import XCTest

@MainActor
final class CloudSyncResolutionUITests: XCTestCase {
  func testConflictFixtureShowsCombinedCloudAndCurrentMac() {
    let app = XCUIApplication()
    app.launchEnvironment["GRIMORA_SYNC_TEST_CONFLICT_FIXTURE"] = "1"
    app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
    app.launch()

    XCTAssertTrue(app.staticTexts["Review iCloud Data"].waitForExistence(timeout: 15))
    XCTAssertTrue(element(containing: "iCloud (combined)", in: app).exists)
    XCTAssertTrue(app.buttons["Combine and Continue"].exists)
    XCTAssertTrue(app.staticTexts["All lists included"].exists)
    XCTAssertTrue(element(containing: "Weekend Commander", in: app).exists)
    XCTAssertFalse(app.staticTexts["Trade Binder"].exists)
    XCTAssertFalse(app.staticTexts["Draft Ideas"].exists)
  }

  private func element(containing label: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", label))
      .firstMatch
  }
}
