#if os(iOS)
import CoreGraphics
import GrimoraCore

/// The bulk-scan state machine, extracted so the Scry tab's Bulk mode and the
/// Commander **Re-scan Deck** flow drive one tuned implementation instead of two
/// drifting copies.
///
/// The host owns the camera and preview; it feeds preview/placement changes in
/// (`consider`, `trackMovement`) and supplies two callbacks: `onScanned` persists a
/// committed card (and owns its own feedback/counter), and `onNeedsReview` asks the
/// host to present the Correct/Incorrect sheet for an uncertain read. A card is only
/// committed once per placement — it must *move* before the next one — which is what
/// lets duplicates (e.g. basic lands) be captured.
@MainActor
final class ScryBulkCoordinator {
  /// Persist a confirmed card. The host owns sound, haptics, and any running count.
  var onScanned: (CardRecord) -> Void = { _ in }
  /// Ask the host to present the Correct/Incorrect review for an uncertain card.
  var onNeedsReview: (CardRecord) -> Void = { _ in }

  private var armed = true
  private var isScanning = false
  private var awaitingReview = false
  private var stableKey: String?
  private var stableCount = 0
  private var committedCentroid: CGPoint?
  private var committedCardID: CardRecord.ID?
  private var rejectedIDs: Set<CardRecord.ID> = []

  /// How far (normalized) a card must move to count as a new placement.
  private let movementThreshold: CGFloat = 0.08

  func reset() {
    armed = true
    isScanning = false
    awaitingReview = false
    stableKey = nil
    stableCount = 0
    committedCentroid = nil
    committedCardID = nil
    rejectedIDs = []
  }

  // MARK: - Driven by the host

  func consider(guess: ScryCameraController.PreviewGuess?, controller: ScryCameraController) {
    guard !awaitingReview, !isScanning else { return }
    guard let guess else { stableKey = nil; stableCount = 0; return }

    let key = guess.card?.id ?? guess.name
    if key == stableKey { stableCount += 1 } else { stableKey = key; stableCount = 1 }
    guard stableCount >= 2 else { return }

    // Re-arm when a *different* confident card appears — a new card was placed,
    // even if it landed in the same spot (centroid movement can miss that).
    if !armed, guess.confident, let card = guess.card, card.id != committedCardID {
      armed = true
      rejectedIDs = []
    }
    guard armed else { return }

    if guess.confident, let card = guess.card, !rejectedIDs.contains(card.id) {
      commit(card, controller: controller)  // confident → straight to the sink
    } else if !guess.confident {
      runUncertainScan(controller: controller)  // need candidates for Correct/Incorrect
    }
  }

  /// Re-arms only when the card actually moves (or leaves), so a stationary card is
  /// never scanned twice — and a swap/duplicate is picked up immediately.
  func trackMovement(cards: [ScryDetectedCard], controller: ScryCameraController) {
    guard !armed else { return }
    switch ScryBulkPlacement.movement(
      detectedCentroid: Self.subjectCentroid(cards),
      committedCentroid: committedCentroid,
      hasCommittedCard: committedCardID != nil,
      threshold: movementThreshold
    ) {
    case .adoptBaseline(let centroid):
      committedCentroid = centroid
    case .rearm:
      armed = true
      committedCentroid = nil
      rejectedIDs = []
      stableKey = nil
      stableCount = 0
    case .hold:
      break
    }
  }

  /// The user answered the uncertain prompt with "Correct".
  func acceptUncertain(_ card: CardRecord, controller: ScryCameraController) {
    awaitingReview = false
    commit(card, controller: controller)
  }

  /// The user answered the uncertain prompt with "Incorrect".
  func rejectUncertain(_ card: CardRecord) {
    awaitingReview = false
    rejectedIDs.insert(card.id)
    stableKey = nil
    stableCount = 0  // re-trigger a scan for the next-best candidate
  }

  /// The review sheet was dismissed without a decision (swipe-down). Resume scanning
  /// without rejecting the card so it can be offered again.
  func reviewDismissed() {
    awaitingReview = false
    stableKey = nil
    stableCount = 0
  }

  // MARK: - Internals

  /// A full scan to get ranked candidates for an uncertain card.
  private func runUncertainScan(controller: ScryCameraController) {
    isScanning = true
    Task { @MainActor in
      let result = await controller.scan()
      isScanning = false
      guard armed, !awaitingReview, let result else { return }
      switch result.resolution.confidence {
      case .auto:
        if let card = result.resolution.card, !rejectedIDs.contains(card.id) {
          commit(card, controller: controller)
        }
      case .ambiguous:
        if let next = result.resolution.candidates.first(where: { !rejectedIDs.contains($0.id) }) {
          awaitingReview = true
          onNeedsReview(next)
        }
      case .none:
        break
      }
    }
  }

  /// Commits a card to the sink and waits for the card to move before the next.
  private func commit(_ card: CardRecord, controller: ScryCameraController) {
    onScanned(card)
    committedCentroid = Self.subjectCentroid(controller.detectedCards)
    committedCardID = card.id
    armed = false
    stableKey = nil
    stableCount = 0
  }

  static func subjectCentroid(_ cards: [ScryDetectedCard]) -> CGPoint? {
    guard let corners = cards.first?.normalizedCorners, !corners.isEmpty else { return nil }
    let sum = corners.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
    return CGPoint(x: sum.x / CGFloat(corners.count), y: sum.y / CGFloat(corners.count))
  }
}
#endif
