import Foundation

/// Pure state machine that decides when a one-shot autofocus has actually
/// finished, so the camera layer can hand focus back (or lock) only after the
/// lens stops hunting — never on a fixed timer that can freeze a mid-hunt, soft
/// frame (the bug this replaces).
///
/// Feed it the device's `isAdjustingFocus` samples as they arrive, each with the
/// time elapsed since the one-shot began. It waits for the lens to *start*
/// hunting and then *stop* (the adjusting → idle edge). If the lens never starts
/// within `grace`, the scene was already sharp and it settles at once. If it is
/// still hunting at `timeout`, it settles anyway rather than hang. The decision
/// is terminal: once it leaves `.waiting`, every later `update` returns the same
/// value.
///
/// The AVFoundation/KVO plumbing that drives this lives in `GrimoraUI`
/// (`ScryFocusSettleCoordinator`); this type is pure so the timing logic — the
/// part that was actually broken — is host-testable without a camera.
public struct ScryFocusSettle: Sendable, Equatable {
  public enum Decision: Sendable, Equatable {
    /// Keep observing — the lens hasn't demonstrably settled yet.
    case waiting
    /// The lens stopped hunting (or was already sharp). Apply the final mode.
    case settled
    /// Never settled within the deadline. Apply the final mode anyway, so a
    /// stuck hunt can't leave the caller waiting forever.
    case timedOut
  }

  /// How long to wait for hunting to *start* before treating a still-idle lens
  /// as "already sharp".
  public let grace: Duration
  /// Hard deadline: settle regardless once this much time has elapsed.
  public let timeout: Duration

  private var hasStartedHunting = false
  private var terminal: Decision?

  public init(grace: Duration = .milliseconds(120), timeout: Duration = .milliseconds(1200)) {
    self.grace = grace
    self.timeout = timeout
  }

  /// Feeds one observation. `isAdjusting` is the device's current
  /// focus-adjusting state; `elapsed` is time since the one-shot was requested.
  public mutating func update(isAdjusting: Bool, elapsed: Duration) -> Decision {
    if let terminal { return terminal }
    if isAdjusting { hasStartedHunting = true }
    let decision = decide(isAdjusting: isAdjusting, elapsed: elapsed)
    if decision != .waiting { terminal = decision }
    return decision
  }

  /// Whether a terminal decision has been reached (for the coordinator's
  /// exactly-once guard and for tests).
  public var isResolved: Bool { terminal != nil }

  private func decide(isAdjusting: Bool, elapsed: Duration) -> Decision {
    if isAdjusting {
      // Still hunting — only give up at the deadline.
      return elapsed >= timeout ? .timedOut : .waiting
    }
    // Idle: settle on the adjusting → idle edge, or if it never started within
    // the grace window (already-sharp scene).
    if hasStartedHunting { return .settled }
    if elapsed >= grace { return .settled }
    return elapsed >= timeout ? .timedOut : .waiting
  }
}
