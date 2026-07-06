@testable import GrimoraCore
import XCTest

final class MTGCardTypeCategoryTests: XCTestCase {
    func testPrimaryTypePicksFirstRealTypeInReadingOrder() {
        XCTAssertEqual(primaryType("Legendary Enchantment Creature — God"), "Enchantment")
        XCTAssertEqual(primaryType("Artifact Creature — Golem"), "Artifact")
        XCTAssertEqual(primaryType("Battle — Siege"), "Battle")
        XCTAssertEqual(primaryType("Legendary Planeswalker — Teferi"), "Planeswalker")
        XCTAssertEqual(primaryType("Basic Snow Land — Island"), "Land")
        XCTAssertEqual(primaryType("Instant"), "Instant")
    }

    func testKindredAndSupertypesAreSkipped() {
        // Kindred/Tribal is a modifier, not the card's main type.
        XCTAssertEqual(primaryType("Kindred Sorcery — Elf"), "Sorcery")
        XCTAssertEqual(primaryType("Tribal Instant — Merfolk"), "Instant")
    }

    func testFrontFaceWinsForSplitAndModalCards() {
        XCTAssertEqual(primaryType("Instant // Land"), "Instant")
        XCTAssertEqual(primaryType("Sorcery // Sorcery"), "Sorcery")
    }

    func testUnrecognizedTypeLineReturnsNil() {
        XCTAssertNil(primaryType(""))
        XCTAssertNil(primaryType("— Just Subtypes"))
        XCTAssertNil(primaryType("Conspiracy"))
    }

    func testPrimaryTypeForCardFallsBackToFrontFace() {
        // No top-level type line: classify by the front face (Dawn = Sorcery).
        let mdfc = CardRecord(
            id: "mdfc",
            name: "Dawn // Dusk",
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            layout: "modal_dfc",
            typeLine: "",
            oracleText: "",
            faces: [
                CardFaceRecord(cardID: "mdfc", faceIndex: 0, name: "Dawn", typeLine: "Sorcery", oracleText: ""),
                CardFaceRecord(cardID: "mdfc", faceIndex: 1, name: "Dusk", typeLine: "Instant", oracleText: ""),
            ]
        )
        XCTAssertEqual(MTGCardTypeCategory.primaryType(for: mdfc), "Sorcery")
    }

    func testCategoryNamePluralization() {
        XCTAssertEqual(MTGCardTypeCategory.categoryName(forType: "Creature"), "Creatures")
        XCTAssertEqual(MTGCardTypeCategory.categoryName(forType: "Land"), "Lands")
        XCTAssertEqual(MTGCardTypeCategory.categoryName(forType: "Sorcery"), "Sorceries")
        XCTAssertEqual(MTGCardTypeCategory.categoryName(forType: "Enchantment"), "Enchantments")
    }

    func testCanonicalOrderPutsCreaturesFirstAndLandsLast() {
        let shuffled = ["Land", "Instant", "Creature", "Artifact", "Planeswalker"]
        let sorted = shuffled.sorted {
            MTGCardTypeCategory.canonicalIndex(forType: $0) < MTGCardTypeCategory.canonicalIndex(forType: $1)
        }
        XCTAssertEqual(sorted, ["Creature", "Planeswalker", "Instant", "Artifact", "Land"])
    }

    private func primaryType(_ typeLine: String) -> String? {
        MTGCardTypeCategory.primaryType(inTypeLine: typeLine)
    }
}
