import GrimoraCore
import XCTest

@testable import GrimoraUI

final class PurchaseProviderTests: XCTestCase {
    func testMTGMateURLForSimpleName() {
        let url = PurchaseProvider.mtgMate.purchaseURL(card(name: "Brand"))
        XCTAssertEqual(url?.absoluteString, "https://www.mtgmate.com.au/cards/Brand")
    }

    func testMTGMateURLEncodesSpaces() {
        let url = PurchaseProvider.mtgMate.purchaseURL(card(name: "Lightning Bolt"))
        XCTAssertEqual(url?.absoluteString, "https://www.mtgmate.com.au/cards/Lightning%20Bolt")
    }

    func testMTGMateURLKeepsApostropheAndEncodesSpaces() {
        let url = PurchaseProvider.mtgMate.purchaseURL(card(name: "Urza's Saga"))
        XCTAssertEqual(url?.absoluteString, "https://www.mtgmate.com.au/cards/Urza's%20Saga")
    }

    func testMTGMateURLUsesFrontFaceForMultiFaceCard() {
        let url = PurchaseProvider.mtgMate.purchaseURL(
            card(
                name: "Brazen Borrower // Petty Theft",
                faces: [
                    CardFaceRecord(
                        cardID: "card",
                        faceIndex: 0,
                        name: "Brazen Borrower",
                        typeLine: "Creature — Faerie",
                        oracleText: ""
                    ),
                    CardFaceRecord(
                        cardID: "card",
                        faceIndex: 1,
                        name: "Petty Theft",
                        typeLine: "Instant — Adventure",
                        oracleText: ""
                    )
                ]
            )
        )

        XCTAssertEqual(url?.absoluteString, "https://www.mtgmate.com.au/cards/Brazen%20Borrower")
    }

    func testMTGMateURLSplitsNameWhenFacesMissing() {
        // Defensive: the name carries "//" but card_faces weren't decoded.
        let url = PurchaseProvider.mtgMate.purchaseURL(card(name: "Fire // Ice"))
        XCTAssertEqual(url?.absoluteString, "https://www.mtgmate.com.au/cards/Fire")
    }

    func testAllProvidersProduceURLForCard() {
        let sample = card(name: "Sol Ring")
        for provider in PurchaseProvider.all {
            XCTAssertNotNil(provider.purchaseURL(sample), "\(provider.id) should produce a URL")
        }
    }

    private func card(
        name: String,
        faces: [CardFaceRecord] = []
    ) -> CardRecord {
        CardRecord(
            id: "card",
            name: name,
            language: "en",
            releasedAt: "2024-01-02",
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            artist: nil,
            edhrecRank: nil,
            manaCost: "",
            manaValue: nil,
            priceUSD: nil,
            priceTIX: nil,
            priceEUR: nil,
            colorSortKey: 0,
            colors: [],
            colorIdentity: [],
            producedMana: [],
            layout: faces.isEmpty ? "normal" : "split",
            typeLine: "Creature",
            oracleText: "",
            keywords: [],
            flavorText: nil,
            games: [],
            finishes: [],
            largeImagePath: nil,
            normalImageURL: nil,
            largeImageURL: nil,
            faces: faces
        )
    }
}
