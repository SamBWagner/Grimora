@testable import GrimoraCore
import XCTest

/// Storage + integrity coverage for multi-category entries: an entry keeps one primary
/// category (`categoryID`) and any number of secondary tags (`secondaryCategoryIDs`).
final class CardCollectionMultiCategoryTests: XCTestCase {
    func testSecondaryCategoriesRoundTripThroughTheDatabase() throws {
        let database = try makeDatabase()
        let list = try database.createCardCollection(named: "Deck")
        let ramp = try database.createCardCollectionCategory(inList: list.id, named: "Ramp")
        let removal = try database.createCardCollectionCategory(inList: list.id, named: "Removal")
        let entry = try database.appendCard("sol-ring", toList: list.id, categoryID: ramp.id)

        try database.addSecondaryCategory(entryID: entry.id, categoryID: removal.id)

        let reloaded = try XCTUnwrap(try database.cardCollectionEntries(forListID: list.id).first)
        XCTAssertEqual(reloaded.categoryID, ramp.id)
        XCTAssertEqual(reloaded.secondaryCategoryIDs, [removal.id])
    }

    func testAddingPrimaryOrDifferentZoneAsSecondaryIsRejectedOrNoop() throws {
        let database = try makeDatabase()
        let list = try database.createCardCollection(named: "Deck", ruleset: .commander)
        let ramp = try database.createCardCollectionCategory(inList: list.id, zone: .mainboard, named: "Ramp")
        let maybe = try database.createCardCollectionCategory(inList: list.id, zone: .maybeboard, named: "Maybe")
        let entry = try database.appendCard("sol-ring", toList: list.id, zone: .mainboard, categoryID: ramp.id)

        // Adding the primary category as a secondary is a no-op (a card is filed under it once).
        let afterPrimary = try database.addSecondaryCategory(entryID: entry.id, categoryID: ramp.id)
        XCTAssertTrue(afterPrimary.secondaryCategoryIDs.isEmpty)

        // A category in another zone can't be a secondary tag.
        XCTAssertThrowsError(try database.addSecondaryCategory(entryID: entry.id, categoryID: maybe.id)) { error in
            XCTAssertEqual(error as? CardCollectionDatabaseError, .categoryNotFound)
        }
    }

    func testSettingPrimaryStripsThatCategoryFromSecondaries() throws {
        let database = try makeDatabase()
        let list = try database.createCardCollection(named: "Deck")
        let ramp = try database.createCardCollectionCategory(inList: list.id, named: "Ramp")
        let removal = try database.createCardCollectionCategory(inList: list.id, named: "Removal")
        let entry = try database.appendCard("sol-ring", toList: list.id, categoryID: ramp.id)
        try database.addSecondaryCategory(entryID: entry.id, categoryID: removal.id)

        // Promote "Removal" to primary; it should no longer also be listed as a secondary.
        let updated = try database.setCardCollectionEntryPrimaryCategory(id: entry.id, categoryID: removal.id)
        XCTAssertEqual(updated.categoryID, removal.id)
        XCTAssertFalse(updated.secondaryCategoryIDs.contains(removal.id))
    }

    func testDeletingCategoryStripsItFromPrimaryAndSecondary() throws {
        let database = try makeDatabase()
        let list = try database.createCardCollection(named: "Deck")
        let ramp = try database.createCardCollectionCategory(inList: list.id, named: "Ramp")
        let removal = try database.createCardCollectionCategory(inList: list.id, named: "Removal")

        let primaryEntry = try database.appendCard("sol-ring", toList: list.id, categoryID: removal.id)
        let secondaryEntry = try database.appendCard("swords", toList: list.id, categoryID: ramp.id)
        try database.addSecondaryCategory(entryID: secondaryEntry.id, categoryID: removal.id)

        try database.deleteCardCollectionCategory(id: removal.id)

        let entries = Dictionary(
            uniqueKeysWithValues: try database.cardCollectionEntries(forListID: list.id).map { ($0.cardID, $0) }
        )
        XCTAssertNil(entries["sol-ring"]?.categoryID)
        XCTAssertEqual(entries["swords"]?.categoryID, ramp.id)
        XCTAssertEqual(entries["swords"]?.secondaryCategoryIDs, [])
    }

    func testMovingZonesClearsSecondaryTags() throws {
        let database = try makeDatabase()
        let list = try database.createCardCollection(named: "Deck", ruleset: .commander)
        let ramp = try database.createCardCollectionCategory(inList: list.id, zone: .mainboard, named: "Ramp")
        let removal = try database.createCardCollectionCategory(inList: list.id, zone: .mainboard, named: "Removal")
        let entry = try database.appendCard("sol-ring", toList: list.id, zone: .mainboard, categoryID: ramp.id)
        try database.addSecondaryCategory(entryID: entry.id, categoryID: removal.id)

        let moved = try database.moveCardCollectionEntry(id: entry.id, toZone: .maybeboard)

        XCTAssertEqual(moved.zone, .maybeboard)
        XCTAssertNil(moved.categoryID)
        XCTAssertTrue(moved.secondaryCategoryIDs.isEmpty)
    }

    func testArchiveDocumentRoundTripsSecondaryCategories() throws {
        let list = CardCollectionRecord(id: "list", name: "Deck", createdAt: .init(), updatedAt: .init())
        let category = CardCollectionCategoryRecord(
            id: "cat-removal", listID: "list", name: "Removal", position: 0, createdAt: .init(), updatedAt: .init()
        )
        let entry = CardCollectionEntryRecord(
            id: "entry", listID: "list", categoryID: "cat-ramp", secondaryCategoryIDs: ["cat-removal"],
            cardID: "sol-ring", position: 0, createdAt: .init()
        )

        let document = CardCollectionArchiveCoder.document(list: list, entries: [entry], categories: [category])
        let data = try CardCollectionArchiveCoder.encode(document)
        let decoded = try CardCollectionArchiveCoder.decode(data)

        XCTAssertEqual(decoded.entries.first?.secondaryCategoryIDs, ["cat-removal"])
    }

    // MARK: - Helpers

    private func makeDatabase() throws -> CardDatabase {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            card(id: "sol-ring", name: "Sol Ring", typeLine: "Artifact"),
            card(id: "swords", name: "Swords to Plowshares", typeLine: "Instant"),
        ])
        return database
    }

    private func card(id: String, name: String, typeLine: String) -> CardRecord {
        CardRecord(
            id: id,
            oracleID: id,
            name: name,
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            colorSortKey: 0,
            layout: "normal",
            typeLine: typeLine,
            oracleText: ""
        )
    }
}
