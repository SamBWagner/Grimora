#if os(iOS) || os(visionOS)
import Foundation
import GrimoraCore
import UIKit
import XCTest

final class CardListCategoryPerformanceUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraCategoryPerformance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testLargeCategorizedListCollapseAndViewModeStayResponsive() throws {
        let app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 8))

        activate(button(app, labeled: "Lists"))
        let listRow = firstElement(app, identifier: "card-list-row-Large Categories")
        if listRow.waitForExistence(timeout: 1) {
            activate(listRow)
        } else {
            let listTile = firstElement(app, identifier: "card-list-overview-tile-Large Categories")
            XCTAssertTrue(listTile.waitForExistence(timeout: 5))
            activate(listTile)
        }

        let viewModePicker = firstElement(app, identifier: "card-list-view-mode-picker")
        XCTAssertTrue(viewModePicker.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: viewModePicker, toEqual: "List"))

        let categoryName = "Category 00"
        let collapseButton = firstElement(app, identifier: "toggle-list-category-collapse-\(categoryName)")
        XCTAssertTrue(collapseButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(collapseButton.frame.width, 43)
        XCTAssertGreaterThanOrEqual(collapseButton.frame.height, 43)

        activate(collapseButton)
        XCTAssertTrue(waitForValue(of: collapseButton, toEqual: "Collapsed"))

        for _ in 0..<3 {
            activate(collapseButton)
            XCTAssertTrue(waitForValue(of: collapseButton, toEqual: "Expanded"))
            activate(collapseButton)
            XCTAssertTrue(waitForValue(of: collapseButton, toEqual: "Collapsed"))
        }
        activate(collapseButton)
        XCTAssertTrue(waitForValue(of: collapseButton, toEqual: "Expanded"))

        if UIDevice.current.userInterfaceIdiom == .pad {
            try activateMenuItem(
                app: app,
                menuIdentifier: "list-detail-actions-menu",
                itemIdentifier: "collapse-all-list-categories-button"
            )
            XCTAssertTrue(waitForValue(of: collapseButton, toEqual: "Collapsed"))

            try activateMenuItem(
                app: app,
                menuIdentifier: "list-detail-actions-menu",
                itemIdentifier: "unfold-all-list-categories-button"
            )
            XCTAssertTrue(waitForValue(of: collapseButton, toEqual: "Expanded"))
        }

        XCTAssertTrue(waitForText(
            of: firstElement(app, identifier: "card-list-entry-count"),
            toEqual: "120 cards"
        ))

        let scrollView = firstElement(app, identifier: "card-list-detail-scroll")
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3))
        for _ in 0..<3 {
            scrollView.swipeUp()
        }

    }

    // iOS-only: this pins a compact (iPhone) push-navigation regression — open a list, tap the
    // navigation back button, and re-tap the just-visited overview tile. At visionOS's default
    // window width the lists use the adaptive split view instead of push navigation, so there is
    // no back button (`navigationBars.buttons.firstMatch` resolves to a system dictation control)
    // and the tile never leaves the screen. The equivalent visionOS coverage forces compact mode
    // in `VisionNavigationUITests.testVisionCompactDashboardTileStaysTappableAfterLeavingAList`.
    #if os(iOS)
    @MainActor
    func testDashboardTileStaysTappableAfterLeavingAList() throws {
        let app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 8))

        activate(button(app, labeled: "Lists"))

        let tile = firstElement(app, identifier: "card-list-overview-tile-Large Categories")
        XCTAssertTrue(tile.waitForExistence(timeout: 5))

        // Open the list, then return to the dashboard via the navigation back button.
        activate(tile)
        XCTAssertTrue(firstElement(app, identifier: "card-list-detail-scroll").waitForExistence(timeout: 3))

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        activate(backButton)

        // Re-tapping the just-visited tile must reopen the list. The regression was
        // that the stale selection left this tile unresponsive after the first visit.
        let reopenedTile = firstElement(app, identifier: "card-list-overview-tile-Large Categories")
        XCTAssertTrue(reopenedTile.waitForExistence(timeout: 5))
        activate(reopenedTile)
        XCTAssertTrue(firstElement(app, identifier: "card-list-detail-scroll").waitForExistence(timeout: 3))
        XCTAssertTrue(waitForText(
            of: firstElement(app, identifier: "card-list-entry-count"),
            toEqual: "120 cards"
        ))
    }
    #endif

    @MainActor
    private func launchSeededApp() throws -> XCUIApplication {
        let databaseURL = try seedDatabase()
        let app = XCUIApplication()
        app.launchArguments += [
            "-\(DefaultSearchPreferenceKeys.text)",
            "",
            "-\(DefaultSearchPreferenceKeys.alwaysIncludedText)",
            "",
            "-\(DefaultSearchPreferenceKeys.sortMode)",
            SortMode.releaseDate.rawValue,
            "-\(DefaultSearchPreferenceKeys.sortDirection)",
            SearchSortDirection.ascending.rawValue,
            "-\(DefaultSearchPreferenceKeys.searchInputMode)",
            "scryfall",
            "-\(DefaultSearchPreferenceKeys.cloudSyncMode)",
            "disabled"
        ]
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] = databaseURL.path
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] = temporaryDirectory
            .appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
            "GrimoraCategoryPerformance-\(UIDevice.current.userInterfaceIdiom.rawValue)-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    private func seedDatabase() throws -> URL {
        let databaseURL = temporaryDirectory.appendingPathComponent("categorized-list.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let cards = (0..<120).map { index in
            CardRecord(
                id: String(format: "category-card-%03d", index),
                oracleID: String(format: "category-oracle-%03d", index),
                name: "Category Card \(index)",
                releasedAt: "2024-01-01",
                setCode: "cat",
                setName: "Category Fixture",
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
        try database.saveMetadataValue(
            "true",
            forKey: MetadataKey.requiredImagesCached.rawValue
        )

        let list = try database.createCardList(named: "Large Categories")
        try database.setCardListViewMode(id: list.id, viewMode: .list)
        let categories = try (0..<8).map { index in
            try database.createCardListCategory(
                inList: list.id,
                named: String(format: "Category %02d", index)
            )
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

    @MainActor
    private func activateMenuItem(
        app: XCUIApplication,
        menuIdentifier: String,
        itemIdentifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var menu = firstElement(app, identifier: menuIdentifier)
        if !menu.waitForExistence(timeout: 1), menuIdentifier == "list-detail-actions-menu" {
            menu = firstElement(app, identifier: "card-list-view-mode-picker")
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 3), file: file, line: line)
        activate(menu)

        let item = firstElement(app, identifier: itemIdentifier)
        if item.waitForExistence(timeout: 2) {
            activate(item)
            return
        }

        let fallbackLabel =
            itemIdentifier == "collapse-all-list-categories-button"
            ? "Collapse All"
            : "Expand All"
        let fallback = app.buttons[fallbackLabel]
        XCTAssertTrue(fallback.waitForExistence(timeout: 2), file: file, line: line)
        activate(fallback)
    }
}

private enum DefaultSearchPreferenceKeys {
    static let text = "Grimora.defaultSearch.text"
    static let alwaysIncludedText = "Grimora.search.alwaysIncludedText"
    static let sortMode = "Grimora.defaultSearch.sortMode"
    static let sortDirection = "Grimora.defaultSearch.sortDirection"
    static let searchInputMode = "Grimora.search.inputMode"
    static let cloudSyncMode = "Grimora.cloudSync.mode"
}
#endif
