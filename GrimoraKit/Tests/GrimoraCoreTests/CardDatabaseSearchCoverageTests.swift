@testable import GrimoraCore
import XCTest

final class CardDatabaseSearchCoverageTests: XCTestCase {
    func testFunctionalTagSearchMatchesExactOracleIdentityBySlug() throws {
        let database = try functionalTagSearchDatabase()

        guard case .results(let cards, let totalCount) = try database.search(
            CardSearchRequest(text: "otag:draw-engine", printingDisplayMode: .all)
        ) else {
            return XCTFail("Expected functional-tag search results")
        }

        XCTAssertEqual(cards.map(\.id), ["draw-engine-card"])
        XCTAssertEqual(totalCount, 1)
    }

    func testFunctionalTagSearchMatchesQuotedLabel() throws {
        let database = try functionalTagSearchDatabase()

        guard case .results(let cards, let totalCount) = try database.search(
            CardSearchRequest(
                text: "oracletag:\"Repeatable Lifegain\"",
                printingDisplayMode: .all
            )
        ) else {
            return XCTFail("Expected quoted functional-tag search results")
        }

        XCTAssertEqual(cards.map(\.id), ["lifegain-card"])
        XCTAssertEqual(totalCount, 1)
    }

    func testFunctionalTagSearchMatchesAlias() throws {
        let database = try functionalTagSearchDatabase()

        guard case .results(let cards, let totalCount) = try database.search(
            CardSearchRequest(text: "function:\"Life Engine\"", printingDisplayMode: .all)
        ) else {
            return XCTFail("Expected aliased functional-tag search results")
        }

        XCTAssertEqual(cards.map(\.id), ["lifegain-card"])
        XCTAssertEqual(totalCount, 1)
    }

    func testFunctionalTagSearchIncludesDescendantTagMemberships() throws {
        let database = try functionalTagSearchDatabase()

        guard case .results(let cards, let totalCount) = try database.search(
            CardSearchRequest(text: "function:draw", printingDisplayMode: .all)
        ) else {
            return XCTFail("Expected hierarchy-expanded functional-tag search results")
        }

        XCTAssertEqual(cards.map(\.id), ["draw-card", "draw-engine-card"])
        XCTAssertEqual(totalCount, 2)
    }

    func testFunctionalTagSearchReportsUnknownTag() throws {
        let database = try functionalTagSearchDatabase()

        guard case .unsupported(let reason) = try database.search(
            CardSearchRequest(text: "otag:not-a-real-tag", printingDisplayMode: .all)
        ) else {
            return XCTFail("Expected an unknown functional-tag diagnostic")
        }

        XCTAssertEqual(reason.token, "otag:not-a-real-tag")
        XCTAssertEqual(reason.detail, "No offline functional tag matches “not-a-real-tag”.")
    }

    func testFunctionalTagSearchReportsCatalogWithoutSemanticData() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "plain-card", name: "Plain Card", typeLine: "Creature")
        ])

        guard case .unsupported(let reason) = try database.search(
            CardSearchRequest(text: "function:draw", printingDisplayMode: .all)
        ) else {
            return XCTFail("Expected a missing semantic-catalog diagnostic")
        }

        XCTAssertEqual(reason.token, "function:draw")
        XCTAssertEqual(
            reason.detail,
            "Functional-tag search is unavailable because this catalog does not include Oracle Tags."
        )
    }

    func testListFunctionalTagSearchReportsCatalogWithoutSemanticData() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "plain-card", name: "Plain Card", typeLine: "Creature")
        ])
        let list = try database.createCardCollection(named: "Searchable")
        try database.appendCard("plain-card", toList: list.id)

        guard case .unsupported(let listReason) = try database.searchCardCollectionEntries(
            forListID: list.id,
            text: "function:draw"
        ) else {
            return XCTFail("Expected a missing semantic-catalog collection diagnostic")
        }
        XCTAssertEqual(
            listReason.detail,
            "Functional-tag search is unavailable because this catalog does not include Oracle Tags."
        )

        guard case .unsupported(let crossListReason) = try database.searchAllCardCollectionEntries(
            text: "otag:draw"
        ) else {
            return XCTFail("Expected a missing semantic-catalog cross-list diagnostic")
        }
        XCTAssertEqual(
            crossListReason.detail,
            "Functional-tag search is unavailable because this catalog does not include Oracle Tags."
        )
    }

    func testAttachedCatalogFunctionalTagSearchUsesCatalogSemantics() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FunctionalTagAttachedCatalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let catalogURL = directory.appendingPathComponent("Catalog.sqlite")
        var catalog: CardDatabase? = try CardDatabase(storage: .file(catalogURL))
        try catalog?.replaceAllCards([
            testCard(
                id: "attached-draw-card",
                oracleID: "attached-oracle-draw",
                name: "Attached Draw",
                typeLine: "Instant"
            )
        ])
        try catalog?.replaceSemanticCatalog(
            with: SemanticCatalogSnapshot(
                tags: [
                    SemanticTagRecord(
                        id: "attached-tag-draw",
                        namespace: "oracle",
                        slug: "draw",
                        label: "Draw",
                        description: nil,
                        similarityEnabled: true,
                        source: "fixture"
                    )
                ],
                aliases: [],
                edges: [],
                cardTags: [
                    SemanticCardTagRecord(
                        cardKey: SemanticCardKey(
                            oracleID: "attached-oracle-draw",
                            printingID: "attached-draw-card"
                        ),
                        tagID: "attached-tag-draw",
                        weightMillis: 1_000,
                        annotation: nil,
                        source: "fixture"
                    )
                ],
                stats: [
                    SemanticTagStatsRecord(
                        tagID: "attached-tag-draw",
                        directCardCount: 1,
                        effectiveCardCount: 1,
                        inverseFrequencyMillis: 1_000
                    )
                ]
            )
        )
        try catalog?.prepareForCatalogDistribution()
        catalog = nil

        let database = try CardDatabase(
            userDatabaseURL: directory.appendingPathComponent("User.sqlite"),
            catalogURL: catalogURL
        )
        XCTAssertTrue(database.usesExternalCatalog)

        guard case .results(let cards, let totalCount) = try database.search(
            CardSearchRequest(text: "function:draw", printingDisplayMode: .all)
        ) else {
            return XCTFail("Expected attached-catalog functional-tag results")
        }
        XCTAssertEqual(cards.map(\.id), ["attached-draw-card"])
        XCTAssertEqual(totalCount, 1)
    }

    func testCollectionFunctionalTagSearchReportsUnknownTag() throws {
        let database = try functionalTagSearchDatabase()
        let list = try database.createCardCollection(named: "Searchable")
        try database.appendCard("draw-card", toList: list.id)

        guard case .unsupported(let reason) = try database.searchCardCollectionEntries(
            forListID: list.id,
            text: "otag:not-a-real-tag"
        ) else {
            return XCTFail("Expected an unknown collection functional-tag diagnostic")
        }

        XCTAssertEqual(reason.token, "otag:not-a-real-tag")
        XCTAssertEqual(reason.detail, "No offline functional tag matches “not-a-real-tag”.")
    }

    func testCrossListFunctionalTagSearchReportsUnknownTag() throws {
        let database = try functionalTagSearchDatabase()
        let list = try database.createCardCollection(named: "Searchable")
        try database.appendCard("draw-card", toList: list.id)

        guard case .unsupported(let reason) = try database.searchAllCardCollectionEntries(
            text: "function:not-a-real-tag"
        ) else {
            return XCTFail("Expected an unknown cross-list functional-tag diagnostic")
        }

        XCTAssertEqual(reason.token, "function:not-a-real-tag")
        XCTAssertEqual(reason.detail, "No offline functional tag matches “not-a-real-tag”.")
    }

    func testFunctionalTagSearchComposesWithAndOrAndNegation() throws {
        let database = try functionalTagSearchDatabase()

        guard case .results(let andCards, _) = try database.search(
            CardSearchRequest(text: "function:draw t:enchantment", printingDisplayMode: .all)
        ) else {
            return XCTFail("Expected functional-tag AND results")
        }
        XCTAssertEqual(andCards.map(\.id), ["draw-engine-card"])

        guard case .results(let orCards, _) = try database.search(
            CardSearchRequest(
                text: "otag:draw-engine OR function:\"Life Engine\"",
                printingDisplayMode: .all
            )
        ) else {
            return XCTFail("Expected functional-tag OR results")
        }
        XCTAssertEqual(orCards.map(\.id), ["draw-engine-card", "lifegain-card"])

        guard case .results(let negatedCards, _) = try database.search(
            CardSearchRequest(text: "function:draw -otag:draw-engine", printingDisplayMode: .all)
        ) else {
            return XCTFail("Expected negated functional-tag results")
        }
        XCTAssertEqual(negatedCards.map(\.id), ["draw-card"])
    }

    func testCollectionFunctionalTagSearchReturnsExactResults() throws {
        let database = try functionalTagSearchDatabase()
        let list = try database.createCardCollection(named: "Searchable")
        try database.appendCard("draw-card", toList: list.id)
        try database.appendCard("draw-engine-card", toList: list.id)
        try database.appendCard("lifegain-card", toList: list.id)

        guard case .results(let entries) = try database.searchCardCollectionEntries(
            forListID: list.id,
            text: "function:draw"
        ) else {
            return XCTFail("Expected collection functional-tag results")
        }
        XCTAssertEqual(entries.map(\.cardID), ["draw-card", "draw-engine-card"])

        guard case .results(let matches) = try database.searchAllCardCollectionEntries(
            text: "function:\"Life Engine\""
        ) else {
            return XCTFail("Expected cross-list functional-tag results")
        }
        XCTAssertEqual(matches.map(\.listID), [list.id])
        XCTAssertEqual(matches.first?.entries.map(\.cardID), ["lifegain-card"])
    }

    func testFunctionalTagSearchUsesOracleIdentityAndPrintingFallback() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(
                id: "oracle-printing-a",
                oracleID: "shared-oracle",
                name: "Shared Oracle",
                typeLine: "Creature"
            ),
            testCard(
                id: "oracle-printing-b",
                oracleID: "shared-oracle",
                name: "Shared Oracle",
                typeLine: "Creature"
            ),
            testCard(id: "printing-fallback", name: "Printing Fallback", typeLine: "Creature"),
        ])
        try database.replaceSemanticCatalog(
            with: SemanticCatalogSnapshot(
                tags: [
                    SemanticTagRecord(
                        id: "tag-draw",
                        namespace: "oracle",
                        slug: "draw",
                        label: "Draw",
                        description: nil,
                        similarityEnabled: true,
                        source: "fixture"
                    )
                ],
                aliases: [],
                edges: [],
                cardTags: [
                    SemanticCardTagRecord(
                        cardKey: SemanticCardKey(oracleID: "shared-oracle", printingID: "oracle-printing-a"),
                        tagID: "tag-draw",
                        weightMillis: 1_000,
                        annotation: nil,
                        source: "fixture"
                    ),
                    SemanticCardTagRecord(
                        cardKey: SemanticCardKey(oracleID: nil, printingID: "printing-fallback"),
                        tagID: "tag-draw",
                        weightMillis: 1_000,
                        annotation: nil,
                        source: "fixture"
                    ),
                ],
                stats: [
                    SemanticTagStatsRecord(
                        tagID: "tag-draw",
                        directCardCount: 2,
                        effectiveCardCount: 2,
                        inverseFrequencyMillis: 1_000
                    )
                ]
            )
        )

        guard case .results(let cards, let totalCount) = try database.search(
            CardSearchRequest(text: "function:draw", printingDisplayMode: .all)
        ) else {
            return XCTFail("Expected identity-aware functional-tag results")
        }

        XCTAssertEqual(cards.map(\.id), ["printing-fallback", "oracle-printing-a", "oracle-printing-b"])
        XCTAssertEqual(totalCount, 3)

        guard case .results(let preferredCards, let preferredTotalCount) = try database.search(
            CardSearchRequest(text: "function:draw")
        ) else {
            return XCTFail("Expected Oracle-deduplicated functional-tag results")
        }
        XCTAssertEqual(preferredCards.map(\.name), ["Printing Fallback", "Shared Oracle"])
        XCTAssertEqual(preferredTotalCount, 2)
    }

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

    func testCardCollectionEntrySearchUsesScryfallSyntaxWithinList() throws {
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

        let list = try database.createCardCollection(named: "Searchable")
        try database.appendCard("forest", toList: list.id)
        try database.appendCard("goblin", toList: list.id)
        try database.appendCard("blue", toList: list.id)

        guard case .results(let goblins) = try database.searchCardCollectionEntries(
            forListID: list.id,
            text: "t:goblin"
        ) else {
            return XCTFail("Expected goblin search results")
        }
        XCTAssertEqual(goblins.map(\.cardID), ["goblin"])

        guard case .results(let blueCards) = try database.searchCardCollectionEntries(
            forListID: list.id,
            text: "c=u"
        ) else {
            return XCTFail("Expected blue search results")
        }
        XCTAssertEqual(blueCards.map(\.cardID), ["blue"])
    }

    func testCardCollectionEntrySearchReturnsUnsupportedSyntaxReason() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "alpha", name: "Alpha Mage", typeLine: "Creature - Wizard")
        ])
        let list = try database.createCardCollection(named: "Searchable")
        try database.appendCard("alpha", toList: list.id)

        guard case .unsupported(let reason) = try database.searchCardCollectionEntries(
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

        let aggro = try database.createCardCollection(named: "Aggro")
        try database.appendCard("goblin", toList: aggro.id, quantity: 2)
        try database.appendCard("blue", toList: aggro.id)

        let control = try database.createCardCollection(named: "Control")
        try database.appendCard("blue", toList: control.id)

        let izzetDeck = try database.createCardCollection(named: "Izzet")
        try database.appendCard("izzet", toList: izzetDeck.id)

        guard case .results(let goblinMatches) = try database.searchAllCardCollectionEntries(text: "t:goblin") else {
            return XCTFail("Expected goblin matches")
        }
        XCTAssertEqual(goblinMatches.map(\.listID), [aggro.id])
        XCTAssertEqual(goblinMatches.first?.entries.map(\.cardID), ["goblin"])
        XCTAssertEqual(goblinMatches.first?.matchedCardQuantity, 2)

        guard case .results(let blueMatches) = try database.searchAllCardCollectionEntries(text: "c=u") else {
            return XCTFail("Expected blue matches")
        }
        XCTAssertEqual(Set(blueMatches.map(\.listID)), [aggro.id, control.id])
        XCTAssertEqual(
            blueMatches.first(where: { $0.listID == aggro.id })?.entries.map(\.cardID),
            ["blue"]
        )

        guard case .results(let izzetMatches) = try database.searchAllCardCollectionEntries(text: "ci=ur") else {
            return XCTFail("Expected izzet matches")
        }
        XCTAssertEqual(izzetMatches.map(\.listID), [izzetDeck.id])
    }

    func testCrossListSearchReturnsNoMatchesForBlankQuery() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "alpha", name: "Alpha Mage", typeLine: "Creature - Wizard")
        ])
        let list = try database.createCardCollection(named: "Searchable")
        try database.appendCard("alpha", toList: list.id)

        guard case .results(let matches) = try database.searchAllCardCollectionEntries(text: "   ") else {
            return XCTFail("Expected empty results for blank query")
        }
        XCTAssertTrue(matches.isEmpty)
    }

    func testCrossListSearchReturnsUnsupportedSyntaxReason() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "alpha", name: "Alpha Mage", typeLine: "Creature - Wizard")
        ])
        let list = try database.createCardCollection(named: "Searchable")
        try database.appendCard("alpha", toList: list.id)

        guard case .unsupported(let reason) = try database.searchAllCardCollectionEntries(text: "cube:vintage") else {
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
        let list = try database.createCardCollection(named: "Mixed")
        try database.appendCard("flyer", toList: list.id)
        try database.appendCard("grounded", toList: list.id)

        guard case .results(let matches) = try database.searchAllCardCollectionEntries(text: "o:/flying/") else {
            return XCTFail("Expected regex post-filter matches")
        }
        XCTAssertEqual(matches.map(\.listID), [list.id])
        XCTAssertEqual(matches.first?.entries.map(\.cardID), ["flyer"])
    }

    private func testCard(
        id: String,
        oracleID: String? = nil,
        name: String,
        colors: [String] = [],
        colorIdentity: [String] = [],
        typeLine: String,
        oracleText: String = ""
    ) -> CardRecord {
        CardRecord(
            id: id,
            oracleID: oracleID,
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

    private func functionalTagSearchDatabase() throws -> CardDatabase {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(
                id: "draw-card",
                oracleID: "oracle-draw",
                name: "Direct Draw",
                typeLine: "Instant"
            ),
            testCard(
                id: "draw-engine-card",
                oracleID: "oracle-draw-engine",
                name: "Draw Engine",
                typeLine: "Enchantment"
            ),
            testCard(
                id: "lifegain-card",
                oracleID: "oracle-lifegain",
                name: "Life Engine",
                typeLine: "Creature"
            ),
            testCard(
                id: "other-card",
                oracleID: "oracle-other",
                name: "Other Card",
                typeLine: "Creature"
            ),
        ])
        try database.replaceSemanticCatalog(
            with: SemanticCatalogSnapshot(
                tags: [
                    SemanticTagRecord(
                        id: "tag-draw",
                        namespace: "oracle",
                        slug: "draw",
                        label: "Draw",
                        description: nil,
                        similarityEnabled: true,
                        source: "fixture"
                    ),
                    SemanticTagRecord(
                        id: "tag-draw-engine",
                        namespace: "oracle",
                        slug: "draw-engine",
                        label: "Draw Engine",
                        description: nil,
                        similarityEnabled: true,
                        source: "fixture"
                    ),
                    SemanticTagRecord(
                        id: "tag-repeatable-lifegain",
                        namespace: "oracle",
                        slug: "repeatable-lifegain",
                        label: "Repeatable Lifegain",
                        description: nil,
                        similarityEnabled: true,
                        source: "fixture"
                    ),
                    SemanticTagRecord(
                        id: "tag-non-oracle-child",
                        namespace: "metadata",
                        slug: "non-oracle-child",
                        label: "Non-Oracle Child",
                        description: nil,
                        similarityEnabled: false,
                        source: "fixture"
                    ),
                ],
                aliases: [
                    SemanticTagAliasRecord(
                        tagID: "tag-repeatable-lifegain",
                        alias: "Life Engine",
                        aliasKey: SemanticTagAliasRecord.normalizedKey(for: "Life Engine")
                    )
                ],
                edges: [
                    SemanticTagEdgeRecord(
                        parentTagID: "tag-draw",
                        childTagID: "tag-draw-engine"
                    ),
                    SemanticTagEdgeRecord(
                        parentTagID: "tag-draw",
                        childTagID: "tag-non-oracle-child"
                    )
                ],
                cardTags: [
                    SemanticCardTagRecord(
                        cardKey: SemanticCardKey(oracleID: "oracle-draw", printingID: "draw-card"),
                        tagID: "tag-draw",
                        weightMillis: 1_000,
                        annotation: nil,
                        source: "fixture"
                    ),
                    SemanticCardTagRecord(
                        cardKey: SemanticCardKey(
                            oracleID: "oracle-draw-engine",
                            printingID: "draw-engine-card"
                        ),
                        tagID: "tag-draw-engine",
                        weightMillis: 1_000,
                        annotation: nil,
                        source: "fixture"
                    ),
                    SemanticCardTagRecord(
                        cardKey: SemanticCardKey(
                            oracleID: "oracle-lifegain",
                            printingID: "lifegain-card"
                        ),
                        tagID: "tag-repeatable-lifegain",
                        weightMillis: 1_000,
                        annotation: nil,
                        source: "fixture"
                    ),
                    SemanticCardTagRecord(
                        cardKey: SemanticCardKey(oracleID: "oracle-other", printingID: "other-card"),
                        tagID: "tag-non-oracle-child",
                        weightMillis: 1_000,
                        annotation: nil,
                        source: "fixture"
                    ),
                ],
                stats: [
                    SemanticTagStatsRecord(
                        tagID: "tag-draw",
                        directCardCount: 1,
                        effectiveCardCount: 2,
                        inverseFrequencyMillis: 1_000
                    ),
                    SemanticTagStatsRecord(
                        tagID: "tag-draw-engine",
                        directCardCount: 1,
                        effectiveCardCount: 1,
                        inverseFrequencyMillis: 1_000
                    ),
                    SemanticTagStatsRecord(
                        tagID: "tag-repeatable-lifegain",
                        directCardCount: 1,
                        effectiveCardCount: 1,
                        inverseFrequencyMillis: 1_000
                    ),
                    SemanticTagStatsRecord(
                        tagID: "tag-non-oracle-child",
                        directCardCount: 1,
                        effectiveCardCount: 1,
                        inverseFrequencyMillis: 0
                    ),
                ]
            )
        )
        return database
    }
}
