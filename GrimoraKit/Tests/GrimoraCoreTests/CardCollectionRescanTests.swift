@testable import GrimoraCore
import XCTest

final class CardCollectionRescanTests: XCTestCase {
    func testEmptyDiffWhenScanMatchesDeck() {
        let sol = card(id: "sol", name: "Sol Ring")
        let cmd = card(id: "cmd", name: "Kenrith")
        let deck = [
            entry(card: cmd, zone: .commander),
            entry(card: sol, zone: .mainboard),
        ]

        let diff = CommanderRescan.diff(
            deckEntries: deck,
            scanned: [scan(cmd), scan(sol)]
        )

        XCTAssertTrue(diff.isEmpty)
        XCTAssertEqual(diff.unchangedCount, 2)
    }

    func testAddsCardsNotInDeck() {
        let sol = card(id: "sol", name: "Sol Ring")
        let bolt = card(id: "bolt", name: "Lightning Bolt")
        let deck = [entry(card: sol, zone: .mainboard)]

        let diff = CommanderRescan.diff(
            deckEntries: deck,
            scanned: [scan(sol), scan(bolt)]
        )

        XCTAssertEqual(diff.additions.map(\.cardID), ["bolt"])
        XCTAssertEqual(diff.additions.first?.delta, 1)
        XCTAssertEqual(diff.additions.first?.zone, .mainboard)
        XCTAssertNil(diff.additions.first?.entryID) // brand new
        XCTAssertTrue(diff.removals.isEmpty)
        XCTAssertEqual(diff.unchangedCount, 1)
    }

    func testRemovesMainboardCardNotScanned() {
        let sol = card(id: "sol", name: "Sol Ring")
        let bolt = card(id: "bolt", name: "Lightning Bolt")
        let deck = [
            entry(card: sol, zone: .mainboard),
            entry(card: bolt, zone: .mainboard),
        ]

        let diff = CommanderRescan.diff(deckEntries: deck, scanned: [scan(sol)])

        XCTAssertEqual(diff.removals.map(\.cardID), ["bolt"])
        XCTAssertEqual(diff.removals.first?.delta, -1)
        XCTAssertEqual(diff.removals.first?.entryID, "mainboard-bolt")
        XCTAssertTrue(diff.additions.isEmpty)
    }

    func testCommanderIsNeverRemovedWhenUnscanned() {
        let cmd = card(id: "cmd", name: "Kenrith")
        let sol = card(id: "sol", name: "Sol Ring")
        let deck = [
            entry(card: cmd, zone: .commander),
            entry(card: sol, zone: .mainboard),
        ]

        // Scan only the mainboard card — the commander is left out.
        let diff = CommanderRescan.diff(deckEntries: deck, scanned: [scan(sol)])

        XCTAssertTrue(diff.isEmpty, "Commander shortfall must not propose a removal")
        XCTAssertEqual(diff.unchangedCount, 1)
    }

    func testDifferentPrintingBecomesRemoveOldAddNew() {
        let oldPrint = card(id: "sol-old", name: "Sol Ring", setCode: "c16", collectorNumber: "220")
        let newPrint = card(id: "sol-new", name: "Sol Ring", setCode: "lcc", collectorNumber: "10")
        let deck = [entry(card: oldPrint, zone: .mainboard)]

        let diff = CommanderRescan.diff(deckEntries: deck, scanned: [scan(newPrint)])

        XCTAssertEqual(diff.additions.map(\.cardID), ["sol-new"])
        XCTAssertEqual(diff.removals.map(\.cardID), ["sol-old"])
        XCTAssertEqual(diff.unchangedCount, 0)
    }

    func testCountsCopiesForBasicLands() {
        let island = card(id: "island", name: "Island")
        // Deck holds 3 Islands; scan finds 5.
        let deck = [entry(card: island, zone: .mainboard, quantity: 3)]

        let diff = CommanderRescan.diff(
            deckEntries: deck,
            scanned: [CommanderRescanScannedCard(card: island, count: 5)]
        )

        XCTAssertEqual(diff.additions.map(\.cardID), ["island"])
        XCTAssertEqual(diff.additions.first?.delta, 2)
        XCTAssertEqual(diff.additions.first?.entryID, "mainboard-island")
        XCTAssertTrue(diff.removals.isEmpty)
    }

    func testReducesCopiesWhenFewerScanned() {
        let island = card(id: "island", name: "Island")
        let deck = [entry(card: island, zone: .mainboard, quantity: 5)]

        let diff = CommanderRescan.diff(
            deckEntries: deck,
            scanned: [CommanderRescanScannedCard(card: island, count: 2)]
        )

        XCTAssertEqual(diff.removals.map(\.cardID), ["island"])
        XCTAssertEqual(diff.removals.first?.delta, -3)
        XCTAssertTrue(diff.additions.isEmpty)
    }

    func testMaybeboardIsIgnored() {
        let sol = card(id: "sol", name: "Sol Ring")
        let wish = card(id: "wish", name: "Wishlist Card")
        let deck = [
            entry(card: sol, zone: .mainboard),
            entry(card: wish, zone: .maybeboard),
        ]

        // Scan the mainboard card only. The maybeboard card must not be removed.
        let diff = CommanderRescan.diff(deckEntries: deck, scanned: [scan(sol)])

        XCTAssertTrue(diff.isEmpty)
        // Maybeboard entries aren't part of the deck, so they don't count as unchanged.
        XCTAssertEqual(diff.unchangedCount, 1)
    }

    func testScanningMaybeboardCardAddsItToMainboard() {
        let wish = card(id: "wish", name: "Wishlist Card")
        let deck = [entry(card: wish, zone: .maybeboard)]

        let diff = CommanderRescan.diff(deckEntries: deck, scanned: [scan(wish)])

        XCTAssertEqual(diff.additions.map(\.cardID), ["wish"])
        XCTAssertEqual(diff.additions.first?.zone, .mainboard)
        XCTAssertNil(diff.additions.first?.entryID)
    }

    // MARK: - Tally (singleton voiding during scanning)

    func testTallyCountsDistinctSingletons() {
        var tally = CommanderRescanTally()
        XCTAssertEqual(tally.record(card(id: "sol", name: "Sol Ring")), .counted)
        XCTAssertEqual(tally.record(card(id: "bolt", name: "Lightning Bolt")), .counted)
        XCTAssertEqual(tally.total, 2)
        XCTAssertEqual(Set(tally.scannedCards.map(\.card.id)), ["sol", "bolt"])
    }

    func testTallyVoidsDuplicateSingletonScan() {
        var tally = CommanderRescanTally()
        let sol = card(id: "sol", name: "Sol Ring")
        XCTAssertEqual(tally.record(sol), .counted)
        XCTAssertEqual(tally.record(sol), .voidedDuplicate) // same printing again
        XCTAssertEqual(tally.total, 1)
        XCTAssertEqual(tally.scannedCards.first?.count, 1)
    }

    func testTallyVoidsDifferentPrintingOfSameSingleton() {
        var tally = CommanderRescanTally()
        // Same oracle identity, different printing → still a singleton, still voided.
        let printA = card(id: "sol-a", name: "Sol Ring", setCode: "c16", collectorNumber: "220")
        let printB = card(id: "sol-b", name: "Sol Ring", setCode: "lcc", collectorNumber: "10")
        XCTAssertEqual(tally.record(printA), .counted)
        XCTAssertEqual(tally.record(printB), .voidedDuplicate)
        XCTAssertEqual(tally.total, 1)
        XCTAssertEqual(tally.scannedCards.map(\.card.id), ["sol-a"])
    }

    func testTallyCountsCopiesOfBasicLands() {
        var tally = CommanderRescanTally()
        let island = card(id: "island", name: "Island", typeLine: "Basic Land — Island")
        XCTAssertEqual(tally.record(island), .counted)
        XCTAssertEqual(tally.record(island), .counted)
        XCTAssertEqual(tally.record(island), .counted)
        XCTAssertEqual(tally.total, 3)
        XCTAssertEqual(tally.scannedCards.first?.count, 3)
    }

    func testTallyCountsCopiesOfAnyNumberCards() {
        var tally = CommanderRescanTally()
        let rats = card(
            id: "rats",
            name: "Relentless Rats",
            oracleText: "A deck can have any number of cards named Relentless Rats."
        )
        XCTAssertEqual(tally.record(rats), .counted)
        XCTAssertEqual(tally.record(rats), .counted)
        XCTAssertEqual(tally.total, 2)
    }

    func testTallyFeedsDiffAfterVoiding() {
        // Scanning a singleton twice must not inflate the deck diff to a quantity of 2.
        var tally = CommanderRescanTally()
        let sol = card(id: "sol", name: "Sol Ring")
        tally.record(sol)
        tally.record(sol)

        let deck = [entry(card: card(id: "other", name: "Other"), zone: .mainboard)]
        let diff = CommanderRescan.diff(deckEntries: deck, scanned: tally.scannedCards)

        XCTAssertEqual(diff.additions.map(\.cardID), ["sol"])
        XCTAssertEqual(diff.additions.first?.delta, 1)
    }

    // MARK: - Helpers

    private func scan(_ card: CardRecord) -> CommanderRescanScannedCard {
        CommanderRescanScannedCard(card: card, count: 1)
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
        name: String,
        setCode: String = "tst",
        collectorNumber: String = "1",
        typeLine: String = "Artifact",
        oracleText: String = "Test text."
    ) -> CardRecord {
        CardRecord(
            id: id,
            oracleID: "\(name.lowercased())-oracle",
            name: name,
            setCode: setCode,
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: collectorNumber,
            collectorNumberNumber: Int(collectorNumber),
            rarity: "rare",
            rarityRank: 2,
            colorSortKey: 0,
            layout: "normal",
            typeLine: typeLine,
            oracleText: oracleText,
            legalities: ["commander": "legal"],
            isRealCard: true
        )
    }
}
