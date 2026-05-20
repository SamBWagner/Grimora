import GrimoraCore
@testable import GrimoraUI
import XCTest

final class CardListTextRowColorIdentityStyleTests: XCTestCase {
    func testColorlessCardsUseNeutralTint() {
        XCTAssertEqual(CardListTextRowColorIdentityStyle(card: nil), .colorless)
        XCTAssertEqual(CardListTextRowColorIdentityStyle(card: card(colorIdentity: [])), .colorless)
    }

    func testMonoColoredCardsUseTheirIdentityColor() {
        XCTAssertEqual(
            CardListTextRowColorIdentityStyle(card: card(colorIdentity: ["r"])),
            .mono("R")
        )
    }

    func testTwoColorCardsUseOrderedPairGradient() {
        XCTAssertEqual(
            CardListTextRowColorIdentityStyle(card: card(colorIdentity: ["G", "U"])),
            .pair("U", "G")
        )
    }

    func testThreeOrMoreColorCardsUseGold() {
        XCTAssertEqual(
            CardListTextRowColorIdentityStyle(card: card(colorIdentity: ["R", "G", "W"])),
            .gold
        )
    }

    func testDevoidCardsUseNeutralTintEvenWithColoredIdentity() {
        XCTAssertEqual(
            CardListTextRowColorIdentityStyle(
                card: card(colorIdentity: ["R"], keywords: ["Devoid"], oracleText: "This spell has no color.")
            ),
            .colorless
        )
        XCTAssertEqual(
            CardListTextRowColorIdentityStyle(
                card: card(colorIdentity: ["U"], oracleText: "Devoid\nDraw a card.")
            ),
            .colorless
        )
    }

    private func card(
        colorIdentity: [String],
        keywords: [String] = [],
        oracleText: String = "",
        faces: [CardFaceRecord] = []
    ) -> CardRecord {
        CardRecord(
            id: UUID().uuidString,
            name: "Test Card",
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            colorIdentity: colorIdentity,
            layout: "normal",
            typeLine: "Instant",
            oracleText: oracleText,
            keywords: keywords,
            faces: faces
        )
    }
}
