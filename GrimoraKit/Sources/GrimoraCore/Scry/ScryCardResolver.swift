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

  /// Minimum name similarity a first-letter-repaired search batch must reach to
  /// be used at all. Without a floor, OCR garbage ("gold foil glare" lines) can
  /// conjure a plausible-looking batch of a completely unrelated card and put a
  /// wrong picker in front of the user — observed on device as a foil legend
  /// offering printings of an unrelated common.
  public var repairedNameSimilarityFloor: Double

  public init(
    database: CardDatabase,
    autoAcceptNameSimilarity: Double = 0.82,
    candidateLimit: Int = 6,
    repairedNameSimilarityFloor: Double = 0.72
  ) {
    self.database = database
    self.autoAcceptNameSimilarity = autoAcceptNameSimilarity
    self.candidateLimit = candidateLimit
    self.repairedNameSimilarityFloor = repairedNameSimilarityFloor
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

      if ScryStringSimilarity.multifaceNameSimilarity(keyed.name, name) >= autoAcceptNameSimilarity {
        return ScryResolution(
          card: keyed,
          candidates: [keyed],
          confidence: .auto,
          method: .exactKey,
          signals: signals
        )
      }

      // A name was read but it doesn't match the keyed printing. That happens two
      // ways and they're indistinguishable locally: a sharp borderless-promo scan
      // whose "name" is a decorative banner (the key is right), or a blurred scan
      // whose set+number itself mis-read into a *different* real card while the
      // garbled title matched nothing (the key is wrong). A large catalog makes
      // that wrong key land on a real card, so trusting it auto-accepts the wrong
      // printing (a blurred "224" → "226" gave a wrong Fallen Shinobi). We never
      // guess here: surface the keyed printing — plus any card the name really
      // does match — as a picker. (An empty/unreadable name is handled above,
      // where there is genuinely nothing to contradict the key.)
      let nameMatches = try nameCandidates(for: name)
      let conflicting = nameMatches.filter {
        $0.id != keyed.id && ScryStringSimilarity.multifaceNameSimilarity($0.name, name) >= autoAcceptNameSimilarity
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
      // Filter by number IN the query, not after: a basic land has 800+
      // printings and the right one won't sit inside a post-hoc search window.
      // Then corroborate the name — this tier's whole premise is a reliably-read
      // title, and the prefix search happily matches a garbage fragment: a real
      // scene read "AL" + collector 7 and auto-accepted Alibou, Ancient Witness
      // [c21 7], the only #7 among "AL…" names. An uncorroborated name never
      // auto-accepts and never fills a picker here; the scan falls through to
      // the tiers that treat the name honestly.
      func corroborated(_ cards: [CardRecord]) -> [CardRecord] {
        cards.filter {
          $0.collectorNumber == number
            && ScryStringSimilarity.multifaceNameSimilarity($0.name, name) >= autoAcceptNameSimilarity
        }
      }
      var matches = corroborated(try nameCandidates(for: name, collectorNumber: number))
      if matches.isEmpty {
        // The word-prefix name search can't survive mid-word OCR damage
        // ("Beamfown Beafstick" never prefix-matches "Beamtown Beatstick"), and
        // first-letter repair only fixes the first letter. Search the collector
        // number instead and let similarity do the matching: number + a
        // strongly-corroborating name is the same key this tier already trusts,
        // just found from the other end.
        matches = corroborated(try numberCandidates(for: number))
      }
      if matches.count == 1 {
        let chosen = matches[0]
        // A lone collector number is a trustworthy unique key only if no *other*
        // printing of the same card sits a single OCR error away. Under blur a
        // digit flips — a real soft-focus scan read Generous Gift's "106" as
        // "100" — and lands on a sibling printing, auto-accepting the wrong
        // version of the right card. When such a confusable sibling exists and no
        // set code corroborates the read, surface the printing picker (the
        // correct printing is among the candidates) instead of guessing.
        let setCodeCorroborates = signals.setCode.map {
          !$0.isEmpty && $0 == chosen.setCode.lowercased()
        } ?? false
        if !setCodeCorroborates {
          let namePrintings = try nameCandidates(for: name).filter {
            ScryStringSimilarity.multifaceNameSimilarity($0.name, name) >= autoAcceptNameSimilarity
          }
          if namePrintings.contains(where: {
            $0.id != chosen.id && Self.collectorNumbersOCRConfusable($0.collectorNumber, number)
          }) {
            return ScryResolution(
              card: nil,
              candidates: rankedForDisambiguation(
                namePrintings, setCode: signals.setCode, copyrightYear: signals.copyrightYear
              ),
              confidence: .ambiguous,
              method: .nameAndNumber,
              signals: signals
            )
          }
        }
        return ScryResolution(
          card: chosen,
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
        // Old frames print no set code but do print the set total ("8/249"), and
        // that total names the set as surely as a set code does — it was read from
        // the same token as the collector number, so if one is trustworthy both
        // are. A unique set-size match is an exact printing key (this is what
        // separates M13's "8/249" from Game Night's #8 of the same card).
        if let total = signals.setTotal {
          let sized = try matches.filter { try database.setSize(setCode: $0.setCode) == total }
          if sized.count == 1 {
            return ScryResolution(
              card: sized[0],
              candidates: matches,
              confidence: .auto,
              method: .nameAndNumber,
              signals: signals
            )
          }
        }
        return ScryResolution(
          card: nil,
          candidates: rankedForDisambiguation(matches, setCode: signals.setCode, copyrightYear: signals.copyrightYear),
          confidence: .ambiguous,
          method: .nameAndNumber,
          signals: signals
        )
      }
    }

    // Tier A″ — collector number + set total, no readable name (a clipped or
    // glared title). "114/249" alone names a set-size family: every set of 249
    // cards has exactly one #114. Without a name to corroborate, this NEVER
    // auto-accepts — a single digit misread would silently pick a sibling — but
    // the year-ranked picker it produces almost always has the right card on top.
    if signals.name?.isEmpty ?? true,
       let number = signals.collectorNumber, !number.isEmpty,
       let total = signals.setTotal {
      let response = try database.search(
        CardSearchRequest(
          text: "cn:" + number.filter { $0.isLetter || $0.isNumber },
          printingDisplayMode: .all,
          limit: max(candidateLimit * 10, 80)
        )
      )
      if case .results(let cards, _) = response {
        let sized = try cards.filter { try database.setSize(setCode: $0.setCode) == total }
        if !sized.isEmpty {
          return ScryResolution(
            card: nil,
            candidates: rankedForDisambiguation(sized, setCode: signals.setCode, copyrightYear: signals.copyrightYear),
            confidence: .ambiguous,
            method: .numberAndTotal,
            signals: signals
          )
        }
      }
    }

    // Tier B — name (printing-level).
    if let name = signals.name, !name.isEmpty {
      let candidates = try nameCandidates(for: name)
      let strong = candidates.filter {
        ScryStringSimilarity.multifaceNameSimilarity($0.name, name) >= autoAcceptNameSimilarity
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
          candidates: rankedForDisambiguation(candidates, setCode: signals.setCode, copyrightYear: signals.copyrightYear),
          confidence: .ambiguous,
          method: .nameOnly,
          signals: signals
        )
      }
    }

    return .none(signals: signals)
  }

  /// Orders picker candidates by the printed signals that can't settle the match
  /// outright: candidates from the OCR'd **set code**'s set come first (the set
  /// code is printed on the card, so an exact read is the strongest picker
  /// signal there is — a real Sram scan read `cmr` cleanly and still buried the
  /// CMR printings mid-list); behind those, printings whose release year matches
  /// the OCR'd copyright year; then printings released **by** that year (± a
  /// year of printing lag) beat later reprints — the vintage rule: a card whose
  /// copyright line ends in 1995 cannot be a 2021 reprint. Original order is
  /// preserved within each band.
  ///
  /// Neither signal is ever an auto-accept key on its own: OCR misreads year
  /// digits under blur (a real "2009" once read as "2000") and set codes
  /// routinely ("otj" → "ots", "cmm" → "imm"), and a misread that happens to
  /// name a sibling printing would auto-accept the wrong card. Ranking first
  /// costs nothing when the read is right and is harmless when it's wrong.
  func rankedForDisambiguation(
    _ cards: [CardRecord],
    setCode: String? = nil,
    copyrightYear: Int?
  ) -> [CardRecord] {
    let setCode = setCode?.lowercased()
    guard setCode != nil || copyrightYear != nil else { return cards }
    let yearPrefix = copyrightYear.map(String.init)

    func releasedYear(_ card: CardRecord) -> Int? {
      card.releasedAt.flatMap { Int($0.prefix(4)) }
    }

    return cards.enumerated().sorted { lhs, rhs in
      if let setCode {
        let lhsSet = lhs.element.setCode.lowercased() == setCode
        let rhsSet = rhs.element.setCode.lowercased() == setCode
        if lhsSet != rhsSet { return lhsSet }
      }
      if let yearPrefix, let copyrightYear {
        let lhsMatches = lhs.element.releasedAt?.hasPrefix(yearPrefix) ?? false
        let rhsMatches = rhs.element.releasedAt?.hasPrefix(yearPrefix) ?? false
        if lhsMatches != rhsMatches { return lhsMatches }
        let lhsInEra = releasedYear(lhs.element).map { $0 <= copyrightYear + 1 } ?? false
        let rhsInEra = releasedYear(rhs.element).map { $0 <= copyrightYear + 1 } ?? false
        if lhsInEra != rhsInEra { return lhsInEra }
      }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }

  /// Whether two printed collector numbers are within a single OCR error of one
  /// another — the regime where a blurred digit could have turned one into the
  /// other (a real soft-focus scan read Generous Gift's "106" as "100", the
  /// number of a *different* printing of the same card).
  ///
  /// Restricted to an **equal-length single substitution of three or more
  /// characters**, compared over the sanitized alphanumeric cores. That is the
  /// only shape a blurred digit realistically takes: a one- or two-character
  /// number sits a single edit from dozens of others (nearly every card is #6 or
  /// #88 in *some* set), so treating those as confusable would demote correct
  /// low-number auto-accepts wholesale; and a length change (an inserted digit,
  /// or a "267" vs "267p" promo suffix) is a segmentation or variant difference,
  /// not a blurred digit. Identical (or empty) numbers are not siblings.
  static func collectorNumbersOCRConfusable(_ lhs: String, _ rhs: String) -> Bool {
    func core(_ value: String) -> [Character] {
      Array(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }
    let a = core(lhs), b = core(rhs)
    guard a.count == b.count, a.count >= 3, a != b else { return false }
    // Equal length + edit distance 1 is exactly one substituted character.
    return ScryStringSimilarity.levenshtein(a, b) == 1
  }

  /// Database printings whose name matches the OCR'd name, ranked by similarity.
  ///
  /// The word-prefix search can't survive a damaged *first* letter — stylized
  /// retro and showcase capitals OCR wrong ("Ajani's Pridemate" → "Hjani's
  /// Dridemate"), and no prefix of a damaged word matches the true word. So when
  /// the raw query comes back empty, retry the longest word with every possible
  /// first letter ("?ridemate" → "Pridemate"): at most 25 cheap indexed
  /// searches, only on the already-failed path. Precision is unaffected: every
  /// caller still gates on name similarity against the OCR'd text before
  /// trusting a candidate.
  ///
  /// `collectorNumber`, when known, is compiled into the query so the right
  /// printing of a many-printing name (a basic land) can't fall outside the
  /// search window.
  /// Every printing with this collector number, for the fuzzy fallback when the
  /// word-prefix name search can't survive mid-word OCR damage. Wide limit: a
  /// low number appears once in nearly every set, and the caller's similarity
  /// filter is what narrows it.
  func numberCandidates(for number: String) throws -> [CardRecord] {
    let sanitized = number.filter { $0.isLetter || $0.isNumber }
    guard !sanitized.isEmpty else { return [] }
    let response = try database.search(
      CardSearchRequest(text: "cn:" + sanitized, printingDisplayMode: .all, limit: 800)
    )
    guard case .results(let cards, _) = response else { return [] }
    return cards
  }

  func nameCandidates(for rawName: String, collectorNumber: String? = nil) throws -> [CardRecord] {
    let query = Self.sanitizeNameQuery(rawName)
    guard !query.isEmpty else { return [] }

    let numberFilter = collectorNumber.map { number in
      " cn:" + number.filter { $0.isLetter || $0.isNumber }
    } ?? ""

    if let cards = try searchCandidates(query: query + numberFilter, rawName: rawName), !cards.isEmpty {
      return cards
    }

    guard let longest = query.split(separator: " ").max(by: { $0.count < $1.count }),
          longest.count >= 5 else { return [] }
    let stem = String(longest.dropFirst())
    var bestBatch: [CardRecord] = []
    var bestScore = 0.0
    // The longest word as-is first (maybe a *shorter* word was the damaged one),
    // then every alternate first letter.
    let attempts = [String(longest)] + "abcdefghijklmnopqrstuvwxyz".compactMap { letter in
      String(letter) == String(longest.first!).lowercased() ? nil : String(letter) + stem
    }
    for repaired in attempts {
      guard let cards = try searchCandidates(query: repaired + numberFilter, rawName: rawName),
            let top = cards.first else { continue }
      // `searchCandidates` sorts by similarity, so the first card scores the batch.
      let score = ScryStringSimilarity.multifaceNameSimilarity(top.name, rawName)
      if score > bestScore {
        bestScore = score
        bestBatch = cards
      }
      if score >= autoAcceptNameSimilarity {
        break  // unambiguously the intended name — no need to try further letters
      }
    }
    // A repaired batch that doesn't strongly resemble what was read is noise,
    // not a repair — better no candidates than a confidently-wrong picker.
    guard bestScore >= repairedNameSimilarityFloor else { return [] }
    return bestBatch
  }

  private func searchCandidates(query: String, rawName: String) throws -> [CardRecord]? {
    let response = try database.search(
      CardSearchRequest(text: query, printingDisplayMode: .all, limit: max(candidateLimit * 10, 80))
    )
    guard case .results(let cards, _) = response else { return nil }

    return cards.sorted { lhs, rhs in
      let lhsScore = ScryStringSimilarity.multifaceNameSimilarity(lhs.name, rawName)
      let rhsScore = ScryStringSimilarity.multifaceNameSimilarity(rhs.name, rawName)
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
