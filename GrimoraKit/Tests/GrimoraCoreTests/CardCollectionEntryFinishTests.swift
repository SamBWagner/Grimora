@testable import GrimoraCore
import XCTest

final class CardCollectionEntryFinishTests: XCTestCase {
    // MARK: - Database persistence

    func testSetCardCollectionEntryFinishPersistsAndClears() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Foils")
        try database.appendCard("beta", toList: list.id) // beta supports foil

        let entry = try XCTUnwrap(try database.cardCollectionEntries(forListID: list.id).first)
        XCTAssertNil(entry.selectedFinish)

        let foiled = try database.setCardCollectionEntryFinish(id: entry.id, finish: .foil)
        XCTAssertEqual(foiled.selectedFinish, .foil)
        XCTAssertEqual(
            try database.cardCollectionEntries(forListID: list.id).first?.selectedFinish,
            .foil
        )

        // `.normal` clears the pin (stored as NULL).
        let cleared = try database.setCardCollectionEntryFinish(id: entry.id, finish: .normal)
        XCTAssertNil(cleared.selectedFinish)
        XCTAssertNil(try database.cardCollectionEntries(forListID: list.id).first?.selectedFinish)
    }

    func testReplacingPrintDropsFoilWhenNewPrintingCannotBeFoil() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Foils")
        try database.appendCard("beta", toList: list.id)

        let entry = try XCTUnwrap(try database.cardCollectionEntries(forListID: list.id).first)
        _ = try database.setCardCollectionEntryFinish(id: entry.id, finish: .foil)

        // alpha has finishes ["nonfoil"] — swapping onto it must drop the foil pin.
        let updated = try database.replaceCardCollectionEntryPrint(id: entry.id, withCardID: "alpha")
        XCTAssertEqual(updated.cardID, "alpha")
        XCTAssertNil(updated.selectedFinish)
    }

    func testSnapshotRoundTripPreservesSelectedFinish() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Foils")
        try database.appendCard("beta", toList: list.id)
        let entry = try XCTUnwrap(try database.cardCollectionEntries(forListID: list.id).first)
        _ = try database.setCardCollectionEntryFinish(id: entry.id, finish: .foil)

        // Export then restore the full library snapshot (the sync apply path).
        let snapshot = try database.cardCollectionLibrarySnapshot()
        let restoreTarget = try Fixtures.database()
        try restoreTarget.restoreCardCollectionLibrarySnapshot(snapshot)

        XCTAssertEqual(
            try restoreTarget.cardCollectionEntries(forListID: list.id).first?.selectedFinish,
            .foil
        )
    }

    // MARK: - Codable backward compatibility

    func testEntryDecodesLegacyJSONWithoutSelectedFinish() throws {
        let legacy = Data("""
        {
          "id": "e1",
          "listID": "l1",
          "zone": "mainboard",
          "cardID": "beta",
          "position": 0,
          "quantity": 1,
          "createdAt": 0,
          "updatedAt": 0
        }
        """.utf8)

        let decoder = JSONDecoder()
        let entry = try decoder.decode(CardCollectionEntryRecord.self, from: legacy)
        XCTAssertNil(entry.selectedFinish)
    }

    func testEntryEncodeDecodeRoundTripWithFoil() throws {
        let entry = CardCollectionEntryRecord(
            id: "e1",
            listID: "l1",
            cardID: "beta",
            position: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            selectedFinish: .foil
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(CardCollectionEntryRecord.self, from: data)
        XCTAssertEqual(decoded.selectedFinish, .foil)
    }
}
