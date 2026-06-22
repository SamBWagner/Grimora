import CoreGraphics
import XCTest

@testable import GrimoraUI

final class CardArtClipRadiusTests: XCTestCase {
    func testUsesDesignRadiusWhenLargerThanProportional() {
        // Small grid thumbnail: the proportional radius (~3.8pt) is below the
        // caller's design radius, so the art keeps nesting inside its chrome.
        let radius = cardArtClipRadius(
            forShortSide: 96,
            minimumRadius: 8,
            fraction: 0.04
        )

        XCTAssertEqual(radius, 8, accuracy: 0.0001)
    }

    func testUsesProportionalRadiusWhenLargerThanDesignRadius() {
        // Large iPad detail art: the design radius (12) under-rounds and would
        // expose the scan corner, so the proportional radius takes over.
        let radius = cardArtClipRadius(
            forShortSide: 500,
            minimumRadius: 12,
            fraction: 0.04
        )

        XCTAssertEqual(radius, 20, accuracy: 0.0001)
    }

    func testProportionalRadiusExceedsScanCornerAcrossDisplaySizes() {
        // Modern scans put the white corner arc at ~0.029 of the short side. The
        // clip must always reach at least that far to remove the white fringe.
        let scanFraction: CGFloat = 0.029
        for shortSide in stride(from: CGFloat(96), through: 520, by: 32) {
            let radius = cardArtClipRadius(
                forShortSide: shortSide,
                minimumRadius: 0
            )

            XCTAssertGreaterThanOrEqual(
                radius,
                shortSide * scanFraction,
                "Clip radius must cover the scan corner at width \(shortSide)"
            )
        }
    }

    func testNonPositiveOrNonFiniteShortSideFallsBackToMinimum() {
        XCTAssertEqual(cardArtClipRadius(forShortSide: 0, minimumRadius: 8), 8, accuracy: 0.0001)
        XCTAssertEqual(cardArtClipRadius(forShortSide: -10, minimumRadius: 8), 8, accuracy: 0.0001)
        XCTAssertEqual(cardArtClipRadius(forShortSide: .nan, minimumRadius: 8), 8, accuracy: 0.0001)
        XCTAssertEqual(cardArtClipRadius(forShortSide: .infinity, minimumRadius: 8), 8, accuracy: 0.0001)
    }

    func testNegativeMinimumRadiusIsClampedToZero() {
        let radius = cardArtClipRadius(forShortSide: 0, minimumRadius: -4)

        XCTAssertEqual(radius, 0, accuracy: 0.0001)
    }

    func testClipShapeUsesShortSideForRadius() {
        // A wide rect (e.g. rotated/landscape art) must base its radius on the
        // short side, not the long one, so corners stay card-accurate.
        let shape = CardArtClipShape(minimumRadius: 0, radiusFraction: 0.04)
        let rect = CGRect(x: 0, y: 0, width: 300, height: 100)
        let path = shape.path(in: rect)

        // Radius = 100 * 0.04 = 4. A rounded rect of radius 4 leaves the corner
        // pixel (0,0) outside its filled area but keeps a mid-edge point.
        XCTAssertFalse(path.contains(CGPoint(x: 0, y: 0)))
        XCTAssertTrue(path.contains(CGPoint(x: 150, y: 50)))
    }
}
