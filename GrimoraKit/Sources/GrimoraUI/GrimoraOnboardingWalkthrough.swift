import Foundation

/// The ordered steps of the first-run walkthrough.
///
/// Each case teaches one idea from the brief — operators, searching, storing
/// cards in lists, and favouriting — bookended by a welcome and a sign-off. The
/// tour is skippable at any step (see `OnboardingTutorialView`); this enum only
/// models the sequence and its framing copy, keeping it testable.
public enum GrimoraOnboardingWalkthroughStep: String, CaseIterable, Identifiable, Sendable {
  case welcome
  case operators
  case search
  case quiz
  case lists
  case favourites
  case finish

  public var id: String { rawValue }

  /// Step header.
  public var title: String {
    switch self {
    case .welcome: "Welcome to Grimora"
    case .operators: "Search operators"
    case .search: "Try a search"
    case .quiz: "Quick quiz"
    case .lists: "Save cards to collections"
    case .favourites: "Favourite the best"
    case .finish: "You're all set"
    }
  }

  /// One- or two-sentence framing shown under the title.
  public var summary: String {
    switch self {
    case .welcome:
      "Grimora searches Magic cards with Scryfall syntax. This quick, skippable tour uses ten sample cards to show the essentials."
    case .operators:
      "Operators narrow a search. Here are the ones you'll reach for most."
    case .search:
      "Tap an operator to filter the sample set and see what it matches."
    case .quiz:
      "Your turn — pick the operator that answers each question."
    case .lists:
      "Collections keep cards together — a deck, a wishlist, a binder. Tap a card to file it."
    case .favourites:
      "Favourites are your one-tap shortlist. Tap a star to add a card."
    case .finish:
      "That's the basics. Search the full library, build collections, and favourite anything you love."
    }
  }

  public var index: Int {
    Self.allCases.firstIndex(of: self) ?? 0
  }

  public var isFirst: Bool { self == Self.allCases.first }
  public var isLast: Bool { self == Self.allCases.last }

  /// The next step, or `nil` past the end.
  public var next: GrimoraOnboardingWalkthroughStep? {
    let all = Self.allCases
    guard let i = all.firstIndex(of: self), all.indices.contains(i + 1) else {
      return nil
    }
    return all[i + 1]
  }

  /// The previous step, or `nil` before the start.
  public var previous: GrimoraOnboardingWalkthroughStep? {
    let all = Self.allCases
    guard let i = all.firstIndex(of: self), all.indices.contains(i - 1) else {
      return nil
    }
    return all[i - 1]
  }
}
