import Foundation

/// Parses the set code and collector number from the bottom-left text of a
/// modern (M15-frame, ~2015+) Magic card.
///
/// Modern cards print two small lines such as:
/// ```
/// L 0256
/// OTJ • EN  Piotr Dura
/// ```
/// (older cards instead print `256/280` with a set total). Together
/// (set code + collector number) form Magic's unique printing key, which
/// `CardDatabase.card(setCode:collectorNumber:)` resolves exactly.
///
/// The parser is deliberately **precision-first**: it would rather return `nil`
/// than guess. Real-card OCR is littered with look-alikes — small-caps artist
/// names ("PIOTR"), the copyright year ("2025"), mana costs, "Wizards of the
/// Coast" — so the rules below only accept text in genuine collector-line shapes.
public enum ScryCollectorLineParser {
  /// Language codes printed next to the set code; used to locate the set code.
  ///
  /// Deliberately omits `it`/`he`/`la`/`ar`: those collide with common English
  /// flavor-text words ("bottle **it**", "T**he**…"), which would make the
  /// parser read flavor text as a set code. Non-English printings are rare enough
  /// to revisit later if the corpus calls for it.
  static let languageCodes: Set<String> = [
    "en", "de", "fr", "es", "pt", "ja", "jp", "ko", "ru", "zh", "zhs", "zht"
  ]

  /// Single-letter rarity stamps that prefix the collector number.
  static let rarityLetters: Set<String> = ["c", "u", "r", "m", "l", "s", "p", "t"]

  public struct Parsed: Equatable, Sendable {
    public var setCode: String?
    public var collectorNumber: String?

    public init(setCode: String? = nil, collectorNumber: String? = nil) {
      self.setCode = setCode
      self.collectorNumber = collectorNumber
    }
  }

  public static func parse(lines: [String]) -> Parsed {
    Parsed(
      setCode: setCode(in: lines),
      collectorNumber: collectorNumber(in: lines)
    )
  }

  // MARK: - Collector number

  static func collectorNumber(in lines: [String]) -> String? {
    // 1. The "number/total" form — but only when the denominator looks like a set
    //    size (≥ 20 and ≥ the number), so a creature's power/toughness ("2/2",
    //    "6/5") isn't mistaken for a collector number.
    for line in lines {
      for token in tokenize(line) where token.contains("/") {
        if let number = slashCollectorNumber(token) { return number }
      }
    }
    // 2. The zero-padded form modern cards print (e.g. "0256", "0005"). The slash form
    //    is rule 1's job; excluding it here keeps a 0-power creature's "0/4" toughness
    //    from being read as collector number "0" (it slips past rule 1 because its total
    //    is < 20, and the P/T line typically sits above the real collector line).
    for line in lines {
      for token in tokenize(line)
      where token.count >= 2 && token.first == "0" && !token.contains("/") {
        if let number = number(fromToken: token) { return number }
      }
    }
    // 3. A number immediately following a lone rarity letter (e.g. "U 263").
    for line in lines {
      let tokens = tokenize(line)
      for index in tokens.indices.dropFirst()
      where tokens[index - 1].count == 1 && rarityLetters.contains(tokens[index - 1].lowercased()) {
        if let number = number(fromToken: tokens[index]) { return number }
      }
    }
    return nil
  }

  /// A `number/total` token, accepted only when `total` looks like a set size
  /// (≥ 20 and ≥ number) — which rejects power/toughness like `2/2` or `6/5`.
  static func slashCollectorNumber(_ token: String) -> String? {
    let parts = token.split(separator: "/", maxSplits: 1)
    guard parts.count == 2,
          let number = number(fromToken: String(parts[0])),
          let total = Int(parts[1].filter(\.isNumber)),
          total >= 20,
          let numeric = Int(number.filter(\.isNumber)),
          numeric <= total else { return nil }
    return number
  }

  /// Accepts `123`, `0123`, `123a`, `123/350`. Returns the number with leading
  /// zeros stripped and any single trailing letter lowercased.
  static func number(fromToken token: String) -> String? {
    let head = token.split(separator: "/", maxSplits: 1).first.map(String.init) ?? token

    var digits = ""
    var suffix = ""
    for character in head {
      if character.isNumber {
        guard suffix.isEmpty else { return nil }
        digits.append(character)
      } else if character.isLetter {
        guard !digits.isEmpty, suffix.isEmpty else { return nil }
        suffix = String(character)
      } else {
        return nil
      }
    }

    guard !digits.isEmpty else { return nil }
    let stripped = String(digits.drop { $0 == "0" })
    return (stripped.isEmpty ? "0" : stripped) + suffix.lowercased()
  }

  // MARK: - Set code

  /// The set code is the candidate token immediately before the language code on
  /// the `SET • LANG` line. Nothing else is trusted — that's what kept artist
  /// names and copyright words from being mistaken for set codes.
  static func setCode(in lines: [String]) -> String? {
    for line in lines {
      let tokens = tokenize(line)
      guard let languageIndex = tokens.firstIndex(where: { languageCodes.contains($0.lowercased()) })
      else { continue }
      for token in tokens[..<languageIndex].reversed() where isSetCodeCandidate(token) {
        return token.lowercased()
      }
    }
    return nil
  }

  static func isSetCodeCandidate(_ token: String) -> Bool {
    let count = token.count
    guard count >= 3, count <= 6 else { return false }
    guard token.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
    guard token.contains(where: { $0.isLetter }) else { return false }  // not purely numeric
    return !languageCodes.contains(token.lowercased())
  }

  // MARK: - Tokenizing

  /// Splits on every character that isn't alphanumeric or `/`, so bullets, the
  /// foil star, and the artist-brush glyph all separate tokens while the
  /// `number/total` form survives intact.
  static func tokenize(_ line: String) -> [String] {
    line
      .split { !($0.isLetter || $0.isNumber || $0 == "/") }
      .map(String.init)
      .filter { !$0.isEmpty }
  }
}
