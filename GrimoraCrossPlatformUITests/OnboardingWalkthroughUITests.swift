import GrimoraCore
import XCTest

/// End-to-end coverage of the onboarding walkthrough (S8a–S8d) on iOS & visionOS.
///
/// The tour is forced on deterministically via `GRIMORA_TEST_ONBOARDING_STATE`
/// (no 551 MB download needed) and isolated from the real defaults domain via
/// `GRIMORA_TEST_USER_DEFAULTS_SUITE`. Driven through the `onboarding-*`
/// accessibility identifiers.
final class OnboardingWalkthroughUITests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OnboardingUITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  // MARK: Tests

  func testTourAppearsSteppedAndCompletes() throws {
    let app = try launchApp(onboardingState: "inProgress")
    XCTAssertTrue(element(app, "onboarding-skip-button").waitForExistence(timeout: 10))
    XCTAssertTrue(element(app, "onboarding-progress").exists)
    XCTAssertTrue(element(app, "onboarding-skip-button").exists)

    // Step all the way through; the last "Next" is "Start Exploring" and finishes.
    // Bound generously (there are 7 steps) and stop once the tour dismisses.
    for _ in 0..<10 {
      guard element(app, "onboarding-skip-button").exists else { break }
      let next = element(app, "onboarding-next-button")
      XCTAssertTrue(next.waitForExistence(timeout: 5))
      activate(next)
    }

    XCTAssertTrue(waitForDisappearance(element(app, "onboarding-skip-button")))
  }

  func testBackButtonAppearsAfterFirstStep() throws {
    let app = try launchApp(onboardingState: "inProgress")
    XCTAssertTrue(element(app, "onboarding-skip-button").waitForExistence(timeout: 10))

    XCTAssertFalse(element(app, "onboarding-back-button").exists, "No Back on the first step")
    activate(element(app, "onboarding-next-button"))
    XCTAssertTrue(element(app, "onboarding-back-button").waitForExistence(timeout: 5))
  }

  func testSkipDismissesTour() throws {
    let app = try launchApp(onboardingState: "inProgress")
    XCTAssertTrue(element(app, "onboarding-skip-button").waitForExistence(timeout: 10))

    activate(element(app, "onboarding-skip-button"))

    XCTAssertTrue(waitForDisappearance(element(app, "onboarding-skip-button")))
  }

  func testInteractiveSearchFiltersTheSampleSet() throws {
    let app = try launchApp(onboardingState: "inProgress")
    XCTAssertTrue(element(app, "onboarding-skip-button").waitForExistence(timeout: 10))

    // welcome -> operators -> search
    activate(element(app, "onboarding-next-button"))
    activate(element(app, "onboarding-next-button"))
    XCTAssertTrue(element(app, "onboarding-operator-playground").waitForExistence(timeout: 5))

    activate(element(app, "onboarding-playground-chip-t:elf"))

    // SwiftUI Text surfaces its string as `label` on iOS but `value` on macOS.
    let summary = app.staticTexts
      .containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "matches 2 of 10", "matches 2 of 10"))
      .firstMatch
    XCTAssertTrue(summary.waitForExistence(timeout: 5), "t:elf should match exactly 2 of 10 cards")
  }

  func testQuizGivesCheckedFeedback() throws {
    let app = try launchApp(onboardingState: "inProgress")
    XCTAssertTrue(element(app, "onboarding-skip-button").waitForExistence(timeout: 10))

    // welcome -> operators -> search -> quiz
    activate(element(app, "onboarding-next-button"))
    activate(element(app, "onboarding-next-button"))
    activate(element(app, "onboarding-next-button"))
    XCTAssertTrue(element(app, "onboarding-quiz").waitForExistence(timeout: 5))

    activate(element(app, "onboarding-quiz-choice-only-elves-t:elf"))

    // Assert on the explanation copy (unique to this question) rather than the
    // feedback container, which SwiftUI doesn't always surface as a queryable
    // element. `label` on iOS, `value` on macOS.
    let feedback = app.staticTexts
      .containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Birds of Paradise", "Birds of Paradise"))
      .firstMatch
    XCTAssertTrue(feedback.waitForExistence(timeout: 5), "Answering should reveal checked feedback")
  }

  func testReturningUserSeesNoTour() throws {
    // Ready library at launch with state notStarted = no missing→ready transition,
    // so the tour must not appear (first-launch gating).
    let app = try launchApp(onboardingState: "notStarted")

    XCTAssertTrue(element(app, "search-options-menu").waitForExistence(timeout: 10))
    XCTAssertFalse(element(app, "onboarding-skip-button").exists)
  }

  func testReplayFromSettingsReopensTour() throws {
    let app = try launchApp(onboardingState: "completed")
    // No tour at launch.
    XCTAssertTrue(element(app, "search-options-menu").waitForExistence(timeout: 10))
    XCTAssertFalse(element(app, "onboarding-skip-button").exists)

    // Open the search options menu → Settings.
    activate(element(app, "search-options-menu"))
    let settingsButton = element(app, "search-settings-button")
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
    activate(settingsButton)

    let replay = element(app, "replay-tutorial-button")
    XCTAssertTrue(replay.waitForExistence(timeout: 5))
    activate(replay)

    // The sheet dismisses and the tour comes back.
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
      "GrimoraOnboardingUITests-\(UUID().uuidString)"
    app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
    app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
    app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
    app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
    if let onboardingState {
      app.launchEnvironment["GRIMORA_TEST_ONBOARDING_STATE"] = onboardingState
    }
    app.launch()
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

  // MARK: Element helpers

  private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func activate(_ element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 5))
    #if os(macOS)
    element.click()
    #else
    element.tap()
    #endif
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
