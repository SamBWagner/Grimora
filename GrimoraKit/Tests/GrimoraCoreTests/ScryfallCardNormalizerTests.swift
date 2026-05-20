@testable import GrimoraCore
import XCTest

final class ScryfallCardNormalizerTests: XCTestCase {
    func testNormalizesCoreFieldsAndImages() throws {
        let cards = try JSONDecoder().decode([ScryfallCardDTO].self, from: Fixtures.defaultCardsJSON())
        let record = ScryfallCardNormalizer.normalize(
            cards[0],
            topLevelImages: LocalImagePair(
                normalPath: "/normal.jpg",
                largePath: "/large.jpg",
                artCropPath: "/art-crop.jpg"
            )
        )

        XCTAssertEqual(record.id, "json-alpha")
        XCTAssertEqual(record.collectorNumberNumber, 12)
        XCTAssertEqual(record.rarityRank, 1)
        XCTAssertEqual(record.colorSortKey, 4)
        XCTAssertEqual(record.powerValue, 2)
        XCTAssertEqual(record.toughnessValue, 3)
        XCTAssertEqual(record.priceUSD, 1.25)
        XCTAssertEqual(record.pennyRank, 456)
        XCTAssertEqual(record.mtgoID, 78901)
        XCTAssertEqual(record.keywords, ["reach"])
        XCTAssertEqual(record.producedMana, ["G"])
        XCTAssertEqual(record.legalities["commander"], "legal")
        XCTAssertEqual(record.games, ["arena", "paper"])
        XCTAssertEqual(record.finishes, ["nonfoil"])
        XCTAssertEqual(record.artistIDs, ["artist-fixture"])
        XCTAssertEqual(record.illustrationID, "illustration-fixture")
        XCTAssertEqual(record.flavorText, "Fixture flavor.")
        XCTAssertEqual(record.watermark, "simic")
        XCTAssertTrue(record.isBooster)
        XCTAssertTrue(record.isHighResolution)
        XCTAssertTrue(record.isNonfoil)
        XCTAssertFalse(record.isFoil)
        XCTAssertEqual(record.displayNameKey, "json forest")
        XCTAssertTrue(record.isBasePrinting)
        XCTAssertEqual(record.normalImagePath, "/normal.jpg")
        XCTAssertEqual(record.artCropImagePath, "/art-crop.jpg")
        XCTAssertEqual(record.smallImageURL, "https://cards.scryfall.io/small/front/a/a/json-alpha.jpg")
        XCTAssertEqual(record.artCropImageURL, "https://cards.scryfall.io/art_crop/front/a/a/json-alpha.jpg")
        XCTAssertTrue(record.isRealCard)
    }

    func testNormalizesFaceImagesAndFaceSearchText() throws {
        let cards = try JSONDecoder().decode([ScryfallCardDTO].self, from: Fixtures.defaultCardsJSON())
        let record = ScryfallCardNormalizer.normalize(
            cards[1],
            faceImages: [
                0: LocalImagePair(
                    normalPath: "/face-normal.jpg",
                    largePath: "/face-large.jpg",
                    artCropPath: "/face-art-crop.jpg"
                )
            ]
        )

        XCTAssertEqual(record.faces.count, 2)
        XCTAssertEqual(record.faces[0].normalImagePath, "/face-normal.jpg")
        XCTAssertEqual(record.faces[0].artCropImagePath, "/face-art-crop.jpg")
        XCTAssertEqual(record.faces[0].smallImageURL, "https://cards.scryfall.io/small/front/d/d/json-dawn.jpg")
        XCTAssertEqual(record.faces[0].artCropImageURL, "https://cards.scryfall.io/art_crop/front/d/d/json-dawn.jpg")
        XCTAssertTrue(record.searchText.contains("JSON Dawn"))
        XCTAssertTrue(record.searchText.contains("Destroy a card."))
    }

    func testImageURLPairDerivesArtCropForRecognizableScryfallURLs() throws {
        let normal = URL(string: "https://cards.scryfall.io/normal/front/a/a/json-alpha.jpg?123")!
        let pair = ImageURLPair(normal: normal, large: nil)
        XCTAssertEqual(
            pair.artCrop?.absoluteString,
            "https://cards.scryfall.io/art_crop/front/a/a/json-alpha.jpg?123"
        )

        let explicitArtCrop = URL(string: "https://images.example.test/custom-art.jpg")!
        let explicitPair = ImageURLPair(normal: normal, large: nil, artCrop: explicitArtCrop)
        XCTAssertEqual(explicitPair.artCrop, explicitArtCrop)

        let nonScryfall = ImageURLPair(normal: URL(string: "https://example.test/normal.jpg")!, large: nil)
        XCTAssertNil(nonScryfall.artCrop)
    }

    func testFlagsUniversesBeyondAlchemyAndRealCards() {
        let ub = ScryfallCardDTO(
            id: "ub",
            name: "UB",
            games: ["paper"],
            digital: false,
            oversized: false,
            setType: "expansion",
            promoTypes: ["universesbeyond"]
        )
        XCTAssertTrue(ScryfallCardNormalizer.normalize(ub).isUniversesBeyond)

        let triangle = ScryfallCardDTO(
            id: "triangle",
            name: "Triangle",
            games: ["paper"],
            digital: false,
            oversized: false,
            setType: "expansion",
            securityStamp: "triangle"
        )
        XCTAssertTrue(ScryfallCardNormalizer.normalize(triangle).isUniversesBeyond)

        let alchemy = ScryfallCardDTO(
            id: "alchemy",
            name: "Alchemy",
            games: ["arena"],
            digital: true,
            setType: "alchemy"
        )
        XCTAssertTrue(ScryfallCardNormalizer.normalize(alchemy).isAlchemy)
        XCTAssertFalse(ScryfallCardNormalizer.normalize(alchemy).isRealCard)

        let token = ScryfallCardDTO(
            id: "token",
            name: "Token",
            layout: "token",
            games: ["paper"],
            digital: false,
            setType: "token"
        )
        XCTAssertFalse(ScryfallCardNormalizer.normalize(token).isRealCard)
    }

    func testDisplayNameKeysAndBasePrintingFlags() {
        let reversible = ScryfallCardDTO(
            id: "reversible",
            name: "Sol Ring // Sol Ring",
            layout: "reversible_card",
            games: ["paper"],
            digital: false,
            setType: "box",
            cardFaces: [
                ScryfallCardFaceDTO(name: "Sol Ring", typeLine: "Artifact", oracleText: "{T}: Add {C}{C}.", imageURIs: nil),
                ScryfallCardFaceDTO(name: "Sol Ring", typeLine: "Artifact", oracleText: "{T}: Add {C}{C}.", imageURIs: nil)
            ]
        )
        let reversibleRecord = ScryfallCardNormalizer.normalize(reversible)
        XCTAssertEqual(reversibleRecord.displayNameKey, "sol ring")
        XCTAssertFalse(reversibleRecord.isBasePrinting)

        let prepare = ScryfallCardDTO(
            id: "prepare",
            name: "Emeritus of Conflict // Lightning Bolt",
            layout: "prepare",
            games: ["paper"],
            digital: false,
            setType: "expansion",
            cardFaces: [
                ScryfallCardFaceDTO(name: "Emeritus of Conflict", typeLine: "Creature", oracleText: "Prepare Lightning Bolt.", imageURIs: nil),
                ScryfallCardFaceDTO(name: "Lightning Bolt", typeLine: "Instant", oracleText: "Deal 3 damage.", imageURIs: nil)
            ]
        )
        let prepareRecord = ScryfallCardNormalizer.normalize(prepare)
        XCTAssertEqual(prepareRecord.displayNameKey, "emeritus of conflict")
        XCTAssertTrue(prepareRecord.isBasePrinting)

        let universeBeyond = ScryfallCardDTO(
            id: "ub",
            name: "Lightning Bolt",
            games: ["paper"],
            digital: false,
            setType: "expansion",
            promoTypes: ["universesbeyond"]
        )
        XCTAssertFalse(ScryfallCardNormalizer.normalize(universeBeyond).isBasePrinting)
    }

    func testNilSortValuesRemainNil() {
        XCTAssertNil(ScryfallCardNormalizer.numericValue("*"))
        XCTAssertNil(ScryfallCardNormalizer.numericValue("1+*"))
        XCTAssertNil(ScryfallCardNormalizer.numericValue("N/A"))
        XCTAssertNil(ScryfallCardNormalizer.price(nil))
        XCTAssertNil(ScryfallCardNormalizer.rarityRank(for: "special"))
    }

    func testSortHelperBranches() {
        XCTAssertEqual(ScryfallCardNormalizer.rarityRank(for: "common"), 0)
        XCTAssertEqual(ScryfallCardNormalizer.rarityRank(for: "mythic"), 3)
        XCTAssertEqual(ScryfallCardNormalizer.colorSortKey(colors: ["W"], colorIdentity: []), 0)
        XCTAssertEqual(ScryfallCardNormalizer.colorSortKey(colors: ["U"], colorIdentity: []), 1)
        XCTAssertEqual(ScryfallCardNormalizer.colorSortKey(colors: ["B"], colorIdentity: []), 2)
        XCTAssertEqual(ScryfallCardNormalizer.colorSortKey(colors: ["R"], colorIdentity: []), 3)
        XCTAssertEqual(ScryfallCardNormalizer.colorSortKey(colors: ["Q"], colorIdentity: []), 6)
        XCTAssertNil(ScryfallCardNormalizer.leadingInteger(in: "A-12"))
    }

    func testAlchemyAndRealCardBranchCoverage() {
        XCTAssertTrue(ScryfallCardNormalizer.isAlchemy(
            setType: "expansion",
            promoTypes: ["alchemy"],
            games: ["paper"],
            digital: false
        ))
        XCTAssertTrue(ScryfallCardNormalizer.isAlchemy(
            setType: "expansion",
            promoTypes: [],
            games: ["arena", "mtgo"],
            digital: true
        ))
        XCTAssertFalse(ScryfallCardNormalizer.isRealCard(
            games: ["paper"],
            digital: false,
            oversized: true,
            layout: "normal",
            setType: "expansion"
        ))
        XCTAssertFalse(ScryfallCardNormalizer.isRealCard(
            games: ["paper"],
            digital: false,
            oversized: false,
            layout: "normal",
            setType: "minigame"
        ))
    }
}
