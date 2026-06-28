import Foundation

/// Turns the noisy `ScrySignals` from one scanned card into a `ScryResolution`,
/// cheapest-and-most-certain tier first.
///
/// - Tier A (exact key): set code + collector number is Magic's unique printing
///   key. A hit on `CardDatabase.card(setCode:collectorNumber:)` whose name
///   corroborates the OCR'd name is auto-accepted — no AI, no network.
/// - Tier B (name): with no usable key, search by name. A name that resolves to a
///   single printing is auto-accepted; multiple printings become candidates.
/// - Tier C (ambiguous): anything the above could not pin down is returned as
///   ranked candidates for the disambiguation UI.
///
/// The cardinal rule is precision: the resolver never reports `.auto` unless it
/// is confident, so auto-accepted identifications stay (effectively) 100% correct
/// and uncertainty is surfaced rather than guessed.
public struct ScryCardResolver: Sendable {
  public let database: CardDatabase

  /// Minimum name similarity (`0...1`) required to treat an OCR'd name as
  /// corroborating a database name.
  public var autoAcceptNameSimilarity: Double

  /// Maximum number of candidates returned for disambiguation.
  public var candidateLimit: Int

  public init(
    database: CardDatabase,
    autoAcceptNameSimilarity: Double = 0.82,
    candidateLimit: Int = 6
  ) {
    self.database = database
    self.autoAcceptNameSimilarity = autoAcceptNameSimilarity
    self.candidateLimit = candidateLimit
  }

  public func resolve(_ signals: ScrySignals) throws -> ScryResolution {
    if signals.isEmpty {
      return .none(signals: signals)
    }

    // Tier A — exact (set code + collector number) unique key.
    if let setCode = signals.setCode, let collectorNumber = signals.collectorNumber,
       !setCode.isEmpty, !collectorNumber.isEmpty,
       let keyed = try database.card(setCode: setCode, collectorNumber: collectorNumber) {
      guard let name = signals.name, !name.isEmpty else {
        // The printed key is itself unique; with no name there's nothing to contradict it.
        return ScryResolution(
          card: keyed,
          candidates: [keyed],
          confidence: .auto,
          method: .exactKey,
          signals: signals
        )
      }

      if ScryStringSimilarity.nameSimilarity(keyed.name, name) >= autoAcceptNameSimilarity {
        return ScryResolution(
          card: keyed,
          candidates: [keyed],
          confidence: .auto,
          method: .exactKey,
          signals: signals
        )
      }

      // The name doesn't match the keyed printing. Two reasons are possible:
      //  - the OCR'd "name" is noise (a borderless promo's decorative banner, or
      //    flavor text) that matches no real card — then the unique set+number key
      //    is authoritative, so auto-accept it; or
      //  - the name strongly matches a *different* card, which means a digit was
      //    likely mis-read — that's a real conflict, so disambiguate.
      let nameMatches = try nameCandidates(for: name)
      let conflicting = nameMatches.filter {
        $0.id != keyed.id && ScryStringSimilarity.nameSimilarity($0.name, name) >= autoAcceptNameSimilarity
      }
      if conflicting.isEmpty {
        return ScryResolution(
          card: keyed,
          candidates: [keyed],
          confidence: .auto,
          method: .exactKey,
          signals: signals
        )
      }
      return ScryResolution(
        card: nil,
        candidates: Array(([keyed] + conflicting).prefix(candidateLimit)),
        confidence: .ambiguous,
        method: .exactKey,
        signals: signals
      )
    }

    // Tier A′ — name + collector number. The name reads reliably and the
    // collector number nearly so, while the set code is the weakest signal (OCR
    // mangles "OTJ" into "OTS" under glare). Name + exact collector number is
    // almost always a unique printing, so this recovers cards a mis-read set code
    // would have lost.
    if let name = signals.name, !name.isEmpty,
       let number = signals.collectorNumber, !number.isEmpty {
      let matches = try nameCandidates(for: name).filter { $0.collectorNumber == number }
      if matches.count == 1 {
        return ScryResolution(
          card: matches[0],
          candidates: matches,
          confidence: .auto,
          method: .nameAndNumber,
          signals: signals
        )
      }
      if matches.count > 1 {
        // Same name + number across printings (rare): let the set code break the tie.
        if let setCode = signals.setCode,
           let exact = matches.first(where: { $0.setCode.lowercased() == setCode }) {
          return ScryResolution(
            card: exact,
            candidates: matches,
            confidence: .auto,
            method: .nameAndNumber,
            signals: signals
          )
        }
        return ScryResolution(
          card: nil,
          candidates: matches,
          confidence: .ambiguous,
          method: .nameAndNumber,
          signals: signals
        )
      }
    }

    // Tier B — name (printing-level).
    if let name = signals.name, !name.isEmpty {
      let candidates = try nameCandidates(for: name)
      let strong = candidates.filter {
        ScryStringSimilarity.nameSimilarity($0.name, name) >= autoAcceptNameSimilarity
      }
      // Only auto-accept when the name pins down exactly one printing; multiple
      // printings of the same card can't be separated by name alone.
      if strong.count == 1 {
        return ScryResolution(
          card: strong[0],
          candidates: strong,
          confidence: .auto,
          method: .nameOnly,
          signals: signals
        )
      }
      if !candidates.isEmpty {
        // Return every matching printing — name alone can't pick one, so the
        // disambiguation UI is a printing picker (the user matches art/set).
        return ScryResolution(
          card: nil,
          candidates: candidates,
          confidence: .ambiguous,
          method: .nameOnly,
          signals: signals
        )
      }
    }

    return .none(signals: signals)
  }

  /// Database printings whose name matches the OCR'd name, ranked by similarity.
  func nameCandidates(for rawName: String) throws -> [CardRecord] {
    let query = Self.sanitizeNameQuery(rawName)
    guard !query.isEmpty else { return [] }

    let response = try database.search(
      CardSearchRequest(text: query, printingDisplayMode: .all, limit: max(candidateLimit * 10, 80))
    )
    guard case .results(let cards, _) = response else { return [] }

    return cards.sorted { lhs, rhs in
      let lhsScore = ScryStringSimilarity.nameSimilarity(lhs.name, rawName)
      let rhsScore = ScryStringSimilarity.nameSimilarity(rhs.name, rawName)
      if lhsScore != rhsScore { return lhsScore > rhsScore }
      if lhs.name != rhs.name { return lhs.name < rhs.name }
      return lhs.id < rhs.id
    }
  }

  /// Reduces an OCR'd name to bare, query-safe words: front face only, letters
  /// and digits kept, everything else collapsed to spaces. Avoids feeding stray
  /// punctuation into the Scryfall query compiler.
  static func sanitizeNameQuery(_ name: String) -> String {
    let frontFace = name.split(separator: "/", maxSplits: 1).first.map(String.init) ?? name
    var cleaned = ""
    for scalar in frontFace.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
        cleaned.unicodeScalars.append(scalar)
      } else {
        cleaned.append(" ")
      }
    }
    return cleaned.split(whereSeparator: { $0 == " " }).joined(separator: " ")
  }
}
