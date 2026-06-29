import CoreGraphics
import XCTest

@testable import GrimoraUI

// The detail pane's "maximized" width fits the card art to the pane's visible
// height, bounded so it never upscales past the source image and never starves
// the sidebar + search grid. These cover which bound wins in each regime.
final class CardDetailPaneWidthTests: XCTestCase {
    // Shared, explicit parameters so the asserts are deterministic (the shipping
    // call uses the real card aspect ratio + chrome constants).
    private func width(paneHeight: CGFloat, windowWidth: CGFloat) -> CGFloat {
        cardDetailMaximizedPaneWidth(
            paneHeight: paneHeight,
            windowWidth: windowWidth,
            minWidth: 300,
            nativeCardWidth: 600,
            reservedLeadingWidth: 500,
            horizontalInsets: 20,
            verticalInsets: 40,
            aspectRatio: 0.7
        )
    }

    func testHeightDrivesWidthInTheCommonCase() {
        // Roomy window, ordinary height: the card fills the height and the width
        // follows (500pt of card height → 500*0.7 + 20 insets = 370).
        XCTAssertEqual(width(paneHeight: 540, windowWidth: 2000), 370, accuracy: 0.001)
    }

    func testTallWindowIsCappedAtNativeResolution() {
        // A very tall window would imply a huge card; the native cap (600 + 20)
        // stops it so the art never upscales/blurs.
        XCTAssertEqual(width(paneHeight: 2000, windowWidth: 3000), 620, accuracy: 0.001)
    }

    func testNarrowWindowIsCappedToKeepGridUsable() {
        // A narrow window: width is capped to what's left after the sidebar+grid
        // minimums (900 − 500 reserved = 400).
        XCTAssertEqual(width(paneHeight: 2000, windowWidth: 900), 400, accuracy: 0.001)
    }

    func testNeverShrinksBelowMinimumWidth() {
        // Window so narrow the cap would go below the readable minimum, and a
        // degenerate tiny height — both floor at minWidth.
        XCTAssertEqual(width(paneHeight: 2000, windowWidth: 600), 300, accuracy: 0.001)
        XCTAssertEqual(width(paneHeight: 40, windowWidth: 2000), 300, accuracy: 0.001)
    }

    func testNonFiniteInputsFallBackToMinimum() {
        XCTAssertEqual(width(paneHeight: .infinity, windowWidth: 2000), 300, accuracy: 0.001)
        XCTAssertEqual(width(paneHeight: 540, windowWidth: .nan), 300, accuracy: 0.001)
    }
}
