import XCTest

@testable import GrimoraUI

final class GrimoraOnboardingQuizTests: XCTestCase {
  private let cards = GrimoraOnboardingSampleSet.cards
  private let questions = GrimoraOnboardingQuizCatalog.questions

  func testCatalogIsNonEmptyWithUniqueQuestionIDs() {
    XCTAssertFalse(questions.isEmpty)
    XCTAssertEqual(Set(questions.map(\.id)).count, questions.count)
  }

  func testEveryQuestionHasACorrectChoiceAmongItsOptions() {
    for question in questions {
      let correct = question.correctChoice
      XCTAssertNotNil(correct, "\(question.id) answer must be one of its choices")
      XCTAssertEqual(correct?.token, question.answerToken)
      XCTAssertEqual(Set(question.choices.map(\.id)).count, question.choices.count, "choices unique")
      XCTAssertGreaterThanOrEqual(question.choices.count, 3, "offer a real choice")
    }
  }

  func testIsCorrectMatchesOnlyTheAnswer() {
    for question in questions {
      for choice in question.choices {
        XCTAssertEqual(
          question.isCorrect(choice),
          choice.token == question.answerToken,
          "\(question.id)/\(choice.token)"
        )
      }
    }
  }

  /// The whole point of the quiz: the correct operator is *more precise* than its
  /// distractors over the sample set, so each question's answer is genuinely the
  /// best one rather than coincidentally right.
  func testCorrectChoiceIsUniquelyPreciseOverTheSampleSet() {
    for question in questions {
      guard let correct = question.correctChoice else {
        XCTFail("\(question.id) has no correct choice")
        continue
      }
      let correctMatches = Set(correct.matchingCards(in: cards).map(\.id))
      XCTAssertFalse(correctMatches.isEmpty, "\(question.id) answer should match something")

      for distractor in question.choices where distractor.token != correct.token {
        let distractorMatches = Set(distractor.matchingCards(in: cards).map(\.id))
        XCTAssertNotEqual(
          distractorMatches,
          correctMatches,
          "\(question.id): distractor \(distractor.token) returns the same cards as the answer \(correct.token), so it isn't a real distractor"
        )
      }
    }
  }

  func testElfQuestionMatchesExactlyTheTwoElves() {
    let question = try? XCTUnwrap(questions.first { $0.id == "only-elves" })
    let correct = question?.correctChoice
    XCTAssertEqual(correct?.token, "t:elf")
    XCTAssertEqual(
      correct?.matchingCards(in: cards).map(\.id),
      ["llanowar-elves", "elvish-mystic"]
    )
  }
}
