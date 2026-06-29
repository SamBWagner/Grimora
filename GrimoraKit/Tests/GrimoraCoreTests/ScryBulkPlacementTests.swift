@testable import GrimoraCore
import CoreGraphics
import XCTest

final class ScryBulkPlacementTests: XCTestCase {
  private let threshold: CGFloat = 0.08

  private func movement(
    detected: CGPoint?,
    committed: CGPoint?,
    hasCommittedCard: Bool
  ) -> ScryBulkPlacement.Movement {
    ScryBulkPlacement.movement(
      detectedCentroid: detected,
      committedCentroid: committed,
      hasCommittedCard: hasCommittedCard,
      threshold: threshold
    )
  }

  func testHoldsWhenStationaryWithinThreshold() {
    let outcome = movement(
      detected: CGPoint(x: 0.50, y: 0.50),
      committed: CGPoint(x: 0.51, y: 0.50),
      hasCommittedCard: true
    )
    XCTAssertEqual(outcome, .hold)
  }

  func testRearmsWhenCardMovesBeyondThreshold() {
    let outcome = movement(
      detected: CGPoint(x: 0.50, y: 0.50),
      committed: CGPoint(x: 0.70, y: 0.50),
      hasCommittedCard: true
    )
    XCTAssertEqual(outcome, .rearm)
  }

  func testRearmsWhenCardLeavesFrame() {
    // Card removed: no detection, but we had a committed baseline.
    let outcome = movement(
      detected: nil,
      committed: CGPoint(x: 0.50, y: 0.50),
      hasCommittedCard: true
    )
    XCTAssertEqual(outcome, .rearm)
  }

  func testRearmsWhenNothingCommittedAndNoCard() {
    let outcome = movement(detected: nil, committed: nil, hasCommittedCard: false)
    XCTAssertEqual(outcome, .rearm)
  }

  // The regression: a commit that captured no baseline (detectedCards was momentarily
  // empty) must NOT be treated as movement when the same card is still in frame, or it
  // re-arms and the same physical card is scanned twice.
  func testAdoptsBaselineInsteadOfRescanningWhenCommitMissedTheCentroid() {
    let here = CGPoint(x: 0.50, y: 0.50)
    let outcome = movement(detected: here, committed: nil, hasCommittedCard: true)
    XCTAssertEqual(outcome, .adoptBaseline(here))

    // Once the baseline is adopted, a stationary card holds (no rescan).
    XCTAssertEqual(
      movement(detected: here, committed: here, hasCommittedCard: true),
      .hold
    )
  }
}
