import XCTest

#if os(iOS)
@MainActor
final class CloudSyncPhysicalVerificationUITests: XCTestCase {
  func testResolveInitialCloudSyncConflictForPhysicalVerification() {
    let app = XCUIApplication()
    app.launchEnvironment["GRIMORA_TEST_ENABLE_CLOUD_SYNC"] = "1"
    app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
    app.launchEnvironment["GRIMORA_SYNC_TEST_EXPOSE_STATUS"] = "1"
    app.launch()

    let resolutionTitle = app.staticTexts["Review iCloud Data"]
    if resolutionTitle.waitForExistence(timeout: 20) {
      let iPhoneSource = app.buttons.matching(
        NSPredicate(format: "label CONTAINS[c] %@", "iPhone")
      ).firstMatch
      if iPhoneSource.exists {
        iPhoneSource.tap()
      }

      let identifiedConfirmButton = app.descendants(matching: .any)[
        "confirm-sync-resolution-button"
      ]
      let labeledConfirmButton = app.buttons["Combine and Continue"]
      let confirmButton = identifiedConfirmButton.exists
        ? identifiedConfirmButton
        : labeledConfirmButton
      if !confirmButton.exists {
        app.swipeUp()
      }
      XCTAssertTrue(
        confirmButton.waitForExistence(timeout: 5),
        "Cloud sync resolution appeared without an actionable confirmation button."
      )
      confirmButton.tap()
      XCTAssertTrue(
        waitForNonExistence(of: resolutionTitle, timeout: 20),
        "Cloud sync resolution did not complete."
      )
    }

    app.terminate()
    app.launchEnvironment["GRIMORA_SYNC_TEST_CREATE_LIST"] =
      "Physical iPhone 20260620-1634"
    app.launchEnvironment["GRIMORA_SYNC_TEST_DEFAULT_SEARCH"] = "type:artifact"
    app.launchEnvironment["GRIMORA_SYNC_TEST_CURRENCY"] = "AUD"
    app.launch()

    let status = app.descendants(matching: .any)["cloud-sync-test-status"]
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    let readyPredicate = NSPredicate(
      format: "label == %@",
      "iCloud sync is ready."
    )
    let readyExpectation = XCTNSPredicateExpectation(
      predicate: readyPredicate,
      object: status
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [readyExpectation], timeout: 30),
      .completed,
      "Cloud sync did not become ready. Last status: \(status.label)"
    )
    XCTAssertFalse(
      resolutionTitle.exists,
      "Cloud sync returned to source resolution after selecting the source."
    )
    XCTAssertFalse(
      app.staticTexts["Checking iCloud..."].exists,
      "Cloud sync remained stuck while applying physical verification changes."
    )
  }

  private func waitForNonExistence(
    of element: XCUIElement,
    timeout: TimeInterval
  ) -> Bool {
    let predicate = NSPredicate(format: "exists == false")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }
}
#endif
