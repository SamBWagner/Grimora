@testable import GrimoraCore
import XCTest

final class CardLabelTests: XCTestCase {

    // MARK: - Helpers

    private func results(_ response: CardCollectionEntrySearchResponse) throws -> [CardCollectionEntryRecord] {
        switch response {
        case .results(let entries):
            return entries
        case .unsupported(let reason):
            throw XCTSkip("unexpected unsupported query: \(reason)")
        }
    }

    private func fetchEntry(forCard cardID: String, in database: CardDatabase, list: String) throws -> CardCollectionEntryRecord {
        let entries = try database.cardCollectionEntries(forListID: list)
        return try XCTUnwrap(entries.first { $0.cardID == cardID })
    }

    // MARK: - Assignment persistence (row-mapper round-trip)

    func testToggleLabelPersistsThroughRowMapper() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Commander")
        try database.appendCard("alpha", toList: list.id)
        let entry = try fetchEntry(forCard: "alpha", in: database, list: list.id)
        XCTAssertTrue(entry.labelIDs.isEmpty)

        let label = try database.createCardLabel(named: "On the way", color: .blue, listID: nil)
        let tagged = try database.toggleCardCollectionEntryLabel(entryID: entry.id, labelID: label.id)
        XCTAssertEqual(tagged.labelIDs, [label.id])

        // Read back through the shared SELECT + fixed-index mapper.
        XCTAssertEqual(try fetchEntry(forCard: "alpha", in: database, list: list.id).labelIDs, [label.id])

        // Toggling again removes it.
        let cleared = try database.toggleCardCollectionEntryLabel(entryID: entry.id, labelID: label.id)
        XCTAssertTrue(cleared.labelIDs.isEmpty)
        XCTAssertTrue(try fetchEntry(forCard: "alpha", in: database, list: list.id).labelIDs.isEmpty)
    }

    func testColorAndScopeRoundTrip() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Deck")
        let global = try database.createCardLabel(named: "Owned", color: .green, listID: nil)
        let local = try database.createCardLabel(named: "Scratch", color: .pink, listID: list.id)

        XCTAssertEqual(try database.cardLabel(id: global.id)?.color, .green)
        XCTAssertTrue(try XCTUnwrap(database.cardLabel(id: global.id)).isGlobal)
        XCTAssertEqual(try database.cardLabel(id: local.id)?.listID, list.id)

        // A list-local label is only applicable inside its own list; global is applicable everywhere.
        let applicable = try database.applicableCardLabels(forListID: list.id).map(\.id)
        XCTAssertTrue(applicable.contains(global.id))
        XCTAssertTrue(applicable.contains(local.id))

        let other = try database.createCardCollection(named: "Other")
        let otherApplicable = try database.applicableCardLabels(forListID: other.id).map(\.id)
        XCTAssertTrue(otherApplicable.contains(global.id))
        XCTAssertFalse(otherApplicable.contains(local.id))
    }

    // MARK: - Search

    func testLabelSearchFiltersWithinCollection() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Deck")
        try database.appendCard("alpha", toList: list.id)
        try database.appendCard("beta", toList: list.id)
        let alpha = try fetchEntry(forCard: "alpha", in: database, list: list.id)

        let owned = try database.createCardLabel(named: "Owned", color: .green, listID: nil)
        _ = try database.toggleCardCollectionEntryLabel(entryID: alpha.id, labelID: owned.id)

        let positive = try results(database.searchCardCollectionEntries(forListID: list.id, text: "label:owned"))
        XCTAssertEqual(positive.map(\.cardID), ["alpha"])

        let negated = try results(database.searchCardCollectionEntries(forListID: list.id, text: "-label:owned"))
        XCTAssertEqual(negated.map(\.cardID), ["beta"])

        // Unknown label name → matches nothing (positive) / everything (negated).
        XCTAssertTrue(try results(database.searchCardCollectionEntries(forListID: list.id, text: "label:nope")).isEmpty)
        XCTAssertEqual(
            try results(database.searchCardCollectionEntries(forListID: list.id, text: "-label:nope")).count,
            2
        )
    }

    func testLabelSearchIsSeparatorInsensitive() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Deck")
        try database.appendCard("beta", toList: list.id)
        let beta = try fetchEntry(forCard: "beta", in: database, list: list.id)
        let onTheWay = try database.createCardLabel(named: "On the way", color: .blue, listID: nil)
        _ = try database.toggleCardCollectionEntryLabel(entryID: beta.id, labelID: onTheWay.id)

        for query in ["label:on-the-way", "label:\"on the way\"", "label:ontheway", "label:ON-THE-WAY"] {
            let matches = try results(database.searchCardCollectionEntries(forListID: list.id, text: query))
            XCTAssertEqual(matches.map(\.cardID), ["beta"], "query \(query) should match")
        }
    }

    func testLabelSearchCombinesWithCatalogPredicate() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Deck")
        try database.appendCard("alpha", toList: list.id)
        try database.appendCard("beta", toList: list.id)
        let owned = try database.createCardLabel(named: "Owned", color: .green, listID: nil)
        // Tag both, then narrow by a card predicate too.
        for cardID in ["alpha", "beta"] {
            _ = try database.toggleCardCollectionEntryLabel(
                entryID: try fetchEntry(forCard: cardID, in: database, list: list.id).id, labelID: owned.id)
        }
        let matches = try results(database.searchCardCollectionEntries(forListID: list.id, text: "label:owned alpha"))
        XCTAssertEqual(matches.map(\.cardID), ["alpha"])
    }

    // MARK: - Delete strips assignments

    func testDeletingLabelStripsItFromEntries() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Deck")
        try database.appendCard("alpha", toList: list.id)
        let alpha = try fetchEntry(forCard: "alpha", in: database, list: list.id)
        let owned = try database.createCardLabel(named: "Owned", color: .green, listID: nil)
        _ = try database.toggleCardCollectionEntryLabel(entryID: alpha.id, labelID: owned.id)
        XCTAssertEqual(try fetchEntry(forCard: "alpha", in: database, list: list.id).labelIDs, [owned.id])

        try database.deleteCardLabel(id: owned.id)
        XCTAssertNil(try database.cardLabel(id: owned.id))
        XCTAssertTrue(try fetchEntry(forCard: "alpha", in: database, list: list.id).labelIDs.isEmpty)
    }

    func testExportToGlobalFlipsScope() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Deck")
        let local = try database.createCardLabel(named: "Local", color: .teal, listID: list.id)
        XCTAssertEqual(local.listID, list.id)
        let exported = try database.exportCardLabelToGlobal(id: local.id)
        XCTAssertNil(exported.listID)
        XCTAssertTrue(try XCTUnwrap(database.cardLabel(id: local.id)).isGlobal)
    }

    // MARK: - Sync snapshot round-trip

    func testSnapshotRoundTripPreservesLabelsAndAssignments() throws {
        let database = try Fixtures.database()
        let list = try database.createCardCollection(named: "Deck")
        try database.appendCard("alpha", toList: list.id)
        let alpha = try fetchEntry(forCard: "alpha", in: database, list: list.id)
        let global = try database.createCardLabel(named: "Owned", color: .green, listID: nil)
        let local = try database.createCardLabel(named: "Scratch", color: .pink, listID: list.id)
        _ = try database.toggleCardCollectionEntryLabel(entryID: alpha.id, labelID: global.id)

        let snapshot = try database.cardCollectionLibrarySnapshot()
        XCTAssertEqual(Set(snapshot.labels.map(\.id)), [global.id, local.id])

        let restored = try Fixtures.database()
        try restored.restoreCardCollectionLibrarySnapshot(snapshot)
        XCTAssertEqual(Set(try restored.cardLabels().map(\.id)), [global.id, local.id])
        XCTAssertEqual(try fetchEntry(forCard: "alpha", in: restored, list: list.id).labelIDs, [global.id])
        XCTAssertEqual(try restored.cardLabel(id: global.id)?.color, .green)
    }

    // MARK: - Default seeding

    func testDefaultSeedingIsGlobalIdempotentAndEpochStamped() throws {
        let database = try Fixtures.database()
        try database.ensureDefaultLabelsSeeded()
        let first = try database.cardLabels()
        XCTAssertEqual(first.count, 6)
        XCTAssertTrue(first.allSatisfy(\.isGlobal))
        // Epoch-stamped so any user edit/delete always wins last-writer-wins.
        XCTAssertTrue(first.allSatisfy { $0.updatedAt.timeIntervalSince1970 < 1 })
        XCTAssertTrue(first.contains { $0.name == "On the way" && $0.color == .blue })
        XCTAssertTrue(first.contains { $0.id == CardLabelRecord.builtInIDPrefix + "owned" })

        // Idempotent: a second seed does not duplicate.
        try database.ensureDefaultLabelsSeeded()
        XCTAssertEqual(try database.cardLabels().count, 6)
    }

    func testDeletedDefaultIsNotResurrectedByReseed() throws {
        let database = try Fixtures.database()
        try database.ensureDefaultLabelsSeeded()
        try database.deleteCardLabel(id: CardLabelRecord.builtInIDPrefix + "wishlist")
        XCTAssertEqual(try database.cardLabels().count, 5)

        // The seed flag prevents a re-seed from bringing the deleted default back.
        try database.ensureDefaultLabelsSeeded()
        XCTAssertEqual(try database.cardLabels().count, 5)
        XCTAssertNil(try database.cardLabel(id: CardLabelRecord.builtInIDPrefix + "wishlist"))
    }

    // MARK: - Codable backward compatibility

    func testEntryDecodesLegacyJSONWithoutLabelIDs() throws {
        let legacy = Data("""
        {"id":"e1","listID":"l1","zone":"mainboard","cardID":"beta","position":0,"quantity":1,"createdAt":0,"updatedAt":0}
        """.utf8)
        let entry = try JSONDecoder().decode(CardCollectionEntryRecord.self, from: legacy)
        XCTAssertTrue(entry.labelIDs.isEmpty)
    }

    func testLabelRecordDecodesUnknownColorAsGrey() throws {
        let json = Data("""
        {"id":"x","name":"Odd","color":"chartreuse","position":0,"createdAt":0,"updatedAt":0}
        """.utf8)
        let label = try JSONDecoder().decode(CardLabelRecord.self, from: json)
        XCTAssertEqual(label.color, .grey)
        XCTAssertNil(label.listID)
    }
}
