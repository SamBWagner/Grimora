import CoreGraphics

/// The pure "one scan per physical placement" rule for Scry's bulk mode.
///
/// Lives here (not in the iOS-only `ScryTabView`) so the subtle "don't rescan the
/// same card" logic is unit-testable on the host. After a card is committed the view
/// stays disarmed until the placement changes; this decides, from a fresh subject
/// centroid and the committed baseline, whether it changed.
public enum ScryBulkPlacement {
  public enum Movement: Equatable {
    /// The committed card never had a baseline (commit landed on a frame with no
    /// detection). Adopt this first centroid as the baseline *without* re-arming —
    /// treating the missing baseline as movement would rescan the same card.
    case adoptBaseline(CGPoint)
    /// The card moved or left the frame — re-arm for the next placement.
    case rearm
    /// Same placement, still in roughly the same spot — hold.
    case hold
  }

  /// - Parameters:
  ///   - detectedCentroid: centroid of the current subject card, or `nil` if none.
  ///   - committedCentroid: the baseline captured at commit, or `nil` if none was.
  ///   - hasCommittedCard: whether a card is currently committed (awaiting movement).
  ///   - threshold: normalized distance the centroid must move to count as a new placement.
  public static func movement(
    detectedCentroid: CGPoint?,
    committedCentroid: CGPoint?,
    hasCommittedCard: Bool,
    threshold: CGFloat
  ) -> Movement {
    // Commit captured no baseline but a card is present now: lock onto it rather than
    // mistaking the absent baseline for movement (which would rescan the same card).
    if hasCommittedCard, committedCentroid == nil, let detectedCentroid {
      return .adoptBaseline(detectedCentroid)
    }
    guard let detectedCentroid, let committedCentroid else {
      return .rearm  // no card in frame (removed), or nothing committed
    }
    let moved = hypot(
      detectedCentroid.x - committedCentroid.x,
      detectedCentroid.y - committedCentroid.y
    ) > threshold
    return moved ? .rearm : .hold
  }
}
