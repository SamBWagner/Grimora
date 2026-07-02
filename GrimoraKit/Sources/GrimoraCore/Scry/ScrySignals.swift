import Foundation

/// The raw fields a single card image yields before it is resolved to a printing.
///
/// Signals come from on-device Vision work (OCR for `name` / `setCode` /
/// `collectorNumber`, frame and pip analysis for `colors`). They are deliberately
/// optional and noisy — `ScryCardResolver` decides how much to trust them.
public struct ScrySignals: Equatable, Sendable {
  /// Card name read from the title line, if any.
  public var name: String?
  /// Three-to-six character set code (e.g. `"neo"`), normalized lowercase, if read.
  public var setCode: String?
  /// Collector number as printed (e.g. `"123"`, `"123a"`), leading zeros stripped, if read.
  public var collectorNumber: String?
  /// The set-size denominator of an old-frame `6/249` collector line, if read.
  /// Identifies the set on pre-2015 frames, which print no set code.
  public var setTotal: Int?
  /// The later year of the copyright line (`© 1993–2009 Wizards…` → 2009), if read.
  /// Approximates the printing's release year — a strong printing-ranking signal
  /// on old frames.
  public var copyrightYear: Int?
  /// Colors inferred from the frame / mana pips (WUBRG letters). Corroboration only.
  public var colors: [String]
  /// Every text line Vision recognized, retained for diagnostics and the AI fallback.
  public var rawTextLines: [String]

  public init(
    name: String? = nil,
    setCode: String? = nil,
    collectorNumber: String? = nil,
    setTotal: Int? = nil,
    copyrightYear: Int? = nil,
    colors: [String] = [],
    rawTextLines: [String] = []
  ) {
    self.name = name
    self.setCode = setCode
    self.collectorNumber = collectorNumber
    self.setTotal = setTotal
    self.copyrightYear = copyrightYear
    self.colors = colors
    self.rawTextLines = rawTextLines
  }

  /// True when both halves of Magic's unique printing key were read.
  public var hasExactKey: Bool {
    guard let setCode, let collectorNumber else { return false }
    return !setCode.isEmpty && !collectorNumber.isEmpty
  }

  /// True when there is nothing worth resolving.
  public var isEmpty: Bool {
    (name?.isEmpty ?? true)
      && !hasExactKey
      && (collectorNumber?.isEmpty ?? true)
      && colors.isEmpty
  }
}

/// How sure the resolver is about an identification.
public enum ScryConfidence: String, Equatable, Sendable {
  /// Identified with enough certainty to add to a collection silently.
  case auto
  /// More than one plausible printing — present a quick disambiguation picker.
  case ambiguous
  /// Nothing matched.
  case none
}

/// Which tier of the pipeline produced the result. Useful for diagnostics and tuning.
public enum ScryMatchMethod: String, Equatable, Sendable {
  /// Set code + collector number hit the unique-key index.
  case exactKey
  /// Name + collector number pinned a single printing (set code missing/mis-read).
  case nameAndNumber
  /// Collector number + printed set total, with no readable name (a clipped or
  /// glared title). Never auto-accepts — surfaces a year-ranked printing picker.
  case numberAndTotal
  /// Set-symbol visual match against candidate printings' reference images
  /// (`ScrySymbolMatcher`) settled a printing picker.
  case nameAndVisual
  /// Resolved by name to a single printing.
  case nameOnly
  /// Disambiguated by the on-device model (Phase 4).
  case ai
  /// Nothing resolved.
  case unresolved
}

/// The output of `ScryCardResolver` for one scanned card.
///
/// When `confidence == .auto`, `card` is the printing to add. Otherwise `card`
/// is `nil` and `candidates` holds the ranked alternatives for the disambiguation UI.
public struct ScryResolution: Equatable, Sendable {
  /// The auto-accepted printing, present only when `confidence == .auto`.
  public var card: CardRecord?
  /// Ranked alternatives (best first) for disambiguation.
  public var candidates: [CardRecord]
  public var confidence: ScryConfidence
  public var method: ScryMatchMethod
  public var signals: ScrySignals

  public init(
    card: CardRecord?,
    candidates: [CardRecord],
    confidence: ScryConfidence,
    method: ScryMatchMethod,
    signals: ScrySignals
  ) {
    self.card = card
    self.candidates = candidates
    self.confidence = confidence
    self.method = method
    self.signals = signals
  }

  /// Convenience for the no-match outcome.
  public static func none(signals: ScrySignals) -> ScryResolution {
    ScryResolution(
      card: nil,
      candidates: [],
      confidence: .none,
      method: .unresolved,
      signals: signals
    )
  }
}
