@testable import GrimoraCore
import XCTest

final class CardCollectionRulesetValidatorTests: XCTestCase {
    func testConstructedRulesetWarningsCoverDeckSizeSideboardCopiesAndLegality() {
        let list = list(ruleset: .modern)
        let entries = [
            entry(
                card: card(id: "bolt", oracleID: "bolt-oracle", name: "Bolt Spell", legalities: ["modern": "legal"]),
                zone: .mainboard,
                quantity: 5
            ),
            entry(
                card: card(id: "side", oracleID: "side-oracle", name: "Side Spell", legalities: ["modern": "legal"]),
                zone: .sideboard,
                quantity: 16
            ),
            entry(
                card: card(id: "banned", oracleID: "banned-oracle", name: "Banned Spell", legalities: ["modern": "banned"]),
                zone: .maybeboard
            ),
        ]

        let warningIDs = Set(CardCollectionRulesetValidator.warnings(for: list, entries: entries).map(\.id))

        XCTAssertTrue(warningIDs.contains("modern-mainboard-size"))
        XCTAssertTrue(warningIDs.contains("modern-sideboard-size"))
        XCTAssertTrue(warningIDs.contains("modern-copy-limit-bolt-oracle"))
        XCTAssertTrue(warningIDs.contains("modern-legality-banned-oracle"))
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
