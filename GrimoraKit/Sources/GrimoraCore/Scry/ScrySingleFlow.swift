import Foundation

/// The passive single-mode scanning flow as a pure reducer — same philosophy as
/// `ScryBulkPlacement`: all the interaction rules live here, camera-free and
/// host-testable as event sequences; the view just feeds events and executes
/// effects.
///
/// Flow: the preview loop passively tracks what's in frame; two consecutive
/// identical guesses trigger a full background scan (high-res still + retry +
/// symbol refinement); its outcome becomes an **offer** — a tappable chip
/// showing the identified card. Tapping the chip opens the review sheet, whose
/// "Add to Scanned" moves the flow to a cooldown that re-arms exactly like bulk
/// mode (subject movement, or a different confident card in the same spot).
/// Tapping the screen anywhere focuses the camera and forces a manual scan with
/// explicit success/failure feedback; passive outcomes stay quiet.
public enum ScrySingleFlow {
  /// Consecutive identical preview guesses required before verifying.
  public static let requiredStableCount = 2
  /// Empty preview ticks an offer survives before dismissing (hand wobble ≠ card gone).
  public static let offerGraceTicks = 3

  public struct Offer: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
      /// The full scan auto-accepted this printing — chip shows the card.
      case confident(CardRecord)
      /// The full scan stayed ambiguous — chip offers the printing picker.
      case ambiguous([CardRecord])
    }

    public var kind: Kind
    /// The stable preview key that produced this offer.
    public var key: String
    /// Whether the user asked for this scan (tap). Manual offers never re-verify
    /// passively — the user is deciding; only their action or the card leaving
    /// moves the flow.
    public var manual: Bool
    /// Consecutive empty ticks while offered (dismiss at `offerGraceTicks`).
    public var missedTicks: Int = 0
    /// A *confident* different read being tracked while an ambiguous offer is up
    /// (the upgrade path: "✓ the right card" replaces a wrong picker).
    public var swapKey: String?
    public var swapCount: Int = 0

    public init(kind: Kind, key: String, manual: Bool = false) {
      self.kind = kind
      self.key = key
      self.manual = manual
    }

    /// A frozen offer ignores preview churn entirely: once a card is nailed
    /// (confident) or the user explicitly asked (manual), passive scanning must
    /// not override it — the on-device failure this prevents was a correct
    /// confident result getting replaced by a flickery wrong one.
    var isFrozen: Bool {
      manual || {
        if case .confident = kind { return true }
        return false
      }()
    }
  }

  public enum Phase: Equatable, Sendable {
    /// Nothing usable in frame.
    case idle
    /// Accumulating preview stability for `key`.
    case tracking(key: String, count: Int)
    /// Stability reached — a full scan is in flight. `key` is empty for manual scans.
    case verifying(key: String, manual: Bool)
    /// A scan outcome is on offer as the tappable chip (or holding while its
    /// review sheet / picker is presented).
    case offer(Offer)
    /// A card was accepted; wait for the subject to move (or change) before
    /// scanning again, so a stationary card is never double-added.
    case cooldown(acceptedKey: String)
  }

  public enum Event: Equatable, Sendable {
    /// One preview-loop cycle. `key` identifies the current guess (card id when
    /// confident, name otherwise), `nil` when nothing is recognized.
    case previewTick(key: String?, confident: Bool)
    /// The full scan finished with this (already-refined) resolution.
    case scanFinished(ScryResolution)
    /// The full scan couldn't lock a card at all.
    case scanFailed
    /// The user tapped the camera view (focus is handled by the caller).
    case userTappedScreen
    /// The user tapped the offer chip.
    case offerTapped
    /// The user swiped the chip left: accept this card into Scanned directly,
    /// no review sheet.
    case offerSwipedToAccept
    /// The user swiped the chip right: "that's wrong — scan it again." Requeues
    /// a quiet scan immediately so an adjusted card gets a fresh chip.
    case offerSwipedToRetry
    /// The review sheet closed; `added` when the card went into Scanned.
    case reviewClosed(added: Bool)
    /// The printing picker closed without a pick (a pick opens the review sheet
    /// instead, so it ends in `reviewClosed`).
    case pickerCancelled
    /// The committed subject moved or left the frame (bulk-placement verdict).
    case subjectMoved
  }

  public enum Effect: Equatable, Sendable {
    case none
    /// Run the full pipeline (still capture + retry + refinement). Manual scans
    /// report failure; passive ones stay quiet.
    case startScan(manual: Bool)
    case presentReview(CardRecord)
    case presentPicker([CardRecord])
    /// Add straight to Scanned (swipe-accept) — the caller plays the commit
    /// sound/haptic and records the placement for cooldown.
    case commitToScanned(CardRecord)
    /// Manual-scan failure feedback (flash + sound + haptic).
    case flashFailure
  }

  public static func reduce(_ phase: Phase, _ event: Event) -> (Phase, Effect) {
    switch (phase, event) {
    // MARK: Tracking stability

    case (.idle, .previewTick(let key?, _)):
      return (.tracking(key: key, count: 1), .none)

    case (.tracking, .previewTick(nil, _)):
      return (.idle, .none)

    case (.tracking(let key, let count), .previewTick(let new?, _)):
      guard new == key else { return (.tracking(key: new, count: 1), .none) }
      let next = count + 1
      if next >= requiredStableCount {
        return (.verifying(key: key, manual: false), .startScan(manual: false))
      }
      return (.tracking(key: key, count: next), .none)

    // MARK: Scan outcomes

    case (.verifying(let key, let manual), .scanFinished(let resolution)):
      switch resolution.confidence {
      case .auto:
        guard let card = resolution.card else { return (.idle, .none) }
        if manual {
          // Manual scans skip the chip: the user explicitly asked, so answer.
          return (.offer(Offer(kind: .confident(card), key: key, manual: true)), .presentReview(card))
        }
        return (.offer(Offer(kind: .confident(card), key: key)), .none)
      case .ambiguous:
        if manual {
          return (
            .offer(Offer(kind: .ambiguous(resolution.candidates), key: key, manual: true)),
            .presentPicker(resolution.candidates)
          )
        }
        return (.offer(Offer(kind: .ambiguous(resolution.candidates), key: key)), .none)
      case .none:
        return (.idle, manual ? .flashFailure : .none)
      }

    case (.verifying(_, let manual), .scanFailed):
      return (.idle, manual ? .flashFailure : .none)

    // MARK: The offer chip

    case (.offer(var offer), .previewTick(let key, let confident)):
      guard let key else {
        offer.missedTicks += 1
        offer.swapKey = nil
        offer.swapCount = 0
        if offer.missedTicks >= offerGraceTicks {
          return (.idle, .none)  // card actually left — chip goes away
        }
        return (.offer(offer), .none)
      }
      offer.missedTicks = 0
      // Frozen offers (confident, or manual) only ever leave via the user or
      // the card leaving — passive churn must not override a nailed card.
      if offer.isFrozen || key == offer.key || !confident {
        offer.swapKey = nil
        offer.swapCount = 0
        return (.offer(offer), .none)
      }
      // Upgrade path for a passive ambiguous offer: a *confident* different
      // read, stable for the usual bar, replaces the picker (this is what lets
      // "✓ the right card" displace a wrong guess — flicker can't, because
      // unconfident ticks never count).
      if key == offer.swapKey {
        offer.swapCount += 1
        if offer.swapCount >= requiredStableCount {
          return (.verifying(key: key, manual: false), .startScan(manual: false))
        }
      } else {
        offer.swapKey = key
        offer.swapCount = 1
      }
      return (.offer(offer), .none)

    case (.offer(let offer), .offerTapped):
      switch offer.kind {
      case .confident(let card):
        return (.offer(offer), .presentReview(card))
      case .ambiguous(let candidates):
        return (.offer(offer), .presentPicker(candidates))
      }

    case (.offer(let offer), .offerSwipedToAccept):
      // Only a confident chip has a single card to accept; an ambiguous one
      // still needs the picker, so the swipe is a no-op there.
      guard case .confident(let card) = offer.kind else { return (.offer(offer), .none) }
      return (.cooldown(acceptedKey: offer.key), .commitToScanned(card))

    case (.offer(let offer), .offerSwipedToRetry):
      // Quiet re-verify (video frame, no shutter): the user will adjust the
      // card and wants a fresh chip, not the review flow.
      return (.verifying(key: offer.key, manual: false), .startScan(manual: false))

    case (.offer(let offer), .reviewClosed(let added)):
      if added {
        return (.cooldown(acceptedKey: offer.key), .none)
      }
      return (.idle, .none)  // rescan / dismissed — resume passive tracking

    case (.offer, .pickerCancelled):
      return (.idle, .none)

    // MARK: Cooldown & re-arm

    case (.cooldown, .subjectMoved):
      return (.idle, .none)

    case (.cooldown(let accepted), .previewTick(let key?, let confident)):
      // Same-spot swap: a *different* confident card re-arms without movement
      // (the bulk-mode lesson — a swapped card can land exactly where the last
      // one sat). Confidence required so recognition flicker can't re-arm.
      if confident, key != accepted {
        return (.tracking(key: key, count: 1), .none)
      }
      return (.cooldown(acceptedKey: accepted), .none)

    // MARK: Manual scan

    case (.idle, .userTappedScreen),
         (.tracking, .userTappedScreen),
         (.offer, .userTappedScreen),
         (.cooldown, .userTappedScreen):
      return (.verifying(key: "", manual: true), .startScan(manual: true))

    case (.verifying, .userTappedScreen):
      return (phase, .none)  // one scan in flight at a time

    // MARK: Anything else changes nothing

    default:
      return (phase, .none)
    }
  }
}
