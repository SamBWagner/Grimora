import GrimoraCore
import UniformTypeIdentifiers
import XCTest

@testable import GrimoraUI

final class CardShareContentTests: XCTestCase {
    func testBuildsScryfallURLFromPrinting() {
        let content = CardShareContent(
            card: card(setCode: "M3C", collectorNumber: "12a")
        )

        XCTAssertEqual(content.scryfallURL.absoluteString, "https://scryfall.com/card/m3c/12a")
    }

    func testEncodesScryfallURLPathSegments() {
        let content = CardShareContent(
            card: card(setCode: "T ST", collectorNumber: "12/13?")
        )

        XCTAssertEqual(content.scryfallURL.absoluteString, "https://scryfall.com/card/t%20st/12%2F13%3F")
    }

    func testBuildsImageShareItemFromExistingLocalJPEG() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("share.jpg")
        let imageData = Data([0xff, 0xd8, 0xff, 0xd9])
        try imageData.write(to: imageURL, options: .atomic)

        let content = CardShareContent(
            card: card(
                name: "Share Mage",
                setCode: "abc",
                collectorNumber: "42",
                largeImagePath: imageURL.path,
                largeImageURL: "https://example.test/remote-large.jpg"
            )
        )

        let shareItem = try XCTUnwrap(content.imageShareItem)
        XCTAssertEqual(shareItem.data, imageData)
        XCTAssertEqual(shareItem.contentType, .jpeg)
        XCTAssertEqual(shareItem.filename, "Share Mage ABC 42.jpeg")
    }

    func testBuildsImageShareItemFromFileURLStoredPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("share-file-url.png")
        let imageData = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        try imageData.write(to: imageURL, options: .atomic)

        let content = CardShareContent(
            card: card(largeImagePath: imageURL.absoluteString)
        )

        let shareItem = try XCTUnwrap(content.imageShareItem)
        XCTAssertEqual(shareItem.data, imageData)
        XCTAssertEqual(shareItem.contentType, .png)
        XCTAssertEqual(shareItem.filename, "Test Card TST 1.png")
    }

    func testImageShareItemDoesNotFallBackToRemoteImageWhenLocalPathIsUnavailable() {
        let content = CardShareContent(
            card: card(
                largeImagePath: "/tmp/missing-card-share-image.jpg",
                normalImageURL: "https://example.test/normal.jpg"
            )
        )

        XCTAssertNil(content.imageShareItem)
    }

    func testBuildsMarkdownDetailsForSingleFaceCard() {
        let content = CardShareContent(
            card: card(
                name: "Lightning Bolt",
                manaCost: "{R}",
                manaValue: 1,
                typeLine: "Instant",
                oracleText: "Lightning Bolt deals 3 damage to any target.",
                keywords: ["Flash"],
                flavorText: "The sparkmage smiled.",
                artist: "Christopher Rush",
                priceUSD: 1.25,
                priceEUR: 0.9,
                edhrecRank: 42,
                colors: ["R"],
                colorIdentity: ["R"],
                games: ["paper", "arena"],
                finishes: ["nonfoil"]
            )
        )

        XCTAssertEqual(
            content.detailsMarkdown,
            """
            # Lightning Bolt
            **Mana Cost:** {R}
            **Type:** Instant
            **Keywords:** Flash

            Lightning Bolt deals 3 damage to any target.

            _The sparkmage smiled._

            ## Printing
            - **Set:** Test Set (TST #1)
            - **Rarity:** Rare
            - **Released:** 2024-01-02
            - **Language:** EN
            - **Artist:** Christopher Rush
            - **Mana Value:** 1
            - **Colors:** R
            - **Color Identity:** R
            - **Games:** Paper, Arena
            - **Finishes:** Nonfoil
            - **Prices:** USD 1.25 | EUR 0.90 | TIX Unknown
            - **EDHREC:** 42
            - **Scryfall:** https://scryfall.com/card/tst/1
            """
        )
    }

    func testBuildsMarkdownDetailsForFacedCard() {
        let content = CardShareContent(
            card: card(
                name: "Day // Night",
                typeLine: "Sorcery // Creature",
                oracleText: "",
                faces: [
                    CardFaceRecord(
                        cardID: "card",
                        faceIndex: 0,
                        name: "Day",
                        typeLine: "Sorcery",
                        oracleText: "Draw a card."
                    ),
                    CardFaceRecord(
                        cardID: "card",
                        faceIndex: 1,
                        name: "Night",
                        typeLine: "Creature",
                        oracleText: "Flying"
                    )
                ]
            )
        )

        XCTAssertTrue(content.detailsMarkdown.contains("## Day\n**Type:** Sorcery\n\nDraw a card."))
        XCTAssertTrue(content.detailsMarkdown.contains("## Night\n**Type:** Creature\n\nFlying"))
    }

    private func card(
        id: String = "card",
        name: String = "Test Card",
        setCode: String = "tst",
        collectorNumber: String = "1",
        manaCost: String = "",
        manaValue: Double? = nil,
        typeLine: String = "Creature",
        oracleText: String = "Rules text.",
        keywords: [String] = [],
        flavorText: String? = nil,
        artist: String? = nil,
        priceUSD: Double? = nil,
        priceEUR: Double? = nil,
        priceTIX: Double? = nil,
        edhrecRank: Int? = nil,
        colors: [String] = [],
        colorIdentity: [String] = [],
        producedMana: [String] = [],
        games: [String] = [],
        finishes: [String] = [],
        largeImagePath: String? = nil,
        normalImageURL: String? = nil,
        largeImageURL: String? = nil,
        faces: [CardFaceRecord] = []
    ) -> CardRecord {
        CardRecord(
            id: id,
            name: name,
            language: "en",
            releasedAt: "2024-01-02",
            setCode: setCode,
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: collectorNumber,
            rarity: "rare",
            artist: artist,
            edhrecRank: edhrecRank,
            manaCost: manaCost,
            manaValue: manaValue,
            priceUSD: priceUSD,
            priceTIX: priceTIX,
            priceEUR: priceEUR,
            colorSortKey: 0,
            colors: colors,
            colorIdentity: colorIdentity,
            producedMana: producedMana,
            layout: faces.isEmpty ? "normal" : "split",
            typeLine: typeLine,
            oracleText: oracleText,
            keywords: keywords,
            flavorText: flavorText,
            games: games,
            finishes: finishes,
            largeImagePath: largeImagePath,
            normalImageURL: normalImageURL,
            largeImageURL: largeImageURL,
            faces: faces
        )
    }
}
