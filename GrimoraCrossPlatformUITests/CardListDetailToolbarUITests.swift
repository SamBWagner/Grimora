#if os(iOS)
import Foundation
import GrimoraCore
import UIKit
import XCTest

/// L3 — the iOS list-detail trailing cluster used to pack the view-mode picker
/// and the actions menu into one `ToolbarItemGroup`. Opening the menu hid the
/// sibling picker but left the group container behind ("empty box"). The fix
/// gives each control its own `ToolbarItem`; this test pins that behaviour: the
/// picker and the menu coexist, and the picker stays present while the menu is
/// open.
final class CardListDetailToolbarUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraToolbar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testViewModePickerStaysVisibleWhileActionsMenuIsOpen() throws {
        let app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 8))

        activate(button(app, labeled: "Lists"))
        openList(app, named: "Toolbar Fixture")

        // Both trailing controls exist as independent toolbar items.
        let viewModePicker = firstElement(app, identifier: "card-list-view-mode-picker")
        let actionsMenu = firstElement(app, identifier: "list-detail-actions-menu")
        XCTAssertTrue(viewModePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(actionsMenu.waitForExistence(timeout: 5))

        // Opening the actions menu must not remove the picker from the cluster.
        activate(actionsMenu)
        XCTAssertTrue(
            firstElement(app, identifier: "rename-list-Toolbar Fixture").waitForExistence(timeout: 3),
            "Actions menu did not present its contents"
        )
        XCTAssertTrue(
            viewModePicker.exists,
            "View-mode picker disappeared while the actions menu was open"
        )

        // Dismiss the menu and confirm the cluster is still intact.
        activate(firstElement(app, identifier: "rename-list-Toolbar Fixture"))
        XCTAssertTrue(viewModePicker.waitForExistence(timeout: 3))
        XCTAssertTrue(actionsMenu.waitForExistence(timeout: 3))
    }

    @MainActor
    private func openList(_ app: XCUIApplication, named name: String) {
        let listRow = firstElement(app, identifier: "card-list-row-\(name)")
        if listRow.waitForExistence(timeout: 1) {
            activate(listRow)
        } else {
            let listTile = firstElement(app, identifier: "card-list-overview-tile-\(name)")
            XCTAssertTrue(listTile.waitForExistence(timeout: 5))
            activate(listTile)
        }
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
            "GrimoraToolbar-\(UIDevice.current.userInterfaceIdiom.rawValue)-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    private func seedDatabase() throws -> URL {
        let databaseURL = temporaryDirectory.appendingPathComponent("toolbar-list.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        let cards = (0..<6).map { index in
            CardRecord(
                id: String(format: "toolbar-card-%03d", index),
                oracleID: String(format: "toolbar-oracle-%03d", index),
                name: "Toolbar Card \(index)",
                releasedAt: "2024-01-01",
                setCode: "tbr",
                setName: "Toolbar Fixture",
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

        let list = try database.createCardList(named: "Toolbar Fixture")
        try database.setCardListViewMode(id: list.id, viewMode: .list)
        let categories = try (0..<2).map { index in
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
    private func firstElement(_ root: XCUIElement, identifier: String) -> XCUIElement {
        root.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func button(_ app: XCUIApplication, labeled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func activate(_ element: XCUIElement) {
        element.tap()
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
