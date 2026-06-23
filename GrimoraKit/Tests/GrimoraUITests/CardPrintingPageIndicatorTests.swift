import CoreGraphics
import XCTest

@testable import GrimoraUI

// D2: the artwork pager shows a page-indicator dot strip. These cover the pure
// windowing/sizing policy that drives how many dots render and which is active.
final class CardPrintingPageIndicatorTests: XCTestCase {
    func testWindowShowsEveryDotWhenCountFitsLimit() {
        // A handful of printings: every print gets its own dot, no windowing.
        XCTAssertEqual(compactPrintingDotWindow(count: 5, current: 2, maxVisible: 7), 0..<5)
        XCTAssertEqual(compactPrintingDotWindow(count: 7, current: 6, maxVisible: 7), 0..<7)
    }

    func testWindowKeepsFixedWidthForLargeCounts() {
        // Many printings (e.g. Sol Ring): the strip caps at `maxVisible` dots.
        let window = compactPrintingDotWindow(count: 30, current: 15, maxVisible: 7)
        XCTAssertEqual(window.count, 7)
        XCTAssertTrue(window.contains(15))
    }

    func testWindowCentresCurrentDotInTheMiddleOfTheRange() {
        // Paging through the middle keeps the active dot centred (half = 3).
        XCTAssertEqual(compactPrintingDotWindow(count: 30, current: 15, maxVisible: 7), 12..<19)
    }

    func testWindowClampsToLeadingEdge() {
        // Near the start the window pins to the front rather than running off.
        XCTAssertEqual(compactPrintingDotWindow(count: 30, current: 0, maxVisible: 7), 0..<7)
        XCTAssertEqual(compactPrintingDotWindow(count: 30, current: 1, maxVisible: 7), 0..<7)
    }

    func testWindowClampsToTrailingEdge() {
        // Near the end the window pins to the back so the last dot stays visible.
        XCTAssertEqual(compactPrintingDotWindow(count: 30, current: 29, maxVisible: 7), 23..<30)
        XCTAssertEqual(compactPrintingDotWindow(count: 30, current: 28, maxVisible: 7), 23..<30)
    }

    func testWindowHandlesDegenerateInputs() {
        XCTAssertEqual(compactPrintingDotWindow(count: 0, current: 0, maxVisible: 7), 0..<0)
        XCTAssertEqual(compactPrintingDotWindow(count: 1, current: 0, maxVisible: 7), 0..<1)
        // An out-of-range current is clamped instead of crashing.
        XCTAssertEqual(compactPrintingDotWindow(count: 30, current: 99, maxVisible: 7), 23..<30)
    }

    func testCurrentDotIsLargest() {
        let window = compactPrintingDotWindow(count: 5, current: 2, maxVisible: 7)
        let current = compactPrintingDotDiameter(index: 2, current: 2, count: 5, window: window)
        let neighbour = compactPrintingDotDiameter(index: 1, current: 2, count: 5, window: window)
        XCTAssertGreaterThan(current, neighbour)
    }

    func testOutermostDotsShrinkOnlyWhenMoreArtIsHidden() {
        // A fully-visible strip keeps its edge dots full-sized.
        let fullWindow = compactPrintingDotWindow(count: 5, current: 0, maxVisible: 7)
        XCTAssertEqual(
            compactPrintingDotDiameter(index: 4, current: 0, count: 5, window: fullWindow), 6)

        // A windowed strip shrinks the edge dot on the side with hidden prints.
        let window = compactPrintingDotWindow(count: 30, current: 15, maxVisible: 7)
        XCTAssertEqual(
            compactPrintingDotDiameter(
                index: window.lowerBound, current: 15, count: 30, window: window), 4)
        XCTAssertEqual(
            compactPrintingDotDiameter(
                index: window.upperBound - 1, current: 15, count: 30, window: window), 4)
    }

    func testLeadingEdgeKeepsLeadingDotFullWhenAtStart() {
        // At the very start there is nothing hidden to the left, so the leading
        // dot stays full while the trailing edge still hints at more art.
        let window = compactPrintingDotWindow(count: 30, current: 0, maxVisible: 7)
        XCTAssertEqual(
            compactPrintingDotDiameter(index: 0, current: 0, count: 30, window: window), 8)
        XCTAssertEqual(
            compactPrintingDotDiameter(
                index: window.upperBound - 1, current: 0, count: 30, window: window), 4)
    }
}
