@testable import GrimoraCore
import XCTest

final class CardRecordFinishTests: XCTestCase {
    private func card(
        finishes: [String],
        isFoil: Bool = false,
        isNonfoil: Bool = false
    ) -> CardRecord {
        CardRecord(
            id: "c",
            name: "Card",
            setCode: "set",
            setName: "Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Creature",
            oracleText: "",
            finishes: finishes,
            isFoil: isFoil,
            isNonfoil: isNonfoil
        )
    }

    func testFoilOnlyPrinting() {
        let c = card(finishes: ["foil"])
        XCTAssertTrue(c.supportsFoil)
        XCTAssertFalse(c.supportsNonfoil)
        XCTAssertTrue(c.isFoilOnly)
    }

    func testBothFinishesIsNotFoilOnly() {
        let c = card(finishes: ["nonfoil", "foil"])
        XCTAssertTrue(c.supportsFoil)
        XCTAssertTrue(c.supportsNonfoil)
        XCTAssertFalse(c.isFoilOnly)
    }

    func testNonfoilOnlyPrinting() {
        let c = card(finishes: ["nonfoil"])
        XCTAssertFalse(c.supportsFoil)
        XCTAssertTrue(c.supportsNonfoil)
        XCTAssertFalse(c.isFoilOnly)
    }

    func testEtchedOnlyIsNotFoilOnly() {
        // Etched isn't "foil" in the holographic-sheen sense; it must not lock the toggle on.
        let c = card(finishes: ["etched"])
        XCTAssertFalse(c.supportsFoil)
        XCTAssertFalse(c.supportsNonfoil)
        XCTAssertFalse(c.isFoilOnly)
    }

    func testLegacyBooleansDriveFinishWhenFinishesEmpty() {
        XCTAssertTrue(card(finishes: [], isFoil: true).isFoilOnly)
        XCTAssertFalse(card(finishes: [], isFoil: true, isNonfoil: true).isFoilOnly)
        // Unknown finish info (no array, no flags) is not treated as foil-only.
        XCTAssertFalse(card(finishes: []).isFoilOnly)
    }
}
