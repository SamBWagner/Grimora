@testable import GrimoraCore
import XCTest

final class CardDatabaseTests: XCTestCase {
    func testBareSearchFindsNamesOnly() throws {
        let database = try Fixtures.database()

        XCTAssertEqual(try names(matching: "forest", database: database), ["Alpha Forest"])
        XCTAssertEqual(try names(matching: "mage", database: database), ["Beta Mage"])
        XCTAssertEqual(try names(matching: "wizard", database: database), [])
        XCTAssertEqual(try names(matching: "cafe", database: database), [])
        XCTAssertEqual(try names(matching: "shadow", database: database), [])
    }

    func testReplaceAllCardsReportsChunkedWriteProgress() throws {
        let database = try CardDatabase(storage: .inMemory)
        let records = (0..<1_001).map { index in
            preferredTestCard(
                id: "progress-\(index)",
                oracleID: "progress-oracle-\(index)",
                name: "Progress Card \(index)"
            )
        }
        var progressEvents: [CardDatabaseWriteProgress] = []

        try database.replaceAllCards(records) { progress in
            progressEvents.append(progress)
        }

        let writeEvents = progressEvents.filter { $0.phase == .writingCards }
        XCTAssertEqual(writeEvents.map(\.writtenCards), [1, 1_000, 1_001])
        XCTAssertEqual(writeEvents.map(\.totalCards), [1_001, 1_001, 1_001])
        XCTAssertEqual(writeEvents.last?.fraction ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(progressEvents.first?.phase, .preparingMetadata)
        XCTAssertTrue(progressEvents.contains { $0.phase == .resettingCachedLibrary })
        XCTAssertEqual(try database.cardCount(), 1_001)

        let clampedProgress = CardDatabaseWriteProgress(writtenCards: 1_005, totalCards: 1_001)
        XCTAssertEqual(clampedProgress.writtenCards, 1_001)
        XCTAssertEqual(clampedProgress.fraction, 1, accuracy: 0.001)
    }

    func testReplaceAllCardsClearsValueHistoryStagingBeforeCardRowsWhenPreservingValues() throws {
        let database = try CardDatabase(storage: .inMemory)
        let card = preferredTestCard(
            id: "value-card",
            oracleID: "value-oracle",
            name: "Value Card"
        )
        try database.replaceAllCards([card])
        _ = try database.replaceCardValueHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-01", version: "1.0.0"),
            mappingsByMTGJSONUUID: ["uuid-value": card.id]
        ) { writer in
            try writer.insert(
                cardID: card.id,
                provider: .tcgplayer,
                finish: .normal,
                date: "2026-05-01",
                price: 2.50
            )
            return 1
        }
        let job = try database.prepareValueHistoryBackgroundJob(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-02", version: "1.0.0"),
            cardDatabaseIdentity: try database.valueHistoryCardDatabaseIdentity()
        )
        _ = try database.stageCardValueHistory(
            jobID: job.id,
            mappingsByMTGJSONUUID: ["uuid-value": card.id]
        ) { writer in
            for date in ["2026-04-29", "2026-04-30", "2026-05-01"] {
                try writer.insert(
                    cardID: card.id,
                    provider: .tcgplayer,
                    finish: .normal,
                    date: date,
                    price: 2.00
                )
            }
            return 3
        }

        XCTAssertEqual(try rowCount(in: "staging_card_price_points", database: database), 3)
        XCTAssertEqual(try rowCount(in: "staging_card_value_mappings", database: database), 1)

        var progressEvents: [CardDatabaseWriteProgress] = []
        try database.replaceAllCards([card], preservesCardValueHistory: true) { progress in
            progressEvents.append(progress)
        }

        let resetEvents = progressEvents.filter { $0.phase == .resettingCachedLibrary }
        XCTAssertEqual(resetEvents.map(\.completedUnitCount), [0, 1, 2, 3, 4])
        XCTAssertEqual(resetEvents.map(\.totalUnitCount), [4, 4, 4, 4, 4])
        XCTAssertEqual(try rowCount(in: "staging_card_price_points", database: database), 0)
        XCTAssertEqual(try rowCount(in: "staging_card_value_mappings", database: database), 0)
        XCTAssertEqual(try database.incompleteValueHistoryBackgroundJob()?.id, job.id)
        XCTAssertEqual(try database.valueGuide(forCardID: card.id).entries.first?.currentPrice, 2.50)
        XCTAssertEqual(try database.cardCount(), 1)
    }

    func testBareSearchDoesNotIncludeCardsWhoseNonNameTextMatches() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(
                id: "krenko",
                oracleID: "krenko-oracle",
                name: "Krenko, Mob Boss",
                oracleText: "Create Goblins."
            ),
            preferredTestCard(
                id: "fervor",
                oracleID: "fervor-oracle",
                name: "Fervor",
                oracleText: "Krenko's mob attacks as though it had haste."
            ),
            preferredTestCard(
                id: "spear-spewer",
                oracleID: "spear-spewer-oracle",
                name: "Spear Spewer",
                oracleText: "This Goblin was part of Krenko's mob."
            )
        ])

        XCTAssertEqual(try names(matching: "Krenko, mob", database: database), ["Krenko, Mob Boss"])
        XCTAssertEqual(try names(matching: "Krenko, Mob Boss", database: database), ["Krenko, Mob Boss"])
    }

    func testExternalOnlySearchReturnsUnsupportedReasonWithoutQuerying() throws {
        let database = try Fixtures.database()
        let response = try database.search(CardSearchRequest(text: "cube:vintage"))

        guard case .unsupported(let reason) = response else {
            return XCTFail("Expected unsupported response")
        }
        XCTAssertEqual(reason.token, "cube:vintage")
    }

    func testCardLookupBySetCodeAndCollectorNumberPrefersEnglishPrint() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(
                id: "french-print",
                oracleID: "oracle-special",
                name: "Sort Special",
                language: "fr",
                setCode: "PDsk",
                collectorNumber: "165p"
            ),
            preferredTestCard(
                id: "english-print",
                oracleID: "oracle-special",
                name: "Special Spell",
                language: "en",
                setCode: "pdsk",
                collectorNumber: "165p"
            )
        ])

        let card = try XCTUnwrap(database.card(setCode: "PDSK", collectorNumber: "165P"))

        XCTAssertEqual(card.id, "english-print")
        XCTAssertEqual(card.name, "Special Spell")
    }

    func testDefaultSearchIncludesAllCardClassesAndExplicitSyntaxStillFilters() throws {
        let database = try Fixtures.database()

        let all = try names(matching: "", database: database)
        XCTAssertTrue(all.contains("Beyond Hero"))
        XCTAssertTrue(all.contains("Digital Conjurer"))
        XCTAssertTrue(all.contains("Soldier Token"))

        XCTAssertEqual(try names(matching: "is:universesbeyond", database: database), ["Beyond Hero"])
        XCTAssertEqual(try names(matching: "is:alchemy", database: database), ["Digital Conjurer"])

        let withoutUB = try names(matching: "prefer:notub", database: database)
        XCTAssertFalse(withoutUB.contains("Beyond Hero"))
        XCTAssertTrue(withoutUB.contains("Digital Conjurer"))
        XCTAssertTrue(withoutUB.contains("Soldier Token"))
    }

    func testScryfallSyntaxPredicatesSearchStoredBulkFields() throws {
        let database = try Fixtures.database()

        XCTAssertEqual(try names(matching: "c:g", database: database), ["Alpha Forest"])
        XCTAssertEqual(try names(matching: "t:wizard", database: database), ["Beta Mage"])
        XCTAssertEqual(try names(matching: "o:cafe", database: database), ["Alpha Forest"])
        XCTAssertEqual(try names(matching: "o:shadow", database: database), ["Daybreak // Nightfall"])
        XCTAssertEqual(try names(matching: "t:wizard o:draw kw:flying", database: database), ["Beta Mage"])
        XCTAssertEqual(try names(matching: "pow>tou", database: database), ["Beta Mage"])
        XCTAssertEqual(try names(matching: "r:mythic usd>=2 year=2021", database: database), ["Beta Mage"])
        XCTAssertEqual(try names(matching: "is:mdfc", database: database), ["Daybreak // Nightfall"])
        XCTAssertEqual(try names(matching: "include:extras t:token", database: database), ["Soldier Token"])
    }

    func testFirstPrintSearchUsesStoredReprintMetadataAcrossCardIdentityEdgeCases() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(
                id: "shared-first",
                oracleID: "shared-oracle",
                name: "Shared Spell",
                releasedAt: "2025-01-02",
                setCode: "ncc",
                collectorNumber: "1",
                isReprint: false
            ),
            preferredTestCard(
                id: "shared-reprint",
                oracleID: "shared-oracle",
                name: "Shared Spell",
                releasedAt: "2024-01-01",
                setCode: "ncc",
                collectorNumber: "2",
                isReprint: true
            ),
            preferredTestCard(
                id: "missing-oracle-first",
                oracleID: nil,
                name: "Nameless Spark",
                releasedAt: "2025-01-03",
                setCode: "ncc",
                collectorNumber: "3",
                isReprint: false
            ),
            preferredTestCard(
                id: "missing-oracle-reprint",
                oracleID: nil,
                name: "Nameless Spark",
                releasedAt: "2024-01-01",
                setCode: "ncc",
                collectorNumber: "4",
                isReprint: true
            ),
            preferredTestCard(
                id: "same-date-first",
                oracleID: "same-date-oracle",
                name: "Same Date Spell",
                releasedAt: "2024-06-01",
                setCode: "ncc",
                collectorNumber: "5",
                isReprint: false
            ),
            preferredTestCard(
                id: "same-date-reprint",
                oracleID: "same-date-oracle",
                name: "Same Date Spell",
                releasedAt: "2024-06-01",
                setCode: "ncc",
                collectorNumber: "6",
                isReprint: true
            ),
            preferredTestCard(
                id: "other-set-first",
                oracleID: "other-set-oracle",
                name: "Other Set Spell",
                setCode: "xyz",
                collectorNumber: "7",
                isReprint: false
            )
        ])

        XCTAssertEqual(
            Set(try cards(
                matching: "set:ncc is:first-print",
                database: database,
                printingDisplayMode: .all
            ).map(\.id)),
            Set(["shared-first", "missing-oracle-first", "same-date-first"])
        )
        XCTAssertEqual(
            Set(try cards(
                matching: "set:ncc -is:first-print",
                database: database,
                printingDisplayMode: .all
            ).map(\.id)),
            Set(["shared-reprint", "missing-oracle-reprint", "same-date-reprint"])
        )
    }

    func testSmartQuotedOracleSearchMatchesStoredText() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(
                id: "fervor",
                oracleID: "fervor-oracle",
                name: "Fervor",
                oracleText: "Creatures you control have haste."
            ),
            preferredTestCard(
                id: "swift-strike",
                oracleID: "swift-strike-oracle",
                name: "Swift Strike",
                oracleText: "Target creature gains haste until end of turn."
            )
        ])

        XCTAssertEqual(
            try names(
                matching: "o:\u{201C}creatures you control have haste\u{201D}",
                database: database
            ),
            ["Fervor"]
        )
    }

    func testCommanderIdentityAliasesMatchIdentitySearch() throws {
        let database = try Fixtures.database()

        assertNames(matching: "ci:g", matchNamesFor: "id:g", database: database)
        assertNames(matching: "commander:g", matchNamesFor: "identity:g", database: database)
        assertNames(matching: "ci<=wb", matchNamesFor: "id<=wb", database: database)
        assertNames(matching: "commander>=wb", matchNamesFor: "id>=wb", database: database)
    }

    func testCommanderIdentityColonMatchesCardsPlayableWithinIdentity() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(id: "colorless", oracleID: "colorless-oracle", name: "Colorless Spell"),
            preferredTestCard(id: "red", oracleID: "red-oracle", name: "Red Spell", colorIdentity: ["R"]),
            preferredTestCard(id: "green", oracleID: "green-oracle", name: "Green Spell", colorIdentity: ["G"]),
            preferredTestCard(id: "gruul", oracleID: "gruul-oracle", name: "Gruul Spell", colorIdentity: ["R", "G"]),
            preferredTestCard(id: "blue", oracleID: "blue-oracle", name: "Blue Spell", colorIdentity: ["U"])
        ])

        XCTAssertEqual(
            Set(try names(matching: "ci:rg", database: database)),
            Set(["Colorless Spell", "Green Spell", "Gruul Spell", "Red Spell"])
        )
        XCTAssertEqual(try names(matching: "ci=rg", database: database), ["Gruul Spell"])
        XCTAssertEqual(
            Set(try names(matching: "commander:gruul", database: database)),
            Set(["Colorless Spell", "Green Spell", "Gruul Spell", "Red Spell"])
        )
    }

    func testReportedGreenCommanderIdentitySearchMatchesCommanders() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(
                id: "green-commander",
                oracleID: "green-commander-oracle",
                name: "Green Commander",
                typeLine: "Legendary Creature",
                colorIdentity: ["G"]
            ),
            preferredTestCard(
                id: "colorless-commander",
                oracleID: "colorless-commander-oracle",
                name: "Colorless Commander",
                typeLine: "Artifact Creature",
                colorIdentity: [],
                oracleText: "This creature can be your commander."
            ),
            preferredTestCard(
                id: "green-noncommander",
                oracleID: "green-noncommander-oracle",
                name: "Green Spell",
                colorIdentity: ["G"]
            ),
            preferredTestCard(
                id: "red-commander",
                oracleID: "red-commander-oracle",
                name: "Red Commander",
                typeLine: "Legendary Creature",
                colorIdentity: ["R"]
            )
        ])

        XCTAssertEqual(
            Set(try names(matching: "ci:g is:commander", database: database)),
            Set(["Colorless Commander", "Green Commander"])
        )
    }

    func testLegalOperatorMatchesStoredFormatLegality() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(
                id: "commander",
                oracleID: "commander-oracle",
                name: "Commander Legal",
                legalities: ["commander": "legal", "pauper": "not_legal"]
            ),
            preferredTestCard(
                id: "pauper",
                oracleID: "pauper-oracle",
                name: "Pauper Legal",
                legalities: ["commander": "banned", "pauper": "legal"]
            )
        ])

        XCTAssertEqual(try names(matching: "legal:commander", database: database), ["Commander Legal"])
        XCTAssertEqual(try names(matching: "legal:pauper", database: database), ["Pauper Legal"])
        XCTAssertEqual(try names(matching: "legal:modern", database: database), [])
    }

    func testScryfallBooleanRegexAndExternalSyntax() throws {
        let database = try Fixtures.database()

        XCTAssertEqual(
            Set(try names(matching: "t:creature (kw:flying or o:cafe)", database: database)),
            Set(["Alpha Forest", "Beta Mage"])
        )
        XCTAssertEqual(try names(matching: "name:/^Beta/", database: database), ["Beta Mage"])
        XCTAssertEqual(try names(matching: "!\"Beta Mage\"", database: database), ["Beta Mage"])
    }

    func testRequestedBooleanGroupingCommanderIdentityAndManaValueSearch() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(
                id: "colorless-sorcery",
                oracleID: "colorless-sorcery-oracle",
                name: "Colorless Rite",
                typeLine: "Sorcery",
                manaValue: 0
            ),
            preferredTestCard(
                id: "red-creature",
                oracleID: "red-creature-oracle",
                name: "Red Beast",
                manaValue: 4,
                colorIdentity: ["R"]
            ),
            preferredTestCard(
                id: "green-sorcery",
                oracleID: "green-sorcery-oracle",
                name: "Green Rite",
                typeLine: "Sorcery",
                manaValue: 1,
                colorIdentity: ["G"]
            ),
            preferredTestCard(
                id: "gruul-creature",
                oracleID: "gruul-creature-oracle",
                name: "Red-Green Beast",
                manaValue: 3,
                colorIdentity: ["R", "G"]
            ),
            preferredTestCard(
                id: "blue-creature",
                oracleID: "blue-creature-oracle",
                name: "Blue Beast",
                manaValue: 2,
                colorIdentity: ["U"]
            ),
            preferredTestCard(
                id: "red-instant",
                oracleID: "red-instant-oracle",
                name: "Red Flash",
                typeLine: "Instant",
                manaValue: 1,
                colorIdentity: ["R"]
            ),
            preferredTestCard(
                id: "large-sorcery",
                oracleID: "large-sorcery-oracle",
                name: "Large Rite",
                typeLine: "Sorcery",
                manaValue: 5,
                colorIdentity: ["R"]
            )
        ])

        XCTAssertEqual(
            Set(try names(matching: "(t:creature or t:sorcery) ci:rg mv<5", database: database)),
            Set(["Colorless Rite", "Green Rite", "Red Beast", "Red-Green Beast"])
        )
    }

    func testSearchResponseIncludesTotalCountBeyondSQLLimit() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards(
            (0..<5).map { index in
                preferredTestCard(
                    id: "total-\(index)",
                    oracleID: "total-oracle-\(index)",
                    name: "Total Fixture \(index)"
                )
            }
        )

        let response = try database.search(
            CardSearchRequest(text: "total", limit: 2)
        )

        guard case .results(let cards, let totalCount) = response else {
            return XCTFail("Expected results")
        }
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(totalCount, 5)
    }

    func testSearchResponseOffsetsSQLBackedPages() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards(
            (0..<5).map { index in
                preferredTestCard(
                    id: "total-\(index)",
                    oracleID: "total-oracle-\(index)",
                    name: "Total Fixture \(index)"
                )
            }
        )

        let response = try database.search(
            CardSearchRequest(text: "total", offset: 2, limit: 2)
        )

        guard case .results(let cards, let totalCount) = response else {
            return XCTFail("Expected results")
        }
        XCTAssertEqual(cards.map(\.id), ["total-2", "total-3"])
        XCTAssertEqual(totalCount, 5)
    }

    func testSearchResponseIncludesTotalCountBeyondPostFilterLimit() throws {
        let database = try CardDatabase(storage: .inMemory)
        var records = (0..<4).map { index in
            preferredTestCard(
                id: "regex-\(index)",
                oracleID: "regex-oracle-\(index)",
                name: "Regex Fixture \(index)"
            )
        }
        records.append(
            preferredTestCard(
                id: "other",
                oracleID: "other-oracle",
                name: "Other Fixture"
            )
        )
        try database.replaceAllCards(records)

        let response = try database.search(
            CardSearchRequest(text: "name:/^Regex Fixture/", limit: 2)
        )

        guard case .results(let cards, let totalCount) = response else {
            return XCTFail("Expected results")
        }
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(totalCount, 4)
        XCTAssertTrue(cards.allSatisfy { $0.name.hasPrefix("Regex Fixture") })
    }

    func testSearchResponseOffsetsPostFilteredPages() throws {
        let database = try CardDatabase(storage: .inMemory)
        var records = (0..<4).map { index in
            preferredTestCard(
                id: "regex-\(index)",
                oracleID: "regex-oracle-\(index)",
                name: "Regex Fixture \(index)"
            )
        }
        records.append(
            preferredTestCard(
                id: "other",
                oracleID: "other-oracle",
                name: "Other Fixture"
            )
        )
        try database.replaceAllCards(records)

        let response = try database.search(
            CardSearchRequest(
                text: "name:/^Regex Fixture/",
                offset: 2,
                limit: 2
            )
        )

        guard case .results(let cards, let totalCount) = response else {
            return XCTFail("Expected results")
        }
        XCTAssertEqual(cards.map(\.id), ["regex-2", "regex-3"])
        XCTAssertEqual(totalCount, 4)
    }

    func testPreferredPrintingModeReturnsBestPrintingByDefault() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards(krenkoPrintings())

        let preferred = try cards(matching: "krenko", database: database)
        XCTAssertEqual(preferred.map(\.id), ["fdn"])

        let all = try cards(
            matching: "krenko",
            database: database,
            printingDisplayMode: .all
        )
        XCTAssertEqual(Set(all.map(\.id)), Set(["fdn", "pfdn", "rvr-regular", "rvr-boosterfun", "fr-newer"]))
    }

    func testPreferredPrintingFallsBackToNameWhenOracleIDIsMissing() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(id: "older", oracleID: nil, name: "Mystery Bolt", releasedAt: "2020-01-01"),
            preferredTestCard(id: "newer", oracleID: nil, name: "Mystery Bolt", releasedAt: "2024-01-01")
        ])

        let preferred = try cards(matching: "mystery bolt", database: database)
        XCTAssertEqual(preferred.map(\.id), ["newer"])
    }

    func testPreferredPrintingRanksRemoteImageAvailabilityWithinOtherwiseEqualPrints() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(id: "without-image", oracleID: "oracle", name: "Twin Bolt", releasedAt: "2024-01-01"),
            preferredTestCard(id: "with-image", oracleID: "oracle", name: "Twin Bolt", releasedAt: "2024-01-01", smallImageURL: "https://example.test/twin-small.jpg")
        ])

        let preferred = try cards(matching: "twin", database: database)
        XCTAssertEqual(preferred.map(\.id), ["with-image"])
    }

    func testPreferredPrintingUsesBaseDisplayNameAndLeavesOddPrintingsExplicit() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(
                id: "base-bolt",
                oracleID: "bolt-oracle",
                name: "Lightning Bolt",
                releasedAt: "2024-02-23",
                setCode: "clu",
                setType: "draft_innovation",
                collectorNumber: "141"
            ),
            preferredTestCard(
                id: "deadpool-bolt",
                oracleID: "bolt-oracle",
                name: "Lightning Bolt",
                releasedAt: "2026-04-01",
                setCode: "sld",
                setType: "box",
                collectorNumber: "IFIYW-2"
            ),
            preferredTestCard(
                id: "emeritus",
                oracleID: "emeritus-oracle",
                name: "Emeritus of Conflict // Lightning Bolt",
                releasedAt: "2026-04-24",
                setCode: "sos",
                collectorNumber: "113",
                layout: "prepare",
                faces: [
                    CardFaceRecord(
                        cardID: "emeritus",
                        faceIndex: 0,
                        name: "Emeritus of Conflict",
                        typeLine: "Creature — Human Wizard",
                        oracleText: "Prepare Lightning Bolt."
                    ),
                    CardFaceRecord(
                        cardID: "emeritus",
                        faceIndex: 1,
                        name: "Lightning Bolt",
                        typeLine: "Instant",
                        oracleText: "Lightning Bolt deals 3 damage to any target."
                    )
                ]
            )
        ])

        XCTAssertEqual(try cards(matching: "lightning bolt", database: database).map(\.id), ["base-bolt"])
        XCTAssertEqual(try cards(matching: "emeritus", database: database).map(\.id), ["emeritus"])
        XCTAssertEqual(try cards(matching: "lightning bolt prefer:atypical", database: database).map(\.id), ["deadpool-bolt"])
        XCTAssertEqual(try cards(matching: "lightning bolt is:atypical", database: database).map(\.id), ["deadpool-bolt"])
    }

    func testPreferredPrintingDeduplicatesReversibleCardsByDisplayName() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(
                id: "sol-ring-base",
                oracleID: "sol-ring-oracle",
                name: "Sol Ring",
                releasedAt: "2026-04-24",
                setCode: "soc",
                setType: "commander",
                collectorNumber: "128"
            ),
            preferredTestCard(
                id: "sol-ring-reversible",
                oracleID: nil,
                name: "Sol Ring // Sol Ring",
                releasedAt: "2026-04-01",
                setCode: "sld",
                setType: "box",
                collectorNumber: "IFIYW-5",
                layout: "reversible_card",
                faces: [
                    CardFaceRecord(cardID: "sol-ring-reversible", faceIndex: 0, name: "Sol Ring", typeLine: "Artifact", oracleText: "{T}: Add {C}{C}."),
                    CardFaceRecord(cardID: "sol-ring-reversible", faceIndex: 1, name: "Sol Ring", typeLine: "Artifact", oracleText: "{T}: Add {C}{C}.")
                ]
            ),
            preferredTestCard(
                id: "command-tower-base",
                oracleID: "command-tower-oracle",
                name: "Command Tower",
                releasedAt: "2026-04-24",
                setCode: "soc",
                setType: "commander",
                collectorNumber: "129"
            ),
            preferredTestCard(
                id: "command-tower-reversible",
                oracleID: nil,
                name: "Command Tower // Command Tower",
                releasedAt: "2023-11-17",
                setCode: "rex",
                setType: "eternal",
                collectorNumber: "26",
                isUniversesBeyond: true,
                isBoosterFun: true,
                layout: "reversible_card",
                faces: [
                    CardFaceRecord(cardID: "command-tower-reversible", faceIndex: 0, name: "Command Tower", typeLine: "Land", oracleText: "{T}: Add one mana."),
                    CardFaceRecord(cardID: "command-tower-reversible", faceIndex: 1, name: "Command Tower", typeLine: "Land", oracleText: "{T}: Add one mana.")
                ]
            )
        ])

        XCTAssertEqual(try cards(matching: "sol ring", database: database).map(\.id), ["sol-ring-base"])
        XCTAssertEqual(
            Set(try cards(matching: "sol ring", database: database, printingDisplayMode: .all).map(\.id)),
            Set(["sol-ring-base", "sol-ring-reversible"])
        )
        XCTAssertEqual(try cards(matching: "command tower", database: database).map(\.id), ["command-tower-base"])
    }

    func testPrintingsForCardReturnsSameDisplayNamePrintingsNewestFirst() throws {
        let database = try CardDatabase(storage: .inMemory)
        let selected = preferredTestCard(
            id: "older",
            oracleID: "shared-oracle",
            name: "Shared Spell",
            releasedAt: "2020-01-01",
            setCode: "old"
        )
        try database.replaceAllCards([
            selected,
            preferredTestCard(
                id: "newer",
                oracleID: "shared-oracle",
                name: "Shared Spell",
                releasedAt: "2024-01-01",
                setCode: "new"
            ),
            preferredTestCard(
                id: "undated",
                oracleID: "shared-oracle",
                name: "Shared Spell",
                releasedAt: nil,
                setCode: "zzz"
            ),
            preferredTestCard(
                id: "other",
                oracleID: "other-oracle",
                name: "Shared Spell",
                releasedAt: "2025-01-01",
                setCode: "oth"
            )
        ])

        let printings = try database.printings(for: selected)

        XCTAssertEqual(printings.map(\.id), ["other", "newer", "older", "undated"])
    }

    func testPrintingsForCardUsesDisplayNameWhenOracleIDIsMissing() throws {
        let database = try CardDatabase(storage: .inMemory)
        let selected = preferredTestCard(
            id: "missing-old",
            oracleID: nil,
            name: "Mystery Bolt",
            releasedAt: "2020-01-01"
        )
        try database.replaceAllCards([
            selected,
            preferredTestCard(
                id: "missing-new",
                oracleID: nil,
                name: "Mystery Bolt",
                releasedAt: "2024-01-01"
            ),
            preferredTestCard(
                id: "has-oracle",
                oracleID: "mystery-oracle",
                name: "Mystery Bolt",
                releasedAt: "2025-01-01"
            ),
            preferredTestCard(
                id: "other-name",
                oracleID: nil,
                name: "Other Bolt",
                releasedAt: "2025-01-01"
            )
        ])

        let printings = try database.printings(for: selected)

        XCTAssertEqual(printings.map(\.id), ["has-oracle", "missing-new", "missing-old"])
    }

    func testPrintingsForCardIncludesFaces() throws {
        let database = try CardDatabase(storage: .inMemory)
        let face = CardFaceRecord(
            cardID: "split",
            faceIndex: 0,
            name: "Split Face",
            typeLine: "Instant",
            oracleText: "Draw."
        )
        let selected = preferredTestCard(
            id: "split",
            oracleID: "split-oracle",
            name: "Split Spell",
            faces: [face]
        )
        try database.replaceAllCards([selected])

        let printings = try database.printings(for: selected)

        XCTAssertEqual(printings.first?.faces, [face])
    }

    func testSearchHydratesFacesForResultPage() throws {
        let database = try CardDatabase(storage: .inMemory)
        let firstFace = CardFaceRecord(
            cardID: "split-a",
            faceIndex: 0,
            name: "Split A Face",
            typeLine: "Instant",
            oracleText: "Draw."
        )
        let secondFace = CardFaceRecord(
            cardID: "split-b",
            faceIndex: 0,
            name: "Split B Face",
            typeLine: "Sorcery",
            oracleText: "Scry."
        )
        try database.replaceAllCards([
            preferredTestCard(id: "split-a", oracleID: "split-a", name: "Hydrated Fixture A", faces: [firstFace]),
            preferredTestCard(id: "split-b", oracleID: "split-b", name: "Hydrated Fixture B", faces: [secondFace])
        ])

        let response = try database.search(
            CardSearchRequest(text: "hydrated", limit: 2)
        )

        guard case .results(let cards, _) = response else {
            return XCTFail("Expected results")
        }
        XCTAssertEqual(cards.map(\.faces), [[firstFace], [secondFace]])
    }

    func testLibraryReadinessRequiresCardsAndManifestButNotStoredImages() throws {
        let database = try CardDatabase(storage: .inMemory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let imageURL = directory.appendingPathComponent("card.jpg")

        try database.replaceAllCards([
            preferredTestCard(id: "ready", oracleID: "oracle", name: "Ready Card", normalImagePath: imageURL.path)
        ])

        XCTAssertFalse(try database.isLibraryReady())
        try database.saveMetadataValue("2026-04-25T09:09:59.477+00:00", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        try database.saveMetadataValue(CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
        XCTAssertTrue(try database.isLibraryReady())
        XCTAssertEqual(try database.missingStoredImageCount(), 1)
    }

    func testDeletingCardDataPreservesUserLists() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(id: "listed", oracleID: "oracle", name: "Listed Card")
        ])
        try database.saveMetadataValue("old", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        try database.saveMetadataValue("https://example.test/default.json", forKey: MetadataKey.defaultCardsDownloadURI.rawValue)
        try database.saveMetadataValue(CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
        try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)
        let list = try database.createCardCollection(named: "Keep Me")
        let category = try database.createCardCollectionCategory(inList: list.id, named: "Ramp")
        try database.appendCard("listed", toList: list.id, categoryID: category.id, quantity: 2)

        try database.deleteAllCardsPreservingLists()

        XCTAssertEqual(try database.cardCount(), 0)
        XCTAssertNil(try database.metadataValue(forKey: MetadataKey.defaultCardsUpdatedAt.rawValue))
        XCTAssertNil(try database.metadataValue(forKey: MetadataKey.defaultCardsDownloadURI.rawValue))
        XCTAssertNil(try database.metadataValue(forKey: MetadataKey.searchSchemaVersion.rawValue))
        XCTAssertNil(try database.metadataValue(forKey: MetadataKey.requiredImagesCached.rawValue))
        XCTAssertEqual(try database.cardCollections().map(\.name), ["Keep Me"])
        XCTAssertEqual(try database.cardCollectionCategories(forListID: list.id).map(\.name), ["Ramp"])
        let entries = try database.cardCollectionEntries(forListID: list.id)
        XCTAssertEqual(entries.map(\.cardID), ["listed"])
        XCTAssertEqual(entries.map(\.quantity), [2])
        XCTAssertNil(entries.first?.card)
    }

    func testClearingStoredImagePathsPreservesCardsAndLists() throws {
        let database = try CardDatabase(storage: .inMemory)
        var card = preferredTestCard(
            id: "listed",
            oracleID: "oracle",
            name: "Listed Card",
            normalImagePath: "/tmp/card-normal.jpg"
        )
        card.artCropImagePath = "/tmp/card-art-crop.jpg"
        card.faces = [
            CardFaceRecord(
                cardID: "listed",
                faceIndex: 0,
                name: "Listed Face",
                typeLine: "Creature",
                oracleText: "",
                normalImagePath: "/tmp/face-normal.jpg",
                artCropImagePath: "/tmp/face-art-crop.jpg"
            )
        ]
        try database.replaceAllCards([card])
        try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)
        let list = try database.createCardCollection(named: "Keep Me")
        try database.appendCard("listed", toList: list.id)

        try database.clearStoredImagePaths()

        XCTAssertEqual(try database.cardCount(), 1)
        XCTAssertEqual(try database.metadataValue(forKey: MetadataKey.requiredImagesCached.rawValue), "false")
        XCTAssertEqual(try database.cardCollections().map(\.name), ["Keep Me"])
        let cards = try cards(matching: "listed", database: database)
        XCTAssertNil(cards.first?.normalImagePath)
        XCTAssertNil(cards.first?.artCropImagePath)
        XCTAssertNil(cards.first?.faces.first?.normalImagePath)
        XCTAssertNil(cards.first?.faces.first?.artCropImagePath)
        XCTAssertEqual(try database.cardCollectionEntries(forListID: list.id).map(\.cardID), ["listed"])
    }

    func testListEntriesPreserveOrderAndBatchHydrateEveryCard() throws {
        let database = try CardDatabase(storage: .inMemory)
        let cards = ["aaa", "bbb", "ccc"].map {
            preferredTestCard(id: $0, oracleID: "oracle-\($0)", name: $0.uppercased())
        }
        try database.replaceAllCards(cards)
        let list = try database.createCardCollection(named: "Order")
        try database.appendCard("aaa", toList: list.id)
        try database.appendCard("bbb", toList: list.id)
        try database.appendCard("ccc", toList: list.id)

        let entries = try database.cardCollectionEntries(forListID: list.id)
        XCTAssertEqual(entries.map(\.cardID), ["aaa", "bbb", "ccc"])
        XCTAssertEqual(entries.map(\.position), [0, 1, 2])
        XCTAssertEqual(entries.compactMap(\.card?.id), ["aaa", "bbb", "ccc"])
        XCTAssertEqual(entries.compactMap(\.card?.name), ["AAA", "BBB", "CCC"])
    }

    func testListEntriesHydrateCardFacesViaBatchPath() throws {
        let database = try CardDatabase(storage: .inMemory)
        var card = preferredTestCard(
            id: "dfc", oracleID: "oracle-dfc", name: "Double Face", layout: "transform")
        card.faces = [
            CardFaceRecord(cardID: "dfc", faceIndex: 0, name: "Front", typeLine: "Creature", oracleText: "Front."),
            CardFaceRecord(cardID: "dfc", faceIndex: 1, name: "Back", typeLine: "Creature", oracleText: "Back.")
        ]
        try database.replaceAllCards([card])
        let list = try database.createCardCollection(named: "DFCs")
        try database.appendCard("dfc", toList: list.id)

        let entries = try database.cardCollectionEntries(forListID: list.id)
        XCTAssertEqual(entries.first?.card?.faces.map(\.name), ["Front", "Back"])
        XCTAssertEqual(entries.first?.card?.faces.map(\.faceIndex), [0, 1])
    }

    func testListEntriesWithSameCardAcrossZonesEachReceiveTheCard() throws {
        let database = try CardDatabase(storage: .inMemory)
        let card = preferredTestCard(
            id: "dup", oracleID: "oracle-dup", name: "Duplicated", legalities: ["commander": "legal"])
        try database.replaceAllCards([card])
        let list = try database.createCardCollection(named: "Deck", ruleset: .commander)
        try database.appendCard("dup", toList: list.id, zone: .commander)
        try database.appendCard("dup", toList: list.id, zone: .mainboard)

        let entries = try database.cardCollectionEntries(forListID: list.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.cardID), ["dup", "dup"])
        XCTAssertEqual(entries.compactMap(\.card?.id), ["dup", "dup"])
    }

    func testListEntryWithUnknownCardYieldsNilCardAlongsideHydratedEntries() throws {
        let database = try CardDatabase(storage: .inMemory)
        let card = preferredTestCard(id: "known", oracleID: "oracle-known", name: "Known")
        try database.replaceAllCards([card])
        let list = try database.createCardCollection(named: "Mixed")
        try database.appendCard("known", toList: list.id)
        try database.appendCard("missing", toList: list.id)

        let entries = try database.cardCollectionEntries(forListID: list.id)
        XCTAssertEqual(entries.map(\.cardID), ["known", "missing"])
        XCTAssertEqual(entries.first(where: { $0.cardID == "known" })?.card?.id, "known")
        XCTAssertNil(entries.first(where: { $0.cardID == "missing" })?.card)
    }

    func testLargeListBatchHydrationCrossesChunkBoundary() throws {
        let database = try CardDatabase(storage: .inMemory)
        let cardCount = 1_000  // greater than the 900-id IN-clause chunk size in cardsByID(forIDs:)
        let cards = (0..<cardCount).map { index in
            preferredTestCard(
                id: String(format: "card-%04d", index),
                oracleID: "oracle-\(index)",
                name: "Card \(index)")
        }
        try database.replaceAllCards(cards)
        let list = try database.createCardCollection(named: "Big")
        for card in cards {
            try database.appendCard(card.id, toList: list.id)
        }

        let entries = try database.cardCollectionEntries(forListID: list.id)
        XCTAssertEqual(entries.count, cardCount)
        XCTAssertEqual(entries.compactMap(\.card).count, cardCount)
        XCTAssertEqual(entries.first?.card?.id, "card-0000")
        XCTAssertEqual(entries.last?.card?.id, String(format: "card-%04d", cardCount - 1))
    }

    func testArtworkVariantsAreStableAcrossRepeatedResolves() {
        let card = preferredTestCard(
            id: "art", oracleID: "oracle-art", name: "Arty", normalImagePath: "/tmp/art-normal.jpg")
        let first = CardArtworkPresentationResolver.variants(for: card)
        let second = CardArtworkPresentationResolver.variants(for: card)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func testArtworkVariantsRecomputeWhenImagePathChanges() {
        // Same card id, image backfilled later: the memo must not serve a stale, image-less result.
        let withoutImage = preferredTestCard(id: "backfill", oracleID: "oracle-backfill", name: "Backfill")
        let imagelessVariants = CardArtworkPresentationResolver.variants(for: withoutImage)

        let withImage = preferredTestCard(
            id: "backfill", oracleID: "oracle-backfill", name: "Backfill",
            normalImagePath: "/tmp/backfill-normal.jpg")
        let imageVariants = CardArtworkPresentationResolver.variants(for: withImage)

        XCTAssertNotEqual(imagelessVariants, imageVariants)
        XCTAssertEqual(imageVariants.first?.imagePath, "/tmp/backfill-normal.jpg")
    }

    func testExistingLibrarySchemaMigratesBeforeCreatingSearchIndexes() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Grimora.sqlite")
        defer {
            try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
        }

        do {
            let legacyDatabase = try SQLiteDatabase(storage: .file(databaseURL))
            try legacyDatabase.execute(
                """
                CREATE TABLE cards (
                    id TEXT PRIMARY KEY,
                    oracle_id TEXT,
                    name TEXT NOT NULL,
                    name_key TEXT NOT NULL,
                    lang TEXT,
                    released_at TEXT,
                    set_code TEXT NOT NULL,
                    set_name TEXT NOT NULL,
                    set_type TEXT NOT NULL,
                    collector_number TEXT NOT NULL,
                    collector_number_number INTEGER,
                    rarity TEXT NOT NULL,
                    rarity_rank INTEGER,
                    artist TEXT,
                    artist_key TEXT,
                    edhrec_rank INTEGER,
                    mana_value REAL,
                    power TEXT,
                    power_value REAL,
                    toughness TEXT,
                    toughness_value REAL,
                    price_usd REAL,
                    price_tix REAL,
                    price_eur REAL,
                    color_sort_key INTEGER NOT NULL,
                    layout TEXT NOT NULL,
                    type_line TEXT NOT NULL,
                    oracle_text TEXT NOT NULL,
                    is_universes_beyond INTEGER NOT NULL,
                    is_alchemy INTEGER NOT NULL,
                    is_real_card INTEGER NOT NULL,
                    is_promo INTEGER NOT NULL DEFAULT 0,
                    is_variation INTEGER NOT NULL DEFAULT 0,
                    is_booster_fun INTEGER NOT NULL DEFAULT 0,
                    small_image_path TEXT,
                    normal_image_path TEXT,
                    large_image_path TEXT,
                    small_image_url TEXT,
                    normal_image_url TEXT,
                    large_image_url TEXT
                )
                """)
            try legacyDatabase.execute(
                """
                INSERT INTO cards (
                    id, name, name_key, set_code, set_name, set_type,
                    collector_number, rarity, color_sort_key, layout, type_line,
                    oracle_text, is_universes_beyond, is_alchemy, is_real_card
                ) VALUES (
                    'legacy', 'Legacy Card', 'legacy card', 'old', 'Old Set', 'expansion',
                    '1', 'common', 6, 'normal', 'Creature', '', 0, 0, 1
                )
                """)
        }

        let database = try CardDatabase(storage: .file(databaseURL))
        XCTAssertFalse(try database.isLibraryReady())
        let migratedSQLite = try SQLiteDatabase(storage: .file(databaseURL))
        let cardColumns = try columnNames(in: "cards", database: migratedSQLite)
        XCTAssertTrue(cardColumns.contains("art_crop_image_path"))
        XCTAssertTrue(cardColumns.contains("art_crop_image_url"))
    }

    func testAllSortModesAreDeterministicAndPlaceNilLast() throws {
        let database = try Fixtures.database()

        let expectations: [SortMode: String] = [
            .name: "Alpha Forest",
            .releaseDate: "Daybreak // Nightfall",
            .setNumber: "Gamma Relic",
            .rarity: "Alpha Forest",
            .color: "Alpha Forest",
            .priceUSD: "Alpha Forest",
            .priceTIX: "Alpha Forest",
            .priceEUR: "Alpha Forest",
            .manaValue: "Alpha Forest",
            .power: "Alpha Forest",
            .toughness: "Alpha Forest",
            .artistName: "Beta Mage",
            .edhrecRank: "Beta Mage",
            .pennyRank: "Beta Mage"
        ]

        for (sort, expectedFirst) in expectations {
            let response = try database.search(CardSearchRequest(text: "", sortMode: sort, limit: 50))
            guard case .results(let cards, _) = response else {
                return XCTFail("Expected results for \(sort)")
            }
            XCTAssertEqual(cards.first?.name, expectedFirst, "Unexpected first card for \(sort)")
        }
    }

    func testMetadataCanBeSavedReadAndDeleted() throws {
        let database = try CardDatabase(storage: .inMemory)

        try database.saveMetadataValue("one", forKey: "sample")
        XCTAssertEqual(try database.metadataValue(forKey: "sample"), "one")

        try database.saveMetadataValue("two", forKey: "sample")
        XCTAssertEqual(try database.metadataValue(forKey: "sample"), "two")

        try database.saveMetadataValue(nil, forKey: "sample")
        XCTAssertNil(try database.metadataValue(forKey: "sample"))
    }

    func testImagePathsCanBeUpdatedAfterInitialImport() throws {
        let database = try CardDatabase(storage: .inMemory)
        var card = Fixtures.records().first!
        card.normalImagePath = nil
        card.largeImagePath = nil
        card.artCropImagePath = nil
        try database.replaceAllCards([card])

        card.normalImagePath = "/tmp/updated-normal.jpg"
        card.largeImagePath = "/tmp/updated-large.jpg"
        card.artCropImagePath = "/tmp/updated-art-crop.jpg"
        try database.updateImagePaths(for: card)

        let response = try database.search(CardSearchRequest(text: "forest"))
        guard case .results(let cards, _) = response else {
            return XCTFail("Expected results")
        }

        XCTAssertEqual(cards.first?.normalImagePath, "/tmp/updated-normal.jpg")
        XCTAssertEqual(cards.first?.largeImagePath, "/tmp/updated-large.jpg")
        XCTAssertEqual(cards.first?.artCropImagePath, "/tmp/updated-art-crop.jpg")
    }

    func testRemoteImageURLsArePersistedForCardsAndFaces() throws {
        let database = try CardDatabase(storage: .inMemory)
        let face = CardFaceRecord(
            cardID: "split",
            faceIndex: 0,
            name: "Split Face",
            typeLine: "Instant",
            oracleText: "Draw.",
            smallImageURL: "https://example.test/face-small.jpg",
            normalImageURL: "https://example.test/face-normal.jpg",
            artCropImageURL: "https://example.test/face-art-crop.jpg"
        )
        let card = CardRecord(
            id: "split",
            oracleID: "split-oracle",
            name: "Split Card",
            releasedAt: "2024-01-01",
            setCode: "set",
            setName: "Set",
            setType: "expansion",
            collectorNumber: "1",
            collectorNumberNumber: 1,
            rarity: "rare",
            rarityRank: 2,
            colorSortKey: 0,
            layout: "split",
            typeLine: "Instant",
            oracleText: "Draw.",
            smallImageURL: "https://example.test/card-small.jpg",
            normalImageURL: "https://example.test/card-normal.jpg",
            artCropImageURL: "https://example.test/card-art-crop.jpg",
            faces: [face]
        )
        try database.replaceAllCards([card])

        let stored = try cards(matching: "split", database: database).first
        XCTAssertEqual(stored?.smallImageURL, "https://example.test/card-small.jpg")
        XCTAssertEqual(stored?.artCropImageURL, "https://example.test/card-art-crop.jpg")
        XCTAssertEqual(stored?.faces.first?.smallImageURL, "https://example.test/face-small.jpg")
        XCTAssertEqual(stored?.faces.first?.artCropImageURL, "https://example.test/face-art-crop.jpg")
    }

    func testMTGOIDIsPersistedForCards() throws {
        let database = try CardDatabase(storage: .inMemory)
        var card = Fixtures.records().first!
        card.mtgoID = 12345
        try database.replaceAllCards([card])

        let stored = try cards(matching: card.name, database: database).first
        XCTAssertEqual(stored?.mtgoID, 12345)
    }

    func testCardCollectionsPersistExactPrintQuantitiesInInsertionOrder() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("lists.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let oldPrinting = preferredTestCard(
            id: "krenko-old",
            oracleID: "krenko-oracle",
            name: "Krenko, Mob Boss",
            releasedAt: "2020-01-01",
            setCode: "old"
        )
        let newPrinting = preferredTestCard(
            id: "krenko-new",
            oracleID: "krenko-oracle",
            name: "Krenko, Mob Boss",
            releasedAt: "2024-01-01",
            setCode: "new"
        )
        try database.replaceAllCards([oldPrinting, newPrinting])

        XCTAssertThrowsError(try database.createCardCollection(named: "   "))

        let list = try database.createCardCollection(
            named: "  Commander Maybes  ",
            now: Date(timeIntervalSince1970: 10)
        )
        XCTAssertEqual(list.name, "Commander Maybes")
        XCTAssertEqual(list.entryCount, 0)

        let first = try database.appendCard(oldPrinting.id, toList: list.id, now: Date(timeIntervalSince1970: 11))
        let second = try database.appendCard(newPrinting.id, toList: list.id, now: Date(timeIntervalSince1970: 12))
        let third = try database.appendCard(oldPrinting.id, toList: list.id, now: Date(timeIntervalSince1970: 13))
        XCTAssertEqual(first.id, third.id)
        XCTAssertEqual(third.quantity, 2)

        let entries = try database.cardCollectionEntries(forListID: list.id)
        XCTAssertEqual(entries.map(\.cardID), ["krenko-old", "krenko-new"])
        XCTAssertEqual(entries.map(\.quantity), [2, 1])
        XCTAssertEqual(entries.map(\.position), [0, 1])
        XCTAssertEqual(entries.compactMap(\.card?.id), ["krenko-old", "krenko-new"])
        XCTAssertEqual(try database.cardCollections().first?.entryCount, 3)

        let renamed = try database.renameCardCollection(
            id: list.id,
            to: "Krenko Box",
            now: Date(timeIntervalSince1970: 14)
        )
        XCTAssertEqual(renamed.name, "Krenko Box")

        let reopened = try CardDatabase(storage: .file(databaseURL))
        XCTAssertEqual(try reopened.cardCollections().map(\.name), ["Krenko Box"])
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.cardID), ["krenko-old", "krenko-new"])
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.quantity), [2, 1])

        try reopened.removeCardCollectionEntry(id: second.id)
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.cardID), ["krenko-old"])
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.quantity), [2])
        XCTAssertEqual(try reopened.cardCollection(id: list.id)?.entryCount, 2)

        try reopened.removeCardCollectionEntry(id: first.id)
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.cardID), ["krenko-old"])
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.quantity), [1])
        XCTAssertEqual(try reopened.cardCollection(id: list.id)?.entryCount, 1)

        try reopened.deleteCardCollection(id: list.id)
        XCTAssertTrue(try reopened.cardCollections().isEmpty)
        XCTAssertTrue(try reopened.cardCollectionEntries(forListID: list.id).isEmpty)
    }

    func testCardCollectionSnapshotRestoresListsCategoriesEntriesAndQuantities() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            preferredTestCard(id: "forest", oracleID: "forest-oracle", name: "Alpha Forest"),
            preferredTestCard(id: "mage", oracleID: "mage-oracle", name: "Beta Mage")
        ])

        let list = try database.createCardCollection(named: "Drafts", now: Date(timeIntervalSince1970: 10))
        let ramp = try database.createCardCollectionCategory(
            inList: list.id,
            named: "Ramp",
            now: Date(timeIntervalSince1970: 11)
        )
        let forest = try database.appendCard("forest", toList: list.id, categoryID: ramp.id, quantity: 2)
        try database.appendCard("mage", toList: list.id)
        try database.setCardCollectionDisplaySort(id: list.id, mode: .edhrecRank, direction: .descending)
        let snapshot = try database.cardCollectionLibrarySnapshot()

        try database.incrementCardCollectionEntryQuantity(id: forest.id)
        try database.removeCardCollectionEntryCompletely(id: forest.id)
        try database.renameCardCollection(id: list.id, to: "Changed")
        try database.setCardCollectionDisplaySort(id: list.id, mode: nil, direction: .ascending)
        try database.restoreCardCollectionLibrarySnapshot(snapshot)

        XCTAssertEqual(try database.cardCollections().map(\.name), ["Drafts"])
        XCTAssertEqual(try database.cardCollection(id: list.id)?.displaySortMode, .edhrecRank)
        XCTAssertEqual(try database.cardCollection(id: list.id)?.displaySortDirection, .descending)
        XCTAssertEqual(try database.cardCollectionCategories(forListID: list.id).map(\.name), ["Ramp"])
        XCTAssertEqual(try database.cardCollectionEntries(forListID: list.id).map(\.cardID), ["forest", "mage"])
        XCTAssertEqual(try database.cardCollectionEntries(forListID: list.id).map(\.quantity), [2, 1])
        XCTAssertEqual(try database.cardCollectionEntries(forListID: list.id).first?.categoryID, ramp.id)
    }

    func testCardCollectionEntryPrintReplacementPersistsAndMergesQuantities() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionPrintReplacementTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("list-printing.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let oldPrinting = preferredTestCard(
            id: "krenko-old",
            oracleID: "krenko-oracle",
            name: "Krenko, Mob Boss",
            releasedAt: "2020-01-01",
            setCode: "old"
        )
        let newPrinting = preferredTestCard(
            id: "krenko-new",
            oracleID: "krenko-oracle",
            name: "Krenko, Mob Boss",
            releasedAt: "2024-01-01",
            setCode: "new"
        )
        let promoPrinting = preferredTestCard(
            id: "krenko-promo",
            oracleID: "krenko-oracle",
            name: "Krenko, Mob Boss",
            releasedAt: "2022-01-01",
            setCode: "prm"
        )
        try database.replaceAllCards([oldPrinting, newPrinting, promoPrinting])

        let list = try database.createCardCollection(named: "Commander Maybes")
        let oldEntry = try database.appendCard(oldPrinting.id, toList: list.id, quantity: 2)
        let newEntry = try database.appendCard(newPrinting.id, toList: list.id)

        let replaced = try database.replaceCardCollectionEntryPrint(
            id: oldEntry.id,
            withCardID: promoPrinting.id,
            now: Date(timeIntervalSince1970: 20)
        )
        XCTAssertEqual(replaced.id, oldEntry.id)
        XCTAssertEqual(replaced.cardID, promoPrinting.id)
        XCTAssertEqual(replaced.quantity, 2)
        XCTAssertEqual(replaced.card?.id, promoPrinting.id)
        XCTAssertEqual(try database.cardCollectionEntries(forListID: list.id).map(\.cardID), ["krenko-promo", "krenko-new"])
        XCTAssertEqual(try database.cardCollectionEntries(forListID: list.id).map(\.quantity), [2, 1])

        let reopened = try CardDatabase(storage: .file(databaseURL))
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.cardID), ["krenko-promo", "krenko-new"])

        let merged = try reopened.replaceCardCollectionEntryPrint(id: oldEntry.id, withCardID: newPrinting.id)
        XCTAssertEqual(merged.id, newEntry.id)
        XCTAssertEqual(merged.cardID, newPrinting.id)
        XCTAssertEqual(merged.quantity, 3)
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.cardID), ["krenko-new"])
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.quantity), [3])
        XCTAssertEqual(try reopened.cardCollection(id: list.id)?.entryCount, 3)
    }

    func testCardCollectionPinningPersistsPinnedStateAndTimestamp() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionPinningTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("pinned-lists.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardCollection(named: "Pinned Deck", now: Date(timeIntervalSince1970: 10))

        let pinned = try database.setCardCollectionPinned(
            id: list.id,
            isPinned: true,
            now: Date(timeIntervalSince1970: 20)
        )
        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(pinned.pinnedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(pinned.position, 0)

        let reopened = try CardDatabase(storage: .file(databaseURL))
        let persisted = try XCTUnwrap(reopened.cardCollection(id: list.id))
        XCTAssertTrue(persisted.isPinned)
        XCTAssertEqual(persisted.pinnedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(persisted.position, 0)

        let unpinned = try reopened.setCardCollectionPinned(
            id: list.id,
            isPinned: false,
            now: Date(timeIntervalSince1970: 30)
        )
        XCTAssertFalse(unpinned.isPinned)
        XCTAssertNil(unpinned.pinnedAt)
        XCTAssertEqual(unpinned.position, 0)
    }

    func testCardCollectionOrderingPersistsAndMovesAcrossPinnedSections() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionOrderingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("ordered-lists.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let first = try database.createCardCollection(named: "First", now: Date(timeIntervalSince1970: 10))
        let second = try database.createCardCollection(named: "Second", now: Date(timeIntervalSince1970: 20))
        let third = try database.createCardCollection(named: "Third", now: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(try database.cardCollections().map(\.name), ["First", "Second", "Third"])
        XCTAssertEqual(try database.cardCollections().map(\.position), [0, 1, 2])

        try database.moveCardCollection(id: third.id, toPosition: 0, now: Date(timeIntervalSince1970: 40))
        XCTAssertEqual(try database.cardCollections().map(\.name), ["Third", "First", "Second"])
        XCTAssertEqual(try database.cardCollections().map(\.position), [0, 1, 2])

        try database.moveCardCollection(
            id: second.id,
            toPosition: 0,
            isPinned: true,
            now: Date(timeIntervalSince1970: 50)
        )
        try database.moveCardCollection(
            id: first.id,
            toPosition: 0,
            isPinned: true,
            now: Date(timeIntervalSince1970: 60)
        )
        XCTAssertEqual(try database.cardCollections().map(\.name), ["First", "Second", "Third"])
        XCTAssertEqual(try database.cardCollections().map(\.isPinned), [true, true, false])
        XCTAssertEqual(try database.cardCollections().map(\.position), [0, 1, 0])

        try database.moveCardCollection(
            id: first.id,
            toPosition: 0,
            isPinned: false,
            now: Date(timeIntervalSince1970: 70)
        )
        XCTAssertEqual(try database.cardCollections().map(\.name), ["Second", "First", "Third"])
        XCTAssertEqual(try database.cardCollections().map(\.isPinned), [true, false, false])
        XCTAssertEqual(try database.cardCollections().map(\.position), [0, 0, 1])

        let reopened = try CardDatabase(storage: .file(databaseURL))
        XCTAssertEqual(try reopened.cardCollections().map(\.name), ["Second", "First", "Third"])
        XCTAssertEqual(try reopened.cardCollections().map(\.position), [0, 0, 1])
    }

    func testLegacyCardCollectionSchemaMigratesPinnedColumnsWithDefaults() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionPinnedMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("legacy-pinned-lists.sqlite")
        do {
            let legacyDatabase = try SQLiteDatabase(storage: .file(databaseURL))
            try legacyDatabase.execute(
                """
                CREATE TABLE card_lists (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try legacyDatabase.execute(
                """
                INSERT INTO card_lists (id, name, created_at, updated_at)
                VALUES ('legacy', 'Legacy Deck', '2026-04-26T00:00:00.000Z', '2026-04-26T00:00:00.000Z')
                """)
        }

        let migratedDatabase = try CardDatabase(storage: .file(databaseURL))
        let migratedList = try XCTUnwrap(migratedDatabase.cardCollection(id: "legacy"))
        XCTAssertFalse(migratedList.isPinned)
        XCTAssertNil(migratedList.pinnedAt)
        XCTAssertEqual(migratedList.position, 0)

        let pinned = try migratedDatabase.setCardCollectionPinned(
            id: "legacy",
            isPinned: true,
            now: Date(timeIntervalSince1970: 40)
        )
        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(pinned.pinnedAt, Date(timeIntervalSince1970: 40))
        XCTAssertEqual(pinned.position, 0)
    }

    func testLegacyCardCollectionSchemaMigratesPositionsUsingPreviousSidebarOrder() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionPositionMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("legacy-list-positions.sqlite")
        do {
            let legacyDatabase = try SQLiteDatabase(storage: .file(databaseURL))
            try legacyDatabase.execute(
                """
                CREATE TABLE card_lists (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    is_pinned INTEGER NOT NULL DEFAULT 0,
                    pinned_at TEXT
                )
                """)
            try legacyDatabase.execute(
                """
                INSERT INTO card_lists (id, name, created_at, updated_at, is_pinned, pinned_at)
                VALUES
                    ('unpinned-old', 'Unpinned Old', '2026-04-26T00:00:00.000Z', '2026-04-26T00:00:00.000Z', 0, NULL),
                    ('pinned-old', 'Pinned Old', '2026-04-26T00:00:01.000Z', '2026-04-26T00:00:01.000Z', 1, '2026-04-26T00:00:10.000Z'),
                    ('unpinned-new', 'Unpinned New', '2026-04-26T00:00:02.000Z', '2026-04-26T00:00:02.000Z', 0, NULL),
                    ('pinned-new', 'Pinned New', '2026-04-26T00:00:03.000Z', '2026-04-26T00:00:03.000Z', 1, '2026-04-26T00:00:20.000Z')
                """)
        }

        let migratedDatabase = try CardDatabase(storage: .file(databaseURL))
        let migratedLists = try migratedDatabase.cardCollections()

        XCTAssertEqual(migratedLists.map(\.name), ["Pinned New", "Pinned Old", "Unpinned Old", "Unpinned New"])
        XCTAssertEqual(migratedLists.map(\.position), [0, 1, 0, 1])
    }

    func testCardCollectionMigrationConsolidatesDuplicateRowsIntoQuantities() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("old-lists.sqlite")
        do {
            let legacyDatabase = try SQLiteDatabase(storage: .file(databaseURL))
            try legacyDatabase.execute(
                """
                CREATE TABLE card_lists (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try legacyDatabase.execute(
                """
                CREATE TABLE card_list_categories (
                    id TEXT PRIMARY KEY,
                    list_id TEXT NOT NULL REFERENCES card_lists(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try legacyDatabase.execute(
                """
                CREATE TABLE card_list_entries (
                    id TEXT PRIMARY KEY,
                    list_id TEXT NOT NULL REFERENCES card_lists(id) ON DELETE CASCADE,
                    category_id TEXT REFERENCES card_list_categories(id) ON DELETE SET NULL,
                    card_id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    created_at TEXT NOT NULL
                )
                """)
            try legacyDatabase.execute(
                """
                INSERT INTO card_lists (id, name, created_at, updated_at)
                VALUES ('list', 'Imported Deck', '2026-04-26T00:00:00.000Z', '2026-04-26T00:00:00.000Z')
                """)
            try legacyDatabase.execute(
                """
                INSERT INTO card_list_categories (id, list_id, name, position, created_at, updated_at)
                VALUES ('lands', 'list', 'Land', 0, '2026-04-26T00:00:00.000Z', '2026-04-26T00:00:00.000Z')
                """)
            try legacyDatabase.execute(
                """
                INSERT INTO card_list_entries (id, list_id, category_id, card_id, position, created_at)
                VALUES
                    ('mountain-1', 'list', 'lands', 'mountain', 0, '2026-04-26T00:00:01.000Z'),
                    ('island-1', 'list', 'lands', 'island', 1, '2026-04-26T00:00:02.000Z'),
                    ('mountain-2', 'list', 'lands', 'mountain', 2, '2026-04-26T00:00:03.000Z'),
                    ('mountain-main-1', 'list', NULL, 'mountain', 3, '2026-04-26T00:00:04.000Z'),
                    ('mountain-main-2', 'list', NULL, 'mountain', 4, '2026-04-26T00:00:05.000Z')
                """)
        }

        let migratedDatabase = try CardDatabase(storage: .file(databaseURL))
        let entries = try migratedDatabase.cardCollectionEntries(forListID: "list")

        XCTAssertEqual(entries.map(\.id), ["mountain-1", "island-1", "mountain-main-1"])
        XCTAssertEqual(entries.map(\.cardID), ["mountain", "island", "mountain"])
        XCTAssertEqual(entries.map(\.categoryID), ["lands", "lands", nil])
        XCTAssertEqual(entries.map(\.zone), [.mainboard, .mainboard, .mainboard])
        XCTAssertEqual(entries.map(\.quantity), [2, 1, 2])
        XCTAssertEqual(try migratedDatabase.cardCollection(id: "list")?.ruleset, .some(.none))
        XCTAssertEqual(try migratedDatabase.cardCollection(id: "list")?.entryCount, 5)
        let categories = try migratedDatabase.cardCollectionCategories(forListID: "list")
        XCTAssertEqual(categories.map(\.zone), [.mainboard])
        XCTAssertEqual(categories.map(\.entryCount), [3])
    }

    func testCardCollectionEntriesSurviveCardReplacementAndResolveMissingCardsAsNil() throws {
        let database = try CardDatabase(storage: .inMemory)
        let alpha = preferredTestCard(id: "alpha-print", oracleID: "alpha-oracle", name: "Alpha Forest")
        let beta = preferredTestCard(id: "beta-print", oracleID: "beta-oracle", name: "Beta Mage")
        try database.replaceAllCards([alpha, beta])
        let list = try database.createCardCollection(named: "Keepers")
        try database.appendCard(alpha.id, toList: list.id)
        try database.appendCard(beta.id, toList: list.id)

        try database.replaceAllCards([beta])

        let entries = try database.cardCollectionEntries(forListID: list.id)
        XCTAssertEqual(entries.map(\.cardID), ["alpha-print", "beta-print"])
        XCTAssertNil(entries[0].card)
        XCTAssertEqual(entries[1].card?.id, "beta-print")
        XCTAssertEqual(try database.cardCollections().first?.entryCount, 2)
    }

    func testCardCollectionDashboardColorStatsSurviveDatabaseRoundTrip() throws {
        let database = try CardDatabase(storage: .inMemory)
        let red = preferredTestCard(id: "red-print", oracleID: "red-oracle", name: "Red Spell", colorIdentity: ["R"])
        let blue = preferredTestCard(id: "blue-print", oracleID: "blue-oracle", name: "Blue Spell", colorIdentity: ["U"])
        let izzet = preferredTestCard(
            id: "izzet-print",
            oracleID: "izzet-oracle",
            name: "Izzet Spell",
            colorIdentity: ["R", "U"]
        )
        try database.replaceAllCards([red, blue, izzet])
        let list = try database.createCardCollection(named: "Izzet")
        try database.appendCard(red.id, toList: list.id, quantity: 2)
        try database.appendCard(blue.id, toList: list.id, quantity: 3)
        try database.appendCard(izzet.id, toList: list.id, quantity: 4)

        let entries = try database.cardCollectionEntries(forListID: list.id)
        let stats = CardCollectionDashboardStats.make(entries: entries, includeLandsInTypes: false)

        XCTAssertEqual(entries.compactMap(\.card?.colorIdentity), [["r"], ["u"], ["r", "u"]])
        XCTAssertEqual(stats.colorDistribution.map(\.bucket), [.blue, .red, .multicolor])
        XCTAssertEqual(stats.colorDistribution.map(\.quantity), [3, 2, 4])
    }

    func testCardCollectionDescriptionPersistsRTFDDataPlainTextAndUpdatedAt() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionDescriptionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("descriptions.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardCollection(named: "Notes", now: Date(timeIntervalSince1970: 10))
        XCTAssertNil(list.descriptionRTFDData)
        XCTAssertEqual(list.descriptionPlainText, "")

        let data = Data([0x52, 0x54, 0x46, 0x44])
        let updated = try database.updateCardCollectionDescription(
            id: list.id,
            rtfdData: data,
            plainText: "Keep this opener.",
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(updated.descriptionRTFDData, data)
        XCTAssertEqual(updated.descriptionPlainText, "Keep this opener.")
        XCTAssertEqual(updated.updatedAt, Date(timeIntervalSince1970: 20))

        let reopened = try CardDatabase(storage: .file(databaseURL))
        let persisted = try XCTUnwrap(reopened.cardCollection(id: list.id))
        XCTAssertEqual(persisted.descriptionRTFDData, data)
        XCTAssertEqual(persisted.descriptionPlainText, "Keep this opener.")
        XCTAssertEqual(try reopened.cardCollections().first?.descriptionPlainText, "Keep this opener.")
    }

    func testCardCollectionDashboardPreferencesDefaultPersistAndMigrate() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionDashboardPreferenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("dashboard.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardCollection(named: "Stats", now: Date(timeIntervalSince1970: 10))
        XCTAssertFalse(list.showsDashboard)
        XCTAssertFalse(list.dashboardIncludesLands)

        let shown = try database.setCardCollectionDashboardVisibility(
            id: list.id,
            showsDashboard: true,
            now: Date(timeIntervalSince1970: 20)
        )
        XCTAssertTrue(shown.showsDashboard)
        XCTAssertEqual(shown.updatedAt, Date(timeIntervalSince1970: 20))

        let hidden = try database.setCardCollectionDashboardVisibility(
            id: list.id,
            showsDashboard: false,
            now: Date(timeIntervalSince1970: 25)
        )
        XCTAssertFalse(hidden.showsDashboard)
        XCTAssertEqual(hidden.updatedAt, Date(timeIntervalSince1970: 25))

        let includesLands = try database.setCardCollectionDashboardIncludesLands(
            id: list.id,
            includesLands: true,
            now: Date(timeIntervalSince1970: 30)
        )
        XCTAssertTrue(includesLands.dashboardIncludesLands)
        XCTAssertEqual(includesLands.updatedAt, Date(timeIntervalSince1970: 30))

        let reopened = try CardDatabase(storage: .file(databaseURL))
        let persisted = try XCTUnwrap(reopened.cardCollection(id: list.id))
        XCTAssertFalse(persisted.showsDashboard)
        XCTAssertTrue(persisted.dashboardIncludesLands)

        let legacyDatabaseURL = temporaryDirectory.appendingPathComponent("legacy-dashboard.sqlite")
        do {
            let legacyDatabase = try SQLiteDatabase(storage: .file(legacyDatabaseURL))
            try legacyDatabase.execute(
                """
                CREATE TABLE card_lists (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try legacyDatabase.execute(
                """
                INSERT INTO card_lists (id, name, created_at, updated_at)
                VALUES ('legacy', 'Legacy Stats', '2026-04-26T00:00:00.000Z', '2026-04-26T00:00:00.000Z')
                """)
        }

        let migratedDatabase = try CardDatabase(storage: .file(legacyDatabaseURL))
        let migratedList = try XCTUnwrap(migratedDatabase.cardCollection(id: "legacy"))
        XCTAssertFalse(migratedList.showsDashboard)
        XCTAssertFalse(migratedList.dashboardIncludesLands)
    }

    func testCardCollectionDisplaySortPreferencesDefaultPersistAndMigrate() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionDisplaySortPreferenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("display-sort.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardCollection(named: "Sorted", now: Date(timeIntervalSince1970: 10))
        XCTAssertNil(list.displaySortMode)
        XCTAssertEqual(list.displaySortDirection, .ascending)

        let sorted = try database.setCardCollectionDisplaySort(
            id: list.id,
            mode: .edhrecRank,
            direction: .descending,
            now: Date(timeIntervalSince1970: 20)
        )
        XCTAssertEqual(sorted.displaySortMode, .edhrecRank)
        XCTAssertEqual(sorted.displaySortDirection, .descending)
        XCTAssertEqual(sorted.updatedAt, Date(timeIntervalSince1970: 20))

        let reopened = try CardDatabase(storage: .file(databaseURL))
        let persisted = try XCTUnwrap(reopened.cardCollection(id: list.id))
        XCTAssertEqual(persisted.displaySortMode, .edhrecRank)
        XCTAssertEqual(persisted.displaySortDirection, .descending)

        let listOrder = try reopened.setCardCollectionDisplaySort(
            id: list.id,
            mode: nil,
            direction: .descending,
            now: Date(timeIntervalSince1970: 30)
        )
        XCTAssertNil(listOrder.displaySortMode)
        XCTAssertEqual(listOrder.displaySortDirection, .descending)

        let legacyDatabaseURL = temporaryDirectory.appendingPathComponent("legacy-display-sort.sqlite")
        do {
            let legacyDatabase = try SQLiteDatabase(storage: .file(legacyDatabaseURL))
            try legacyDatabase.execute(
                """
                CREATE TABLE card_lists (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try legacyDatabase.execute(
                """
                INSERT INTO card_lists (id, name, created_at, updated_at)
                VALUES ('legacy', 'Legacy Sort', '2026-04-26T00:00:00.000Z', '2026-04-26T00:00:00.000Z')
                """)
        }

        let migratedDatabase = try CardDatabase(storage: .file(legacyDatabaseURL))
        let migratedList = try XCTUnwrap(migratedDatabase.cardCollection(id: "legacy"))
        XCTAssertNil(migratedList.displaySortMode)
        XCTAssertEqual(migratedList.displaySortDirection, .ascending)
    }

    func testCardCollectionViewModeDefaultsPersistsMigratesAndRestores() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionViewModeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("view-mode.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardCollection(named: "Views", now: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(list.viewMode, .grid)

        let updated = try database.setCardCollectionViewMode(
            id: list.id,
            viewMode: .list,
            now: Date(timeIntervalSince1970: 20)
        )
        XCTAssertEqual(updated.viewMode, .list)
        XCTAssertEqual(updated.updatedAt, Date(timeIntervalSince1970: 20))

        let reopened = try CardDatabase(storage: .file(databaseURL))
        let persisted = try XCTUnwrap(reopened.cardCollection(id: list.id))
        XCTAssertEqual(persisted.viewMode, .list)

        let snapshot = try reopened.cardCollectionLibrarySnapshot()
        let restoredDatabase = try CardDatabase(storage: .inMemory)
        try restoredDatabase.restoreCardCollectionLibrarySnapshot(snapshot)
        XCTAssertEqual(try restoredDatabase.cardCollection(id: list.id)?.viewMode, .list)

        let legacyJSON = Data(
            """
            {
              "id": "legacy-json",
              "name": "Legacy JSON",
              "createdAt": 0,
              "updatedAt": 0
            }
            """.utf8)
        let decodedLegacyList = try JSONDecoder().decode(CardCollectionRecord.self, from: legacyJSON)
        XCTAssertEqual(decodedLegacyList.viewMode, .grid)

        let legacyDatabaseURL = temporaryDirectory.appendingPathComponent("legacy-view-mode.sqlite")
        do {
            let legacyDatabase = try SQLiteDatabase(storage: .file(legacyDatabaseURL))
            try legacyDatabase.execute(
                """
                CREATE TABLE card_lists (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try legacyDatabase.execute(
                """
                INSERT INTO card_lists (id, name, created_at, updated_at)
                VALUES ('legacy', 'Legacy View', '2026-04-26T00:00:00.000Z', '2026-04-26T00:00:00.000Z')
                """)
        }

        let migratedDatabase = try CardDatabase(storage: .file(legacyDatabaseURL))
        let migratedList = try XCTUnwrap(migratedDatabase.cardCollection(id: "legacy"))
        XCTAssertEqual(migratedList.viewMode, .grid)
    }

    func testCardCollectionCategoriesPersistOrderMoveEntriesAndDeleteToUncategorized() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardCollectionCategoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent("categories.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let alpha = preferredTestCard(id: "alpha-print", oracleID: "alpha-oracle", name: "Alpha Forest")
        let beta = preferredTestCard(id: "beta-print", oracleID: "beta-oracle", name: "Beta Mage")
        try database.replaceAllCards([alpha, beta])
        let list = try database.createCardCollection(named: "Commander")

        let ramp = try database.createCardCollectionCategory(
            inList: list.id,
            named: "  Ramp  ",
            now: Date(timeIntervalSince1970: 10)
        )
        let removal = try database.createCardCollectionCategory(
            inList: list.id,
            named: "Removal",
            now: Date(timeIntervalSince1970: 11)
        )
        XCTAssertEqual(try database.cardCollectionCategories(forListID: list.id).map(\.name), ["Ramp", "Removal"])
        XCTAssertThrowsError(try database.createCardCollectionCategory(inList: list.id, named: "ramp")) { error in
            XCTAssertEqual(error as? CardCollectionDatabaseError, .duplicateName)
        }
        XCTAssertThrowsError(try database.createCardCollectionCategory(inList: list.id, named: "uncategorized")) { error in
            XCTAssertEqual(error as? CardCollectionDatabaseError, .duplicateName)
        }

        let uncategorized = try database.appendCard(alpha.id, toList: list.id)
        let rampEntry = try database.appendCard(beta.id, toList: list.id, categoryID: ramp.id)
        let removalEntry = try database.appendCard(alpha.id, toList: list.id, categoryID: removal.id)
        XCTAssertNil(uncategorized.categoryID)
        XCTAssertEqual(rampEntry.categoryID, ramp.id)
        XCTAssertEqual(removalEntry.categoryID, removal.id)
        XCTAssertEqual(try database.cardCollectionCategories(forListID: list.id).map(\.entryCount), [1, 1])

        let renamed = try database.renameCardCollectionCategory(id: removal.id, to: "Interaction")
        XCTAssertEqual(renamed.name, "Interaction")
        XCTAssertThrowsError(try database.renameCardCollectionCategory(id: removal.id, to: "Uncategorized")) { error in
            XCTAssertEqual(error as? CardCollectionDatabaseError, .duplicateName)
        }
        try database.moveCardCollectionCategory(id: removal.id, toPosition: 0)
        XCTAssertEqual(try database.cardCollectionCategories(forListID: list.id).map(\.name), ["Interaction", "Ramp"])

        let moved = try database.moveCardCollectionEntry(id: uncategorized.id, toCategory: ramp.id)
        XCTAssertEqual(moved.categoryID, ramp.id)
        XCTAssertEqual(try database.cardCollectionCategories(forListID: list.id).map(\.entryCount), [1, 2])

        let reopened = try CardDatabase(storage: .file(databaseURL))
        XCTAssertEqual(try reopened.cardCollectionCategories(forListID: list.id).map(\.name), ["Interaction", "Ramp"])
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.categoryID), [
            ramp.id, ramp.id, removal.id,
        ])

        try reopened.deleteCardCollectionCategory(id: ramp.id)
        XCTAssertEqual(try reopened.cardCollectionCategories(forListID: list.id).map(\.name), ["Interaction"])
        XCTAssertEqual(try reopened.cardCollectionEntries(forListID: list.id).map(\.categoryID), [
            nil, nil, removal.id,
        ])

        try reopened.deleteCardCollection(id: list.id)
        XCTAssertTrue(try reopened.cardCollectionCategories(forListID: list.id).isEmpty)
        XCTAssertTrue(try reopened.cardCollectionEntries(forListID: list.id).isEmpty)
    }

    func testMovingEntryMergesWithMatchingCardInDestinationCategory() throws {
        let database = try CardDatabase(storage: .inMemory)
        let alpha = preferredTestCard(id: "alpha-print", oracleID: "alpha-oracle", name: "Alpha Forest")
        try database.replaceAllCards([alpha])
        let list = try database.createCardCollection(named: "Commander")
        let ramp = try database.createCardCollectionCategory(inList: list.id, named: "Ramp")

        let uncategorized = try database.appendCard(alpha.id, toList: list.id, quantity: 2)
        let categorized = try database.appendCard(alpha.id, toList: list.id, categoryID: ramp.id)

        let moved = try database.moveCardCollectionEntry(id: uncategorized.id, toCategory: ramp.id)
        let entries = try database.cardCollectionEntries(forListID: list.id)

        XCTAssertEqual(moved.id, categorized.id)
        XCTAssertEqual(entries.map(\.id), [categorized.id])
        XCTAssertEqual(entries.map(\.categoryID), [ramp.id])
        XCTAssertEqual(entries.map(\.quantity), [3])
        XCTAssertEqual(try database.cardCollection(id: list.id)?.entryCount, 3)
        XCTAssertEqual(try database.cardCollectionCategories(forListID: list.id).map(\.entryCount), [3])
    }

    func testCardCollectionRulesetZonesAndExactQuantityPersist() throws {
        let database = try CardDatabase(storage: .inMemory)
        let alpha = preferredTestCard(id: "alpha-print", oracleID: "alpha-oracle", name: "Alpha Forest")
        let beta = preferredTestCard(id: "beta-print", oracleID: "beta-oracle", name: "Beta Mage")
        try database.replaceAllCards([alpha, beta])

        let list = try database.createCardCollection(named: "Deck", ruleset: .commander)
        XCTAssertEqual(list.ruleset, .commander)

        // Same-named categories can coexist across distinct zones.
        let mainCategory = try database.createCardCollectionCategory(inList: list.id, named: "Core")
        let maybeCategory = try database.createCardCollectionCategory(inList: list.id, zone: .maybeboard, named: "Core")
        let mainEntry = try database.appendCard(alpha.id, toList: list.id, categoryID: mainCategory.id, quantity: 2)
        _ = try database.appendCard(beta.id, toList: list.id, categoryID: maybeCategory.id, quantity: 1)
        let commanderEntry = try database.appendCard(alpha.id, toList: list.id, zone: .commander, quantity: 1)

        let updatedMainEntry = try database.setCardCollectionEntryQuantity(id: mainEntry.id, quantity: 4)
        let movedEntry = try database.moveCardCollectionEntry(id: commanderEntry.id, toZone: .maybeboard)
        let categories = try database.cardCollectionCategories(forListID: list.id)
        let entries = try database.cardCollectionEntries(forListID: list.id)

        XCTAssertEqual(try database.cardCollection(id: list.id)?.ruleset, .commander)
        XCTAssertEqual(categories.map(\.name), ["Core", "Core"])
        XCTAssertEqual(Set(categories.map(\.zone)), [.mainboard, .maybeboard])
        XCTAssertEqual(updatedMainEntry.quantity, 4)
        XCTAssertEqual(movedEntry.zone, .maybeboard)
        XCTAssertNil(movedEntry.categoryID)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.quantity }, 6)
        XCTAssertEqual(try database.cardCollection(id: list.id)?.entryCount, 6)
    }

    func testSwitchingCommanderDeckToCollectionNormalizesCommanderZoneAndValidation() throws {
        let database = try CardDatabase(storage: .inMemory)
        let commander = preferredTestCard(
            id: "commander-print",
            oracleID: "commander-oracle",
            name: "Commander Creature",
            legalities: ["commander": "legal"],
            typeLine: "Legendary Creature"
        )
        let forest = preferredTestCard(
            id: "forest-print",
            oracleID: "forest-oracle",
            name: "Forest",
            legalities: ["commander": "legal"],
            typeLine: "Basic Land"
        )
        try database.replaceAllCards([commander, forest])

        let list = try database.createCardCollection(named: "Deck", ruleset: .commander)
        let mainCategory = try database.createCardCollectionCategory(inList: list.id, named: "Core")
        try database.appendCard(forest.id, toList: list.id, categoryID: mainCategory.id, quantity: 99)
        try database.appendCard(commander.id, toList: list.id, zone: .commander)

        // A 100-card Commander deck (99 forests + commander) reports no size warning.
        let commanderEntries = try database.cardCollectionEntries(forListID: list.id)
        let commanderWarnings = Set(
            CardCollectionRulesetValidator.warnings(for: list, entries: commanderEntries).map(\.id)
        )
        XCTAssertFalse(commanderWarnings.contains("commander-size"))
        XCTAssertEqual(Set(commanderEntries.map(\.zone)), [.commander, .mainboard])

        // Turning the deck back into a plain Collection rehomes the commander-zone card.
        let updatedList = try database.setCardCollectionRuleset(id: list.id, ruleset: .none)
        let entries = try database.cardCollectionEntries(forListID: list.id)
        let categories = try database.cardCollectionCategories(forListID: list.id)

        XCTAssertEqual(updatedList.ruleset, .none)
        XCTAssertEqual(categories.map(\.zone), [.mainboard])
        XCTAssertEqual(Set(entries.map(\.zone)), [.mainboard])
        XCTAssertEqual(entries.reduce(0) { $0 + $1.quantity }, 100)
    }

    func testMigrationCoercesRetiredRulesetsAndRehomesSideboardEntries() throws {
        let database = try CardDatabase(storage: .inMemory)
        let card = preferredTestCard(id: "c1", oracleID: "oracle-c1", name: "Card One")
        try database.replaceAllCards([card])
        let list = try database.createCardCollection(named: "Old Modern Deck")
        let entry = try database.appendCard(card.id, toList: list.id)

        // Simulate a pre-1.6 deck persisted as a retired constructed format with a
        // sideboard entry — state that today's API can no longer produce.
        try database.database.execute("UPDATE card_lists SET ruleset = 'modern' WHERE id = '\(list.id)'")
        try database.database.execute("UPDATE card_list_entries SET zone = 'sideboard' WHERE id = '\(entry.id)'")

        try database.migrate()

        XCTAssertEqual(try database.cardCollection(id: list.id)?.ruleset, CardCollectionRuleset.none)
        XCTAssertEqual(try database.cardCollectionEntries(forListID: list.id).map(\.zone), [.mainboard])

        // Idempotent: a second pass leaves the healed state untouched.
        try database.migrate()
        XCTAssertEqual(try database.cardCollection(id: list.id)?.ruleset, CardCollectionRuleset.none)
        XCTAssertEqual(try database.cardCollectionEntries(forListID: list.id).map(\.zone), [.mainboard])
    }

    private func names(
        matching text: String,
        database: CardDatabase
    ) throws -> [String] {
        try cards(matching: text, database: database).map(\.name)
    }

    private func assertNames(
        matching text: String,
        matchNamesFor referenceText: String,
        database: CardDatabase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let actual = try names(matching: text, database: database)
            let expected = try names(matching: referenceText, database: database)
            XCTAssertEqual(actual, expected, file: file, line: line)
        } catch {
            XCTFail("Search failed: \(error)", file: file, line: line)
        }
    }

    private func cards(
        matching text: String,
        database: CardDatabase,
        printingDisplayMode: PrintingDisplayMode = .preferred
    ) throws -> [CardRecord] {
        let request = CardSearchRequest(
            text: text,
            printingDisplayMode: printingDisplayMode,
            limit: 50
        )
        let response = try database.search(request)
        guard case .results(let cards, _) = response else {
            XCTFail("Expected results")
            return []
        }
        return cards
    }

    private func columnNames(in table: String, database: SQLiteDatabase) throws -> Set<String> {
        let statement = try database.prepare("PRAGMA table_info(\(table))")
        var names: Set<String> = []
        while try statement.step() {
            if let name = statement.string(at: 1) {
                names.insert(name)
            }
        }
        return names
    }

    private func krenkoPrintings() -> [CardRecord] {
        [
            preferredTestCard(
                id: "rvr-regular",
                oracleID: "krenko-oracle",
                name: "Krenko, Mob Boss",
                releasedAt: "2024-01-12",
                setCode: "rvr",
                collectorNumber: "114",
                normalImagePath: "/tmp/rvr-regular.jpg"
            ),
            preferredTestCard(
                id: "rvr-boosterfun",
                oracleID: "krenko-oracle",
                name: "Krenko, Mob Boss",
                releasedAt: "2024-01-12",
                setCode: "rvr",
                collectorNumber: "430",
                isBoosterFun: true,
                normalImagePath: "/tmp/rvr-boosterfun.jpg"
            ),
            preferredTestCard(
                id: "fdn",
                oracleID: "krenko-oracle",
                name: "Krenko, Mob Boss",
                releasedAt: "2024-11-15",
                setCode: "fdn",
                collectorNumber: "204",
                normalImagePath: "/tmp/fdn.jpg"
            ),
            preferredTestCard(
                id: "pfdn",
                oracleID: "krenko-oracle",
                name: "Krenko, Mob Boss",
                releasedAt: "2024-11-15",
                setCode: "pfdn",
                collectorNumber: "204s",
                isPromo: true,
                normalImagePath: "/tmp/pfdn.jpg"
            ),
            preferredTestCard(
                id: "fr-newer",
                oracleID: "krenko-oracle",
                name: "Krenko, Mob Boss",
                language: "fr",
                releasedAt: "2025-01-01",
                setCode: "zzz",
                collectorNumber: "1",
                normalImagePath: "/tmp/fr.jpg"
            )
        ]
    }

    private func preferredTestCard(
        id: String,
        oracleID: String?,
        name: String,
        language: String = "en",
        releasedAt: String? = "2024-01-01",
        setCode: String = "tst",
        setType: String = "expansion",
        collectorNumber: String = "1",
        isPromo: Bool = false,
        isUniversesBeyond: Bool = false,
        isReprint: Bool = false,
        isVariation: Bool = false,
        isBoosterFun: Bool = false,
        layout: String = "normal",
        normalImagePath: String? = nil,
        smallImageURL: String? = nil,
        legalities: [String: String] = [:],
        typeLine: String = "Creature",
        manaValue: Double? = nil,
        colors: [String] = [],
        colorIdentity: [String] = [],
        oracleText: String = "Test text.",
        faces: [CardFaceRecord] = []
    ) -> CardRecord {
        CardRecord(
            id: id,
            oracleID: oracleID,
            name: name,
            language: language,
            releasedAt: releasedAt,
            setCode: setCode,
            setName: "Test Set",
            setType: setType,
            collectorNumber: collectorNumber,
            collectorNumberNumber: Int(collectorNumber.prefix { $0.isNumber }),
            rarity: "rare",
            rarityRank: 2,
            manaValue: manaValue,
            colorSortKey: 0,
            colors: colors,
            colorIdentity: colorIdentity,
            layout: layout,
            typeLine: typeLine,
            oracleText: oracleText,
            legalities: legalities,
            isUniversesBeyond: isUniversesBeyond,
            isRealCard: true,
            isPromo: isPromo,
            isVariation: isVariation,
            isBoosterFun: isBoosterFun,
            isReprint: isReprint,
            normalImagePath: normalImagePath,
            smallImageURL: smallImageURL,
            faces: faces
        )
    }

    private func rowCount(in tableName: String, database: CardDatabase) throws -> Int {
        let statement = try database.database.prepare("SELECT COUNT(*) FROM \(tableName)")
        _ = try statement.step()
        return statement.int(at: 0) ?? 0
    }
}
