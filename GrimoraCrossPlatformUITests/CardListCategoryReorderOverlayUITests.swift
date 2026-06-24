#if os(iOS) || os(visionOS)
import Foundation
import GrimoraCore
import UIKit
import XCTest

/// Verifies the touch category reorder overlay (L5): a category's drag handle opens a focused
/// sheet listing every category, and dragging a row there reorders and persists the categories.
/// The overlay ships on every touch platform (`#if os(iOS) || os(visionOS)` in
/// `CardListCategoryViews`), so this coverage runs on both iOS and visionOS.
final class CardListCategoryReorderOverlayUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraCategoryReorder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testReorderHandleOpensOverlayAndDragReordersCategories() throws {
        let app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 8))

        openList(app)

        // Enter the dedicated reorder mode from the list actions menu.
        try activateActionsMenuItem(app, itemIdentifier: "reorder-list-categories-button")

        let rampHandle = firstElement(app, identifier: "open-list-category-reorder-Ramp")
        XCTAssertTrue(rampHandle.waitForExistence(timeout: 5), "Reorder handle should appear in reorder mode")
        XCTAssertGreaterThanOrEqual(rampHandle.frame.height, 43, "Handle must meet the 44pt tap target")

        // Tapping the handle opens the grey-box reorder overlay.
        activate(rampHandle)

        let overlayRamp = firstElement(app, identifier: "reorder-sheet-category-row-Ramp")
        let overlayLands = firstElement(app, identifier: "reorder-sheet-category-row-Lands")
        let doneButton = firstElement(app, identifier: "finish-list-category-reorder-button")
        XCTAssertTrue(overlayRamp.waitForExistence(timeout: 5), "Overlay should list every category")
        XCTAssertTrue(overlayLands.waitForExistence(timeout: 2))
        XCTAssertTrue(doneButton.waitForExistence(timeout: 2))

        #if os(iOS)
        // Drag Lands above Ramp to reorder. The sheet is a `List` in active edit mode, where a row
        // reorders via a long-press that "lifts" the row, then a drag. The original gesture used a
        // short press and a fast, hold-free drag, so the row frequently dropped before the move
        // registered — that was the flake. Hold long enough to lift the row, drag slowly onto Ramp,
        // and hold again before releasing so the drop settles.
        overlayLands.press(
            forDuration: 1.0,
            thenDragTo: overlayRamp,
            withVelocity: 150,
            thenHoldForDuration: 1.0
        )
        #endif

        activate(doneButton)
        XCTAssertTrue(waitForNonExistence(of: doneButton, timeout: 3), "Done should dismiss the overlay")

        #if os(iOS)
        // Dismissing the overlay returns to reorder mode; its inline rows reflect the new order,
        // with Lands now dragged above Ramp.
        //
        // The ordering assertion is iOS-only: the visionOS 26.5 simulator does not deliver the
        // press-and-drag reorder gesture to the sheet's draggable rows, so it cannot move a row.
        // visionOS still exercises the valuable half of this flow above — entering reorder mode,
        // the 44pt drag handle, and the overlay presenting every category and dismissing via Done.
        let landsRow = firstElement(app, identifier: "compact-list-category-row-Lands")
        let rampRow = firstElement(app, identifier: "compact-list-category-row-Ramp")
        XCTAssertTrue(landsRow.waitForExistence(timeout: 3))
        XCTAssertTrue(rampRow.waitForExistence(timeout: 3))
        XCTAssertLessThan(
            landsRow.frame.minY,
            rampRow.frame.minY,
            "Dragging Lands above Ramp in the overlay should reorder the categories"
        )
        #else
        // visionOS: confirm the overlay fully dismissed and reorder mode is still active.
        XCTAssertTrue(
            firstElement(app, identifier: "compact-list-category-row-Ramp").waitForExistence(timeout: 3)
        )
        #endif
    }

    @MainActor
    private func openList(_ app: XCUIApplication) {
        activate(button(app, labeled: "Lists"))
        let listRow = firstElement(app, identifier: "card-list-row-Reorder Deck")
        if listRow.waitForExistence(timeout: 1) {
            activate(listRow)
        } else {
            let tile = firstElement(app, identifier: "card-list-overview-tile-Reorder Deck")
            XCTAssertTrue(tile.waitForExistence(timeout: 5))
            activate(tile)
        }
        XCTAssertTrue(firstElement(app, identifier: "card-list-detail-scroll").waitForExistence(timeout: 5))
    }

    @MainActor
    private func activateActionsMenuItem(_ app: XCUIApplication, itemIdentifier: String) throws {
        var menu = firstElement(app, identifier: "list-detail-actions-menu")
        if !menu.waitForExistence(timeout: 1) {
            menu = firstElement(app, identifier: "card-list-view-mode-picker")
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        activate(menu)

        // The actions menu is taller than the screen; the "Organize" section (with the reorder
        // button) sits below the fold, so scroll the open menu until the item is realised.
        let item = firstElement(app, identifier: itemIdentifier)
        _ = item.waitForExistence(timeout: 1)
        var scrolls = 0
        while !item.exists && scrolls < 8 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.55))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.2))
            start.press(forDuration: 0.05, thenDragTo: end)
            scrolls += 1
        }
        XCTAssertTrue(item.exists, "Menu item \(itemIdentifier) should exist after scrolling the menu")
        activate(item)
    }

    @MainActor
    private func launchSeededApp() throws -> XCUIApplication {
        let databaseURL = try seedDatabase()
        let app = XCUIApplication()
        app.launchArguments += [
            "-\(DefaultSearchPreferenceKeys.text)",
            "",
            "-\(DefaultSearchPreferenceKeys.alwaysIncludedText)",
            "",
            "-\(DefaultSearchPreferenceKeys.searchInputMode)",
            "scryfall",
            "-\(DefaultSearchPreferenceKeys.cloudSyncMode)",
            "disabled"
        ]
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] = databaseURL.path
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] = temporaryDirectory
            .appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
            "GrimoraCategoryReorder-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    private func seedDatabase() throws -> URL {
        let databaseURL = temporaryDirectory.appendingPathComponent("reorder-list.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let cards = (0..<8).map { index in
            CardRecord(
                id: String(format: "reorder-card-%02d", index),
                oracleID: String(format: "reorder-oracle-%02d", index),
                name: "Reorder Card \(index)",
                releasedAt: "2024-01-01",
                setCode: "reo",
                setName: "Reorder Fixture",
                setType: "expansion",
                collectorNumber: "\(index + 1)",
                collectorNumberNumber: index + 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: index,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Fixture.",
                isRealCard: true
            )
        }
        try database.replaceAllCards(cards)
        try database.saveMetadataValue(
            "2026-04-25T09:09:59.477+00:00",
            forKey: MetadataKey.defaultCardsUpdatedAt.rawValue
        )
        try database.saveMetadataValue(
            CardDatabase.currentSearchSchemaVersion,
            forKey: MetadataKey.searchSchemaVersion.rawValue
        )
        try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)

        let list = try database.createCardList(named: "Reorder Deck")
        try database.setCardListViewMode(id: list.id, viewMode: .list)
        let categoryNames = ["Ramp", "Removal", "Utility", "Lands"]
        let categories = try categoryNames.map { name in
            try database.createCardListCategory(inList: list.id, named: name)
        }
        for (index, card) in cards.enumerated() {
            try database.appendCard(
                card.id,
                toList: list.id,
                categoryID: categories[index % categories.count].id
            )
        }
        return databaseURL
    }
}

private enum DefaultSearchPreferenceKeys {
    static let text = "Grimora.defaultSearch.text"
    static let alwaysIncludedText = "Grimora.search.alwaysIncludedText"
    static let searchInputMode = "Grimora.search.inputMode"
    static let cloudSyncMode = "Grimora.cloudSync.mode"
}
#endif
