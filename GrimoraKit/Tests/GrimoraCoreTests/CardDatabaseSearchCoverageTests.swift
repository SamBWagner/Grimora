@testable import GrimoraCore
import XCTest

final class CardDatabaseSearchCoverageTests: XCTestCase {
    func testDatabaseSearchCoversArtDisplayMode() throws {
        let database = try Fixtures.database()
        let response = try database.search(
            CardSearchRequest(text: "", printingDisplayMode: .art, limit: 10)
        )

        guard case .results(let cards, let totalCount) = response else {
            return XCTFail("Expected art search results")
        }
        XCTAssertFalse(cards.isEmpty)
        XCTAssertGreaterThan(totalCount, 0)
    }

    func testDatabasePrintingsFallbackUsesNameSortKey() throws {
        let database = try Fixtures.database()
        let card = CardRecord(
            id: "manual-alpha",
            name: "Alpha Forest",
            displayNameKey: "",
            setCode: "tst",
            setName: "Test",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "common",
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Creature",
            oracleText: ""
        )

        XCTAssertEqual(try database.printings(for: card).map(\.name), ["Alpha Forest"])
    }

    func testCardListEntrySearchUsesScryfallSyntaxWithinList() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(
                id: "goblin",
                name: "Goblin Guide",
                colors: ["R"],
                colorIdentity: ["R"],
                typeLine: "Creature - Goblin Scout"
            ),
            testCard(
                id: "blue",
                name: "Blue Adept",
                colors: ["U"],
                colorIdentity: ["U"],
                typeLine: "Creature - Wizard"
            ),
            testCard(
                id: "forest",
                name: "Patient Forest",
                colorIdentity: ["G"],
                typeLine: "Land - Forest"
            ),
            testCard(
                id: "off-list-goblin",
                name: "Off-List Goblin",
                colors: ["R"],
                colorIdentity: ["R"],
                typeLine: "Creature - Goblin"
            ),
        ])

        let list = try database.createCardList(named: "Searchable")
        try database.appendCard("forest", toList: list.id)
        try database.appendCard("goblin", toList: list.id)
        try database.appendCard("blue", toList: list.id)

        guard case .results(let goblins) = try database.searchCardListEntries(
            forListID: list.id,
            text: "t:goblin"
        ) else {
            return XCTFail("Expected goblin search results")
        }
        XCTAssertEqual(goblins.map(\.cardID), ["goblin"])

        guard case .results(let blueCards) = try database.searchCardListEntries(
            forListID: list.id,
            text: "c=u"
        ) else {
            return XCTFail("Expected blue search results")
        }
        XCTAssertEqual(blueCards.map(\.cardID), ["blue"])
    }

    func testCardListEntrySearchReturnsUnsupportedSyntaxReason() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "alpha", name: "Alpha Mage", typeLine: "Creature - Wizard")
        ])
        let list = try database.createCardList(named: "Searchable")
        try database.appendCard("alpha", toList: list.id)

        guard case .unsupported(let reason) = try database.searchCardListEntries(
            forListID: list.id,
            text: "cube:vintage"
        ) else {
            return XCTFail("Expected unsupported search response")
        }

        XCTAssertEqual(reason.token, "cube:vintage")
    }

    func testCrossListSearchSurfacesOnlyMatchingListsGroupedByList() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(
                id: "goblin",
                name: "Goblin Guide",
                colors: ["R"],
                colorIdentity: ["R"],
                typeLine: "Creature - Goblin Scout"
            ),
            testCard(
                id: "blue",
                name: "Blue Adept",
                colors: ["U"],
                colorIdentity: ["U"],
                typeLine: "Creature - Wizard"
            ),
            testCard(
                id: "izzet",
                name: "Izzet Spell",
                colors: ["U", "R"],
                colorIdentity: ["U", "R"],
                typeLine: "Instant"
            ),
        ])

        let aggro = try database.createCardList(named: "Aggro")
        try database.appendCard("goblin", toList: aggro.id, quantity: 2)
        try database.appendCard("blue", toList: aggro.id)

        let control = try database.createCardList(named: "Control")
        try database.appendCard("blue", toList: control.id)

        let izzetDeck = try database.createCardList(named: "Izzet")
        try database.appendCard("izzet", toList: izzetDeck.id)

        guard case .results(let goblinMatches) = try database.searchAllCardListEntries(text: "t:goblin") else {
            return XCTFail("Expected goblin matches")
        }
        XCTAssertEqual(goblinMatches.map(\.listID), [aggro.id])
        XCTAssertEqual(goblinMatches.first?.entries.map(\.cardID), ["goblin"])
        XCTAssertEqual(goblinMatches.first?.matchedCardQuantity, 2)

        guard case .results(let blueMatches) = try database.searchAllCardListEntries(text: "c=u") else {
            return XCTFail("Expected blue matches")
        }
        XCTAssertEqual(Set(blueMatches.map(\.listID)), [aggro.id, control.id])
        XCTAssertEqual(
            blueMatches.first(where: { $0.listID == aggro.id })?.entries.map(\.cardID),
            ["blue"]
        )

        guard case .results(let izzetMatches) = try database.searchAllCardListEntries(text: "ci=ur") else {
            return XCTFail("Expected izzet matches")
        }
        XCTAssertEqual(izzetMatches.map(\.listID), [izzetDeck.id])
    }

    func testCrossListSearchReturnsNoMatchesForBlankQuery() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "alpha", name: "Alpha Mage", typeLine: "Creature - Wizard")
        ])
        let list = try database.createCardList(named: "Searchable")
        try database.appendCard("alpha", toList: list.id)

        guard case .results(let matches) = try database.searchAllCardListEntries(text: "   ") else {
            return XCTFail("Expected empty results for blank query")
        }
        XCTAssertTrue(matches.isEmpty)
    }

    func testCrossListSearchReturnsUnsupportedSyntaxReason() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "alpha", name: "Alpha Mage", typeLine: "Creature - Wizard")
        ])
        let list = try database.createCardList(named: "Searchable")
        try database.appendCard("alpha", toList: list.id)

        guard case .unsupported(let reason) = try database.searchAllCardListEntries(text: "cube:vintage") else {
            return XCTFail("Expected unsupported response")
        }
        XCTAssertEqual(reason.token, "cube:vintage")
    }

    func testCrossListSearchAppliesRegexPostFilters() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(
                id: "flyer",
                name: "Sky Knight",
                typeLine: "Creature - Knight",
                oracleText: "Flying"
            ),
            testCard(
                id: "grounded",
                name: "Stone Golem",
                typeLine: "Artifact Creature - Golem",
                oracleText: "Defender"
            ),
        ])
        let list = try database.createCardList(named: "Mixed")
        try database.appendCard("flyer", toList: list.id)
        try database.appendCard("grounded", toList: list.id)

        guard case .results(let matches) = try database.searchAllCardListEntries(text: "o:/flying/") else {
            return XCTFail("Expected regex post-filter matches")
        }
        XCTAssertEqual(matches.map(\.listID), [list.id])
        XCTAssertEqual(matches.first?.entries.map(\.cardID), ["flyer"])
    }

    private func testCard(
        id: String,
        name: String,
        colors: [String] = [],
        colorIdentity: [String] = [],
        typeLine: String,
        oracleText: String = ""
    ) -> CardRecord {
        CardRecord(
            id: id,
            name: name,
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "common",
            colorSortKey: 0,
            colors: colors,
            colorIdentity: colorIdentity,
            layout: "normal",
            typeLine: typeLine,
            oracleText: oracleText
        )
    }
}
