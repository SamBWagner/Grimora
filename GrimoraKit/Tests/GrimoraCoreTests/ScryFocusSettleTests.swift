@testable import GrimoraCore
import XCTest

/// The timing logic that was actually broken by the old fixed-0.7s lock: decide
/// when a one-shot autofocus has truly settled. Host-testable because
/// `ScryFocusSettle` is pure; the KVO plumbing that feeds it
/// (`ScryFocusSettleCoordinator`) is device-only.
final class ScryFocusSettleTests: XCTestCase {
  private func make() -> ScryFocusSettle {
    ScryFocusSettle(grace: .milliseconds(100), timeout: .milliseconds(1000))
  }

  func testSettlesOnAdjustingToIdleEdge() {
    var settle = make()
    // The lens is hunting — never settle mid-hunt, even past the grace window.
    XCTAssertEqual(settle.update(isAdjusting: true, elapsed: .milliseconds(50)), .waiting)
    XCTAssertEqual(settle.update(isAdjusting: true, elapsed: .milliseconds(300)), .waiting)
    // It stops: the adjusting → idle edge is a genuine settle.
    XCTAssertEqual(settle.update(isAdjusting: false, elapsed: .milliseconds(400)), .settled)
  }

  func testStaysWaitingWhileStillHunting() {
    var settle = make()
    XCTAssertEqual(settle.update(isAdjusting: true, elapsed: .milliseconds(200)), .waiting)
    XCTAssertEqual(settle.update(isAdjusting: true, elapsed: .milliseconds(800)), .waiting)
  }

  func testAlreadySharpSettlesAfterGraceWithoutHunting() {
    var settle = make()
    // Idle before grace: still waiting to see whether a hunt starts.
    XCTAssertEqual(settle.update(isAdjusting: false, elapsed: .milliseconds(50)), .waiting)
    // Idle past grace and it never hunted: the scene was already sharp.
    XCTAssertEqual(settle.update(isAdjusting: false, elapsed: .milliseconds(120)), .settled)
  }

  func testTimesOutWhenStuckHunting() {
    var settle = make()
    XCTAssertEqual(settle.update(isAdjusting: true, elapsed: .milliseconds(500)), .waiting)
    // Still hunting at the deadline: settle anyway rather than hang forever.
    XCTAssertEqual(settle.update(isAdjusting: true, elapsed: .milliseconds(1000)), .timedOut)
  }

  func testDecisionIsTerminalAndSticky() {
    var settle = make()
    XCTAssertFalse(settle.isResolved)
    XCTAssertEqual(settle.update(isAdjusting: true, elapsed: .milliseconds(100)), .waiting)
    XCTAssertEqual(settle.update(isAdjusting: false, elapsed: .milliseconds(200)), .settled)
    XCTAssertTrue(settle.isResolved)
    // A late spurious "hunting" sample must not un-settle it.
    XCTAssertEqual(settle.update(isAdjusting: true, elapsed: .milliseconds(300)), .settled)
  }

  func testTimeoutIsTerminalAndSticky() {
    var settle = make()
    XCTAssertEqual(settle.update(isAdjusting: true, elapsed: .milliseconds(1000)), .timedOut)
    XCTAssertEqual(settle.update(isAdjusting: false, elapsed: .milliseconds(1100)), .timedOut)
  }
}
