@testable import GrimoraCore
import XCTest

/// Event-sequence tests for the passive single-mode reducer. The whole UX
/// contract lives in `ScrySingleFlow.reduce`, so these are plain state tests —
/// no camera, no Vision.
final class ScrySingleFlowTests: XCTestCase {
  private var cardA: CardRecord!
  private var cardB: CardRecord!

  override func setUp() {
    super.setUp()
    var a = Fixtures.records()[0]
    a.id = "card-a"
    a.name = "Alpha Forest"
    var b = a
    b.id = "card-b"
    b.name = "Beta Mage"
    cardA = a
    cardB = b
  }

  private func auto(_ card: CardRecord) -> ScryResolution {
    ScryResolution(card: card, candidates: [card], confidence: .auto, method: .exactKey, signals: ScrySignals())
  }

  private func ambiguous(_ candidates: [CardRecord]) -> ScryResolution {
    ScryResolution(card: nil, candidates: candidates, confidence: .ambiguous, method: .nameOnly, signals: ScrySignals())
  }

  /// Applies events in order, asserting nothing in between; returns the end state.
  private func run(_ phase: ScrySingleFlow.Phase, _ events: [ScrySingleFlow.Event]) -> ScrySingleFlow.Phase {
    events.reduce(phase) { ScrySingleFlow.reduce($0, $1).0 }
  }

  // MARK: - Happy path

  func testStableTrackVerifiesOffersAndCommits() {
    var (phase, effect) = ScrySingleFlow.reduce(.idle, .previewTick(key: "card-a", confident: true))
    XCTAssertEqual(phase, .tracking(key: "card-a", count: 1))

    (phase, effect) = ScrySingleFlow.reduce(phase, .previewTick(key: "card-a", confident: true))
    XCTAssertEqual(phase, .verifying(key: "card-a", manual: false))
    XCTAssertEqual(effect, .startScan(manual: false))

    (phase, effect) = ScrySingleFlow.reduce(phase, .scanFinished(auto(cardA)))
    guard case .offer(let offer) = phase, case .confident(let offered) = offer.kind else {
      return XCTFail("expected a confident offer, got \(phase)")
    }
    XCTAssertEqual(offered.id, "card-a")
    XCTAssertEqual(effect, .none, "passive offers are quiet — the chip is the announcement")

    (phase, effect) = ScrySingleFlow.reduce(phase, .offerTapped)
    XCTAssertEqual(effect, .presentReview(cardA))

    (phase, _) = ScrySingleFlow.reduce(phase, .reviewClosed(added: true))
    XCTAssertEqual(phase, .cooldown(acceptedKey: "card-a"))

    (phase, _) = ScrySingleFlow.reduce(phase, .subjectMoved)
    XCTAssertEqual(phase, .idle)
  }

  // MARK: - The full scan outranks the preview guess

  func testFullScanOutcomeOverridesPreviewGuess() {
    let verifying = run(.idle, [
      .previewTick(key: "card-a", confident: true),
      .previewTick(key: "card-a", confident: true)
    ])
    let (phase, _) = ScrySingleFlow.reduce(verifying, .scanFinished(auto(cardB)))
    guard case .offer(let offer) = phase, case .confident(let offered) = offer.kind else {
      return XCTFail("expected an offer, got \(phase)")
    }
    XCTAssertEqual(offered.id, "card-b", "the high-res scan is authoritative over the preview key")
  }

  // MARK: - Chip debounce and swap

  func testOfferSurvivesBriefDetectionLossThenDismisses() {
    var phase = offerPhase(for: cardA)
    for _ in 0..<(ScrySingleFlow.offerGraceTicks - 1) {
      (phase, _) = ScrySingleFlow.reduce(phase, .previewTick(key: nil, confident: false))
      guard case .offer = phase else { return XCTFail("chip must survive a wobble") }
    }
    (phase, _) = ScrySingleFlow.reduce(phase, .previewTick(key: nil, confident: false))
    XCTAssertEqual(phase, .idle, "sustained loss dismisses the chip")
  }

  func testConfidentOfferIsFrozenAgainstPreviewChurn() {
    // On-device failure this guards: a correct confident offer was overridden
    // by flickery wrong reads. Once nailed, only the user or the card leaving
    // moves the flow — even a confident different read doesn't.
    var phase = offerPhase(for: cardA)
    for _ in 0..<4 {
      let (next, effect) = ScrySingleFlow.reduce(phase, .previewTick(key: "card-b", confident: true))
      XCTAssertEqual(effect, .none)
      guard case .offer(let offer) = next, case .confident(let card) = offer.kind else {
        return XCTFail("confident offer must hold, got \(next)")
      }
      XCTAssertEqual(card.id, "card-a")
      phase = next
    }
  }

  func testAmbiguousOfferUpgradesOnlyOnStableConfidentReads() {
    // The Bria case: a wrong ambiguous picker on offer while the preview is
    // confident about the real card — the confident read replaces the picker.
    var phase = ambiguousOfferPhase([cardB])
    (phase, _) = ScrySingleFlow.reduce(phase, .previewTick(key: "card-a", confident: true))
    guard case .offer = phase else { return XCTFail("one confident tick must not swap yet") }

    let (next, effect) = ScrySingleFlow.reduce(phase, .previewTick(key: "card-a", confident: true))
    XCTAssertEqual(next, .verifying(key: "card-a", manual: false))
    XCTAssertEqual(effect, .startScan(manual: false))
  }

  func testAmbiguousOfferIgnoresUnconfidentFlicker() {
    var phase = ambiguousOfferPhase([cardB])
    for _ in 0..<5 {
      let (next, effect) = ScrySingleFlow.reduce(phase, .previewTick(key: "card-a", confident: false))
      XCTAssertEqual(effect, .none)
      guard case .offer = next else { return XCTFail("unconfident flicker must never re-verify") }
      phase = next
    }
  }

  func testManualAmbiguousOfferIsFrozen() {
    // While the user is inside the picker they explicitly asked for, passive
    // reads — however confident — must not restart scanning underneath them.
    let (manualOffer, _) = ScrySingleFlow.reduce(
      .verifying(key: "", manual: true), .scanFinished(ambiguous([cardB]))
    )
    var phase = manualOffer
    for _ in 0..<3 {
      let (next, effect) = ScrySingleFlow.reduce(phase, .previewTick(key: "card-a", confident: true))
      XCTAssertEqual(effect, .none)
      guard case .offer = next else { return XCTFail("manual offer must hold") }
      phase = next
    }
  }

  func testMatchingTickResetsOfferCounters() {
    var phase = offerPhase(for: cardA)
    (phase, _) = ScrySingleFlow.reduce(phase, .previewTick(key: nil, confident: false))
    (phase, _) = ScrySingleFlow.reduce(phase, .previewTick(key: "card-a", confident: true))
    guard case .offer(let offer) = phase else { return XCTFail() }
    XCTAssertEqual(offer.missedTicks, 0)
    XCTAssertNil(offer.swapKey)
  }

  // MARK: - Ambiguous offers

  func testAmbiguousScanOffersPicker() {
    let verifying = run(.idle, [
      .previewTick(key: "some name", confident: false),
      .previewTick(key: "some name", confident: false)
    ])
    var (phase, effect) = ScrySingleFlow.reduce(verifying, .scanFinished(ambiguous([cardA, cardB])))
    XCTAssertEqual(effect, .none)
    (phase, effect) = ScrySingleFlow.reduce(phase, .offerTapped)
    XCTAssertEqual(effect, .presentPicker([cardA, cardB]))

    let (afterCancel, _) = ScrySingleFlow.reduce(phase, .pickerCancelled)
    XCTAssertEqual(afterCancel, .idle)
  }

  // MARK: - Manual scans (tap anywhere)

  func testManualScanReportsOutcomesLoudly() {
    var (phase, effect) = ScrySingleFlow.reduce(.idle, .userTappedScreen)
    XCTAssertEqual(effect, .startScan(manual: true))

    // Failure is announced (passive failures are silent — tested below).
    let failed = ScrySingleFlow.reduce(phase, .scanFailed)
    XCTAssertEqual(failed.0, .idle)
    XCTAssertEqual(failed.1, .flashFailure)

    // Success opens the review sheet immediately, no chip stop.
    (phase, effect) = ScrySingleFlow.reduce(.verifying(key: "", manual: true), .scanFinished(auto(cardA)))
    XCTAssertEqual(effect, .presentReview(cardA))

    // Ambiguity opens the picker immediately.
    (phase, effect) = ScrySingleFlow.reduce(.verifying(key: "", manual: true), .scanFinished(ambiguous([cardA, cardB])))
    XCTAssertEqual(effect, .presentPicker([cardA, cardB]))
  }

  func testPassiveFailuresStayQuiet() {
    let (phase, effect) = ScrySingleFlow.reduce(.verifying(key: "card-a", manual: false), .scanFailed)
    XCTAssertEqual(phase, .idle)
    XCTAssertEqual(effect, .none)
  }

  func testOnlyOneScanInFlight() {
    let verifying = ScrySingleFlow.Phase.verifying(key: "card-a", manual: false)
    let (phase, effect) = ScrySingleFlow.reduce(verifying, .userTappedScreen)
    XCTAssertEqual(phase, verifying)
    XCTAssertEqual(effect, .none)
  }

  // MARK: - Swipe gestures

  func testSwipeLeftAcceptsConfidentOfferDirectly() {
    let (phase, effect) = ScrySingleFlow.reduce(offerPhase(for: cardA), .offerSwipedToAccept)
    XCTAssertEqual(effect, .commitToScanned(cardA), "swipe-accept skips the review sheet")
    XCTAssertEqual(phase, .cooldown(acceptedKey: "card-a"))
  }

  func testSwipeLeftOnAmbiguousOfferDoesNothing() {
    let ambiguousOffer = ambiguousOfferPhase([cardA, cardB])
    let (phase, effect) = ScrySingleFlow.reduce(ambiguousOffer, .offerSwipedToAccept)
    XCTAssertEqual(effect, .none, "no single card to accept — the picker is still required")
    XCTAssertEqual(phase, ambiguousOffer)
  }

  func testSwipeRightRescansQuietly() {
    let (phase, effect) = ScrySingleFlow.reduce(offerPhase(for: cardA), .offerSwipedToRetry)
    XCTAssertEqual(phase, .verifying(key: "card-a", manual: false))
    XCTAssertEqual(effect, .startScan(manual: false), "rescan is the quiet kind — no shutter sound")
  }

  func testSwipeRightWorksOnAmbiguousOffersToo() {
    let (phase, effect) = ScrySingleFlow.reduce(ambiguousOfferPhase([cardA, cardB]), .offerSwipedToRetry)
    guard case .verifying(_, let manual) = phase else { return XCTFail("expected verifying, got \(phase)") }
    XCTAssertFalse(manual)
    XCTAssertEqual(effect, .startScan(manual: false))
  }

  // MARK: - Cooldown

  func testStationaryCardNeverDoubleAdds() {
    let cooldown = ScrySingleFlow.Phase.cooldown(acceptedKey: "card-a")
    let (phase, effect) = ScrySingleFlow.reduce(cooldown, .previewTick(key: "card-a", confident: true))
    XCTAssertEqual(phase, cooldown)
    XCTAssertEqual(effect, .none)
  }

  func testDifferentConfidentCardRearmsInPlace() {
    // The bulk-mode lesson: the next card can land exactly where the last one
    // sat, so a different *confident* id re-arms without movement.
    let cooldown = ScrySingleFlow.Phase.cooldown(acceptedKey: "card-a")
    let (phase, _) = ScrySingleFlow.reduce(cooldown, .previewTick(key: "card-b", confident: true))
    XCTAssertEqual(phase, .tracking(key: "card-b", count: 1))

    // …but an unconfident guess (recognition flicker) must not.
    let (held, _) = ScrySingleFlow.reduce(cooldown, .previewTick(key: "card-b", confident: false))
    XCTAssertEqual(held, cooldown)
  }

  func testDismissedReviewResumesPassiveTracking() {
    let (phase, _) = ScrySingleFlow.reduce(offerPhase(for: cardA), .reviewClosed(added: false))
    XCTAssertEqual(phase, .idle)
  }

  // MARK: - Helpers

  private func offerPhase(for card: CardRecord) -> ScrySingleFlow.Phase {
    let verifying = run(.idle, [
      .previewTick(key: card.id, confident: true),
      .previewTick(key: card.id, confident: true)
    ])
    return ScrySingleFlow.reduce(verifying, .scanFinished(auto(card))).0
  }

  private func ambiguousOfferPhase(_ candidates: [CardRecord]) -> ScrySingleFlow.Phase {
    let verifying = run(.idle, [
      .previewTick(key: "some name", confident: false),
      .previewTick(key: "some name", confident: false)
    ])
    return ScrySingleFlow.reduce(verifying, .scanFinished(ambiguous(candidates))).0
  }
}
