import Foundation

/// The five Magic colours, in WUBRG order, as the onboarding walkthrough teaches
/// them. Raw values match the single-letter Scryfall colour codes (`c:r`).
public enum GrimoraOnboardingColor: String, CaseIterable, Equatable, Sendable {
  case white = "w"
  case blue = "u"
  case black = "b"
  case red = "r"
  case green = "g"

  /// Capitalised name for prose, e.g. "Green".
  public var displayName: String {
    switch self {
    case .white: "White"
    case .blue: "Blue"
    case .black: "Black"
    case .red: "Red"
    case .green: "Green"
    }
  }
}

/// A single Scryfall search clause the walkthrough can demonstrate against the
/// sample set.
///
/// This is a deliberately tiny matcher covering only the operators the tutorial
/// teaches — it runs over the in-memory sample cards rather than the database, so
/// the playground stays self-contained and never touches the real search engine.
public enum GrimoraOnboardingClause: Equatable, Sendable {
  /// `c:` — matches a card that includes the given colour.
  case color(GrimoraOnboardingColor)
  /// `t:` — matches a card whose type line includes the given type or subtype
  /// (e.g. `t:creature` or `t:elf`).
  case type(String)
  /// `mv=` — matches a card with the exact mana value.
  case manaValue(Int)

  /// The Scryfall token the user would type for this clause, e.g. `c:r`.
  public var token: String {
    switch self {
    case .color(let color): "c:\(color.rawValue)"
    case .type(let type): "t:\(type.lowercased())"
    case .manaValue(let value): "mv=\(value)"
    }
  }

  public func matches(_ card: GrimoraOnboardingSampleCard) -> Bool {
    switch self {
    case .color(let color):
      return card.colors.contains(color)
    case .type(let type):
      let needle = type.lowercased()
      return card.types.contains(needle) || card.subtypes.contains(needle)
    case .manaValue(let value):
      return card.manaValue == value
    }
  }
}

/// A teachable operator: a clause plus the human-facing copy the walkthrough
/// shows alongside it.
public struct GrimoraOnboardingOperator: Identifiable, Equatable, Sendable {
  public let clause: GrimoraOnboardingClause
  /// Short label, e.g. "Red cards".
  public let title: String
  /// One-line explanation of what the operator does.
  public let detail: String

  /// The Scryfall token, also used as stable identity.
  public var id: String { clause.token }
  public var token: String { clause.token }

  public init(clause: GrimoraOnboardingClause, title: String, detail: String) {
    self.clause = clause
    self.title = title
    self.detail = detail
  }

  public func matches(_ card: GrimoraOnboardingSampleCard) -> Bool {
    clause.matches(card)
  }

  /// Sample cards this operator selects, preserving the set's order.
  public func matchingCards(
    in cards: [GrimoraOnboardingSampleCard]
  ) -> [GrimoraOnboardingSampleCard] {
    cards.filter(matches)
  }
}

/// Curated operator lists the walkthrough draws on.
public enum GrimoraOnboardingOperatorCatalog {
  /// The "cheatsheet" shown on the operators step — one example per operator
  /// family with teaching copy.
  public static let cheatsheet: [GrimoraOnboardingOperator] = [
    GrimoraOnboardingOperator(
      clause: .color(.green),
      title: "Colour",
      detail: "c: matches a card's colours. c:g finds green cards."
    ),
    GrimoraOnboardingOperator(
      clause: .type("creature"),
      title: "Card type",
      detail: "t: matches a card's type, like creature, instant, or artifact."
    ),
    GrimoraOnboardingOperator(
      clause: .type("elf"),
      title: "Creature type",
      detail: "t: also matches subtypes — t:elf finds every Elf."
    ),
    GrimoraOnboardingOperator(
      clause: .manaValue(1),
      title: "Mana value",
      detail: "mv: matches total mana cost. mv=1 finds one-mana cards."
    ),
  ]

  /// The tappable filter chips offered on the interactive search step, chosen so
  /// each gives a satisfying, easy-to-verify result over the sample set.
  public static let playground: [GrimoraOnboardingOperator] = [
    GrimoraOnboardingOperator(
      clause: .type("elf"),
      title: "Elves",
      detail: "t:elf"
    ),
    GrimoraOnboardingOperator(
      clause: .color(.green),
      title: "Green",
      detail: "c:g"
    ),
    GrimoraOnboardingOperator(
      clause: .color(.red),
      title: "Red",
      detail: "c:r"
    ),
    GrimoraOnboardingOperator(
      clause: .type("creature"),
      title: "Creatures",
      detail: "t:creature"
    ),
    GrimoraOnboardingOperator(
      clause: .type("instant"),
      title: "Instants",
      detail: "t:instant"
    ),
    GrimoraOnboardingOperator(
      clause: .manaValue(1),
      title: "One mana",
      detail: "mv=1"
    ),
  ]
}
