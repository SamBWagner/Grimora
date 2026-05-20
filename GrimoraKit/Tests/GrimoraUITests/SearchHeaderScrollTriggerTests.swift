@testable import GrimoraUI
import XCTest

final class SearchHeaderScrollTriggerTests: XCTestCase {
    func testNegativeAndTopOffsetsExpandHeader() {
        XCTAssertEqual(MacSearchHeaderScrollTrigger(contentOffsetY: -24), .expand)
        XCTAssertEqual(MacSearchHeaderScrollTrigger(contentOffsetY: 0), .expand)
        XCTAssertEqual(MacSearchHeaderScrollTrigger(contentOffsetY: 8), .expand)
    }

    func testOffsetsBetweenThresholdsHoldCurrentHeaderState() {
        XCTAssertEqual(MacSearchHeaderScrollTrigger(contentOffsetY: 8.1), .hold)
        XCTAssertEqual(MacSearchHeaderScrollTrigger(contentOffsetY: 24), .hold)
        XCTAssertEqual(MacSearchHeaderScrollTrigger(contentOffsetY: 47.9), .hold)
    }

    func testMeaningfulDownwardScrollCollapsesHeader() {
        XCTAssertEqual(MacSearchHeaderScrollTrigger(contentOffsetY: 48), .collapse)
        XCTAssertEqual(MacSearchHeaderScrollTrigger(contentOffsetY: 120), .collapse)
    }

    func testLegacyMinYUsesTheSameThresholds() {
        XCTAssertEqual(MacSearchHeaderScrollTrigger(legacyContentMinY: 12), .expand)
        XCTAssertEqual(MacSearchHeaderScrollTrigger(legacyContentMinY: -8), .expand)
        XCTAssertEqual(MacSearchHeaderScrollTrigger(legacyContentMinY: -24), .hold)
        XCTAssertEqual(MacSearchHeaderScrollTrigger(legacyContentMinY: -48), .collapse)
    }
}
