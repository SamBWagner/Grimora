@testable import GrimoraCore
import XCTest

final class CardFoilTreatmentTests: XCTestCase {
    func testMapsKnownPromoTokens() {
        XCTAssertEqual(CardFoilTreatment.from(promoTypes: ["halofoil"]), .halo)
        XCTAssertEqual(CardFoilTreatment.from(promoTypes: ["surgefoil", "universesbeyond", "foil"]), .surge)
        XCTAssertEqual(CardFoilTreatment.from(promoTypes: ["galaxyfoil", "boosterfun"]), .galaxy)
    }

    func testPriorityWhenMultipleFoilTokens() {
        // Cards can carry more than one foil-treatment token; the distinctive one wins.
        XCTAssertEqual(CardFoilTreatment.from(promoTypes: ["oilslick", "raisedfoil"]), .oilSlick)
    }

    func testReturnsNilForNoFoilToken() {
        XCTAssertNil(CardFoilTreatment.from(promoTypes: []))
        XCTAssertNil(CardFoilTreatment.from(promoTypes: ["showcase", "boosterfun"]))
    }

    func testPromoTypeTokensCoverEverySpecialTreatment() {
        // Every special case must have a token so search + identification stay in sync.
        let specialCases = CardFoilTreatment.allCases.filter(\.isSpecial)
        XCTAssertEqual(CardFoilTreatment.promoTypeTokens.count, specialCases.count)
        XCTAssertTrue(CardFoilTreatment.promoTypeTokens.contains("surgefoil"))
        XCTAssertTrue(CardFoilTreatment.promoTypeTokens.contains("halofoil"))
    }

    func testIsSpecialClassification() {
        XCTAssertFalse(CardFoilTreatment.none.isSpecial)
        XCTAssertFalse(CardFoilTreatment.standard.isSpecial)
        XCTAssertFalse(CardFoilTreatment.etched.isSpecial)
        XCTAssertTrue(CardFoilTreatment.halo.isSpecial)
    }

    func testDisplayNames() {
        XCTAssertEqual(CardFoilTreatment.none.displayName, "")
        XCTAssertEqual(CardFoilTreatment.standard.displayName, "Foil")
        XCTAssertEqual(CardFoilTreatment.etched.displayName, "Etched")
        XCTAssertEqual(CardFoilTreatment.halo.displayName, "Halo Foil")
        // Every special treatment must be labellable.
        for treatment in CardFoilTreatment.allCases where treatment.isSpecial {
            XCTAssertFalse(treatment.displayName.isEmpty, "\(treatment) needs a display name")
        }
    }
}
