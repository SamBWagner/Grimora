@testable import GrimoraCore
import XCTest

final class ArchidektListImporterTests: XCTestCase {
    func testParserReadsArchidektTextExportMetadataAndCategories() {
        let result = ArchidektListParser.parse(
            """
            1x An Offer You Can't Refuse (snc) 51 *F* [Removal] ^Have,#37d67a^
            1x Blazing Firesinger // Seething Song (sos) 109 *F* [Ramp] ^Have,#37d67a^
            1x Prismari, the Inspiration (sos) 212 [Commander{top}] ^Have,#37d67a^
            1x Mindsplice Apparatus (one) 63 [Sideboard,Ramp] ^Have,#37d67a^
            1x Waltz of Rage (pdsk) 165p *F* [Sideboard,Sorcery] ^Have,#37d67a^
            not an archidekt card line
            """
        )

        XCTAssertEqual(result.cards.count, 5)
        XCTAssertEqual(result.skippedLines.count, 1)

        XCTAssertEqual(result.cards[0].quantity, 1)
        XCTAssertEqual(result.cards[0].name, "An Offer You Can't Refuse")
        XCTAssertEqual(result.cards[0].setCode, "snc")
        XCTAssertEqual(result.cards[0].collectorNumber, "51")
        XCTAssertEqual(result.cards[0].categories, ["Removal"])

        XCTAssertEqual(result.cards[1].name, "Blazing Firesinger // Seething Song")
        XCTAssertEqual(result.cards[2].categories, ["Commander"])
        XCTAssertEqual(result.cards[3].categories, ["Sideboard", "Ramp"])
        XCTAssertEqual(result.cards[4].collectorNumber, "165p")
    }

    func testParserSupportsQuantitiesAndDeckURLIDs() {
        let result = ArchidektListParser.parse("12x Island (sos) 274 [Land] ^Have,#37d67a^")

        XCTAssertEqual(result.cards.first?.quantity, 12)
        XCTAssertEqual(result.cards.first?.name, "Island")
        XCTAssertEqual(result.cards.first?.categories, ["Land"])
        XCTAssertEqual(
            ArchidektListParser.deckID(from: "https://archidekt.com/decks/21928855/knives_and_forks"),
            21_928_855
        )
        XCTAssertEqual(
            ArchidektListParser.deckID(from: "https://archidekt.com/api/decks/21928855/"),
            21_928_855
        )
        XCTAssertNil(ArchidektListParser.deckID(from: "12x Island (sos) 274"))
    }
}
