import XCTest

@testable import GrimoraUI

// D4a: dragging the price chart snaps the readout to the nearest day's reading.
// These cover the pure nearest-point policy that backs that scrub.
final class CardValueChartScrubTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(dayOffset: Int, price: Double) -> CardValueChartPoint {
        CardValueChartPoint(
            date: reference.addingTimeInterval(Double(dayOffset) * 86_400),
            price: price
        )
    }

    func testReturnsExactPointWhenScrubLandsOnAReading() {
        let points = [point(dayOffset: 0, price: 1), point(dayOffset: 1, price: 2)]
        let target = points[1].date

        XCTAssertEqual(nearestChartPoint(to: target, in: points), points[1])
    }

    func testSnapsToTheCloserOfTwoSurroundingReadings() {
        let points = [point(dayOffset: 0, price: 1), point(dayOffset: 10, price: 2)]
        // Two-thirds of the way toward the later reading.
        let between = reference.addingTimeInterval(6.5 * 86_400)

        XCTAssertEqual(nearestChartPoint(to: between, in: points), points[1])
    }

    func testClampsToTheEdgesBeyondTheDataRange() {
        let points = [
            point(dayOffset: 0, price: 1),
            point(dayOffset: 5, price: 2),
            point(dayOffset: 9, price: 3),
        ]

        XCTAssertEqual(
            nearestChartPoint(to: reference.addingTimeInterval(-100 * 86_400), in: points),
            points.first
        )
        XCTAssertEqual(
            nearestChartPoint(to: reference.addingTimeInterval(100 * 86_400), in: points),
            points.last
        )
    }

    func testReturnsNilForEmptyHistory() {
        XCTAssertNil(nearestChartPoint(to: reference, in: []))
    }
}
