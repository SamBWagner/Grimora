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
