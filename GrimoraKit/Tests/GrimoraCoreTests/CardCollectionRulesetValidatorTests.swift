@testable import GrimoraCore
import XCTest

final class CardCollectionRulesetValidatorTests: XCTestCase {
    func testCollectionRulesetProducesNoWarnings() {
        let list = list(ruleset: .none)
        let entries = [
            entry(
                card: card(id: "bolt", oracleID: "bolt-oracle", name: "Bolt Spell", legalities: [:]),
                zone: .mainboard,
                quantity: 5
            ),
        ]

        XCTAssertTrue(CardCollectionRulesetValidator.warnings(for: list, entries: entries).isEmpty)
    }

    func testCommanderRulesetWarningsCoverCommandersSizeSingletonAndLegality() {
        let list = list(ruleset: .commander)
        let entries = [
            entry(
                card: card(
                    id: "echo-a",
                    oracleID: "echo-oracle",
                    name: "Echo Spell",
                    legalities: ["commander": "legal"]
                ),
                zone: .mainboard,
                quantity: 2
            ),
            entry(
                card: card(
                    id: "banned",
                    oracleID: "banned-oracle",
                    name: "Banned Spell",
                    legalities: ["commander": "not_legal"]
                ),
                zone: .maybeboard
            ),
        ]

        let warningIDs = Set(CardCollectionRulesetValidator.warnings(for: list, entries: entries).map(\.id))

        XCTAssertTrue(warningIDs.contains("commander-missing"))
        XCTAssertTrue(warningIDs.contains("commander-size"))
        XCTAssertTrue(warningIDs.contains("commander-singleton-echo-oracle"))
        XCTAssertTrue(warningIDs.contains("commander-legality-banned-oracle"))
    }

    func testCommanderSingletonBlocksSecondCopyOfSameCard() {
        let bolt = card(id: "bolt", oracleID: "bolt-oracle", name: "Bolt", legalities: [:])
        let existing = [entry(card: bolt, zone: .mainboard)]
        XCTAssertFalse(
            CardCollectionRulesetValidator.commanderSingletonAllowsAdding(bolt, toExisting: existing))
    }

    func testCommanderSingletonBlocksDifferentPrintingOfSameCard() {
        let printingA = card(id: "bolt-a", oracleID: "bolt-oracle", name: "Bolt", legalities: [:])
        let printingB = card(id: "bolt-b", oracleID: "bolt-oracle", name: "Bolt", legalities: [:])
        let existing = [entry(card: printingA, zone: .commander)]
        XCTAssertFalse(
            CardCollectionRulesetValidator.commanderSingletonAllowsAdding(printingB, toExisting: existing))
    }

    func testCommanderSingletonAllowsDistinctNewCard() {
        let existing = [entry(card: card(id: "bolt", oracleID: "bolt-oracle", name: "Bolt", legalities: [:]), zone: .mainboard)]
        let shock = card(id: "shock", oracleID: "shock-oracle", name: "Shock", legalities: [:])
        XCTAssertTrue(
            CardCollectionRulesetValidator.commanderSingletonAllowsAdding(shock, toExisting: existing))
    }

    func testCommanderSingletonAllowsRepeatedBasicLand() {
        let island = card(
            id: "island",
            oracleID: "island-oracle",
            name: "Island",
            legalities: [:],
            typeLine: "Basic Land — Island",
            oracleText: ""
        )
        let existing = [entry(card: island, zone: .mainboard, quantity: 30)]
        XCTAssertTrue(
            CardCollectionRulesetValidator.commanderSingletonAllowsAdding(island, toExisting: existing))
    }

    func testCommanderSingletonAllowsAnyNumberCards() {
        let rats = card(
            id: "rats",
            oracleID: "rats-oracle",
            name: "Relentless Rats",
            legalities: [:],
            typeLine: "Creature — Rat",
            oracleText: "A deck can have any number of cards named Relentless Rats."
        )
        let existing = [entry(card: rats, zone: .mainboard, quantity: 12)]
        XCTAssertTrue(
            CardCollectionRulesetValidator.commanderSingletonAllowsAdding(rats, toExisting: existing))
    }

    func testCommanderSingletonIgnoresMaybeboardCopies() {
        let bolt = card(id: "bolt", oracleID: "bolt-oracle", name: "Bolt", legalities: [:])
        let existing = [entry(card: bolt, zone: .maybeboard)]
        XCTAssertTrue(
            CardCollectionRulesetValidator.commanderSingletonAllowsAdding(bolt, toExisting: existing))
    }

    private func list(ruleset: CardCollectionRuleset) -> CardCollectionRecord {
        CardCollectionRecord(
            id: "list",
            name: "List",
            ruleset: ruleset,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func entry(
        card: CardRecord,
        zone: CardCollectionZone,
        quantity: Int = 1
    ) -> CardCollectionEntryRecord {
        CardCollectionEntryRecord(
            id: "\(zone.rawValue)-\(card.id)",
            listID: "list",
            zone: zone,
            categoryID: nil,
            cardID: card.id,
            position: 0,
            quantity: quantity,
            createdAt: Date(timeIntervalSince1970: 0),
            card: card
        )
    }

    private func card(
        id: String,
        oracleID: String,
        name: String,
        legalities: [String: String],
        typeLine: String = "Instant",
        oracleText: String = "Test text."
    ) -> CardRecord {
        CardRecord(
            id: id,
            oracleID: oracleID,
            name: name,
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: "1",
            collectorNumberNumber: 1,
            rarity: "rare",
            rarityRank: 2,
            colorSortKey: 0,
            layout: "normal",
            typeLine: typeLine,
            oracleText: oracleText,
            legalities: legalities,
            isRealCard: true
        )
    }
}
