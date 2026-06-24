#if os(visionOS)
import Foundation
import GrimoraCore
import XCTest

final class VisionNavigationUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraVisionUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testVisionUsesTouchTabShellWithoutDuplicateLibraryControls() throws {
        let app = try launchSeededApp()

        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 8))
        XCTAssertFalse(firstElement(app, identifier: "search-sidebar-button").exists)
        XCTAssertFalse(firstElement(app, identifier: "library-maintenance-menu").exists)

        attachScreenshot(app, named: "Vision Search Grid")

        activate(firstElement(app, identifier: "search-options-menu"))
        XCTAssertTrue(firstElement(app, identifier: "library-maintenance-menu").waitForExistence(timeout: 3))
        attachScreenshot(app, named: "Vision Search Options")
    }

    @MainActor
    func testVisionSearchOptionsSortAndOpenDetailWithoutLegacyFilters() throws {
        let app = try launchSeededApp()

        XCTAssertTrue(firstElement(app, identifier: "open-card-beta-mage").waitForExistence(timeout: 8))
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))
        XCTAssertTrue(firstElement(app, identifier: "open-card-token-mage").exists)
        XCTAssertTrue(card("beta-mage", appearsBefore: "alpha-mage", in: app))

        try activateMenuItem(app: app, menuIdentifier: "search-options-menu", itemIdentifier: "search-view-options-menu")
        activate(firstElement(app, identifier: "search-sort-direction-option-descending"))
        XCTAssertTrue(card("alpha-mage", appearsBefore: "beta-mage", in: app))

        activate(firstElement(app, identifier: "search-options-menu"))
        XCTAssertTrue(firstElement(app, identifier: "search-view-options-menu").waitForExistence(timeout: 3))
        XCTAssertFalse(firstElement(app, identifier: "search-filter-menu").exists)
        XCTAssertFalse(firstElement(app, identifier: "filter-universes-beyond").exists)
        XCTAssertFalse(firstElement(app, identifier: "filter-alchemy").exists)
        XCTAssertFalse(firstElement(app, identifier: "filter-real-cards").exists)

        app.terminate()
        let detailApp = try launchSeededApp()
        let betaCard = firstElement(detailApp, identifier: "open-card-beta-mage")
        XCTAssertTrue(betaCard.waitForExistence(timeout: 8))
        activate(betaCard)
        XCTAssertTrue(firstElement(detailApp, identifier: "card-detail").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForHittable(firstElement(detailApp, identifier: "open-card-alpha-mage")))
        XCTAssertTrue(firstElement(detailApp, identifier: "card-detail-add-to-list-button").waitForExistence(timeout: 3))
        XCTAssertTrue(firstElement(detailApp, identifier: "card-share-button").exists)
        XCTAssertTrue(firstElement(detailApp, identifier: "card-value-section").exists)
        XCTAssertTrue(firstElement(detailApp, identifier: "card-printings").exists)
        attachScreenshot(detailApp, named: "Vision Card Detail")

        activate(firstElement(detailApp, identifier: "card-detail-close-button"))
        XCTAssertTrue(waitForNonExistence(of: firstElement(detailApp, identifier: "card-detail")))
    }

    @MainActor
    func testVisionSearchSupportsFirstPrintSyntax() throws {
        let app = try launchSeededApp(defaultSearchText: "is:first-print")
        let total = app.staticTexts["search-results-total"]

        XCTAssertTrue(total.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue(of: total, toEqual: "2 cards"))
        XCTAssertTrue(firstElement(app, identifier: "open-card-alpha-mage").exists)
        XCTAssertTrue(firstElement(app, identifier: "open-card-token-mage").exists)
        XCTAssertFalse(firstElement(app, identifier: "open-card-beta-mage").exists)
    }

    @MainActor
    func testVisionSearchWaitsForSubmit() throws {
        let app = try launchSeededApp()
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        activate(searchField)
        searchField.typeText("alpha")

        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))
        XCTAssertTrue(firstElement(app, identifier: "open-card-beta-mage").exists)

        searchField.typeText(XCUIKeyboardKey.return.rawValue)

        XCTAssertTrue(waitForValue(of: total, toEqual: "1 card"))
        XCTAssertTrue(firstElement(app, identifier: "open-card-alpha-mage").exists)
        XCTAssertFalse(firstElement(app, identifier: "open-card-beta-mage").exists)
    }

    @MainActor
    func testVisionListsTabExposesOverview() throws {
        let app = try launchSeededApp()

        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 8))
        activate(button(app, labeled: "Lists"))

        XCTAssertTrue(firstElement(app, identifier: "card-lists-overview").waitForExistence(timeout: 3))
        XCTAssertTrue(firstElement(app, identifier: "card-list-overview-tile-Favourites").exists)
        XCTAssertTrue(firstElement(app, identifier: "create-list-button").waitForExistence(timeout: 3))
        XCTAssertFalse(firstElement(app, identifier: "empty-lists-browser").exists)
        attachScreenshot(app, named: "Vision Lists Overview")
    }

    @MainActor
    func testVisionListsUseAdaptiveSplitViewAtDefaultWidth() throws {
        let app = try launchListSeededApp()

        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 8))
        activate(button(app, labeled: "Lists"))
        XCTAssertTrue(firstElement(app, identifier: "card-lists-overview").waitForExistence(timeout: 3))
        XCTAssertTrue(firstElement(app, identifier: "card-lists-split-sidebar").exists)
        XCTAssertTrue(firstElement(app, identifier: "card-list-overview-tile-Favourites").exists)
        XCTAssertTrue(firstElement(app, identifier: "card-list-overview-tile-Drafts").exists)

        try openDraftsList(app)

        XCTAssertTrue(firstElement(app, identifier: "card-lists-split-sidebar").exists)
        XCTAssertTrue(firstElement(app, identifier: "card-list-row-Drafts").exists)
        XCTAssertTrue(firstElement(app, identifier: "card-list-row-Favourites").exists)
        XCTAssertTrue(firstElement(app, identifier: "list-detail-actions-menu").exists)

        let listCount = firstElement(app, identifier: "card-list-entry-count")
        XCTAssertTrue(listCount.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForText(of: listCount, toEqual: "1 card"))
        attachScreenshot(app, named: "Vision Wide Lists")
    }

    @MainActor
    func testVisionListsUseCompactNavigationWhenWindowIsNarrow() throws {
        let app = try launchListSeededApp(forceCompactLists: true)

        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 8))
        activate(button(app, labeled: "Lists"))

        XCTAssertTrue(firstElement(app, identifier: "card-lists-compact-stack").waitForExistence(timeout: 3))
        XCTAssertFalse(firstElement(app, identifier: "card-lists-split-sidebar").exists)

        XCTAssertTrue(firstElement(app, identifier: "card-lists-overview").waitForExistence(timeout: 3))
        XCTAssertTrue(firstElement(app, identifier: "card-list-overview-tile-Favourites").exists)
        let draftsTile = firstElement(app, identifier: "card-list-overview-tile-Drafts")
        XCTAssertTrue(draftsTile.waitForExistence(timeout: 3))
        activate(draftsTile)
        XCTAssertTrue(firstElement(app, identifier: "list-detail-actions-menu").waitForExistence(timeout: 3))
        XCTAssertTrue(firstElement(app, identifier: "card-list-entry-count").waitForExistence(timeout: 3))
    }

    @MainActor
    func testVisionCompactDashboardTileStaysTappableAfterLeavingAList() throws {
        let app = try launchListSeededApp(forceCompactLists: true)

        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 8))
        activate(button(app, labeled: "Lists"))

        XCTAssertTrue(firstElement(app, identifier: "card-lists-compact-stack").waitForExistence(timeout: 3))

        let draftsTile = firstElement(app, identifier: "card-list-overview-tile-Drafts")
        XCTAssertTrue(draftsTile.waitForExistence(timeout: 3))

        // Open the list, then return to the dashboard via the navigation back button.
        activate(draftsTile)
        XCTAssertTrue(firstElement(app, identifier: "list-detail-actions-menu").waitForExistence(timeout: 3))

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        activate(backButton)

        // Re-tapping the just-visited tile must reopen it — the regression was that
        // the stale selection left this tile unresponsive.
        let reopenedTile = firstElement(app, identifier: "card-list-overview-tile-Drafts")
        XCTAssertTrue(reopenedTile.waitForExistence(timeout: 3))
        activate(reopenedTile)
        XCTAssertTrue(firstElement(app, identifier: "list-detail-actions-menu").waitForExistence(timeout: 3))
        XCTAssertTrue(firstElement(app, identifier: "card-list-entry-count").waitForExistence(timeout: 3))
    }

    @MainActor
    func testVisionListActionsToggleStatsDescriptionTransferRenameAndUndo() throws {
        let app = try launchListSeededApp()

        try openDraftsList(app)
        XCTAssertTrue(waitForNonExistence(of: firstElement(app, identifier: "card-list-dashboard")))

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "toggle-list-dashboard-button"
        )
        XCTAssertTrue(firstElement(app, identifier: "card-list-dashboard").waitForExistence(timeout: 3))

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "undo-list-action-button"
        )
        XCTAssertTrue(waitForNonExistence(of: firstElement(app, identifier: "card-list-dashboard")))

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "toggle-list-description-button"
        )
        XCTAssertTrue(firstElement(app, identifier: "card-list-description-panel").waitForExistence(timeout: 3))

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "import-list-detail-button"
        )
        XCTAssertTrue(firstElement(app, identifier: "list-import-title").waitForExistence(timeout: 3))
        activate(app.buttons["Cancel"])

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "export-list-button"
        )
        XCTAssertTrue(firstElement(app, identifier: "card-list-export-format-picker").waitForExistence(timeout: 3))
        activate(app.buttons["Done"])

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "rename-list-Drafts"
        )
        try submitNamePrompt(app: app, name: "Vision Drafts", buttonTitle: "Rename", replacesExistingText: true)
        XCTAssertTrue(firstElement(app, identifier: "card-list-row-Vision Drafts").waitForExistence(timeout: 3))
    }

    @MainActor
    func testVisionListCategoriesCanBeCreatedRenamedMovedCollapsedAndDeleted() throws {
        let app = try launchListSeededApp()

        try openDraftsList(app)
        XCTAssertTrue(firstElement(app, identifier: "list-category-section-Ramp").waitForExistence(timeout: 3))

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "create-list-category-button"
        )
        try submitNamePrompt(app: app, name: "Removal", buttonTitle: "Create")
        XCTAssertTrue(firstElement(app, identifier: "list-category-section-Removal").waitForExistence(timeout: 3))

        try selectCategoryAction(app: app, category: "Ramp", actionIdentifier: "rename-list-category-Ramp")
        try submitNamePrompt(app: app, name: "Mana", buttonTitle: "Rename", replacesExistingText: true)
        XCTAssertTrue(firstElement(app, identifier: "list-category-section-Mana").waitForExistence(timeout: 3))

        try moveFirstListEntry(app: app, fromSectionNamed: "Uncategorized", toCategoryNamed: "Mana")
        XCTAssertTrue(waitForNonExistence(of: firstElement(app, identifier: "list-category-section-Uncategorized")))

        try moveFirstListEntry(app: app, fromSectionNamed: "Mana", toCategoryNamed: "Uncategorized")
        XCTAssertTrue(firstElement(app, identifier: "list-category-section-Uncategorized").waitForExistence(timeout: 3))

        let collapseButton = firstElement(app, identifier: "toggle-list-category-collapse-Mana")
        XCTAssertTrue(collapseButton.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(collapseButton.frame.width, 43)
        XCTAssertGreaterThanOrEqual(collapseButton.frame.height, 43)
        XCTAssertTrue(waitForValue(of: collapseButton, toEqual: "Expanded"))
        activate(collapseButton)
        XCTAssertTrue(waitForValue(of: collapseButton, toEqual: "Collapsed"))
        activate(collapseButton)
        XCTAssertTrue(waitForValue(of: collapseButton, toEqual: "Expanded"))

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "collapse-all-list-categories-button"
        )
        XCTAssertTrue(waitForNonExistence(of: firstElementWithPrefix(app, identifierPrefix: "open-list-entry-")))

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "unfold-all-list-categories-button"
        )
        XCTAssertTrue(firstElementWithPrefix(app, identifierPrefix: "open-list-entry-").waitForExistence(timeout: 3))

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "reorder-list-categories-button"
        )
        XCTAssertTrue(firstElement(app, identifier: "compact-list-category-row-Mana").waitForExistence(timeout: 3))

        let moveManaDownButton = firstElement(app, identifier: "move-list-category-down-Mana")
        XCTAssertTrue(moveManaDownButton.waitForExistence(timeout: 3))
        activate(moveManaDownButton)

        let moveManaToTopButton = firstElement(app, identifier: "move-list-category-top-Mana")
        XCTAssertTrue(moveManaToTopButton.waitForExistence(timeout: 3))
        activate(moveManaToTopButton)

        try activateMenuItem(
            app: app,
            menuIdentifier: "list-detail-actions-menu",
            itemIdentifier: "finish-reorder-list-categories-button"
        )

        let manaSection = firstElement(app, identifier: "list-category-section-Mana")
        let removalSection = firstElement(app, identifier: "list-category-section-Removal")
        XCTAssertTrue(manaSection.waitForExistence(timeout: 3))
        XCTAssertTrue(removalSection.waitForExistence(timeout: 3))
        XCTAssertLessThan(manaSection.frame.minY, removalSection.frame.minY)

        try selectCategoryAction(app: app, category: "Removal", actionIdentifier: "delete-list-category-Removal")
        XCTAssertTrue(waitForNonExistence(of: firstElement(app, identifier: "list-category-section-Removal")))
    }

    @MainActor
    private func launchSeededApp(defaultSearchText: String = "mage") throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-\(DefaultSearchPreferenceKeys.text)",
            defaultSearchText,
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
        let fixtureData = try JSONEncoder().encode(Self.fixtureCards)
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] =
            temporaryDirectory.appendingPathComponent("vision-search-fixture.sqlite").path
        app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] = String(decoding: fixtureData, as: Unicode.UTF8.self)
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] = temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] = "GrimoraVisionUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func launchListSeededApp(forceCompactLists: Bool = false) throws -> XCUIApplication {
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
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] = temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] = "GrimoraVisionListUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        if forceCompactLists {
            app.launchEnvironment["GRIMORA_TEST_FORCE_COMPACT_LISTS"] = "1"
        }
        app.launch()
        return app
    }

    private func seedDatabase() throws -> URL {
        let databaseURL = temporaryDirectory.appendingPathComponent("vision-list-fixture.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        try database.replaceAllCards(Self.fixtureCards)
        try database.saveMetadataValue("2026-04-25T09:09:59.477+00:00", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        try database.saveMetadataValue(CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
        try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)

        let list = try database.createCardList(named: "Drafts")
        _ = try database.createCardListCategory(inList: list.id, named: "Ramp")
        try database.appendCard("alpha-mage", toList: list.id)
        return databaseURL
    }

    @MainActor
    private func openDraftsList(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 8), file: file, line: line)
        activate(button(app, labeled: "Lists"))

        let row = firstElement(app, identifier: "card-list-row-Drafts")
        XCTAssertTrue(row.waitForExistence(timeout: 3), file: file, line: line)
        activate(row)
        XCTAssertTrue(firstElement(app, identifier: "card-list-detail-scroll").waitForExistence(timeout: 3), file: file, line: line)
    }

    @MainActor
    private func activateMenuItem(
        app: XCUIApplication,
        menuIdentifier: String,
        itemIdentifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let menu = firstElement(app, identifier: menuIdentifier)
        XCTAssertTrue(menu.waitForExistence(timeout: 3), file: file, line: line)
        activate(menu)

        let item = firstElement(app, identifier: itemIdentifier)
        if item.waitForExistence(timeout: 3) {
            activate(item)
            return
        }

        if let labels = nativeMenuFallbackLabels(for: itemIdentifier) {
            for label in labels {
                if clickMenuItemOrButton(app: app, named: label) {
                    return
                }
            }
        }

        XCTFail("Expected menu item \(itemIdentifier) to exist", file: file, line: line)
    }

    @MainActor
    private func card(_ lhsID: String, appearsBefore rhsID: String, in app: XCUIApplication) -> Bool {
        let lhs = app.buttons["open-card-\(lhsID)"]
        let rhs = app.buttons["open-card-\(rhsID)"]
        guard lhs.waitForExistence(timeout: 3), rhs.waitForExistence(timeout: 3) else {
            return false
        }

        if abs(lhs.frame.minY - rhs.frame.minY) > 1 {
            return lhs.frame.minY < rhs.frame.minY
        }
        return lhs.frame.minX < rhs.frame.minX
    }

    @MainActor
    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.exists && element.isHittable
    }

    @MainActor
    private func submitNamePrompt(
        app: XCUIApplication,
        name: String,
        buttonTitle: String,
        replacesExistingText: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), file: file, line: line)
        activate(field)
        if replacesExistingText {
            let existingText = field.value as? String ?? ""
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            for _ in existingText {
                field.typeText(XCUIKeyboardKey.delete.rawValue)
            }
        }
        field.typeText(name)

        let button = app.buttons[buttonTitle]
        XCTAssertTrue(button.waitForExistence(timeout: 3), file: file, line: line)
        activate(button)
    }

    @MainActor
    private func selectCategoryAction(
        app: XCUIApplication,
        category: String,
        actionIdentifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actionButton = firstElement(app, identifier: "list-category-actions-\(category)")
        XCTAssertTrue(actionButton.waitForExistence(timeout: 3), file: file, line: line)
        activate(actionButton)

        let action = firstElement(app, identifier: actionIdentifier)
        if action.waitForExistence(timeout: 3) {
            activate(action)
            return
        }

        if let labels = nativeMenuFallbackLabels(for: actionIdentifier) {
            for label in labels {
                if clickMenuItemOrButton(app: app, named: label) {
                    return
                }
            }
        }

        XCTFail("Expected category action \(actionIdentifier) to exist", file: file, line: line)
    }

    @MainActor
    private func moveFirstListEntry(
        app: XCUIApplication,
        fromSectionNamed sectionName: String,
        toCategoryNamed categoryName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let section = firstElement(app, identifier: "list-category-section-content-\(sectionName)")
        XCTAssertTrue(section.waitForExistence(timeout: 3), file: file, line: line)

        // Move is now nested inside the per-card "more" (ellipsis) menu, so open
        // that first, then drill into the Move to Category submenu. The submenu
        // items render in a menu overlay outside the section, so search the whole
        // app for them.
        let moreButton = section.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "more-list-entry-"))
            .firstMatch
        XCTAssertTrue(moreButton.waitForExistence(timeout: 3), file: file, line: line)
        activate(moreButton)

        let moveButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "move-list-entry-", "-category"))
            .firstMatch
        XCTAssertTrue(moveButton.waitForExistence(timeout: 3), file: file, line: line)
        activate(moveButton)
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: categoryName), file: file, line: line)
    }

    @MainActor
    private func clickMenuItemOrButton(app: XCUIApplication, named name: String) -> Bool {
        let menuItem = app.menuItems[name]
        if menuItem.waitForExistence(timeout: 1) {
            activate(menuItem)
            return true
        }

        let button = app.buttons[name]
        if button.waitForExistence(timeout: 1) {
            activate(button)
            return true
        }

        return false
    }

    private func nativeMenuFallbackLabels(for identifier: String) -> [String]? {
        switch identifier {
        case "toggle-list-dashboard-button":
            ["Show Stats", "Hide Stats"]
        case "undo-list-action-button":
            ["Undo"]
        case "toggle-list-description-button":
            ["Description"]
        case "import-list-detail-button":
            ["Import"]
        case "export-list-button":
            ["Export List"]
        case "create-list-category-button":
            ["New Category"]
        case "collapse-all-list-categories-button":
            ["Collapse All"]
        case "unfold-all-list-categories-button":
            ["Expand All"]
        case "reorder-list-categories-button":
            ["Reorder Categories"]
        case "finish-reorder-list-categories-button":
            ["Finish Reordering"]
        default:
            if identifier.hasPrefix("rename-list-category-") {
                ["Rename"]
            } else if identifier.hasPrefix("delete-list-category-") {
                ["Delete"]
            } else if identifier.hasPrefix("rename-list-") {
                ["Rename List"]
            } else {
                nil
            }
        }
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

private extension VisionNavigationUITests {
    static var fixtureCards: [CardRecord] {
        [
            mageCard(
                id: "beta-mage",
                name: "Beta Mage",
                oracleID: "beta-oracle",
                releasedAt: "2024-02-02",
                collectorNumber: "2",
                rarity: "rare",
                colorSortKey: 1,
                oracleText: "Draw two cards.",
                artist: "Vision Artist",
                priceUSD: 4.5,
                isRealCard: true,
                isReprint: true
            ),
            mageCard(
                id: "alpha-mage",
                name: "Alpha Mage",
                oracleID: "alpha-oracle",
                releasedAt: "2020-01-01",
                collectorNumber: "1",
                rarity: "common",
                colorSortKey: 2,
                oracleText: "Scry 1.",
                artist: "Vision Artist",
                priceUSD: 1.25,
                isRealCard: true
            ),
            mageCard(
                id: "token-mage",
                name: "Token Mage",
                oracleID: "token-oracle",
                releasedAt: "2022-03-03",
                collectorNumber: "3",
                rarity: "common",
                colorSortKey: 3,
                oracleText: "A non-real token fixture.",
                artist: "Vision Artist",
                priceUSD: nil,
                isRealCard: false
            )
        ]
    }

    static func mageCard(
        id: String,
        name: String,
        oracleID: String,
        releasedAt: String,
        collectorNumber: String,
        rarity: String,
        colorSortKey: Int,
        oracleText: String,
        artist: String,
        priceUSD: Double?,
        isRealCard: Bool,
        isReprint: Bool = false
    ) -> CardRecord {
        CardRecord(
            id: id,
            oracleID: oracleID,
            name: name,
            releasedAt: releasedAt,
            setCode: "vis",
            setName: "Vision Fixture",
            setType: "expansion",
            collectorNumber: collectorNumber,
            collectorNumberNumber: Int(collectorNumber),
            rarity: rarity,
            rarityRank: rarity == "rare" ? 2 : 0,
            artist: artist,
            manaCost: "{1}{U}",
            manaValue: 2,
            priceUSD: priceUSD,
            colorSortKey: colorSortKey,
            colors: ["U"],
            colorIdentity: ["U"],
            layout: "normal",
            typeLine: "Creature — Wizard",
            oracleText: oracleText,
            games: ["paper"],
            finishes: ["nonfoil"],
            isRealCard: isRealCard,
            isReprint: isReprint
        )
    }
}
#endif
