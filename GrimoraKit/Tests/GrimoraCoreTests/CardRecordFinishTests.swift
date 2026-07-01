@testable import GrimoraCore
import XCTest

final class CardRecordFinishTests: XCTestCase {
    private func card(
        finishes: [String],
        promoTypes: [String] = [],
        frameEffects: [String] = [],
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
            promoTypes: promoTypes,
            frameEffects: frameEffects,
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

    // MARK: - Etched support

    func testSupportsEtchedFromFinishesArray() {
        XCTAssertTrue(card(finishes: ["nonfoil", "foil", "etched"]).supportsEtched)
        XCTAssertTrue(card(finishes: ["etched"]).supportsEtched)
        XCTAssertFalse(card(finishes: ["nonfoil", "foil"]).supportsEtched)
    }

    func testSupportsEtchedFromFrameEffects() {
        // Some sets carry etched as a frame effect rather than a finish.
        XCTAssertTrue(card(finishes: ["foil"], frameEffects: ["etched"]).supportsEtched)
    }

    // MARK: - Available finishes & default

    func testAvailableFinishesInDisplayOrder() {
        XCTAssertEqual(card(finishes: ["nonfoil", "foil", "etched"]).availableFinishes, [.normal, .foil, .etched])
        XCTAssertEqual(card(finishes: ["foil"]).availableFinishes, [.foil])
        XCTAssertEqual(card(finishes: ["nonfoil"]).availableFinishes, [.normal])
    }

    func testDefaultFinishPrefersSoleFinish() {
        XCTAssertEqual(card(finishes: ["foil"]).defaultFinish, .foil)
        XCTAssertEqual(card(finishes: ["etched"]).defaultFinish, .etched)
        XCTAssertEqual(card(finishes: ["nonfoil", "foil"]).defaultFinish, .normal)
        // Unknown finishes default to normal.
        XCTAssertEqual(card(finishes: []).defaultFinish, .normal)
    }

    // MARK: - Treatment resolution

    func testFoilTreatmentForSelectedFinish() {
        let mh2Wonder = card(finishes: ["nonfoil", "foil", "etched"])
        XCTAssertEqual(mh2Wonder.foilTreatment(for: .normal), CardFoilTreatment.none)
        XCTAssertEqual(mh2Wonder.foilTreatment(for: .etched), .etched)
        XCTAssertEqual(mh2Wonder.foilTreatment(for: .foil), .standard)
    }

    func testFoilTreatmentUsesSpecialPromoType() {
        let haloUtvara = card(finishes: ["foil"], promoTypes: ["halofoil"])
        XCTAssertEqual(haloUtvara.specialFoilTreatment, .halo)
        XCTAssertEqual(haloUtvara.foilTreatment(for: .foil), .halo)
        // Non-foil finish never renders a treatment, even for a special printing.
        XCTAssertEqual(haloUtvara.foilTreatment(for: .normal), CardFoilTreatment.none)
    }
}
