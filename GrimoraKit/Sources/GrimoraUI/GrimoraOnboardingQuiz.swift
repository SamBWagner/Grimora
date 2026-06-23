import Foundation

/// A single multiple-choice quiz question on the sample set.
///
/// Each question asks which operator answers a goal (e.g. "show only the Elves")
/// and offers a handful of operator choices. The distractors are deliberately
/// *close* — they return overlapping but wrong results — so the right answer
/// teaches precision rather than guessing.
public struct GrimoraOnboardingQuizQuestion: Identifiable, Equatable, Sendable {
  public let id: String
  /// What the user is asked to achieve.
  public let prompt: String
  /// Operator options shown as tappable choices.
  public let choices: [GrimoraOnboardingOperator]
  /// Token of the correct choice.
  public let answerToken: String
  /// Shown after answering — why the answer is right (and a distractor wrong).
  public let explanation: String

  public init(
    id: String,
    prompt: String,
    choices: [GrimoraOnboardingOperator],
    answerToken: String,
    explanation: String
  ) {
    self.id = id
    self.prompt = prompt
    self.choices = choices
    self.answerToken = answerToken
    self.explanation = explanation
  }

  /// The correct operator, if present in `choices`.
  public var correctChoice: GrimoraOnboardingOperator? {
    choices.first { $0.token == answerToken }
  }

  public func isCorrect(_ choice: GrimoraOnboardingOperator) -> Bool {
    choice.token == answerToken
  }
}

/// The quiz questions the walkthrough poses, drawn from the sample set.
public enum GrimoraOnboardingQuizCatalog {
  public static let questions: [GrimoraOnboardingQuizQuestion] = [
    GrimoraOnboardingQuizQuestion(
      id: "only-elves",
      prompt: "Show only the Elves in this set.",
      choices: [
        GrimoraOnboardingOperator(clause: .type("elf"), title: "Elves", detail: "t:elf"),
        GrimoraOnboardingOperator(clause: .color(.green), title: "Green", detail: "c:g"),
        GrimoraOnboardingOperator(clause: .type("creature"), title: "Creatures", detail: "t:creature"),
        GrimoraOnboardingOperator(clause: .manaValue(1), title: "One mana", detail: "mv=1"),
      ],
      answerToken: "t:elf",
      explanation: "t:elf matches the subtype on the type line. c:g would also pull in Birds of Paradise."
    ),
    GrimoraOnboardingQuizQuestion(
      id: "every-red-card",
      prompt: "Find every red card.",
      choices: [
        GrimoraOnboardingOperator(clause: .color(.red), title: "Red", detail: "c:r"),
        GrimoraOnboardingOperator(clause: .type("dragon"), title: "Dragons", detail: "t:dragon"),
        GrimoraOnboardingOperator(clause: .type("instant"), title: "Instants", detail: "t:instant"),
        GrimoraOnboardingOperator(clause: .color(.green), title: "Green", detail: "c:g"),
      ],
      answerToken: "c:r",
      explanation: "c:r matches a card's colour. t:dragon would miss Lightning Bolt."
    ),
    GrimoraOnboardingQuizQuestion(
      id: "one-mana",
      prompt: "Which search finds the one-mana cards?",
      choices: [
        GrimoraOnboardingOperator(clause: .manaValue(1), title: "One mana", detail: "mv=1"),
        GrimoraOnboardingOperator(clause: .type("creature"), title: "Creatures", detail: "t:creature"),
        GrimoraOnboardingOperator(clause: .color(.green), title: "Green", detail: "c:g"),
        GrimoraOnboardingOperator(clause: .type("artifact"), title: "Artifacts", detail: "t:artifact"),
      ],
      answerToken: "mv=1",
      explanation: "mv= matches total mana cost, so mv=1 catches every one-drop regardless of colour or type."
    ),
  ]
}
