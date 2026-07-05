@testable import GrimoraCore
import XCTest

final class ScryRecognitionTests: XCTestCase {
  // MARK: - String similarity

  func testNameSimilarityIdenticalIsOne() {
    XCTAssertEqual(ScryStringSimilarity.nameSimilarity("Lightning Bolt", "Lightning Bolt"), 1, accuracy: 0.0001)
  }

  func testNameSimilarityIgnoresCaseAndDiacritics() {
    XCTAssertEqual(ScryStringSimilarity.nameSimilarity("Juzám Djinn", "juzam djinn"), 1, accuracy: 0.0001)
  }

  func testNameSimilarityToleratesOneOCRSlip() {
    // "Llanowar EIves" (capital-i misread for l) should still score high.
    XCTAssertGreaterThan(ScryStringSimilarity.nameSimilarity("Llanowar Elves", "Llanowar EIves"), 0.85)
  }

  func testNameSimilarityDistinctNamesScoreLow() {
    XCTAssertLessThan(ScryStringSimilarity.nameSimilarity("Alpha Forest", "Beta Mage"), 0.5)
  }

  // MARK: - Collector / set line parsing

  func testParsesModernCollectorAndSetLine() {
    let parsed = ScryCollectorLineParser.parse(lines: ["0123/350 R", "NEO • EN"])
    XCTAssertEqual(parsed.setCode, "neo")
    XCTAssertEqual(parsed.collectorNumber, "123")
  }

  func testParsesCollectorNumberWithLetterSuffix() {
    let parsed = ScryCollectorLineParser.parse(lines: ["R 123a", "WAR • JA"])
    XCTAssertEqual(parsed.setCode, "war")
    XCTAssertEqual(parsed.collectorNumber, "123a")
  }

  func testParsesZeroPaddedRarityPrefixedLine() {
    // The real modern printed form: rarity letter + zero-padded number, then SET • LANG.
    let parsed = ScryCollectorLineParser.parse(lines: ["L 0256", "OTJ • EN  Piotr Dura"])
    XCTAssertEqual(parsed.setCode, "otj")
    XCTAssertEqual(parsed.collectorNumber, "256")
  }

  func testParsesFoilStarLine() {
    // Foils print a star between set code and language, plus an artist-brush glyph.
    let parsed = ScryCollectorLineParser.parse(lines: ["U 0263", "OTJ ★ EN  Jorge Jacinto"])
    XCTAssertEqual(parsed.setCode, "otj")
    XCTAssertEqual(parsed.collectorNumber, "263")
  }

  func testDoesNotMistakeArtistOrCopyrightForSetCode() {
    // No language code on these lines → no set code, by design (precision over recall).
    let parsed = ScryCollectorLineParser.parse(lines: [
      "Piotr Dura", "TM & © 2024 Wizards of the Coast"
    ])
    XCTAssertNil(parsed.setCode)
    XCTAssertNil(parsed.collectorNumber)
  }

  func testStripsLeadingZerosFromCollectorNumber() {
    let parsed = ScryCollectorLineParser.parse(lines: ["0007/350", "DOM • EN"])
    XCTAssertEqual(parsed.setCode, "dom")
    XCTAssertEqual(parsed.collectorNumber, "7")
  }

  func testPrefersSetCodeBeforeLanguageOverTrailingArtist() {
    // Artist tokens follow the language code and must not win over the set code.
    let parsed = ScryCollectorLineParser.parse(lines: ["NEO • EN John Avon"])
    XCTAssertEqual(parsed.setCode, "neo")
    XCTAssertNil(parsed.collectorNumber)
  }

  func testHandlesAlphanumericSetCode() {
    let parsed = ScryCollectorLineParser.parse(lines: ["42/180 C", "40K • EN"])
    XCTAssertEqual(parsed.setCode, "40k")
    XCTAssertEqual(parsed.collectorNumber, "42")
  }

  func testBareNumberWithoutCollectorContextIsNotTrusted() {
    // A lone number could be a set total, a year, anything — don't guess.
    let parsed = ScryCollectorLineParser.parse(lines: ["350"])
    XCTAssertNil(parsed.setCode)
    XCTAssertNil(parsed.collectorNumber)
  }

  func testZeroPowerToughnessIsNotReadAsCollectorNumber() {
    // A 0-power creature (e.g. a Wall) prints "0/4" power/toughness, which the OCR
    // surfaces above the real collector line. It must not be read as "0".
    let alone = ScryCollectorLineParser.parse(lines: ["0/4", "Creature — Wall"])
    XCTAssertNil(alone.collectorNumber)

    // The genuine zero-padded collector number must still win over the "0/4" toughness
    // that precedes it (the toughness line sorts above the collector line).
    let withCollector = ScryCollectorLineParser.parse(lines: ["0/4", "0256", "OTJ • EN"])
    XCTAssertEqual(withCollector.collectorNumber, "256")
    XCTAssertEqual(withCollector.setCode, "otj")
  }

  // MARK: - Old-frame copyright line (year + set total)

  func testParsesOldFrameCopyrightLineNumberTotalAndYear() {
    // The real M10 form: collector info is a fragment at the end of the copyright
    // line — no set code exists anywhere on the card.
    let parsed = ScryCollectorLineParser.parse(lines: [
      "Greg Staples", "TM & © 1993-2009 Wizards of the Coast LLC 6/249"
    ])
    XCTAssertNil(parsed.setCode)
    XCTAssertEqual(parsed.collectorNumber, "6")
    XCTAssertEqual(parsed.setTotal, 249)
    XCTAssertEqual(parsed.copyrightYear, 2009)
  }

  func testParsesRetroFrameCollectorNumberFromCopyrightLine() {
    // Retro (1997) frame reprints — e.g. Innistrad Remastered's old-border Edgar
    // Markov — print the collector number as a bare integer after the studio name:
    // "™ & © 2025 Wizards of the Coast 428". No slash, no set code, no zero pad.
    let parsed = ScryCollectorLineParser.parse(lines: [
      "Illus. Volkan Baga", "TM & © 2025 Wizards of the Coast 428"
    ])
    XCTAssertEqual(parsed.collectorNumber, "428")
    XCTAssertEqual(parsed.copyrightYear, 2025)
    XCTAssertNil(parsed.setTotal)  // no slash fragment
    XCTAssertNil(parsed.setCode)   // the retro frame prints none
  }

  func testLeadingCopyrightYearIsNotReadAsRetroCollectorNumber() {
    // The year precedes the "Wizards"/"Coast" marker; with no real number after
    // the marker, nothing may be read as a collector number.
    let parsed = ScryCollectorLineParser.parse(lines: ["TM & © 2024 Wizards of the Coast"])
    XCTAssertNil(parsed.collectorNumber)
    XCTAssertEqual(parsed.copyrightYear, 2024)
  }

  func testCopyrightYearTakesLaterYearOfSpan() {
    let parsed = ScryCollectorLineParser.parse(lines: ["™ & © 1993-2012 Wizards of the Coast LLC"])
    XCTAssertEqual(parsed.copyrightYear, 2012)
  }

  func testModernCopyrightLineYieldsSingleYear() {
    let parsed = ScryCollectorLineParser.parse(lines: ["TM & © 2024 Wizards of the Coast"])
    XCTAssertEqual(parsed.copyrightYear, 2024)
  }

  func testYearWithoutCopyrightMarkerIsIgnored() {
    // A bare year (flavor text, dates in card names like "1996 World Champion")
    // must not be read as the copyright year.
    let parsed = ScryCollectorLineParser.parse(lines: ["Chronicle of the year 2005", "Piotr Dura"])
    XCTAssertNil(parsed.copyrightYear)
  }

  func testImplausibleYearOnCopyrightLineIsIgnored() {
    let parsed = ScryCollectorLineParser.parse(lines: ["© 1899 Wizards of the Coast"])
    XCTAssertNil(parsed.copyrightYear)
  }

  func testModernSlashFormStillCarriesSetTotal() {
    let parsed = ScryCollectorLineParser.parse(lines: ["0123/350 R", "NEO • EN"])
    XCTAssertEqual(parsed.setTotal, 350)
    XCTAssertEqual(parsed.collectorNumber, "123")
  }

  func testPowerToughnessNeverBecomesSetTotal() {
    let parsed = ScryCollectorLineParser.parse(lines: ["3/3", "Creature — Human Soldier"])
    XCTAssertNil(parsed.setTotal)
    XCTAssertNil(parsed.collectorNumber)
  }

  // MARK: - Name heuristics (don't read the type line as the name)

  func testTypeLinesAreNotAcceptedAsNames() {
    XCTAssertTrue(ScryNameHeuristics.looksLikeTypeLine("Land"))
    XCTAssertTrue(ScryNameHeuristics.looksLikeTypeLine("Land — Desert"))
    XCTAssertTrue(ScryNameHeuristics.looksLikeTypeLine("Creature — Goblin Sorcerer"))
    XCTAssertTrue(ScryNameHeuristics.looksLikeTypeLine("Artifact"))
    XCTAssertFalse(ScryNameHeuristics.isAcceptableName("Land"))

    // Real names — including a basic land's NAME (not its type) — stay acceptable.
    XCTAssertFalse(ScryNameHeuristics.looksLikeTypeLine("Izzet Boilerworks"))
    XCTAssertTrue(ScryNameHeuristics.isAcceptableName("Izzet Boilerworks"))
    XCTAssertTrue(ScryNameHeuristics.isAcceptableName("Llanowar Elves"))
    XCTAssertFalse(ScryNameHeuristics.looksLikeTypeLine("Mountain"))
  }

  // MARK: - Resolver: exact key (Tier A)

  func testExactKeyWithMatchingNameAutoAccepts() throws {
    let resolver = ScryCardResolver(database: try Fixtures.database())
    let signals = ScrySignals(name: "Alpha Forest", setCode: "abc", collectorNumber: "2")

    let resolution = try resolver.resolve(signals)

    XCTAssertEqual(resolution.confidence, .auto)
    XCTAssertEqual(resolution.method, .exactKey)
    XCTAssertEqual(resolution.card?.id, "alpha")
  }

  func testExactKeyWithoutNameStillAutoAcceptsOnUniqueKey() throws {
    let resolver = ScryCardResolver(database: try Fixtures.database())
    let signals = ScrySignals(setCode: "abc", collectorNumber: "10")

    let resolution = try resolver.resolve(signals)

    XCTAssertEqual(resolution.confidence, .auto)
    XCTAssertEqual(resolution.card?.id, "beta")
  }

  func testExactKeyWithMismatchedNameIsAmbiguous() throws {
    // The key points at Alpha Forest, but OCR read the name as Beta Mage.
    // Precision rule: do not silently accept — surface both for the picker.
    let resolver = ScryCardResolver(database: try Fixtures.database())
    let signals = ScrySignals(name: "Beta Mage", setCode: "abc", collectorNumber: "2")

    let resolution = try resolver.resolve(signals)

    XCTAssertEqual(resolution.confidence, .ambiguous)
    XCTAssertNil(resolution.card)
    XCTAssertTrue(resolution.candidates.contains { $0.id == "alpha" })
  }

  // MARK: - Resolver: name (Tier B)

  func testNameOnlySinglePrintingAutoAccepts() throws {
    let resolver = ScryCardResolver(database: try Fixtures.database())
    let signals = ScrySignals(name: "Beta Mage")

    let resolution = try resolver.resolve(signals)

    XCTAssertEqual(resolution.confidence, .auto)
    XCTAssertEqual(resolution.method, .nameOnly)
    XCTAssertEqual(resolution.card?.id, "beta")
  }

  func testNameWithMultiplePrintingsIsAmbiguous() throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(twinPrintings())
    let resolver = ScryCardResolver(database: database)

    let resolution = try resolver.resolve(ScrySignals(name: "Twin Card"))

    XCTAssertEqual(resolution.confidence, .ambiguous)
    XCTAssertNil(resolution.card)
    XCTAssertEqual(Set(resolution.candidates.map(\.id)), ["twin-1", "twin-2"])
  }

  // MARK: - Multi-face names (split / flip / adventure)

  func testFaceNameSimilarityMatchesEitherFace() {
    XCTAssertEqual(ScryStringSimilarity.multifaceNameSimilarity("Fire // Ice", "Fire"), 1, accuracy: 0.0001)
    XCTAssertEqual(ScryStringSimilarity.multifaceNameSimilarity("Fire // Ice", "Ice"), 1, accuracy: 0.0001)
    XCTAssertEqual(
      ScryStringSimilarity.multifaceNameSimilarity(
        "Bushi Tenderfoot // Kenzo the Hardhearted", "Kenzo the Hardhearted"
      ), 1, accuracy: 0.0001
    )
    // Whole-name reads still count.
    XCTAssertGreaterThan(ScryStringSimilarity.multifaceNameSimilarity("Fire // Ice", "Fire // Ice"), 0.99)
    // A face match is not a free pass for unrelated text.
    XCTAssertLessThan(ScryStringSimilarity.multifaceNameSimilarity("Fire // Ice", "Firebrand Archer"), 0.6)
  }

  // MARK: - Foreign-language guard

  func testForeignNameOnlyScanNeverAutoAccepts() throws {
    // A Japanese title OCR'd against an English database matches nothing — the
    // resolver must return none/ambiguous, never a confident wrong card. (The
    // exact-key tier handles foreign cards; the name tier must just stay safe.)
    let resolver = ScryCardResolver(database: try Fixtures.database())
    let resolution = try resolver.resolve(ScrySignals(name: "祖先の刀"))
    XCTAssertNotEqual(resolution.confidence, .auto)
    XCTAssertNil(resolution.card)
  }

  // MARK: - First-letter-repair search precision

  func testRepairedSearchRejectsLowSimilarityBatches() throws {
    // "Xiller" repairs to "filler" and finds the Filler cards — but at ~0.5
    // similarity that batch is noise, and surfacing it would put a wrong picker
    // in front of the user (the on-device Bria → "Lurking Lizards" failure).
    let resolver = ScryCardResolver(database: try collisionDatabase())
    let resolution = try resolver.resolve(ScrySignals(name: "Xiller"))
    XCTAssertEqual(resolution.confidence, .none, "junk repairs must yield nothing, not a wrong picker")
  }

  func testRepairRecoversWhenAShorterWordWasDamaged() throws {
    // "Xld Filler": the long word is intact, the short one is mangled — the
    // longest-word-alone attempt recovers it, and the 0.9 similarity clears
    // both the floor and the auto gate.
    let resolver = ScryCardResolver(database: try collisionDatabase())
    let resolution = try resolver.resolve(ScrySignals(name: "Xld Filler"))
    XCTAssertEqual(resolution.confidence, .auto)
    XCTAssertEqual(resolution.card?.name, "Old Filler")
  }

  // MARK: - Vintage era ranking

  func testEraRankingPrefersPlausiblePrintingsWithoutExactYear() throws {
    let template = Fixtures.records()[0]
    func printing(_ id: String, releasedAt: String) -> CardRecord {
      var card = template
      card.id = id
      card.releasedAt = releasedAt
      return card
    }
    let vintage = printing("vintage", releasedAt: "1994-06-01")
    let middle = printing("middle", releasedAt: "2010-07-01")
    let recent = printing("recent", releasedAt: "2021-03-01")
    let resolver = ScryCardResolver(database: try Fixtures.database())

    // Copyright year 1995, no exact-year printing: the era-plausible 1994
    // printing outranks reprints that didn't exist yet.
    let ranked = resolver.rankedForDisambiguation([recent, middle, vintage], copyrightYear: 1995)
    XCTAssertEqual(ranked.map(\.id), ["vintage", "recent", "middle"])
  }

  func testSetCodeRankingPutsReadSetFirstInPicker() throws {
    // A cleanly OCR'd set code is the strongest picker signal there is (it's
    // printed on the card), but it is NEVER an auto key — misreads like
    // "otj"→"ots" could name a sibling set. A real Sram scan read `cmr` and
    // still buried the CMR printings mid-list; this pins them to the top.
    let template = Fixtures.records()[0]
    func printing(_ id: String, setCode: String, releasedAt: String) -> CardRecord {
      var card = template
      card.id = id
      card.setCode = setCode
      card.releasedAt = releasedAt
      return card
    }
    let aer = printing("aer", setCode: "aer", releasedAt: "2017-01-20")
    let cmr = printing("cmr", setCode: "cmr", releasedAt: "2020-11-20")
    let tsr = printing("tsr", setCode: "tsr", releasedAt: "2021-03-19")
    let resolver = ScryCardResolver(database: try Fixtures.database())

    let ranked = resolver.rankedForDisambiguation([aer, tsr, cmr], setCode: "cmr", copyrightYear: nil)
    XCTAssertEqual(ranked.map(\.id), ["cmr", "aer", "tsr"])

    // The set match outranks a copyright-year match on a different printing.
    let both = resolver.rankedForDisambiguation([aer, tsr, cmr], setCode: "cmr", copyrightYear: 2021)
    XCTAssertEqual(both.first?.id, "cmr")

    // An unreadable or misread set code that names no candidate changes nothing.
    let unchanged = resolver.rankedForDisambiguation([aer, tsr, cmr], setCode: "imm", copyrightYear: nil)
    XCTAssertEqual(unchanged.map(\.id), ["aer", "tsr", "cmr"])
  }

  // MARK: - Resolver: number + total with no name (clipped title)

  func testNumberAndTotalWithoutNameYieldsRankedPicker() throws {
    // A clipped/glared title leaves only the "8/249" fragment — enough to name
    // the set-size family. Must be a picker (no name to corroborate ⇒ never
    // auto), with the copyright year putting the right printing first.
    let resolver = ScryCardResolver(database: try collisionDatabase())

    let resolution = try resolver.resolve(
      ScrySignals(collectorNumber: "8", setTotal: 249, copyrightYear: 2012)
    )

    XCTAssertEqual(resolution.confidence, .ambiguous)
    XCTAssertEqual(resolution.method, .numberAndTotal)
    XCTAssertNil(resolution.card)
    XCTAssertEqual(resolution.candidates.first?.setCode, "oldx")
  }

  func testNumberAndTotalMatchingNoSetYieldsNone() throws {
    let resolver = ScryCardResolver(database: try collisionDatabase())
    let resolution = try resolver.resolve(ScrySignals(collectorNumber: "8", setTotal: 300))
    XCTAssertEqual(resolution.confidence, .none)
  }

  // MARK: - Name heuristics: rules-text fragments

  func testRulesTextFragmentsAreNotNames() {
    // Real clipped-crop failure: the title was cut off and "creature." (with
    // OCR punctuation) or the aura's "Enchant creature" line became the name.
    XCTAssertFalse(ScryNameHeuristics.isAcceptableName("creature."))
    XCTAssertFalse(ScryNameHeuristics.isAcceptableName("Enchant creature"))
    XCTAssertFalse(ScryNameHeuristics.isAcceptableName("Enchant land"))
    // Equipment's keyword cost line, same trap (a real Beamtown Beatstick
    // capture read "Equip 2 (2: Attach to target creature you" as the name).
    XCTAssertFalse(ScryNameHeuristics.isAcceptableName("Equip 2 (2: Attach to target creature you"))
    XCTAssertFalse(ScryNameHeuristics.isAcceptableName("Equip {2}"))
    // Names that merely contain these words stay acceptable.
    XCTAssertTrue(ScryNameHeuristics.isAcceptableName("Enchanted Evening"))
    XCTAssertTrue(ScryNameHeuristics.isAcceptableName("Creature Guy"))
    XCTAssertTrue(ScryNameHeuristics.isAcceptableName("Equipoise"))
  }

  // MARK: - Resolver: old-frame signals (set total + copyright year)

  func testNameAndNumberCollisionResolvedBySetTotal() throws {
    // Two printings share name AND collector number (the real M13 #8 vs GN3 #8
    // case). The old frame prints "8/249"; a unique set-size match on the total
    // is as good as a printed set code.
    let database = try collisionDatabase()
    let resolver = ScryCardResolver(database: database)

    let resolution = try resolver.resolve(
      ScrySignals(name: "Twin Card", collectorNumber: "8", setTotal: 249)
    )

    XCTAssertEqual(resolution.confidence, .auto)
    XCTAssertEqual(resolution.method, .nameAndNumber)
    XCTAssertEqual(resolution.card?.setCode, "oldx")
  }

  func testMisreadSetTotalNeverAutoAccepts() throws {
    // A total matching no candidate's set size must fall back to the picker.
    let database = try collisionDatabase()
    let resolver = ScryCardResolver(database: database)

    let resolution = try resolver.resolve(
      ScrySignals(name: "Twin Card", collectorNumber: "8", setTotal: 300)
    )

    XCTAssertEqual(resolution.confidence, .ambiguous)
    XCTAssertNil(resolution.card)
  }

  func testNumberCollisionCandidatesRankedByCopyrightYear() throws {
    // Year is a ranking signal only — a misread year digit could hit a sibling
    // printing's year, so it must never auto-accept. But when present it should
    // put the matching printing first in the picker.
    let database = try collisionDatabase()
    let resolver = ScryCardResolver(database: database)

    let resolution = try resolver.resolve(
      ScrySignals(name: "Twin Card", collectorNumber: "8", copyrightYear: 2022)
    )

    XCTAssertEqual(resolution.confidence, .ambiguous)
    XCTAssertEqual(resolution.candidates.first?.setCode, "newx")
  }

  func testNameOnlyCandidatesRankedByCopyrightYear() throws {
    let database = try collisionDatabase()
    let resolver = ScryCardResolver(database: database)

    let resolution = try resolver.resolve(
      ScrySignals(name: "Twin Card", copyrightYear: 2012)
    )

    XCTAssertEqual(resolution.confidence, .ambiguous)
    XCTAssertEqual(resolution.candidates.first?.setCode, "oldx")
  }

  func testSetSizeIsLargestCollectorNumberInSet() throws {
    let database = try collisionDatabase()
    XCTAssertEqual(try database.setSize(setCode: "oldx"), 249)
    XCTAssertEqual(try database.setSize(setCode: "newx"), 134)
    XCTAssertNil(try database.setSize(setCode: "nope"))
  }

  // MARK: - Resolver: precision guards

  func testEmptySignalsResolveToNone() throws {
    let resolver = ScryCardResolver(database: try Fixtures.database())
    let resolution = try resolver.resolve(ScrySignals())
    XCTAssertEqual(resolution.confidence, .none)
    XCTAssertNil(resolution.card)
  }

  func testUnknownKeyAndUnknownNameNeverAutoAccept() throws {
    let resolver = ScryCardResolver(database: try Fixtures.database())
    let signals = ScrySignals(name: "Totally Unknown Card", setCode: "zzz", collectorNumber: "999")

    let resolution = try resolver.resolve(signals)

    XCTAssertEqual(resolution.confidence, .none)
    XCTAssertNil(resolution.card)
  }

  func testMidWordOCRSlipsResolveViaNumberSearch() throws {
    // Real capture: "Beamfown Beafstick" (two t→f slips) + collector 131. The
    // word-prefix search can't match a mid-word slip and first-letter repair
    // only fixes the first letter — but the collector number finds the card
    // from the other end, and 0.89 name similarity corroborates it.
    let template = Fixtures.records()[0]
    func printing(_ id: String, name: String, setCode: String, number: Int) -> CardRecord {
      var card = template
      card.id = id
      card.oracleID = "\(name)-oracle"
      card.name = name
      card.displayNameKey = name.normalizedQueryKey
      card.setCode = setCode
      card.collectorNumber = String(number)
      card.collectorNumberNumber = number
      return card
    }
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([
      printing("beatstick", name: "Beamtown Beatstick", setCode: "mom", number: 131),
      printing("decoy-same-number", name: "Completely Different", setCode: "xyz", number: 131),
      printing("decoy-other-number", name: "Beamtown Bully", setCode: "mom", number: 130),
    ])
    let resolver = ScryCardResolver(database: database)

    let resolution = try resolver.resolve(
      ScrySignals(name: "Beamfown Beafstick", collectorNumber: "131")
    )

    XCTAssertEqual(resolution.confidence, .auto)
    XCTAssertEqual(resolution.method, .nameAndNumber)
    XCTAssertEqual(resolution.card?.id, "beatstick")
  }

  func testNameFragmentPlusNumberNeverAutoAccepts() throws {
    // Real precision failure: a clipped title read "AL" plus collector 7, and
    // the prefix search found exactly one #7 among "AL…" names — Alibou,
    // Ancient Witness — which Tier A′ auto-accepted without ever checking that
    // "AL" actually resembles "Alibou, Ancient Witness". A name that doesn't
    // corroborate its match must never auto-accept, no matter how unique the
    // number filter makes it.
    let template = Fixtures.records()[0]
    var alibou = template
    alibou.id = "alibou-c21"
    alibou.oracleID = "alibou-oracle"
    alibou.name = "Alibou, Ancient Witness"
    alibou.displayNameKey = "Alibou, Ancient Witness".normalizedQueryKey
    alibou.setCode = "c21"
    alibou.collectorNumber = "7"
    alibou.collectorNumberNumber = 7

    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([alibou])
    let resolver = ScryCardResolver(database: database)

    let resolution = try resolver.resolve(ScrySignals(name: "AL", collectorNumber: "7"))

    XCTAssertNotEqual(resolution.confidence, .auto)
    XCTAssertNil(resolution.card)
  }

  // MARK: - Resolver: blur-confusable sibling guard

  func testNameAndNumberWithBlurConfusableSiblingDisambiguates() throws {
    // Soft-focus regression: a real scan of Generous Gift [blc 106] blurred the
    // "6" into "0", so name + collector "100" uniquely keyed the *dmc* #100
    // printing and auto-accepted the wrong version of the right card. With a
    // same-length single-digit sibling (#106) one OCR error away and no set code,
    // the lone number is not a trustworthy key — surface the picker, with the
    // real printing present, rather than guessing.
    let database = try siblingPrintings([("blc", 106), ("dmc", 100)])
    let resolver = ScryCardResolver(database: database)

    let resolution = try resolver.resolve(ScrySignals(name: "Gift Card", collectorNumber: "100"))

    XCTAssertEqual(resolution.confidence, .ambiguous)
    XCTAssertNil(resolution.card)
    XCTAssertTrue(resolution.candidates.contains { $0.setCode == "blc" && $0.collectorNumber == "106" })
    XCTAssertTrue(resolution.candidates.contains { $0.setCode == "dmc" && $0.collectorNumber == "100" })
  }

  func testNameAndNumberWithNoConfusableSiblingStillAutoAccepts() throws {
    // Recall guard: the lone-number path must keep auto-accepting when no sibling
    // printing sits an OCR error away — #100 vs #250 differ by two digits.
    let database = try siblingPrintings([("dmc", 100), ("blc", 250)])
    let resolver = ScryCardResolver(database: database)

    let resolution = try resolver.resolve(ScrySignals(name: "Gift Card", collectorNumber: "100"))

    XCTAssertEqual(resolution.confidence, .auto)
    XCTAssertEqual(resolution.method, .nameAndNumber)
    XCTAssertEqual(resolution.card?.setCode, "dmc")
  }

  func testNameAndNumberShortNumberSiblingsStillAutoAccept() throws {
    // Recall guard: a one- or two-digit number sits a single edit from dozens of
    // others (nearly every card is #6 in some set), so short-number siblings must
    // not trip the guard — #6 vs #3 stays a clean auto-accept.
    let database = try siblingPrintings([("m10", 6), ("cmr", 3)])
    let resolver = ScryCardResolver(database: database)

    let resolution = try resolver.resolve(ScrySignals(name: "Gift Card", collectorNumber: "6"))

    XCTAssertEqual(resolution.confidence, .auto)
    XCTAssertEqual(resolution.card?.setCode, "m10")
  }

  func testCollectorNumbersOCRConfusableTruthTable() {
    // Real blur: an equal-length single substitution of three or more characters.
    XCTAssertTrue(ScryCardResolver.collectorNumbersOCRConfusable("106", "100"))
    XCTAssertTrue(ScryCardResolver.collectorNumbersOCRConfusable("123a", "123b"))
    // Short numbers are one edit from too much to mean anything.
    XCTAssertFalse(ScryCardResolver.collectorNumbersOCRConfusable("6", "3"))
    XCTAssertFalse(ScryCardResolver.collectorNumbersOCRConfusable("88", "83"))
    // A length change is a segmentation or suffix difference, not a blurred digit.
    XCTAssertFalse(ScryCardResolver.collectorNumbersOCRConfusable("267", "267p"))
    XCTAssertFalse(ScryCardResolver.collectorNumbersOCRConfusable("100", "1000"))
    // Two substitutions is not a single OCR slip; identical numbers aren't siblings.
    XCTAssertFalse(ScryCardResolver.collectorNumbersOCRConfusable("267", "244"))
    XCTAssertFalse(ScryCardResolver.collectorNumbersOCRConfusable("100", "100"))
  }

  // MARK: - Disambiguator seam

  func testUnavailableDisambiguatorDeclines() async throws {
    let disambiguator = UnavailableScryDisambiguator()
    XCTAssertFalse(disambiguator.isAvailable)
    let result = try await disambiguator.disambiguate(
      ScryDisambiguationRequest(signals: ScrySignals(name: "Twin Card"), candidates: twinPrintings())
    )
    XCTAssertNil(result.chosenCardID)
  }

  func testScriptedDisambiguatorPicksOfferedCandidate() async throws {
    let disambiguator = ScriptedScryDisambiguator(script: "Twin Card\ttwin-2")
    let result = try await disambiguator.disambiguate(
      ScryDisambiguationRequest(signals: ScrySignals(name: "Twin Card"), candidates: twinPrintings())
    )
    XCTAssertEqual(result.chosenCardID, "twin-2")
  }

  func testScriptedDisambiguatorIgnoresUnofferedCandidate() async throws {
    let disambiguator = ScriptedScryDisambiguator(script: "Twin Card\tnot-a-candidate")
    let result = try await disambiguator.disambiguate(
      ScryDisambiguationRequest(signals: ScrySignals(name: "Twin Card"), candidates: twinPrintings())
    )
    XCTAssertNil(result.chosenCardID)
  }

  // MARK: - Helpers

  /// A database with the "same name, same collector number, different set" shape
  /// of the real M13 #8 / GN3 #8 collision: `oldx` is a 249-card 2012 set, `newx`
  /// a 134-card 2022 set, and "Twin Card" is #8 in both. Filler cards give each
  /// set its size.
  private func collisionDatabase() throws -> CardDatabase {
    let template = Fixtures.records()[0]

    func printing(
      id: String, name: String, setCode: String,
      number: Int, releasedAt: String
    ) -> CardRecord {
      var card = template
      card.id = id
      card.oracleID = "\(name)-oracle"
      card.name = name
      card.displayNameKey = name.normalizedQueryKey
      card.setCode = setCode
      card.collectorNumber = String(number)
      card.collectorNumberNumber = number
      card.releasedAt = releasedAt
      return card
    }

    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([
      printing(id: "twin-old", name: "Twin Card", setCode: "oldx", number: 8, releasedAt: "2012-07-13"),
      printing(id: "twin-new", name: "Twin Card", setCode: "newx", number: 8, releasedAt: "2022-10-14"),
      printing(id: "filler-old", name: "Old Filler", setCode: "oldx", number: 249, releasedAt: "2012-07-13"),
      printing(id: "filler-new", name: "New Filler", setCode: "newx", number: 134, releasedAt: "2022-10-14")
    ])
    return database
  }

  /// Printings of one card ("Gift Card"), one per `(setCode, number)` pair, built
  /// off a fixture record so the full initializer isn't spelled out. Used to
  /// probe the blur-confusable collector-number guard.
  private func siblingPrintings(_ printings: [(set: String, number: Int)]) throws -> CardDatabase {
    let template = Fixtures.records()[0]
    let cards = printings.map { printing -> CardRecord in
      var card = template
      card.id = "gift-\(printing.set)-\(printing.number)"
      card.oracleID = "gift-oracle"
      card.name = "Gift Card"
      card.displayNameKey = "Gift Card".normalizedQueryKey
      card.setCode = printing.set
      card.collectorNumber = String(printing.number)
      card.collectorNumberNumber = printing.number
      return card
    }
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(cards)
    return database
  }

  /// Two printings of one card, built by copying a fixture record so the full
  /// `CardRecord` initializer doesn't have to be spelled out here.
  private func twinPrintings() -> [CardRecord] {
    let template = Fixtures.records()[0]

    var first = template
    first.id = "twin-1"
    first.oracleID = "twin-oracle"
    first.name = "Twin Card"
    first.displayNameKey = "Twin Card".normalizedQueryKey
    first.setCode = "ones"
    first.collectorNumber = "1"
    first.collectorNumberNumber = 1

    var second = template
    second.id = "twin-2"
    second.oracleID = "twin-oracle"
    second.name = "Twin Card"
    second.displayNameKey = "Twin Card".normalizedQueryKey
    second.setCode = "twos"
    second.collectorNumber = "5"
    second.collectorNumberNumber = 5

    return [first, second]
  }
}
