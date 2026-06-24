import GrimoraCore
import XCTest

/// macOS coverage of the onboarding walkthrough (S8a–S8d). The tour is forced on
/// via `GRIMORA_TEST_ONBOARDING_STATE` and isolated via
/// `GRIMORA_TEST_USER_DEFAULTS_SUITE`. (Replay-from-Settings is exercised by the
/// cross-platform sheet test + the `requestOnboardingReplay` unit test; the macOS
/// Settings *window* isn't reliably automatable here.)
final class OnboardingWalkthroughMacUITests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OnboardingMacUITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  func testTourAppearsSteppedAndCompletes() throws {
    let app = try launchApp(onboardingState: "inProgress")
    XCTAssertTrue(element(app, "onboarding-skip-button").waitForExistence(timeout: 10))
    XCTAssertTrue(element(app, "onboarding-progress").exists)

    for _ in 0..<10 {
      guard element(app, "onboarding-skip-button").exists else { break }
      let next = element(app, "onboarding-next-button")
      XCTAssertTrue(next.waitForExistence(timeout: 5))
      next.click()
    }

    XCTAssertTrue(waitForDisappearance(element(app, "onboarding-skip-button")))
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
  }

  func testSkipDismissesTour() throws {
    let app = try launchApp(onboardingState: "inProgress")
    let skip = element(app, "onboarding-skip-button")
    XCTAssertTrue(skip.waitForExistence(timeout: 10))
    app.activate() // Ensure Grimora is frontmost (the top-right Skip can sit under other windows).
    skip.click()
    XCTAssertTrue(waitForDisappearance(element(app, "onboarding-skip-button")))
  }

  func testInteractiveSearchFiltersTheSampleSet() throws {
    let app = try launchApp(onboardingState: "inProgress")
    XCTAssertTrue(element(app, "onboarding-skip-button").waitForExistence(timeout: 10))

    element(app, "onboarding-next-button").click()
    element(app, "onboarding-next-button").click()
    XCTAssertTrue(element(app, "onboarding-operator-playground").waitForExistence(timeout: 5))

    element(app, "onboarding-playground-chip-t:elf").click()

    // SwiftUI Text surfaces its string as `value` on macOS.
    let summary = app.staticTexts
      .containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "matches 2 of 10", "matches 2 of 10"))
      .firstMatch
    XCTAssertTrue(summary.waitForExistence(timeout: 5))
  }

  func testReturningUserSeesNoTour() throws {
    let app = try launchApp(onboardingState: "notStarted")
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
    XCTAssertFalse(element(app, "onboarding-skip-button").exists)
  }

  func testReplayFromHelpMenuReopensTour() throws {
    let app = try launchApp(onboardingState: "completed")
    // No tour at launch (already completed).
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
    XCTAssertFalse(element(app, "onboarding-skip-button").exists)

    // Help → Replay Tutorial brings the walkthrough back — the recovery path for
    // a first-time user who skipped the tour by accident.
    let helpMenu = app.menuBars.menuBarItems["Help"]
    XCTAssertTrue(helpMenu.waitForExistence(timeout: 5))
    helpMenu.click()
    let replay = app.menuItems["Replay Tutorial"]
    XCTAssertTrue(replay.waitForExistence(timeout: 5))
    replay.click()

    XCTAssertTrue(element(app, "onboarding-skip-button").waitForExistence(timeout: 5))
  }

  // MARK: Launch + seeding

  private func launchApp(onboardingState: String?) throws -> XCUIApplication {
    let databaseURL = try seedReadyLibrary()
    let app = XCUIApplication()
    app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] = databaseURL.path
    app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] =
      temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
    app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
      "GrimoraOnboardingMacUITests-\(UUID().uuidString)"
    app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
    app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
    app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
    app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
    if let onboardingState {
      app.launchEnvironment["GRIMORA_TEST_ONBOARDING_STATE"] = onboardingState
    }
    app.launch()
    app.activate()
    return app
  }

  private func seedReadyLibrary() throws -> URL {
    let databaseURL = temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).sqlite")
    let database = try CardDatabase(storage: .file(databaseURL))
    try database.replaceAllCards([Self.sampleCard])
    try database.saveMetadataValue(
      "2026-05-23T00:00:00.000+00:00", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
    try database.saveMetadataValue(
      CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
    try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)
    return databaseURL
  }

  private static var sampleCard: CardRecord {
    CardRecord(
      id: "alpha-forest",
      name: "Alpha Forest",
      setCode: "tst",
      setName: "Test Set",
      setType: "expansion",
      collectorNumber: "1",
      rarity: "common",
      colorSortKey: 0,
      layout: "normal",
      typeLine: "Basic Land — Forest",
      oracleText: "",
      isRealCard: true
    )
  }

  private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 6) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if !element.exists { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    return !element.exists
  }
}
