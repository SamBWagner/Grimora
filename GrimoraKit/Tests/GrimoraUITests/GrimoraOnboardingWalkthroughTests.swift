import XCTest

@testable import GrimoraUI

final class GrimoraOnboardingWalkthroughTests: XCTestCase {
  private let cards = GrimoraOnboardingSampleSet.cards

  // MARK: Operator matching

  func testColourClauseMatchesEveryCardOfThatColour() {
    XCTAssertEqual(matchedIDs(.color(.green)), ["llanowar-elves", "elvish-mystic", "birds-of-paradise"])
    XCTAssertEqual(matchedIDs(.color(.red)), ["lightning-bolt", "shivan-dragon"])
    XCTAssertEqual(matchedIDs(.color(.white)), ["serra-angel", "wrath-of-god"])
    XCTAssertEqual(matchedIDs(.color(.blue)), ["counterspell"])
    XCTAssertEqual(matchedIDs(.color(.black)), ["dark-ritual"])
  }

  func testColourlessCardMatchesNoColourClause() {
    for color in GrimoraOnboardingColor.allCases {
      XCTAssertFalse(
        GrimoraOnboardingClause.color(color).matches(solRing),
        "Sol Ring is colourless and should not match c:\(color.rawValue)"
      )
    }
  }

  func testTypeClauseMatchesTypesAndSubtypes() {
    XCTAssertEqual(matchedIDs(.type("creature")).count, 5)
    XCTAssertEqual(matchedIDs(.type("instant")), ["lightning-bolt", "counterspell", "dark-ritual"])
    XCTAssertEqual(matchedIDs(.type("artifact")), ["sol-ring"])
    // Subtypes are part of the type line, so t:elf matches the two elves.
    XCTAssertEqual(matchedIDs(.type("elf")), ["llanowar-elves", "elvish-mystic"])
    XCTAssertEqual(matchedIDs(.type("dragon")), ["shivan-dragon"])
  }

  func testTypeClauseIsCaseInsensitive() {
    XCTAssertEqual(matchedIDs(.type("ELF")), ["llanowar-elves", "elvish-mystic"])
  }

  func testManaValueClause() {
    XCTAssertEqual(matchedIDs(.manaValue(1)).count, 6)
    XCTAssertEqual(matchedIDs(.manaValue(6)), ["shivan-dragon"])
    XCTAssertTrue(matchedIDs(.manaValue(3)).isEmpty)
  }

  func testClauseTokens() {
    XCTAssertEqual(GrimoraOnboardingClause.color(.red).token, "c:r")
    XCTAssertEqual(GrimoraOnboardingClause.type("Elf").token, "t:elf")
    XCTAssertEqual(GrimoraOnboardingClause.manaValue(1).token, "mv=1")
  }

  func testMatchingCardsPreservesSetOrder() {
    let op = GrimoraOnboardingOperator(clause: .color(.green), title: "Green", detail: "c:g")
    XCTAssertEqual(
      op.matchingCards(in: cards).map(\.id),
      cards.filter { $0.colors.contains(.green) }.map(\.id)
    )
  }

  // MARK: Catalogs

  func testPlaygroundOperatorsAreLiveAndUnique() {
    let playground = GrimoraOnboardingOperatorCatalog.playground
    XCTAssertFalse(playground.isEmpty)
    XCTAssertEqual(Set(playground.map(\.id)).count, playground.count, "Chip tokens must be unique")

    for op in playground {
      XCTAssertEqual(op.id, op.token)
      XCTAssertFalse(
        op.matchingCards(in: cards).isEmpty,
        "Chip \(op.token) should match at least one sample card so it isn't a dead end"
      )
    }
  }

  func testCheatsheetIsNonEmptyWithStableIDs() {
    let cheatsheet = GrimoraOnboardingOperatorCatalog.cheatsheet
    XCTAssertFalse(cheatsheet.isEmpty)
    XCTAssertEqual(Set(cheatsheet.map(\.id)).count, cheatsheet.count)
  }

  // MARK: Walkthrough steps

  func testStepOrder() {
    XCTAssertEqual(
      GrimoraOnboardingWalkthroughStep.allCases,
      [.welcome, .operators, .search, .lists, .favourites, .finish]
    )
  }

  func testStepNavigationEndpoints() {
    XCTAssertTrue(GrimoraOnboardingWalkthroughStep.welcome.isFirst)
    XCTAssertNil(GrimoraOnboardingWalkthroughStep.welcome.previous)
    XCTAssertEqual(GrimoraOnboardingWalkthroughStep.welcome.next, .operators)

    XCTAssertTrue(GrimoraOnboardingWalkthroughStep.finish.isLast)
    XCTAssertNil(GrimoraOnboardingWalkthroughStep.finish.next)
    XCTAssertEqual(GrimoraOnboardingWalkthroughStep.finish.previous, .favourites)
  }

  func testStepIndexMatchesPosition() {
    for (offset, step) in GrimoraOnboardingWalkthroughStep.allCases.enumerated() {
      XCTAssertEqual(step.index, offset)
    }
  }

  // MARK: Helpers

  private func matchedIDs(_ clause: GrimoraOnboardingClause) -> [String] {
    cards.filter(clause.matches).map(\.id)
  }

  private var solRing: GrimoraOnboardingSampleCard {
    cards.first { $0.id == "sol-ring" }!
  }
}
