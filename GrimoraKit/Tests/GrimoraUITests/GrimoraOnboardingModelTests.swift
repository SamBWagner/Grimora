import XCTest

@testable import GrimoraUI

@MainActor
final class GrimoraOnboardingModelTests: XCTestCase {
  private func makeUserDefaults() throws -> (UserDefaults, String) {
    let suiteName = "GrimoraOnboardingModelTests-\(UUID().uuidString)"
    let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
    return (userDefaults, suiteName)
  }

  func testDefaultsToNotStarted() throws {
    let (userDefaults, _) = try makeUserDefaults()
    let model = GrimoraOnboardingModel(userDefaults: userDefaults)

    XCTAssertEqual(model.state, .notStarted)
    XCTAssertFalse(model.isActive)
  }

  func testLibraryReadyStartsAndPersistsWalkthrough() throws {
    let (userDefaults, _) = try makeUserDefaults()
    let model = GrimoraOnboardingModel(userDefaults: userDefaults)

    model.libraryDidBecomeReady()

    XCTAssertEqual(model.state, .inProgress)
    XCTAssertTrue(model.isActive)

    // A freshly constructed model rehydrates the persisted state.
    let reloaded = GrimoraOnboardingModel(userDefaults: userDefaults)
    XCTAssertEqual(reloaded.state, .inProgress)
  }

  func testCompletePersistsAndStopsBeingActive() throws {
    let (userDefaults, _) = try makeUserDefaults()
    let model = GrimoraOnboardingModel(userDefaults: userDefaults)
    model.libraryDidBecomeReady()

    model.complete()

    XCTAssertEqual(model.state, .completed)
    XCTAssertFalse(model.isActive)

    let reloaded = GrimoraOnboardingModel(userDefaults: userDefaults)
    XCTAssertEqual(reloaded.state, .completed)
  }

  func testLibraryReadyDoesNotReopenCompletedWalkthrough() throws {
    let (userDefaults, _) = try makeUserDefaults()
    let model = GrimoraOnboardingModel(userDefaults: userDefaults)
    model.libraryDidBecomeReady()
    model.complete()

    // Re-downloading the library must not re-trigger the tour.
    model.libraryDidBecomeReady()

    XCTAssertEqual(model.state, .completed)
  }

  func testRestartReopensWalkthrough() throws {
    let (userDefaults, _) = try makeUserDefaults()
    let model = GrimoraOnboardingModel(userDefaults: userDefaults)
    model.libraryDidBecomeReady()
    model.complete()

    model.restart()

    XCTAssertEqual(model.state, .inProgress)
    XCTAssertTrue(model.isActive)
  }

  func testDisableEnvironmentForcesCompletedAndSuppressesTrigger() throws {
    let (userDefaults, _) = try makeUserDefaults()
    let processInfo = StubProcessInfo(
      environment: [GrimoraOnboardingPreferences.disableEnvironmentKey: "1"]
    )
    let model = GrimoraOnboardingModel(userDefaults: userDefaults, processInfo: processInfo)

    XCTAssertEqual(model.state, .completed)

    model.libraryDidBecomeReady()
    XCTAssertEqual(model.state, .completed)

    model.restart()
    XCTAssertEqual(model.state, .completed)
  }

  func testResolvedUserDefaultsHonoursTestSuiteAndFallsBackToStandard() throws {
    let suiteName = "GrimoraOnboardingResolved-\(UUID().uuidString)"
    addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }

    let withSuite = StubProcessInfo(environment: ["GRIMORA_TEST_USER_DEFAULTS_SUITE": suiteName])
    let resolved = GrimoraOnboardingPreferences.resolvedUserDefaults(processInfo: withSuite)
    // Writing through the resolved defaults lands in the named suite, not .standard.
    resolved.set("inProgress", forKey: GrimoraOnboardingPreferences.stateKey)
    XCTAssertEqual(
      UserDefaults(suiteName: suiteName)?.string(forKey: GrimoraOnboardingPreferences.stateKey),
      "inProgress"
    )

    let noSuite = StubProcessInfo(environment: [:])
    XCTAssertEqual(GrimoraOnboardingPreferences.resolvedUserDefaults(processInfo: noSuite), .standard)
  }

  func testModelSeededInProgressViaSuiteIsActiveAtLaunch() throws {
    // Mirrors how a UI test forces the tour on: pre-seed the suite, construct the
    // model with only a processInfo pointing at it.
    let suiteName = "GrimoraOnboardingSeeded-\(UUID().uuidString)"
    let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    addTeardownBlock { suite.removePersistentDomain(forName: suiteName) }
    suite.set(GrimoraOnboardingState.inProgress.rawValue, forKey: GrimoraOnboardingPreferences.stateKey)

    let processInfo = StubProcessInfo(environment: ["GRIMORA_TEST_USER_DEFAULTS_SUITE": suiteName])
    let model = GrimoraOnboardingModel(processInfo: processInfo)

    XCTAssertEqual(model.state, .inProgress)
    XCTAssertTrue(model.isActive)
  }

  func testSampleSetTeachesTheElfQuiz() {
    let cards = GrimoraOnboardingSampleSet.cards

    XCTAssertEqual(cards.count, 10)
    XCTAssertEqual(Set(cards.map(\.id)).count, cards.count, "Sample card ids must be unique")

    let elves = cards.filter { $0.exampleQuery == "t:elf" }
    XCTAssertEqual(
      elves.count,
      2,
      "Exactly two elves so a 'find only the elves' quiz has a clear answer"
    )
  }
}

private final class StubProcessInfo: ProcessInfo {
  private let stubEnvironment: [String: String]

  init(environment: [String: String]) {
    self.stubEnvironment = environment
    super.init()
  }

  override var environment: [String: String] {
    stubEnvironment
  }
}
