import Foundation
import Observation

/// Where the user is in the first-run onboarding walkthrough.
///
/// The walkthrough is built up across the S8 lane; this scaffold only models the
/// state machine and the sample set it teaches with. `inProgress` is entered the
/// first time the local library finishes downloading (see ``GrimoraOnboardingModel``).
public enum GrimoraOnboardingState: String, Equatable, Sendable {
  case notStarted
  case inProgress
  case completed
}

/// Persistence keys and environment overrides for onboarding.
public enum GrimoraOnboardingPreferences {
  public static let stateKey = "Grimora.onboarding.state"

  /// Set `GRIMORA_DISABLE_ONBOARDING=1` to keep the walkthrough from ever
  /// appearing (used by UI/screenshot tests that drive a freshly-imported
  /// library and shouldn't be interrupted by the tour).
  static let disableEnvironmentKey = "GRIMORA_DISABLE_ONBOARDING"

  /// Forces the walkthrough's *initial* state for UI tests (e.g. `inProgress` to
  /// show the tour at launch, `completed` to keep it hidden). Persisted writes
  /// still go to the resolved (suite-isolated) defaults, so this never touches the
  /// real defaults domain.
  static let stateEnvironmentKey = "GRIMORA_TEST_ONBOARDING_STATE"

  public static func state(from rawValue: String?) -> GrimoraOnboardingState {
    rawValue.flatMap(GrimoraOnboardingState.init(rawValue:)) ?? .notStarted
  }

  /// The `UserDefaults` onboarding state persists to. Honours
  /// `GRIMORA_TEST_USER_DEFAULTS_SUITE` (mirroring `GrimoraEnvironment`) so UI
  /// tests stay isolated from the real defaults domain and can seed the tour's
  /// state deterministically; falls back to `.standard` in production.
  public static func resolvedUserDefaults(processInfo: ProcessInfo = .processInfo) -> UserDefaults {
    processInfo.environment["GRIMORA_TEST_USER_DEFAULTS_SUITE"]
      .flatMap(UserDefaults.init(suiteName:)) ?? .standard
  }
}

/// One card in the curated onboarding sample set.
///
/// The set is hand-picked so a handful of Scryfall operators each have an obvious
/// answer (colours, card types, creature types, mana value). Later S8 steps hydrate
/// these into real `CardRecord`s by `name` and build searches/quizzes from
/// `exampleQuery`.
public struct GrimoraOnboardingSampleCard: Identifiable, Equatable, Sendable {
  /// Stable slug used for view identity and accessibility identifiers.
  public let id: String
  /// Exact card name, used to load the real card from the library.
  public let name: String
  /// Short human summary, e.g. "Green · Elf Creature".
  public let summary: String
  /// The operator this card helps teach, e.g. "Creature types · t:elf".
  public let teachingPoint: String
  /// A Scryfall query that surfaces this card (or its group) within the sample set.
  public let exampleQuery: String
  /// Colours the card includes (empty for colourless), used by the interactive
  /// `c:` filters in the walkthrough.
  public let colors: Set<GrimoraOnboardingColor>
  /// Card types, lowercased (e.g. "creature", "instant"), used by `t:` filters.
  public let types: Set<String>
  /// Creature/permanent subtypes, lowercased (e.g. "elf"), also matched by `t:`.
  public let subtypes: Set<String>
  /// Total mana value, used by `mv=` filters.
  public let manaValue: Int

  public init(
    id: String,
    name: String,
    summary: String,
    teachingPoint: String,
    exampleQuery: String,
    colors: Set<GrimoraOnboardingColor>,
    types: Set<String>,
    subtypes: Set<String> = [],
    manaValue: Int
  ) {
    self.id = id
    self.name = name
    self.summary = summary
    self.teachingPoint = teachingPoint
    self.exampleQuery = exampleQuery
    self.colors = colors
    self.types = types
    self.subtypes = subtypes
    self.manaValue = manaValue
  }
}

/// The ~10-card example set the walkthrough teaches with.
///
/// Spread across all five colours, several card types, and a few creature
/// subtypes so operators like `c:`, `t:`, and `mv` each have a clear answer. The
/// two elves intentionally collide so a "find only the elves" quiz (`t:elf`) has
/// exactly two matches.
public enum GrimoraOnboardingSampleSet {
  public static let cards: [GrimoraOnboardingSampleCard] = [
    GrimoraOnboardingSampleCard(
      id: "llanowar-elves",
      name: "Llanowar Elves",
      summary: "Green · Elf Creature",
      teachingPoint: "Creature types · t:elf",
      exampleQuery: "t:elf",
      colors: [.green],
      types: ["creature"],
      subtypes: ["elf"],
      manaValue: 1
    ),
    GrimoraOnboardingSampleCard(
      id: "elvish-mystic",
      name: "Elvish Mystic",
      summary: "Green · Elf Creature",
      teachingPoint: "Creature types · t:elf",
      exampleQuery: "t:elf",
      colors: [.green],
      types: ["creature"],
      subtypes: ["elf"],
      manaValue: 1
    ),
    GrimoraOnboardingSampleCard(
      id: "birds-of-paradise",
      name: "Birds of Paradise",
      summary: "Green · Bird Creature",
      teachingPoint: "Mana value · mv=1",
      exampleQuery: "mv=1",
      colors: [.green],
      types: ["creature"],
      subtypes: ["bird"],
      manaValue: 1
    ),
    GrimoraOnboardingSampleCard(
      id: "lightning-bolt",
      name: "Lightning Bolt",
      summary: "Red · Instant",
      teachingPoint: "Card types · t:instant",
      exampleQuery: "t:instant",
      colors: [.red],
      types: ["instant"],
      manaValue: 1
    ),
    GrimoraOnboardingSampleCard(
      id: "shivan-dragon",
      name: "Shivan Dragon",
      summary: "Red · Dragon Creature",
      teachingPoint: "Colours · c:r",
      exampleQuery: "c:r",
      colors: [.red],
      types: ["creature"],
      subtypes: ["dragon"],
      manaValue: 6
    ),
    GrimoraOnboardingSampleCard(
      id: "counterspell",
      name: "Counterspell",
      summary: "Blue · Instant",
      teachingPoint: "Colours · c:u",
      exampleQuery: "c:u",
      colors: [.blue],
      types: ["instant"],
      manaValue: 2
    ),
    GrimoraOnboardingSampleCard(
      id: "dark-ritual",
      name: "Dark Ritual",
      summary: "Black · Instant",
      teachingPoint: "Colours · c:b",
      exampleQuery: "c:b",
      colors: [.black],
      types: ["instant"],
      manaValue: 1
    ),
    GrimoraOnboardingSampleCard(
      id: "serra-angel",
      name: "Serra Angel",
      summary: "White · Angel Creature",
      teachingPoint: "Creature types · t:angel",
      exampleQuery: "t:angel",
      colors: [.white],
      types: ["creature"],
      subtypes: ["angel"],
      manaValue: 5
    ),
    GrimoraOnboardingSampleCard(
      id: "wrath-of-god",
      name: "Wrath of God",
      summary: "White · Sorcery",
      teachingPoint: "Card types · t:sorcery",
      exampleQuery: "t:sorcery",
      colors: [.white],
      types: ["sorcery"],
      manaValue: 4
    ),
    GrimoraOnboardingSampleCard(
      id: "sol-ring",
      name: "Sol Ring",
      summary: "Colourless · Artifact",
      teachingPoint: "Card types · t:artifact",
      exampleQuery: "t:artifact",
      colors: [],
      types: ["artifact"],
      manaValue: 1
    ),
  ]
}

/// Drives the first-run onboarding walkthrough: owns the persisted
/// ``GrimoraOnboardingState`` and the sample set the later steps build on.
///
/// Created once by `GrimoraRootView`. The walkthrough begins the first time the
/// library transitions to ready (post-download); completing or skipping it marks
/// it done so it never reappears. `restart()` exists for the "Replay tutorial"
/// affordance added in S8d.
@Observable
@MainActor
public final class GrimoraOnboardingModel {
  public private(set) var state: GrimoraOnboardingState

  public let sampleCards: [GrimoraOnboardingSampleCard]

  private let userDefaults: UserDefaults
  private let isDisabled: Bool

  public init(
    userDefaults: UserDefaults? = nil,
    sampleCards: [GrimoraOnboardingSampleCard] = GrimoraOnboardingSampleSet.cards,
    processInfo: ProcessInfo = .processInfo
  ) {
    let resolvedDefaults =
      userDefaults ?? GrimoraOnboardingPreferences.resolvedUserDefaults(processInfo: processInfo)
    self.userDefaults = resolvedDefaults
    self.sampleCards = sampleCards
    self.isDisabled =
      processInfo.environment[GrimoraOnboardingPreferences.disableEnvironmentKey] == "1"
    let storedState = GrimoraOnboardingPreferences.state(
      from: resolvedDefaults.string(forKey: GrimoraOnboardingPreferences.stateKey)
    )
    let seededState = processInfo.environment[GrimoraOnboardingPreferences.stateEnvironmentKey]
      .flatMap(GrimoraOnboardingState.init(rawValue:))
    self.state = isDisabled ? .completed : (seededState ?? storedState)
  }

  /// `true` while the walkthrough should be presented over the app.
  public var isActive: Bool {
    state == .inProgress
  }

  /// Start the walkthrough the first time the library becomes ready. No-op once it
  /// has already started, completed, or been disabled, so re-downloading the
  /// library never re-triggers the tour.
  public func libraryDidBecomeReady() {
    guard !isDisabled, state == .notStarted else {
      return
    }
    setState(.inProgress)
  }

  /// Mark the walkthrough finished, whether the user completed or skipped it.
  public func complete() {
    guard state != .completed else {
      return
    }
    setState(.completed)
  }

  /// Replay the walkthrough from the beginning (S8d "Replay tutorial").
  public func restart() {
    guard !isDisabled else {
      return
    }
    setState(.inProgress)
  }

  private func setState(_ newState: GrimoraOnboardingState) {
    guard newState != state else {
      return
    }
    state = newState
    userDefaults.set(newState.rawValue, forKey: GrimoraOnboardingPreferences.stateKey)
  }
}
