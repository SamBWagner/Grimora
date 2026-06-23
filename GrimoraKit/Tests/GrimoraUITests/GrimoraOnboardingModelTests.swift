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
