import GrimoraCore
import XCTest

@testable import GrimoraUI

final class SearchVisibleImageWindowTrackerTests: XCTestCase {
  func testAdjacentIndicesStayInSameWindowBucket() {
    var tracker = SearchVisibleImageWindowTracker(stride: 12)
    let ids = cardIDs(count: 60)
    let firstStart = tracker.windowStart(for: 0)
    let adjacentStart = tracker.windowStart(for: 11)

    XCTAssertEqual(firstStart, 0)
    XCTAssertEqual(adjacentStart, 0)
    XCTAssertTrue(
      tracker.shouldRefresh(
        windowStart: firstStart,
        cardIDs: windowIDs(ids, start: firstStart),
        quality: .small
      ))
    XCTAssertFalse(
      tracker.shouldRefresh(
        windowStart: adjacentStart,
        cardIDs: windowIDs(ids, start: adjacentStart),
        quality: .small
      ))
  }

  func testJumpBeyondStrideRefreshesWindow() {
    var tracker = SearchVisibleImageWindowTracker(stride: 12)
    let ids = cardIDs(count: 60)
    let firstStart = tracker.windowStart(for: 0)
    let jumpedStart = tracker.windowStart(for: 13)

    XCTAssertEqual(jumpedStart, 12)
    XCTAssertTrue(
      tracker.shouldRefresh(
        windowStart: firstStart,
        cardIDs: windowIDs(ids, start: firstStart),
        quality: .small
      ))
    XCTAssertTrue(
      tracker.shouldRefresh(
        windowStart: jumpedStart,
        cardIDs: windowIDs(ids, start: jumpedStart),
        quality: .small
      ))
  }

  func testQualityChangeRefreshesSameWindow() {
    var tracker = SearchVisibleImageWindowTracker(stride: 12)
    let ids = cardIDs(count: 60)
    let start = tracker.windowStart(for: 4)
    let window = windowIDs(ids, start: start)

    XCTAssertEqual(start, 0)
    XCTAssertTrue(tracker.shouldRefresh(windowStart: start, cardIDs: window, quality: .small))
    XCTAssertTrue(tracker.shouldRefresh(windowStart: start, cardIDs: window, quality: .normal))
    XCTAssertFalse(tracker.shouldRefresh(windowStart: start, cardIDs: window, quality: .normal))
  }

  func testForceRefreshAllowsSameWindowAgain() {
    var tracker = SearchVisibleImageWindowTracker(stride: 12)
    let ids = cardIDs(count: 60)
    let start = tracker.windowStart(for: 4)
    let window = windowIDs(ids, start: start)

    XCTAssertTrue(tracker.shouldRefresh(windowStart: start, cardIDs: window, quality: .small))
    XCTAssertFalse(tracker.shouldRefresh(windowStart: start, cardIDs: window, quality: .small))
    XCTAssertTrue(
      tracker.shouldRefresh(
        windowStart: start,
        cardIDs: window,
        quality: .small,
        force: true
      ))
    XCTAssertFalse(tracker.shouldRefresh(windowStart: start, cardIDs: window, quality: .small))
  }

  func testNegativeIndicesClampToFirstWindow() {
    var tracker = SearchVisibleImageWindowTracker(stride: 12)
    let ids = cardIDs(count: 60)
    let start = tracker.windowStart(for: -20)

    XCTAssertEqual(start, 0)
    XCTAssertTrue(
      tracker.shouldRefresh(
        windowStart: start,
        cardIDs: windowIDs(ids, start: start),
        quality: .small
      ))
  }

  private func cardIDs(count: Int) -> [CardRecord.ID] {
    (0..<count).map { "card-\($0)" }
  }

  private func windowIDs(
    _ ids: [CardRecord.ID],
    start: Int,
    lookaheadCount: Int = 36
  ) -> [CardRecord.ID] {
    let safeStart = min(max(0, start), ids.count - 1)
    let end = min(ids.count, safeStart + lookaheadCount + 1)
    return Array(ids[safeStart..<end])
  }
}
