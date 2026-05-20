import CoreGraphics
@testable import GrimoraUI
import XCTest

final class JumpToTopScrollStateTests: XCTestCase {
    func testTopAndNegativeOffsetsHideButton() {
        XCTAssertFalse(JumpToTopScrollState.showsButton(contentOffsetY: 0, viewportHeight: 600))
        XCTAssertFalse(JumpToTopScrollState.showsButton(contentOffsetY: -1, viewportHeight: 600))
    }

    func testOffsetsBelowMinimumThresholdHideButton() {
        XCTAssertFalse(JumpToTopScrollState.showsButton(contentOffsetY: 319.9, viewportHeight: 100))
        XCTAssertTrue(JumpToTopScrollState.showsButton(contentOffsetY: 320, viewportHeight: 100))
    }

    func testViewportScaledThresholdControlsLargeViewports() {
        XCTAssertFalse(JumpToTopScrollState.showsButton(contentOffsetY: 599.9, viewportHeight: 800))
        XCTAssertTrue(JumpToTopScrollState.showsButton(contentOffsetY: 600, viewportHeight: 800))
    }

    func testInvalidGeometryFallsBackToHiddenState() {
        XCTAssertEqual(
            JumpToTopScrollState(contentOffsetY: .infinity, viewportHeight: .infinity),
            .top
        )
        XCTAssertFalse(JumpToTopScrollState.showsButton(contentOffsetY: .nan, viewportHeight: 800))
    }
}
