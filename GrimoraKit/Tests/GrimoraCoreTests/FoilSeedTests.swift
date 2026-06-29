@testable import GrimoraCore
import XCTest

final class FoilSeedTests: XCTestCase {
    func testSeedIsDeterministicForSameID() {
        let a = FoilSeed(id: "abc-123")
        let b = FoilSeed(id: "abc-123")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.phaseOffset, b.phaseOffset)
        XCTAssertEqual(a.speed, b.speed)
        XCTAssertEqual(a.angle, b.angle)
    }

    func testDifferentIDsProduceDifferentSeeds() {
        // Neighbours in a grid must not shimmer in lockstep.
        let ids = ["alpha", "beta", "gamma", "delta", "epsilon"]
        let offsets = ids.map { FoilSeed(id: $0).phaseOffset }
        XCTAssertEqual(Set(offsets).count, offsets.count, "phase offsets should be distinct")
    }

    func testDerivedParametersStayInRange() {
        for id in ["", "a", "card-001", "very-long-card-identifier-9988", "🂡"] {
            let seed = FoilSeed(id: id)
            XCTAssertTrue((0..<1).contains(seed.phaseOffset), "phaseOffset out of range for \(id)")
            XCTAssertGreaterThanOrEqual(seed.speed, 0.7)
            XCTAssertLessThanOrEqual(seed.speed, 1.3)
            XCTAssertGreaterThanOrEqual(seed.angle, -.pi / 12 - 1e-9)
            XCTAssertLessThanOrEqual(seed.angle, .pi / 12 + 1e-9)
        }
    }
}
