import AppKit
import Darwin
import GrimoraCore
import XCTest

@MainActor
final class GrimoraMacUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testSearchIncludesAllCardClassesWithoutLegacyFilterControls() throws {
        let databaseURL = try seedDatabase(cards: allCardClassFixtureCards())
        let app = launchApp(databaseURL: databaseURL)
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))
        XCTAssertTrue(app.buttons["open-card-token"].exists)
        XCTAssertFalse(firstElement(app, identifier: "search-filter-menu").exists)
        XCTAssertFalse(firstElement(app, identifier: "filter-universes-beyond").exists)
        XCTAssertFalse(firstElement(app, identifier: "filter-alchemy").exists)
        XCTAssertFalse(firstElement(app, identifier: "filter-real-cards").exists)
    }

    func testSearchWaitsForReturn() throws {
        let databaseURL = try seedDatabase(cards: allCardClassFixtureCards())
        let app = launchApp(databaseURL: databaseURL)
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("forest")

        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))
        XCTAssertTrue(app.buttons["open-card-token"].exists)

        searchField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(of: total, toEqual: "1 card"))
        XCTAssertTrue(app.buttons["open-card-alpha"].exists)
        XCTAssertFalse(app.buttons["open-card-token"].exists)

        // Clearing the field in one step (⌘A + delete) while the draft still mirrors the
        // committed query drops the active search and returns to the default results
        // immediately, like the ✕ button — only character-by-character backspacing keeps an
        // unsubmitted edit that waits for return.
        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])

        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))
        XCTAssertTrue(app.buttons["open-card-token"].exists)
    }

    func testAdvancedSearchFieldButtonOpensFormAndAppliesQuery() throws {
        let databaseURL = try seedDatabase(cards: allCardClassFixtureCards())
        let app = launchApp(databaseURL: databaseURL)
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))

        // Open via the permanent search-field button.
        let launchButton = firstElement(app, identifier: "advanced-search-launch-button")
        XCTAssertTrue(launchButton.waitForExistence(timeout: 5))
        launchButton.click()

        let form = firstElement(app, identifier: "advanced-search-form")
        XCTAssertTrue(form.waitForExistence(timeout: 5))

        // Build a name query in the form.
        let nameField = firstElement(app, identifier: "advanced-search-name-field")
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("Forest")

        // Tapping Search runs it through the normal submit path and filters results.
        let submit = firstElement(app, identifier: "advanced-search-submit")
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        submit.click()

        XCTAssertTrue(waitForNonExistence(of: form, timeout: 5))
        XCTAssertTrue(waitForValue(of: total, toEqual: "1 card"))
        XCTAssertTrue(app.buttons["open-card-alpha"].exists)
        XCTAssertFalse(app.buttons["open-card-token"].exists)
    }

    func testAdvancedSearchMenuCommandOpensFormAndAppliesQuery() throws {
        let databaseURL = try seedDatabase(cards: allCardClassFixtureCards())
        let app = launchApp(databaseURL: databaseURL)
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))

        // The ⇧⌘F menu command must open the same form, even when the search
        // field already holds keyboard focus on launch.
        app.typeKey("f", modifierFlags: [.command, .shift])

        let form = firstElement(app, identifier: "advanced-search-form")
        XCTAssertTrue(form.waitForExistence(timeout: 5))

        let nameField = firstElement(app, identifier: "advanced-search-name-field")
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("Mage")
        firstElement(app, identifier: "advanced-search-submit").click()

        XCTAssertTrue(waitForNonExistence(of: form, timeout: 5))
        XCTAssertTrue(waitForValue(of: total, toEqual: "1 card"))
        XCTAssertTrue(app.buttons["open-card-beta"].exists)
        XCTAssertFalse(app.buttons["open-card-token"].exists)
    }

    func testSearchSupportsFirstPrintSyntax() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "first-print",
                name: "First Print Fixture",
                releasedAt: "2025-01-01",
                setCode: "ncc",
                setName: "First Print Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "",
                isReprint: false
            ),
            CardRecord(
                id: "reprint",
                name: "Reprint Fixture",
                releasedAt: "2024-01-01",
                setCode: "ncc",
                setName: "First Print Set",
                setType: "expansion",
                collectorNumber: "2",
                collectorNumberNumber: 2,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 2,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "",
                isReprint: true
            )
        ])
        let app = launchApp(databaseURL: databaseURL, defaultSearchText: "is:first-print")
        let total = app.staticTexts["search-results-total"]

        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: total, toEqual: "1 card"))
        XCTAssertTrue(app.buttons["open-card-first-print"].exists)
        XCTAssertFalse(app.buttons["open-card-reprint"].exists)
    }

    func testCardDetailActionsAddToListAndExposeShareOptions() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                artist: "Fixture Artist",
                manaValue: 1,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature — Treefolk",
                oracleText: "Reach",
                isRealCard: true
            )
        ])
        let database = try CardDatabase(storage: .file(databaseURL))
        _ = try database.createCardCollection(named: "Detail Picks")

        let app = launchApp(databaseURL: databaseURL)
        let cardButton = app.buttons["open-card-alpha"]
        XCTAssertTrue(cardButton.waitForExistence(timeout: 5))
        doubleClickSearchResultCard(cardButton)

        let detailAddButton = app.descendants(matching: .any)["card-detail-add-to-list-button"]
        XCTAssertTrue(detailAddButton.waitForExistence(timeout: 3))
        detailAddButton.click()
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Detail Picks"))

        let detailPicksRow = app.buttons["card-list-row-Detail Picks"]
        XCTAssertTrue(detailPicksRow.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: detailPicksRow, toEqual: "1 card"))

        let shareButton = app.descendants(matching: .any)["card-share-button"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 3))
        shareButton.click()
        XCTAssertTrue(contextMenuContains(app: app, named: "Link"))
        XCTAssertTrue(contextMenuContains(app: app, named: "Details"))
        app.typeKey(.escape, modifierFlags: [])
    }

    func testUnsupportedSearchShowsOfflineSyntaxState() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                manaValue: 2,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Reach",
                isRealCard: true
            )
        ])

        let app = launchApp(databaseURL: databaseURL, appearance: .light)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("atag:dragon")
        XCTAssertFalse(app.staticTexts["Unsupported Search"].exists)

        searchField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Unsupported Search"].waitForExistence(timeout: 2))
    }

    func testSearchHistorySuggestionReplaysRecentQuery() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Reach",
                isRealCard: true
            ),
            CardRecord(
                id: "beta",
                name: "Beta Mage",
                releasedAt: "2020-01-02",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "2",
                collectorNumberNumber: 2,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Draw a card.",
                isRealCard: true
            )
        ])

        let app = launchApp(databaseURL: databaseURL, appearance: .light, searchHistory: ["forest"])
        let resultTotal = app.staticTexts["search-results-total"]
        XCTAssertTrue(resultTotal.waitForExistence(timeout: 5))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("fo")
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "2 cards"))
        XCTAssertTrue(app.buttons["open-card-beta"].exists)

        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])
        searchField.typeText("forest")
        searchField.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(waitForValue(of: searchField, toEqual: "forest"))
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "1 card"))
        XCTAssertFalse(app.buttons["open-card-beta"].exists)
    }

    func testDefaultSearchPreferencesApplyToEmptySearchAndOpenSettings() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Reach",
                isRealCard: true
            ),
            CardRecord(
                id: "beta",
                name: "Beta Mage",
                releasedAt: "2020-01-02",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "2",
                collectorNumberNumber: 2,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Draw a card.",
                isRealCard: true
            )
        ])

        let app = launchApp(databaseURL: databaseURL, defaultSearchText: "mage")
        XCTAssertTrue(app.buttons["open-card-beta"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForNonExistence(of: app.buttons["open-card-alpha"], timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["default-search-indicator"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["edit-default-search-button"].exists)
        XCTAssertTrue(firstElement(app, identifier: "search-sort-menu").isEnabled)
        XCTAssertFalse(firstElement(app, identifier: "search-filter-menu").exists)

        app.typeKey(",", modifierFlags: .command)
        // macOS persists the last-selected Settings tab across launches, so the
        // window may reopen on a different pane. Select the Search tab explicitly
        // before asserting its fields are present.
        selectSettingsTab(app: app, named: "Search")
        XCTAssertTrue(app.textFields["default-search-text-field"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["default-search-sort-picker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["default-search-direction-picker"].exists)
    }

    func testCardDetailPrintingSelectionPersistsForListEntry() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "tempo-current",
                oracleID: "tempo-oracle",
                name: "Tempo Mage",
                language: "en",
                releasedAt: "2024-01-01",
                setCode: "cur",
                setName: "Current Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature — Wizard",
                oracleText: "Draw.",
                isRealCard: true
            ),
            CardRecord(
                id: "tempo-old",
                oracleID: "tempo-oracle",
                name: "Tempo Mage",
                language: "en",
                releasedAt: "2021-01-01",
                setCode: "old",
                setName: "Old Set",
                setType: "expansion",
                collectorNumber: "7",
                collectorNumberNumber: 7,
                rarity: "uncommon",
                rarityRank: 1,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature — Wizard",
                oracleText: "Draw.",
                isRealCard: true
            )
        ])
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardCollection(named: "Tempo Picks")
        try database.appendCard("tempo-old", toList: list.id)

        var app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["card-list-row-Tempo Picks"].waitForExistence(timeout: 5))
        app.buttons["card-list-row-Tempo Picks"].click()

        var listEntryButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-list-entry-"))
            .firstMatch
        XCTAssertTrue(listEntryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(listEntryButton.label.contains("OLD #7"))
        listEntryButton.click()

        let currentPrintingButton = app.buttons["card-printing-tempo-current-button"]
        XCTAssertTrue(currentPrintingButton.waitForExistence(timeout: 3))
        currentPrintingButton.click()
        XCTAssertTrue(waitForValue(of: currentPrintingButton, toEqual: "Current Printing"))

        let closeButton = app.buttons["card-detail-close-button"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.click()

        listEntryButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-list-entry-"))
            .firstMatch
        XCTAssertTrue(listEntryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(listEntryButton.label.contains("CUR #1"))

        app.terminate()
        app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["card-list-row-Tempo Picks"].waitForExistence(timeout: 5))
        app.buttons["card-list-row-Tempo Picks"].click()

        listEntryButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-list-entry-"))
            .firstMatch
        XCTAssertTrue(listEntryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(listEntryButton.label.contains("CUR #1"))
    }

    func testListsOverviewActionShowsProtectedFavouritesAndTilesNavigate() throws {
        let imageURL = try makeFixtureImage(named: "overview-alpha.png")
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Reach",
                isRealCard: true,
                normalImagePath: imageURL.path,
                largeImagePath: imageURL.path,
                artCropImagePath: imageURL.path
            )
        ])
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardCollection(named: "Drafts")
        try database.appendCard("alpha", toList: list.id)

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 5))

        let overviewAction = app.buttons["lists-overview-sidebar-button"]
        XCTAssertTrue(overviewAction.waitForExistence(timeout: 3))
        overviewAction.click()

        XCTAssertTrue(firstElement(app, identifier: "card-lists-overview").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["card-list-row-Favourites"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["card-list-row-Drafts"].exists)
        let favouritesTile = app.buttons["card-list-overview-tile-Favourites"]
        let draftsTile = app.buttons["card-list-overview-tile-Drafts"]
        XCTAssertTrue(favouritesTile.exists)
        XCTAssertTrue(draftsTile.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["unpin-list-pin-Favourites"].exists)
        XCTAssertFalse(listActionMenuContains(app: app, listName: "Favourites", action: "Rename"))

        draftsTile.click()
        let listCount = app.staticTexts["card-list-entry-count"]
        XCTAssertTrue(listCount.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: listCount, toEqual: "1 card"))
        XCTAssertTrue(app.buttons["card-list-row-Favourites"].exists)
        XCTAssertTrue(app.buttons["lists-overview-sidebar-button"].exists)

        app.buttons["lists-overview-sidebar-button"].click()
        XCTAssertTrue(firstElement(app, identifier: "card-lists-overview").waitForExistence(timeout: 3))
        XCTAssertTrue(draftsTile.exists)
    }

    func testSidebarListsCanBeReorderedByMenuAndDrag() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Reach",
                isRealCard: true
            )
        ])

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 5))

        try createSidebarList(app: app, named: "Alpha")
        try createSidebarList(app: app, named: "Beta")
        try createSidebarList(app: app, named: "Gamma")

        let alphaRow = app.buttons["card-list-row-Alpha"]
        let betaRow = app.buttons["card-list-row-Beta"]
        let gammaRow = app.buttons["card-list-row-Gamma"]
        XCTAssertTrue(alphaRow.waitForExistence(timeout: 3))
        XCTAssertTrue(betaRow.waitForExistence(timeout: 3))
        XCTAssertTrue(gammaRow.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForVerticalOrder(alphaRow, before: betaRow))
        XCTAssertTrue(waitForVerticalOrder(betaRow, before: gammaRow))
        XCTAssertFalse(app.descendants(matching: .any)["list-actions-Gamma"].exists)

        try openListActions(app: app, listName: "Gamma")
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Move Up"))
        XCTAssertTrue(waitForVerticalOrder(gammaRow, before: betaRow))

        let emptyPinnedLists = app.staticTexts["empty-pinned-lists-sidebar"]
        XCTAssertTrue(emptyPinnedLists.waitForExistence(timeout: 3))
        gammaRow.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 72, dy: 0))
            .press(
                forDuration: 0.5,
                thenDragTo: emptyPinnedLists.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            )

        XCTAssertTrue(listActionMenuContains(app: app, listName: "Gamma", action: "Unpin"))

        let gammaPinButton = app.buttons["unpin-list-pin-Gamma"]
        XCTAssertTrue(gammaPinButton.waitForExistence(timeout: 3))
        gammaPinButton.click()
        XCTAssertTrue(app.staticTexts["empty-pinned-lists-sidebar"].waitForExistence(timeout: 3))
        XCTAssertTrue(gammaRow.waitForExistence(timeout: 3))
        XCTAssertFalse(gammaPinButton.exists)
    }

    func testSidebarListNameCanBeRenamedByDoubleClickingRow() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Reach",
                isRealCard: true
            )
        ])

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 5))

        try createSidebarList(app: app, named: "Drafts")

        let draftsRow = app.buttons["card-list-row-Drafts"]
        XCTAssertTrue(draftsRow.waitForExistence(timeout: 3))
        draftsRow.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 72, dy: 0))
            .doubleClick()

        let listNameField = app.textFields.firstMatch
        XCTAssertTrue(listNameField.waitForExistence(timeout: 2))
        listNameField.click()
        listNameField.typeKey("a", modifierFlags: [.command])
        listNameField.typeText("Maybeboard")

        let renameButton = app.sheets.firstMatch.buttons["Rename"]
        XCTAssertTrue(renameButton.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForEnabled(of: renameButton))
        renameButton.click()

        XCTAssertTrue(app.buttons["card-list-row-Maybeboard"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["card-list-row-Drafts"].exists)
    }

    func testSelectedSearchCardsBulkAddIntoSidebarList() throws {
        let databaseURL = try seedDatabase(cards: makeZoomFixtureCards(count: 4))
        let database = try CardDatabase(storage: .file(databaseURL))
        _ = try database.createCardCollection(named: "Bulk Drops")

        let app = launchApp(databaseURL: databaseURL)
        let resultTotal = app.staticTexts["search-results-total"]
        XCTAssertTrue(resultTotal.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "4 cards"))

        let firstCard = app.buttons["open-card-zoom-00"]
        let secondCard = app.buttons["open-card-zoom-01"]
        let thirdCard = app.buttons["open-card-zoom-02"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        XCTAssertTrue(secondCard.waitForExistence(timeout: 3))
        XCTAssertTrue(thirdCard.waitForExistence(timeout: 3))

        firstCard.click()
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            thirdCard.click()
        }

        XCTAssertTrue(waitForValue(of: firstCard, containing: "Selected"))
        XCTAssertTrue(waitForValue(of: secondCard, containing: "Selected"))
        XCTAssertTrue(waitForValue(of: thirdCard, containing: "Selected"))

        let listRow = app.buttons["card-list-row-Bulk Drops"]
        XCTAssertTrue(listRow.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: listRow, toEqual: "0 cards"))

        let addSelectedButton = app.descendants(matching: .any)["add-card-to-list-zoom-01"]
        XCTAssertTrue(addSelectedButton.waitForExistence(timeout: 3))
        addSelectedButton.click()
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Bulk Drops"))

        XCTAssertTrue(
            waitForValue(of: listRow, toEqual: "3 cards", timeout: 5),
            "Expected Bulk Drops to contain 3 cards, got \(listRow.value as? String ?? "nil")"
        )
        listRow.click()

        let listCount = app.descendants(matching: .any)["card-list-entry-count"]
        XCTAssertTrue(listCount.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: listCount, toEqual: "3 cards"))
        XCTAssertTrue(app.staticTexts["Zoom Fixture 0"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Zoom Fixture 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Zoom Fixture 2"].waitForExistence(timeout: 3))
    }

    func testCardCollectionsCreateAddDuplicateQuantitiesRemoveAndClose() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                manaCost: "{1}{G}",
                manaValue: 2,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Reach",
                isRealCard: true
            )
        ])

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["import-list-button"].exists)

        app.buttons["create-list-button"].click()
        let createDestination = app.staticTexts["create-list-destination"]
        XCTAssertTrue(createDestination.waitForExistence(timeout: 2))
        XCTAssertFalse(app.sheets.firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["list-import-source-picker"].exists)
        let submitButton = app.descendants(matching: .any)["list-import-submit-button"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 2))
        XCTAssertFalse(submitButton.isEnabled)
        let listNameField = app.textFields["list-import-name-field"]
        XCTAssertTrue(listNameField.waitForExistence(timeout: 2))
        listNameField.click()
        listNameField.typeText("Drafts")
        XCTAssertTrue(waitForEnabled(of: submitButton))
        submitButton.click()

        let listRow = app.buttons["card-list-row-Drafts"]
        XCTAssertTrue(listRow.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["card-list-entry-count"].waitForExistence(timeout: 3))

        try openListActions(app: app, listName: "Drafts")
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Pin"))
        XCTAssertTrue(app.buttons["card-list-row-Drafts"].waitForExistence(timeout: 3))
        try openListActions(app: app, listName: "Drafts")
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Unpin"))

        app.buttons["search-sidebar-button"].click()
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 3))

        try addCardToDraftsList(app: app, cardID: "alpha")
        try addCardToDraftsList(app: app, cardID: "alpha")

        XCTAssertTrue(waitForValue(of: listRow, toEqual: "2 cards"))
        listRow.click()

        let listCount = app.descendants(matching: .any)["card-list-entry-count"]
        XCTAssertTrue(listCount.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: listCount, toEqual: "2 cards"))

        let viewModePicker = firstElement(app, identifier: "card-list-view-mode-picker")
        XCTAssertTrue(viewModePicker.waitForExistence(timeout: 3))
        viewModePicker.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).click()

        let textRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-list-text-row-"))
            .firstMatch
        XCTAssertTrue(textRow.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Alpha Forest"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Creature - ABC #1"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            textRow.label.localizedCaseInsensitiveContains("mana cost 1 green"),
            textRow.label
        )
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "list-entry-mana-cost-"))
            .firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-grid-item-"))
            .firstMatch.exists)

        viewModePicker.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).click()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-grid-item-"))
            .firstMatch.waitForExistence(timeout: 3))

        try clickToolbarMenuItem(
            app: app,
            menuIdentifier: "list-detail-more-menu",
            itemIdentifier: "import-list-detail-button"
        )
        XCTAssertTrue(app.staticTexts["list-import-title"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].click()

        let quantityBadge = app.staticTexts
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "quantity-list-entry-"))
            .firstMatch
        XCTAssertTrue(quantityBadge.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: quantityBadge, toEqual: "2"))

        let increaseButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "increase-list-entry-"))
            .firstMatch
        XCTAssertTrue(increaseButton.waitForExistence(timeout: 3))
        increaseButton.click()
        XCTAssertTrue(waitForValue(of: quantityBadge, toEqual: "3"))

        let undoButton = app.buttons["undo-list-action-button"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 3))
        XCTAssertTrue(undoButton.isEnabled)
        undoButton.click()
        XCTAssertTrue(waitForValue(of: quantityBadge, toEqual: "2"))

        try createCategory(app: app, named: "Ramp")
        try createCategory(app: app, named: "Removal")
        XCTAssertTrue(app.descendants(matching: .any)["list-category-section-Ramp"].waitForExistence(timeout: 3))

        XCTAssertTrue(moveFirstVisibleListEntry(app: app, toCategoryNamed: "Ramp"))
        XCTAssertFalse(app.descendants(matching: .any)["list-category-section-Uncategorized"].waitForExistence(timeout: 1))

        try clickToolbarMenuItem(
            app: app,
            menuIdentifier: "list-detail-more-menu",
            itemIdentifier: "collapse-all-list-categories-button"
        )
        XCTAssertTrue(waitForNonExistence(of: app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-list-entry-")).firstMatch, timeout: 3))

        try clickToolbarMenuItem(
            app: app,
            menuIdentifier: "list-detail-more-menu",
            itemIdentifier: "unfold-all-list-categories-button"
        )
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-list-entry-")).firstMatch.waitForExistence(timeout: 3))

        let collapseRampButton = app.buttons["toggle-list-category-collapse-Ramp"]
        XCTAssertTrue(collapseRampButton.waitForExistence(timeout: 3))
        collapseRampButton.click()
        XCTAssertTrue(waitForNonExistence(of: app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-list-entry-")).firstMatch, timeout: 3))
        collapseRampButton.click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-list-entry-")).firstMatch.waitForExistence(timeout: 3))

        try clickToolbarMenuItem(
            app: app,
            menuIdentifier: "list-detail-more-menu",
            itemIdentifier: "export-list-button"
        )

        let exportSheet = app.sheets.firstMatch
        XCTAssertTrue(exportSheet.waitForExistence(timeout: 3))
        XCTAssertTrue(exportSheet.buttons["card-list-export-copy-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(exportSheet.buttons["card-list-export-download-button"].exists)
        exportSheet.buttons["card-list-export-copy-button"].click()
        XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains("Ramp\n2x Alpha Forest") == true)

        let formatPicker = exportSheet.descendants(matching: .any)["card-list-export-format-picker"]
        if formatPicker.waitForExistence(timeout: 2) {
            formatPicker.click()
        } else {
            exportSheet.popUpButtons.firstMatch.click()
        }
        let csvMenuItem = app.menuItems["CSV"]
        XCTAssertTrue(csvMenuItem.waitForExistence(timeout: 2))
        csvMenuItem.click()

        XCTAssertTrue(exportSheet.staticTexts["Header row"].waitForExistence(timeout: 2))
        exportSheet.buttons["card-list-export-copy-button"].click()
        XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains("Quantity,Category,Name") == true)
        exportSheet.buttons["Done"].click()

        try renameCategory(app: app, from: "Ramp", to: "Mana")
        XCTAssertTrue(app.descendants(matching: .any)["list-category-section-Mana"].waitForExistence(timeout: 3))
        let moveManaDownButton = app.descendants(matching: .any)["move-list-category-down-Mana"]
        XCTAssertTrue(moveManaDownButton.waitForExistence(timeout: 3))
        XCTAssertTrue(moveManaDownButton.isHittable)
        moveManaDownButton.click()

        try clickToolbarMenuItem(
            app: app,
            menuIdentifier: "list-detail-more-menu",
            itemIdentifier: "reorder-list-categories-button"
        )

        let compactManaRow = app.descendants(matching: .any)["compact-list-category-row-Mana"]
        XCTAssertTrue(compactManaRow.waitForExistence(timeout: 3))
        let moveManaToTopButton = app.descendants(matching: .any)["move-list-category-top-Mana"]
        XCTAssertTrue(moveManaToTopButton.waitForExistence(timeout: 3))
        XCTAssertTrue(moveManaToTopButton.isHittable)
        moveManaToTopButton.click()

        try clickToolbarMenuItem(
            app: app,
            menuIdentifier: "list-detail-more-menu",
            itemIdentifier: "finish-reorder-list-categories-button"
        )

        let manaSection = app.descendants(matching: .any)["list-category-section-Mana"]
        let removalSection = app.descendants(matching: .any)["list-category-section-Removal"]
        XCTAssertTrue(manaSection.waitForExistence(timeout: 3))
        XCTAssertTrue(removalSection.waitForExistence(timeout: 3))
        XCTAssertLessThan(manaSection.frame.minY, removalSection.frame.minY)

        try selectCategoryAction(app: app, category: "Removal", action: "Delete")
        XCTAssertTrue(waitForNonExistence(of: app.descendants(matching: .any)["list-category-section-Removal"], timeout: 3))

        let removeButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "remove-list-entry-")).firstMatch
        XCTAssertTrue(removeButton.waitForExistence(timeout: 3))
        removeButton.click()
        XCTAssertTrue(waitForValue(of: listCount, toEqual: "1 card"))
        XCTAssertTrue(waitForNonExistence(of: quantityBadge, timeout: 3))

        app.buttons["search-sidebar-button"].click()
        XCTAssertTrue(app.scrollViews["results-grid"].waitForExistence(timeout: 3) || app.buttons["open-card-alpha"].waitForExistence(timeout: 3))
    }

    func testArtworkContextMenuAddsFavouritesAndCreatesList() throws {
        let imageURL = try makeFixtureImage(named: "context-menu-alpha.png")
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Reach",
                isRealCard: true,
                normalImagePath: imageURL.path
            )
        ])

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 5))

        try openArtworkContextMenu(app: app, cardID: "alpha")
        XCTAssertTrue(contextMenuContains(app: app, named: "Share"))
        XCTAssertTrue(contextMenuContains(app: app, named: "Add to Favourites"))
        XCTAssertTrue(contextMenuContains(app: app, named: "Create New Collection"))
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Add to Favourites"))

        let favouritesRow = app.buttons["card-list-row-Favourites"]
        XCTAssertTrue(favouritesRow.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: favouritesRow, toEqual: "1 card"))

        try openArtworkContextMenu(app: app, cardID: "alpha")
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Add to Favourites"))
        XCTAssertTrue(waitForValue(of: favouritesRow, toEqual: "1 card"))

        try openArtworkContextMenu(app: app, cardID: "alpha")
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Create New Collection"))

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeText("Context Picks")
        app.sheets.firstMatch.buttons["Create"].click()

        let contextRow = app.buttons["card-list-row-Context Picks"]
        XCTAssertTrue(contextRow.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: contextRow, toEqual: "1 card"))
    }

    func testOracleSelectionMenuOffersOnlyTransientPhraseRefinements() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "oracle-selection",
                name: "Oracle Selection",
                releasedAt: "2026-01-01",
                setCode: "tst",
                setName: "Test Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Sorcery",
                oracleText: "Reveal a card from your hand.",
                isRealCard: true
            )
        ])

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-oracle-selection"].waitForExistence(timeout: 5))
        openSearchResultCard(app: app, cardID: "oracle-selection")

        let oracleText = app.descendants(matching: .any)["card-detail-oracle-text"]
        XCTAssertTrue(oracleText.waitForExistence(timeout: 3))
        let selectionStart = oracleText.coordinate(
            withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)
        )
        let selectionEnd = oracleText.coordinate(
            withNormalizedOffset: CGVector(dx: 0.38, dy: 0.5)
        )
        selectionStart.press(forDuration: 0.05, thenDragTo: selectionEnd)
        oracleText.coordinate(
            withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)
        ).rightClick()

        XCTAssertTrue(
            app.descendants(matching: .menuItem)
                .matching(identifier: "oracle-selection-more-cards")
                .firstMatch
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.descendants(matching: .menuItem)
                .matching(identifier: "oracle-selection-exclude")
                .firstMatch
                .exists
        )
        XCTAssertFalse(app.menuItems["Always Hide"].exists)
    }

    /// The full refine journey: search oracle text, open a result, refine on its
    /// oracle text via "More cards with …" (which appends an `o:"…"` clause and
    /// re-runs the search), and open a flying card from the narrowed results.
    func testOracleRefineNarrowsSearchThenOpensFlyingCard() throws {
        let databaseURL = try seedDatabase(cards: refineWorkflowFixtureCards())
        let app = launchApp(databaseURL: databaseURL)
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))

        // Step 1 — type the oracle search and submit. The flyer-only distractor,
        // which lacks "Deals combat damage", is filtered out.
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("o:\"Deals combat damage\"")
        searchField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))
        XCTAssertTrue(app.buttons["open-card-goad-combat"].exists)
        XCTAssertTrue(app.buttons["open-card-goad-flyer"].exists)
        XCTAssertTrue(app.buttons["open-card-combat-only"].exists)
        XCTAssertFalse(app.buttons["open-card-flyer-only"].exists)

        // Step 2 — open the goad card.
        openSearchResultCard(app: app, cardID: "goad-combat")
        let oracle = app.descendants(matching: .any)["card-detail-oracle-text"]
        XCTAssertTrue(oracle.waitForExistence(timeout: 3))

        // Step 3 — drag-select the leading "Goad target…" line, right-click, and
        // choose "More cards with …". The captured text is a prefix of the goad
        // cards' first oracle line and absent from the combat-only distractor, so
        // the assertion holds even if the drag grabs only part of the phrase.
        let start = oracle.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.22))
        let end = oracle.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)
        oracle.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.22)).rightClick()
        let moreCards = app.descendants(matching: .menuItem)
            .matching(identifier: "oracle-selection-more-cards")
            .firstMatch
        XCTAssertTrue(moreCards.waitForExistence(timeout: 2))
        moreCards.click()

        // "More cards with …" appends the clause and re-runs the search in one step —
        // no manual submit needed. The refine narrows to the two goad cards; the
        // combat-only card drops out.
        XCTAssertTrue(waitForValue(of: total, toEqual: "2 cards"))
        XCTAssertTrue(app.buttons["open-card-goad-flyer"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["open-card-combat-only"].exists)

        // Step 4 — open the flying card from the still-visible grid (the macOS
        // detail is a side inspector, so the grid stays usable).
        openSearchResultCard(app: app, cardID: "goad-flyer")
        XCTAssertTrue(app.scrollViews["card-detail"].waitForExistence(timeout: 3))
    }

    func testCardCollectionDescriptionNotesShortcutsPersistPlainText() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Reach",
                isRealCard: true
            )
        ])

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 5))

        try createSidebarList(app: app, named: "Notes")

        let listRow = app.buttons["card-list-row-Notes"]
        XCTAssertTrue(listRow.waitForExistence(timeout: 3))
        listRow.click()

        let descriptionButton = app.buttons["toggle-list-description-button"]
        XCTAssertTrue(descriptionButton.waitForExistence(timeout: 3))
        descriptionButton.click()

        let descriptionHeading = app.descendants(matching: .any)["card-list-description-heading"]
        XCTAssertTrue(descriptionHeading.waitForExistence(timeout: 3))

        let descriptionEditor = app.textViews.firstMatch
        XCTAssertTrue(descriptionEditor.waitForExistence(timeout: 3))
        descriptionEditor.click()

        app.typeText("Opening hand")
        app.typeKey("h", modifierFlags: [.command, .shift])
        app.typeKey(.return, modifierFlags: [])
        app.typeKey("7", modifierFlags: [.command, .shift])
        app.typeText("Keep two lands")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey("l", modifierFlags: [.command, .shift])
        app.typeText("Check matchup")
        app.typeKey("u", modifierFlags: [.command, .shift])

        descriptionButton.click()
        XCTAssertTrue(waitForNonExistence(of: descriptionEditor, timeout: 3))
        descriptionButton.click()

        let reopenedEditor = app.textViews.firstMatch
        XCTAssertTrue(reopenedEditor.waitForExistence(timeout: 3))
        let persistedText = reopenedEditor.value as? String ?? ""
        XCTAssertTrue(persistedText.contains("Opening hand"))
        XCTAssertTrue(persistedText.contains("Keep two lands"))
        XCTAssertTrue(persistedText.contains("Check matchup"))
    }

    private enum Appearance {
        case light
        case dark
    }

    private enum DefaultSearchPreferenceKeys {
        static let text = "Grimora.defaultSearch.text"
        static let alwaysIncludedText = "Grimora.search.alwaysIncludedText"
        static let sortMode = "Grimora.defaultSearch.sortMode"
        static let sortDirection = "Grimora.defaultSearch.sortDirection"
        static let searchHistory = "Grimora.searchHistory.queries"
        static let cloudSyncMode = "Grimora.cloudSync.mode"
        static let valueDisplayCurrency = "Grimora.value.displayCurrency"
    }

    private func launchApp(
        databaseURL: URL,
        appearance: Appearance = .light,
        defaultSearchText: String = "",
        defaultSearchSortMode: SortMode = .releaseDate,
        defaultSearchSortDirection: SearchSortDirection = .ascending,
        searchHistory: [String] = [],
        valueDisplayCurrency: CardValueDisplayCurrency? = nil,
        usdToAUDRate: Double? = nil,
        imageDirectory: URL? = nil,
        fixtureCards: [CardRecord]? = nil,
        categorizedListName: String? = nil,
        categoryNames: [String] = [],
        resetDatabase: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        switch appearance {
        case .light:
            app.launchArguments += ["-AppleInterfaceStyle", "Light"]
        case .dark:
            app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        }
        app.launchArguments += [
            "-\(DefaultSearchPreferenceKeys.text)",
            defaultSearchText,
            "-\(DefaultSearchPreferenceKeys.alwaysIncludedText)",
            "",
            "-\(DefaultSearchPreferenceKeys.sortMode)",
            defaultSearchSortMode.rawValue,
            "-\(DefaultSearchPreferenceKeys.sortDirection)",
            defaultSearchSortDirection.rawValue,
            "-\(DefaultSearchPreferenceKeys.cloudSyncMode)",
            "undecided"
        ]
        if let valueDisplayCurrency {
            app.launchArguments += [
                "-\(DefaultSearchPreferenceKeys.valueDisplayCurrency)",
                valueDisplayCurrency.rawValue
            ]
        }
        let userDefaultsSuite = "GrimoraMacUITests-\(UUID().uuidString)"
        if !searchHistory.isEmpty,
           let userDefaults = UserDefaults(suiteName: userDefaultsSuite) {
            userDefaults.set(searchHistory, forKey: DefaultSearchPreferenceKeys.searchHistory)
            userDefaults.synchronize()
            app.launchEnvironment["GRIMORA_TEST_SEARCH_HISTORY"] = searchHistory.joined(separator: "\n")
        }
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] = databaseURL.path
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] =
            (imageDirectory ?? temporaryDirectory.appendingPathComponent("Images", isDirectory: true)).path
        if let fixtureCards,
           let fixtureData = try? JSONEncoder().encode(fixtureCards) {
            app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] =
                String(decoding: fixtureData, as: UTF8.self)
        }
        if let categorizedListName, !categoryNames.isEmpty {
            app.launchEnvironment["GRIMORA_TEST_CATEGORIZED_LIST_NAME"] = categorizedListName
            app.launchEnvironment["GRIMORA_TEST_CATEGORY_NAMES"] = categoryNames.joined(separator: "\n")
        }
        if resetDatabase {
            app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
        }
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] = userDefaultsSuite
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_TEST_RESET_VALUE_DEFAULTS"] = "1"
        if let usdToAUDRate {
            app.launchEnvironment["GRIMORA_TEST_USD_TO_AUD_RATE"] = "\(usdToAUDRate)"
            app.launchEnvironment["GRIMORA_TEST_USD_TO_AUD_RATE_DATE"] = "2026-05-19"
        }
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        // These suites drive a freshly-imported library; keep the first-run
        // onboarding tour from overlaying the search UI under test.
        app.launchEnvironment["GRIMORA_DISABLE_ONBOARDING"] = "1"
        app.launch()
        return app
    }

    private func allCardClassFixtureCards() -> [CardRecord] {
        [
            CardRecord(
                id: "alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Reach",
                isRealCard: true
            ),
            CardRecord(
                id: "beta",
                name: "Beta Mage",
                releasedAt: "2020-01-02",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "2",
                collectorNumberNumber: 2,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 2,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Draw a card.",
                isRealCard: true
            ),
            CardRecord(
                id: "token",
                name: "Soldier Token",
                releasedAt: "2020-01-03",
                setCode: "tok",
                setName: "Token Set",
                setType: "token",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 3,
                layout: "token",
                typeLine: "Token Creature",
                oracleText: "",
                isRealCard: false
            )
        ]
    }

    /// Fixtures for the search → open → refine → open journey. The two goad cards
    /// lead with "Goad target …" on the first oracle line and carry "Deals combat
    /// damage" on the second, so a partial first-line selection still refines on a
    /// goad-only substring. `combat-only` matches the initial search but not the
    /// goad refine; `flyer-only` matches neither and proves the initial search filters.
    private func refineWorkflowFixtureCards() -> [CardRecord] {
        [
            CardRecord(
                id: "goad-combat",
                name: "Pyre Goader",
                releasedAt: "2026-01-01",
                setCode: "tst",
                setName: "Test Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature — Elemental",
                oracleText: "Goad target creature you control until the start of your next turn, even while it stays tapped.\nDeals combat damage.",
                isRealCard: true
            ),
            CardRecord(
                id: "goad-flyer",
                name: "Skyward Goader",
                releasedAt: "2026-01-02",
                setCode: "tst",
                setName: "Test Set",
                setType: "expansion",
                collectorNumber: "2",
                collectorNumberNumber: 2,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 2,
                layout: "normal",
                typeLine: "Creature — Bird",
                oracleText: "Goad target creature you control until the start of your next turn, even while it stays tapped.\nDeals combat damage.",
                keywords: ["Flying"],
                isRealCard: true
            ),
            CardRecord(
                id: "combat-only",
                name: "Brutal Striker",
                releasedAt: "2026-01-03",
                setCode: "tst",
                setName: "Test Set",
                setType: "expansion",
                collectorNumber: "3",
                collectorNumberNumber: 3,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 3,
                layout: "normal",
                typeLine: "Creature — Warrior",
                oracleText: "Deals combat damage to any opponent.",
                isRealCard: true
            ),
            CardRecord(
                id: "flyer-only",
                name: "Idle Sparrow",
                releasedAt: "2026-01-04",
                setCode: "tst",
                setName: "Test Set",
                setType: "expansion",
                collectorNumber: "4",
                collectorNumberNumber: 4,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 4,
                layout: "normal",
                typeLine: "Creature — Bird",
                oracleText: "Whenever this attacks, draw a card.",
                keywords: ["Flying"],
                isRealCard: true
            )
        ]
    }

    private func seedDatabase(cards: [CardRecord]) throws -> URL {
        let databaseURL = temporaryDirectory.appendingPathComponent("fixture.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        try database.replaceAllCards(cards)
        try database.saveMetadataValue("2026-04-25T09:09:59.477+00:00", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        try database.saveMetadataValue(CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
        try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)
        return databaseURL
    }

    private func makeZoomFixtureCards(count: Int) -> [CardRecord] {
        (0..<count).map { index in
            CardRecord(
                id: String(format: "zoom-%02d", index),
                name: "Zoom Fixture \(index)",
                releasedAt: "2020-01-01",
                setCode: "zom",
                setName: "Zoom Set",
                setType: "expansion",
                collectorNumber: "\(index + 1)",
                collectorNumberNumber: index + 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: index,
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Zoom test fixture.",
                isRealCard: true
            )
        }
    }

    private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return !element.exists
    }

    private func waitForValue(of element: XCUIElement, toEqual expectedValue: String, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.value as? String == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.value as? String == expectedValue
    }

    private func waitForValue(of element: XCUIElement, containing expectedSubstring: String, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String)?.contains(expectedSubstring) == true {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return (element.value as? String)?.contains(expectedSubstring) == true
    }

    private func waitForValue(of element: XCUIElement, notContaining substring: String, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String)?.contains(substring) != true {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return (element.value as? String)?.contains(substring) != true
    }

    /// Selects a tab in the macOS Settings window by its toolbar label. Scoped to
    /// the Settings window so it never matches a same-named control in the main
    /// window (e.g. the sidebar "Search" button). No-op if the tab isn't found.
    private func selectSettingsTab(app: XCUIApplication, named name: String) {
        let settingsWindow = app.windows["com_apple_SwiftUI_Settings_window"]
        guard settingsWindow.waitForExistence(timeout: 3) else { return }
        let tab = settingsWindow.buttons[name]
        if tab.waitForExistence(timeout: 2) {
            tab.click()
        }
    }

    private func waitForEnabled(of element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isEnabled {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.exists && element.isEnabled
    }

    private func waitForVerticalOrder(
        _ first: XCUIElement,
        before second: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if first.exists, second.exists, first.frame.minY < second.frame.minY {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return first.exists && second.exists && first.frame.minY < second.frame.minY
    }

    private func createSidebarList(app: XCUIApplication, named name: String) throws {
        app.buttons["create-list-button"].click()
        let createDestination = app.staticTexts["create-list-destination"]
        XCTAssertTrue(createDestination.waitForExistence(timeout: 2))
        XCTAssertFalse(app.sheets.firstMatch.exists)

        let listNameField = app.textFields["list-import-name-field"]
        XCTAssertTrue(listNameField.waitForExistence(timeout: 2))
        listNameField.click()
        listNameField.typeText(name)

        let submitButton = app.descendants(matching: .any)["list-import-submit-button"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForEnabled(of: submitButton))
        submitButton.click()

        XCTAssertTrue(app.buttons["card-list-row-\(name)"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
    }

    private func openListActions(app: XCUIApplication, listName: String) throws {
        let row = app.buttons["card-list-row-\(listName)"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let rowFrame = row.frame
        XCTAssertTrue(rowFrame.minX.isFinite)
        XCTAssertTrue(rowFrame.midY.isFinite)

        // SwiftUI can expose the expanding row button with an infinite width on
        // macOS. Anchor from the finite leading edge instead of reading maxX.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 250, dy: 0))
            .rightClick()
    }

    private func openArtworkContextMenu(app: XCUIApplication, cardID: String) throws {
        let cardButton = app.buttons["open-card-\(cardID)"]
        XCTAssertTrue(cardButton.waitForExistence(timeout: 3))
        let frame = cardButton.frame
        XCTAssertTrue(frame.minX.isFinite)
        XCTAssertTrue(frame.midY.isFinite)
        cardButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).rightClick()
    }

    private func openSearchResultCard(app: XCUIApplication, cardID: String) {
        let cardButton = app.buttons["open-card-\(cardID)"]
        XCTAssertTrue(cardButton.waitForExistence(timeout: 3))
        doubleClickSearchResultCard(cardButton)
    }

    private func doubleClickSearchResultCard(_ cardButton: XCUIElement) {
        let frame = cardButton.frame
        XCTAssertTrue(frame.minX.isFinite)
        XCTAssertTrue(frame.midY.isFinite)
        cardButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).doubleClick()
    }

    private func contextMenuContains(app: XCUIApplication, named name: String) -> Bool {
        let menuItem = app.menuItems[name]
        if menuItem.waitForExistence(timeout: 1) {
            return true
        }

        let button = app.buttons[name]
        return button.waitForExistence(timeout: 1)
    }

    private func listActionMenuContains(
        app: XCUIApplication,
        listName: String,
        action: String
    ) -> Bool {
        do {
            try openListActions(app: app, listName: listName)
        } catch {
            return false
        }
        let menuItem = app.menuItems[action]
        let button = app.buttons[action]
        let containsAction = menuItem.waitForExistence(timeout: 1) || button.waitForExistence(timeout: 1)
        app.typeKey(.escape, modifierFlags: [])
        return containsAction
    }

    private func addCardToDraftsList(app: XCUIApplication, cardID: String) throws {
        let addButton = app.descendants(matching: .any)["add-card-to-list-\(cardID)"]
        if addButton.waitForExistence(timeout: 1) {
            addButton.click()
        } else {
            let cardButton = app.buttons["open-card-\(cardID)"]
            XCTAssertTrue(cardButton.waitForExistence(timeout: 3))
            cardButton.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.08)).click()
        }

        let identifiedMenuItem = app.descendants(matching: .any)["add-card-\(cardID)-to-list-Drafts"]
        if identifiedMenuItem.waitForExistence(timeout: 1) {
            identifiedMenuItem.click()
            return
        }

        let namedMenuItem = app.menuItems["Drafts"]
        if namedMenuItem.waitForExistence(timeout: 1) {
            namedMenuItem.click()
            return
        }

        let namedButton = app.buttons["Drafts"]
        if namedButton.waitForExistence(timeout: 1) {
            namedButton.click()
            return
        }

        XCTFail("Could not find Drafts menu item")
    }

    private func createCategory(app: XCUIApplication, named name: String) throws {
        app.buttons["create-list-category-button"].click()
        let categoryNameField = app.textFields.firstMatch
        XCTAssertTrue(categoryNameField.waitForExistence(timeout: 2))
        categoryNameField.typeText(name)
        app.sheets.firstMatch.buttons["Create"].click()
    }

    private func renameCategory(app: XCUIApplication, from oldName: String, to newName: String) throws {
        try selectCategoryAction(app: app, category: oldName, action: "Rename")
        let categoryNameField = app.textFields.firstMatch
        XCTAssertTrue(categoryNameField.waitForExistence(timeout: 2))
        categoryNameField.click()
        categoryNameField.typeKey("a", modifierFlags: [.command])
        categoryNameField.typeText(newName)
        app.sheets.firstMatch.buttons["Rename"].click()
    }

    private func selectCategoryAction(app: XCUIApplication, category: String, action: String) throws {
        let actionButton = app.descendants(matching: .any)["list-category-actions-\(category)"]
        for _ in 0..<8 {
            if actionButton.waitForExistence(timeout: 1), actionButton.isHittable {
                break
            }

            let scrollView = cardCollectionScrollView(app: app)
            if actionButton.exists, scrollView.exists {
                if actionButton.frame.midY < scrollView.frame.minY {
                    scrollPrimaryScrollView(app: app, down: false)
                } else {
                    scrollPrimaryScrollView(app: app, down: true)
                }
            } else {
                scrollPrimaryScrollView(app: app, down: true)
            }
        }

        XCTAssertTrue(actionButton.waitForExistence(timeout: 3))
        XCTAssertTrue(actionButton.isHittable)
        actionButton.click()

        if let actionIdentifier = categoryActionIdentifier(category: category, action: action) {
            let identifiedAction = app.descendants(matching: .any)[actionIdentifier]
            if identifiedAction.waitForExistence(timeout: 1) {
                identifiedAction.click()
                return
            }
        }

        XCTAssertTrue(clickMenuItemOrButton(app: app, named: action))
    }

    private func categoryActionIdentifier(category: String, action: String) -> String? {
        switch action {
        case "Rename":
            return "rename-list-category-\(category)"
        case "Move Up":
            return "move-list-category-up-\(category)"
        case "Move Down":
            return "move-list-category-down-\(category)"
        case "Delete":
            return "delete-list-category-\(category)"
        default:
            return nil
        }
    }

    private func cardCollectionScrollView(app: XCUIApplication) -> XCUIElement {
        let identifiedScrollView = app.scrollViews["card-list-detail-scroll"]
        return identifiedScrollView.exists ? identifiedScrollView : app.scrollViews.firstMatch
    }

    private func scrollPrimaryScrollView(app: XCUIApplication, down: Bool) {
        let scrollView = cardCollectionScrollView(app: app)
        guard scrollView.waitForExistence(timeout: 1) else {
            return
        }

        let startY = down ? 0.82 : 0.24
        let endY = down ? 0.24 : 0.82
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @discardableResult
    private func clickMenuItemOrButton(app: XCUIApplication, named name: String) -> Bool {
        let menuItem = app.menuItems[name]
        if menuItem.waitForExistence(timeout: 1) {
            menuItem.click()
            return true
        }

        let button = app.buttons[name]
        if button.waitForExistence(timeout: 1) {
            button.click()
            return true
        }

        return false
    }

    /// Moves the first visible list entry to a category through the per-card
    /// "more" (ellipsis) menu, which now nests the Move to Category submenu.
    @discardableResult
    private func moveFirstVisibleListEntry(
        app: XCUIApplication,
        toCategoryNamed name: String
    ) -> Bool {
        let moreButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "more-list-entry-"))
            .firstMatch
        guard moreButton.waitForExistence(timeout: 3) else {
            return false
        }
        moreButton.click()

        let moveToCategoryButton = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                "move-list-entry-",
                "-category"
            ))
            .firstMatch
        guard moveToCategoryButton.waitForExistence(timeout: 3) else {
            return false
        }
        moveToCategoryButton.click()

        return clickMenuItemOrButton(app: app, named: name)
    }

    private func clickToolbarMenuItem(
        app: XCUIApplication,
        menuIdentifier: String,
        itemIdentifier: String
    ) throws {
        let menu = firstElement(app, identifier: menuIdentifier)
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.click()

        let identifiedItem = app.descendants(matching: .any)[itemIdentifier]
        if identifiedItem.waitForExistence(timeout: 1) {
            identifiedItem.click()
            return
        }

        XCTFail("Could not find toolbar menu item \(itemIdentifier)")
    }

    private func firstElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func makeFixtureImage(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        let size = NSSize(width: 240, height: 336)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 0.82, green: 0.74, blue: 0.62, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor(red: 0.17, green: 0.09, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 22, y: 22, width: 196, height: 292), xRadius: 12, yRadius: 12).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "GrimoraUITests", code: 1)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

}
