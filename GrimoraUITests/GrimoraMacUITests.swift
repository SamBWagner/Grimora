import AppKit
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

    func testLightAppearanceSearchFilterSortAndDetailUseOnlyLocalData() throws {
        try runSearchFilterSortAndDetailFlow(appearance: .light)
    }

    func testDarkAppearanceSearchFilterSortAndDetailUseOnlyLocalData() throws {
        try runSearchFilterSortAndDetailFlow(appearance: .dark)
    }

    func testInitialCloudSyncChoiceCanGoBackBeforeDownload() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("setup.sqlite")
        let app = launchApp(databaseURL: databaseURL)

        let syncButton = app.buttons["Sync with iCloud"]
        XCTAssertTrue(syncButton.waitForExistence(timeout: 5))

        app.buttons["Keep This Device Separate"].click()
        XCTAssertTrue(app.buttons["Start Download"].waitForExistence(timeout: 2))

        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.click()
        XCTAssertTrue(syncButton.waitForExistence(timeout: 2))

        syncButton.click()
        XCTAssertTrue(app.buttons["Start Download"].waitForExistence(timeout: 2))
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.click()
        XCTAssertTrue(app.buttons["Keep This Device Separate"].waitForExistence(timeout: 2))
    }

    private func runSearchFilterSortAndDetailFlow(appearance: Appearance) throws {
        let imageURL = try makeFixtureImage(named: "alpha.png")
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
                isRealCard: true,
                normalImagePath: imageURL.path,
                largeImagePath: imageURL.path
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
                artist: "Another Artist",
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature — Wizard",
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
                colorSortKey: 0,
                layout: "token",
                typeLine: "Token Creature — Soldier",
                oracleText: "",
                isRealCard: false
            )
        ])

        let app = launchApp(databaseURL: databaseURL, appearance: appearance)
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 5))
        XCTAssertTrue(firstElement(app, identifier: "search-sort-menu").waitForExistence(timeout: 5))
        let resultTotal = app.staticTexts["search-results-total"]
        XCTAssertTrue(resultTotal.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "2 cards"))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("forest")
        XCTAssertTrue(app.buttons["open-card-alpha"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "1 card"))
        XCTAssertFalse(app.buttons["open-card-beta"].exists)

        searchField.click()
        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.buttons["open-card-beta"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "2 cards"))

        try clickToolbarMenuItem(app: app, menuIdentifier: "search-filter-menu", itemIdentifier: "filter-real-cards")
        XCTAssertTrue(app.buttons["open-card-token"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "3 cards"))

        openSearchResultCard(app: app, cardID: "alpha")
        XCTAssertTrue(app.scrollViews["card-detail"].waitForExistence(timeout: 3) || app.staticTexts["Fixture Artist"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Fixture Artist"].exists)
    }

    func testCardDetailInspectorClosesFromCloseButtonAndPersistsThroughOutsideClick() throws {
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

        let app = launchApp(databaseURL: databaseURL)
        let cardButton = app.buttons["open-card-alpha"]
        XCTAssertTrue(cardButton.waitForExistence(timeout: 5))
        doubleClickSearchResultCard(cardButton)

        let closeButton = app.buttons["card-detail-close-button"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.click()
        XCTAssertTrue(waitForNonExistence(of: closeButton, timeout: 3))

        XCTAssertTrue(cardButton.waitForExistence(timeout: 3))
        doubleClickSearchResultCard(cardButton)
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))

        let searchResults = app.scrollViews["search-results-scroll"]
        XCTAssertTrue(searchResults.waitForExistence(timeout: 3))
        searchResults.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.14)).click()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2))

        closeButton.click()
        XCTAssertTrue(waitForNonExistence(of: closeButton, timeout: 3))
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
        _ = try database.createCardList(named: "Detail Picks")

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

        XCTAssertTrue(app.staticTexts["Unsupported Search"].waitForExistence(timeout: 2))
    }

    func testPlainTextSearchModeToggleIsHiddenForNow() throws {
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "dragon",
                name: "Ruby Whelp",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "rare",
                rarityRank: 2,
                manaValue: 3,
                colorSortKey: 3,
                colors: ["R"],
                layout: "normal",
                typeLine: "Creature — Dragon",
                oracleText: "Flying",
                isRealCard: true
            ),
            CardRecord(
                id: "mage",
                name: "Azure Mage",
                releasedAt: "2020-01-02",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "2",
                collectorNumberNumber: 2,
                rarity: "uncommon",
                rarityRank: 1,
                manaValue: 2,
                colorSortKey: 1,
                colors: ["U"],
                layout: "normal",
                typeLine: "Creature — Human Wizard",
                oracleText: "Draw a card.",
                isRealCard: true
            )
        ])

        let app = launchApp(
            databaseURL: databaseURL,
            plainTextSearchResponses: [
                "red dragons under 4 mana": "t:dragon c:r mv<4"
            ]
        )
        let toggle = app.buttons["plain-text-search-mode-toggle"]
        XCTAssertFalse(toggle.waitForExistence(timeout: 1))
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    }

    func testCreateListFromSearchResultsPromptsForNameAndSelectsList() throws {
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

        let app = launchApp(databaseURL: databaseURL, appearance: .light)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("forest")

        let resultTotal = app.staticTexts["search-results-total"]
        XCTAssertTrue(resultTotal.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "1 card"))

        let createButton = app.buttons["create-list-from-search-button"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 2))
        XCTAssertTrue(createButton.isEnabled)
        createButton.click()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.typeText("Forest Picks")
        app.sheets.firstMatch.buttons["Create"].click()

        let listRow = app.buttons["card-list-row-Forest Picks"]
        XCTAssertTrue(listRow.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: listRow, toEqual: "1 card"))
        XCTAssertTrue(app.staticTexts["card-list-entry-count"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: app.staticTexts["card-list-entry-count"], toEqual: "1 card"))
        let listEntry = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-list-entry-"))
            .firstMatch
        XCTAssertTrue(listEntry.waitForExistence(timeout: 3))
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
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "1 card"))

        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])
        searchField.typeText("forest")

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
        XCTAssertTrue(firstElement(app, identifier: "search-filter-menu").isEnabled)

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.textFields["default-search-text-field"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["default-search-sort-picker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["default-search-direction-picker"].exists)
    }

    func testCardValueSectionShowsSummaryDetailsAndChart() async throws {
        let databaseURL = try seedDatabase(cards: [
            valueFixtureCard(id: "value", name: "Value Drake")
        ])
        try await seedValueHistory(databaseURL: databaseURL, cardID: "value")

        let app = launchApp(databaseURL: databaseURL)
        openSearchResultCard(app: app, cardID: "value")

        let currentValue = app.descendants(matching: .any)["card-value-current"]
        XCTAssertTrue(currentValue.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibilityText(of: currentValue).contains("Current"))
        XCTAssertTrue(accessibilityText(of: currentValue).contains("USD 3.25"))

        let highValue = app.descendants(matching: .any)["card-value-high"]
        XCTAssertTrue(highValue.waitForExistence(timeout: 3))
        XCTAssertTrue(accessibilityText(of: highValue).contains("90-Day High"))
        XCTAssertTrue(accessibilityText(of: highValue).contains("USD 5.00"))

        let detailsDisclosure = app.descendants(matching: .any)["card-value-details-disclosure"]
        XCTAssertTrue(detailsDisclosure.waitForExistence(timeout: 3))
        detailsDisclosure.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).click()
        XCTAssertTrue(waitForValue(of: detailsDisclosure, toEqual: "Expanded", timeout: 2))
        app.scrollViews["card-detail"].scroll(byDeltaX: 0, deltaY: -260)

        let chart = app.descendants(matching: .any)["card-value-history-chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 3))
        XCTAssertTrue(accessibilityText(of: chart).contains("90-day value chart"))
        XCTAssertTrue(app.descendants(matching: .any)["card-value-change"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["card-value-source"].waitForExistence(timeout: 3))
    }

    func testCardValueSectionShowsUnavailableState() throws {
        let databaseURL = try seedDatabase(cards: [
            valueFixtureCard(id: "missing", name: "Missing Value Drake")
        ])

        let app = launchApp(databaseURL: databaseURL)
        openSearchResultCard(app: app, cardID: "missing")
        XCTAssertTrue(app.descendants(matching: .any)["card-value-unavailable"].waitForExistence(timeout: 5))
    }

    func testSettingsCurrencySwitchDisplaysAUDCardValue() async throws {
        let databaseURL = try seedDatabase(cards: [
            valueFixtureCard(id: "value", name: "Value Drake")
        ])
        try await seedValueHistory(databaseURL: databaseURL, cardID: "value")

        let app = launchApp(databaseURL: databaseURL, usdToAUDRate: 1.5)
        app.typeKey(",", modifierFlags: .command)

        let valueTab = app.buttons["Value"]
        if valueTab.waitForExistence(timeout: 2) {
            valueTab.click()
        }
        let currencyPicker = app.descendants(matching: .any)["value-currency-picker"]
        XCTAssertTrue(currencyPicker.waitForExistence(timeout: 3))
        XCTAssertTrue(selectPickerOption(app: app, picker: currencyPicker, option: "AUD"))
        app.typeKey("w", modifierFlags: .command)

        openSearchResultCard(app: app, cardID: "value")
        let currentValue = app.descendants(matching: .any)["card-value-current"]
        XCTAssertTrue(currentValue.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibilityText(of: currentValue).contains("AUD 4.88"), accessibilityText(of: currentValue))
    }

    func testAllPrintingsUncachedCardsRenderAsTextOnlyCells() throws {
        let imageURL = try makeFixtureImage(named: "preferred.png")
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "preferred",
                oracleID: "shared-oracle",
                name: "Shared Mage",
                releasedAt: "2024-01-01",
                setCode: "new",
                setName: "New Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature — Wizard",
                oracleText: "Draw.",
                isRealCard: true,
                smallImagePath: imageURL.path,
                smallImageURL: "https://example.test/preferred-small.jpg"
            ),
            CardRecord(
                id: "uncached",
                oracleID: "shared-oracle",
                name: "Shared Mage",
                releasedAt: "2020-01-01",
                setCode: "old",
                setName: "Old Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature — Wizard",
                oracleText: "Draw.",
                isRealCard: true,
                smallImageURL: "https://example.test/uncached-small.jpg"
            )
        ])

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-preferred"].waitForExistence(timeout: 5))
        let printingModePicker = app.descendants(matching: .any)["printing-display-mode-picker"]
        XCTAssertTrue(printingModePicker.waitForExistence(timeout: 5))
        XCTAssertEqual(printingModePicker.value as? String, "Preferred Printings")
        XCTAssertFalse(app.buttons["open-card-uncached"].exists)
        printingModePicker.click()
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Preferred Printings"))
        printingModePicker.click()
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "All Printings"))

        let uncachedButton = app.buttons["open-card-uncached"]
        XCTAssertTrue(uncachedButton.waitForExistence(timeout: 3))
        XCTAssertTrue(
            waitForValue(of: uncachedButton, toEqual: "Text Only", timeout: 5),
            "Expected uncached card to settle as text-only, found \(String(describing: uncachedButton.value))"
        )
    }

    func testCardDetailShowsAllPrintingsForSelectedCard() throws {
        let imageURL = try makeFixtureImage(named: "detail-printing.png")
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "preferred",
                oracleID: "shared-oracle",
                name: "Shared Mage",
                language: "en",
                releasedAt: "2024-01-01",
                setCode: "new",
                setName: "New Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature — Wizard",
                oracleText: "Draw.",
                isRealCard: true,
                normalImagePath: imageURL.path,
                largeImagePath: imageURL.path
            ),
            CardRecord(
                id: "older",
                oracleID: "shared-oracle",
                name: "Shared Mage",
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
            ),
            CardRecord(
                id: "middle",
                oracleID: "shared-oracle",
                name: "Shared Mage",
                language: "en",
                releasedAt: "2023-01-01",
                setCode: "mid",
                setName: "Middle Set",
                setType: "expansion",
                collectorNumber: "2",
                collectorNumberNumber: 2,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature — Wizard",
                oracleText: "Draw.",
                isRealCard: true
            ),
            CardRecord(
                id: "fourth",
                oracleID: "shared-oracle",
                name: "Shared Mage",
                language: "en",
                releasedAt: "2022-01-01",
                setCode: "for",
                setName: "Fourth Set",
                setType: "expansion",
                collectorNumber: "4",
                collectorNumberNumber: 4,
                rarity: "uncommon",
                rarityRank: 1,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature — Wizard",
                oracleText: "Draw.",
                isRealCard: true
            ),
            CardRecord(
                id: "oldest",
                oracleID: "shared-oracle",
                name: "Shared Mage",
                language: "en",
                releasedAt: "2020-01-01",
                setCode: "ost",
                setName: "Oldest Set",
                setType: "expansion",
                collectorNumber: "9",
                collectorNumberNumber: 9,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 1,
                layout: "normal",
                typeLine: "Creature — Wizard",
                oracleText: "Draw.",
                isRealCard: true
            ),
            CardRecord(
                id: "other",
                oracleID: "other-oracle",
                name: "Other Mage",
                language: "en",
                releasedAt: "2025-01-01",
                setCode: "oth",
                setName: "Other Set",
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
            )
        ])

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-preferred"].waitForExistence(timeout: 5))
        openSearchResultCard(app: app, cardID: "preferred")

        let printingsSection = app.staticTexts["card-printings"]
        XCTAssertTrue(printingsSection.waitForExistence(timeout: 3))
        let currentButton = app.buttons["card-printing-preferred-button"]
        let olderButton = app.buttons["card-printing-older-button"]
        if !currentButton.waitForExistence(timeout: 1) {
            app.scrollViews["card-detail"].swipeUp()
        }
        XCTAssertTrue(currentButton.waitForExistence(timeout: 3))
        XCTAssertTrue(olderButton.waitForExistence(timeout: 3))
        XCTAssertTrue(currentButton.label.contains("New Set"))
        XCTAssertTrue(currentButton.label.contains("NEW #1 | 2024-01-01 | Rare | EN | USD Unknown"))
        XCTAssertEqual(currentButton.value as? String, "Current Printing")
        XCTAssertTrue(olderButton.label.contains("Old Set"))
        XCTAssertTrue(olderButton.label.contains("OLD #7 | 2021-01-01 | Uncommon | EN | USD Unknown"))
        XCTAssertEqual(olderButton.value as? String, "Select Printing")
        XCTAssertFalse(app.buttons["card-printing-oldest-button"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["card-printing-other"].exists)

        let showAllButton = app.buttons["card-printings-show-all-button"]
        XCTAssertTrue(showAllButton.waitForExistence(timeout: 3))
        XCTAssertEqual(showAllButton.value as? String, "Collapsed")
        showAllButton.click()
        XCTAssertEqual(showAllButton.value as? String, "Expanded")
        let preview = app.descendants(matching: .any)["card-printings-expanded-preview"]
        let previewMetadata = app.descendants(matching: .any)["card-printings-expanded-metadata"]
        let printingsGrid = app.descendants(matching: .any)["card-printings-grid"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        XCTAssertTrue(previewMetadata.waitForExistence(timeout: 3))
        XCTAssertTrue(printingsGrid.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["New Set (NEW #1)"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["card-printing-oldest-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["card-printing-oldest-button"].label.contains("Oldest Set"))

        let expandedOlderButton = app.buttons
            .matching(identifier: "card-printing-older-button")
            .element(boundBy: 0)
        XCTAssertTrue(expandedOlderButton.waitForExistence(timeout: 3))
        XCTAssertTrue(expandedOlderButton.label.contains("Old Set"))
        XCTAssertEqual(expandedOlderButton.value as? String, "Select Preview")
        XCTAssertEqual(showAllButton.value as? String, "Expanded")
        XCTAssertTrue(app.buttons["card-printing-oldest-button"].exists)
        XCTAssertTrue(preview.exists)
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
        let list = try database.createCardList(named: "Tempo Picks")
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

    func testGridZoomCommandsChangeCardWidthAndResetRestoresDefault() throws {
        let databaseURL = try seedDatabase(cards: makeZoomFixtureCards(count: 36))
        let app = launchApp(databaseURL: databaseURL)
        let firstCard = app.buttons["open-card-zoom-00"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))

        XCTAssertFalse(app.buttons["grid-zoom-out-button"].exists)
        XCTAssertFalse(app.buttons["grid-zoom-in-button"].exists)
        XCTAssertFalse(app.buttons["grid-zoom-reset-button"].exists)

        app.typeKey(".", modifierFlags: [.command, .shift])
        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))

        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))

        for _ in 0..<4 {
            app.typeKey(",", modifierFlags: [.command, .shift])
        }
        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))

        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))
    }

    func testSearchHeaderCollapsesOnScrollAndFocusExpandsAndFocusesSearch() throws {
        let databaseURL = try seedDatabase(cards: makeZoomFixtureCards(count: 36))
        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-zoom-00"].waitForExistence(timeout: 5))
        let expandedHeader = app.descendants(matching: .any)["mac-search-expanded-header"]
        XCTAssertTrue(expandedHeader.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["search-filter-menu"].exists)
        let expandedSearchField = app.searchFields.firstMatch
        XCTAssertTrue(expandedSearchField.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(expandedSearchField.frame.height, 28)
        XCTAssertLessThanOrEqual(expandedSearchField.frame.height, 38)
        XCTAssertLessThan(expandedHeader.frame.maxX - expandedSearchField.frame.maxX, 32)
        let createButton = app.buttons["create-list-from-search-button"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(createButton.frame.minY, expandedSearchField.frame.maxY - 1)
        let printingModePicker = firstElement(app, identifier: "printing-display-mode-picker")
        XCTAssertTrue(printingModePicker.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(createButton.frame.minX - printingModePicker.frame.maxX, 80)

        let identifiedScrollView = app.scrollViews["search-results-scroll"]
        let scrollView = identifiedScrollView.waitForExistence(timeout: 1)
            ? identifiedScrollView
            : app.scrollViews["results-grid"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3))
        let firstCardYBeforeScroll = app.buttons["open-card-zoom-00"].frame.minY
        scrollView.scroll(byDeltaX: 0, deltaY: -300)
        if app.buttons["open-card-zoom-00"].frame.minY >= firstCardYBeforeScroll - 2 {
            scrollView.scroll(byDeltaX: 0, deltaY: 300)
        }

        XCTAssertTrue(app.descendants(matching: .any)["mac-search-collapsed-header"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["search-filter-menu"].exists)
        let compactSearchBar = app.buttons["mac-compact-search-bar"]
        XCTAssertTrue(compactSearchBar.waitForExistence(timeout: 3))
        XCTAssertLessThan(compactSearchBar.frame.height, 80)

        compactSearchBar.click()
        XCTAssertTrue(app.descendants(matching: .any)["mac-search-expanded-header"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["search-filter-menu"].waitForExistence(timeout: 3))
        app.typeText("35")

        XCTAssertTrue(app.buttons["open-card-zoom-35"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: app.staticTexts["search-results-total"], toEqual: "1 card"))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.click()
        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.buttons["open-card-zoom-00"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: app.staticTexts["search-results-total"], toEqual: "36 cards"))

        let firstCardYBeforeFocusedScroll = app.buttons["open-card-zoom-00"].frame.minY
        scrollView.scroll(byDeltaX: 0, deltaY: -300)
        if app.buttons["open-card-zoom-00"].frame.minY >= firstCardYBeforeFocusedScroll - 2 {
            scrollView.scroll(byDeltaX: 0, deltaY: 300)
        }

        XCTAssertTrue(app.descendants(matching: .any)["mac-search-expanded-header"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["search-filter-menu"].exists)
    }

    func testJumpToTopButtonsReturnMainBrowsersToStart() throws {
        let cards = makeZoomFixtureCards(count: 96)
        let databaseURL = try seedDatabase(cards: cards)
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardList(named: "Jump Picks")
        for card in cards {
            try database.appendCard(card.id, toList: list.id)
        }

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-zoom-00"].waitForExistence(timeout: 5))

        let searchJumpButton = revealJumpToTopButton(
            app: app,
            identifier: "search-results-jump-to-top-button",
            scrollView: searchResultsScrollView(app: app),
            topElement: app.buttons["open-card-zoom-00"]
        )
        searchJumpButton.click()
        XCTAssertTrue(waitForNonExistence(of: searchJumpButton, timeout: 3))
        XCTAssertTrue(app.buttons["open-card-zoom-00"].waitForExistence(timeout: 3))

        let listRow = app.buttons["card-list-row-Jump Picks"]
        XCTAssertTrue(listRow.waitForExistence(timeout: 3))
        listRow.click()
        XCTAssertTrue(app.staticTexts["card-list-entry-count"].waitForExistence(timeout: 3))

        let listGridJumpButton = revealJumpToTopButton(
            app: app,
            identifier: "card-list-detail-jump-to-top-button",
            scrollView: cardListScrollView(app: app),
            topElement: app.staticTexts["card-list-entry-count"]
        )
        listGridJumpButton.click()
        XCTAssertTrue(waitForNonExistence(of: listGridJumpButton, timeout: 3))
        XCTAssertTrue(app.staticTexts["card-list-entry-count"].waitForExistence(timeout: 3))

        let viewModePicker = firstElement(app, identifier: "card-list-view-mode-picker")
        XCTAssertTrue(viewModePicker.waitForExistence(timeout: 3))
        viewModePicker.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).click()

        let textRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-list-text-row-"))
            .firstMatch
        XCTAssertTrue(textRow.waitForExistence(timeout: 3))

        let listModeJumpButton = revealJumpToTopButton(
            app: app,
            identifier: "card-list-detail-jump-to-top-button",
            scrollView: cardListScrollView(app: app),
            topElement: textRow
        )
        listModeJumpButton.click()
        XCTAssertTrue(waitForNonExistence(of: listModeJumpButton, timeout: 3))
        XCTAssertTrue(app.staticTexts["card-list-entry-count"].waitForExistence(timeout: 3))
    }

    func testRapidListSearchSwitchingAndScrollingStaysResponsive() throws {
        let cards = makeZoomFixtureCards(count: 72)
        let databaseURL = try seedDatabase(cards: cards)
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardList(named: "Scroll Picks")
        for card in cards {
            try database.appendCard(card.id, toList: list.id)
        }

        let app = launchApp(databaseURL: databaseURL)
        let searchButton = app.buttons["search-sidebar-button"]
        let listRow = app.buttons["card-list-row-Scroll Picks"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: listRow, toEqual: "72 cards"))

        for _ in 0..<5 {
            listRow.click()
            XCTAssertTrue(app.staticTexts["card-list-entry-count"].waitForExistence(timeout: 3))
            rapidlyScroll(cardListScrollView(app: app))

            searchButton.click()
            XCTAssertTrue(app.buttons["open-card-zoom-00"].waitForExistence(timeout: 3))
            rapidlyScroll(searchResultsScrollView(app: app))
        }

        listRow.click()
        XCTAssertTrue(firstElement(app, identifier: "list-detail-more-menu").waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: app.staticTexts["card-list-entry-count"], toEqual: "72 cards"))

        searchButton.click()
        XCTAssertTrue(app.buttons["open-card-zoom-00"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: app.staticTexts["search-results-total"], toEqual: "72 cards"))
    }

    func testHeavySearchAndListScrollingWithImagesStaysResponsive() throws {
        let imageURL = try makeFixtureImage(named: "heavy-scroll.png")
        let cards = makeZoomFixtureCards(count: 180).map { card -> CardRecord in
            var card = card
            card.normalImagePath = imageURL.path
            return card
        }
        let databaseURL = try seedDatabase(cards: cards)
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardList(named: "Heavy Scroll")
        for card in cards.prefix(120) {
            try database.appendCard(card.id, toList: list.id)
        }

        let app = launchApp(databaseURL: databaseURL)
        let searchButton = app.buttons["search-sidebar-button"]
        let listRow = app.buttons["card-list-row-Heavy Scroll"]
        let anySearchCard = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-card-zoom-"))
            .firstMatch
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        XCTAssertTrue(anySearchCard.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: listRow, toEqual: "120 cards"))

        for _ in 0..<8 {
            rapidlyScroll(searchResultsScrollView(app: app), passes: 8)

            listRow.click()
            XCTAssertTrue(app.staticTexts["card-list-entry-count"].waitForExistence(timeout: 3))
            rapidlyScroll(cardListScrollView(app: app), passes: 8)

            searchButton.click()
            XCTAssertTrue(searchResultsScrollView(app: app).waitForExistence(timeout: 3))
            XCTAssertTrue(anySearchCard.waitForExistence(timeout: 3))
        }

        XCTAssertTrue(searchButton.exists)
        XCTAssertTrue(anySearchCard.exists)
    }

    func testCategorizedListFastScrollingWithImagesStaysResponsive() throws {
        let imageURL = try makeFixtureImage(named: "categorized-scroll.png")
        let cards = makeZoomFixtureCards(count: 96).map { card -> CardRecord in
            var card = card
            card.normalImagePath = imageURL.path
            return card
        }
        let databaseURL = try seedDatabase(cards: cards)
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardList(named: "Categorized Scroll")
        let categories = try ["Core", "Land", "Interaction", "Setup", "Finishers", "Sideboard"].map { name in
            try database.createCardListCategory(inList: list.id, named: name)
        }
        for (index, card) in cards.enumerated() {
            try database.appendCard(card.id, toList: list.id, categoryID: categories[index % categories.count].id)
        }

        let app = launchApp(databaseURL: databaseURL)
        let searchButton = app.buttons["search-sidebar-button"]
        let listRow = app.buttons["card-list-row-Categorized Scroll"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: listRow, toEqual: "96 cards"))

        listRow.click()
        XCTAssertTrue(app.staticTexts["card-list-entry-count"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["list-category-section-Core"].waitForExistence(timeout: 3))

        for _ in 0..<6 {
            rapidlyScroll(cardListScrollView(app: app), passes: 10)
            XCTAssertTrue(firstElement(app, identifier: "list-detail-more-menu").waitForExistence(timeout: 3))

            searchButton.click()
            XCTAssertTrue(searchResultsScrollView(app: app).waitForExistence(timeout: 3))

            listRow.click()
            XCTAssertTrue(app.staticTexts["card-list-entry-count"].waitForExistence(timeout: 3))
        }

        XCTAssertTrue(waitForValue(of: app.staticTexts["card-list-entry-count"], toEqual: "96 cards"))
        XCTAssertTrue(firstElement(app, identifier: "list-detail-more-menu").exists)
    }

    func testSearchHeaderDoesNotExposeDefaultSearchControl() throws {
        let databaseURL = try seedDatabase(cards: makeZoomFixtureCards(count: 18))
        let app = launchApp(
            databaseURL: databaseURL,
            defaultSearchText: "Zoom Fixture"
        )
        XCTAssertTrue(app.descendants(matching: .any)["mac-search-expanded-header"].waitForExistence(timeout: 3))

        XCTAssertFalse(firstElement(app, identifier: "default-search-indicator").exists)
        XCTAssertFalse(firstElement(app, identifier: "edit-default-search-button").exists)
        XCTAssertTrue(firstElement(app, identifier: "search-sort-menu").waitForExistence(timeout: 3))
        XCTAssertTrue(firstElement(app, identifier: "search-filter-menu").exists)
        XCTAssertTrue(firstElement(app, identifier: "printing-display-mode-picker").exists)
    }

    func testCommandFFocusesFloatingSearchField() throws {
        let databaseURL = try seedDatabase(cards: makeZoomFixtureCards(count: 36))
        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.buttons["open-card-zoom-00"].waitForExistence(timeout: 5))

        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["mac-search-expanded-header"].waitForExistence(timeout: 3))
        app.typeText("35")

        XCTAssertTrue(app.buttons["open-card-zoom-35"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: app.staticTexts["search-results-total"], toEqual: "1 card"))
    }

    func testGridTilesKeepEqualHeightsWithLongNames() throws {
        let imageURL = try makeFixtureImage(named: "equal-height.png")
        let databaseURL = try seedDatabase(cards: [
            gridTileFixtureCard(id: "short", name: "Bolt", collectorNumber: "1", imagePath: imageURL.path),
            gridTileFixtureCard(
                id: "long",
                name: "This Is An Extremely Long Magic Card Name That Should Truncate Inside The Grid Footer",
                collectorNumber: "2",
                imagePath: imageURL.path
            ),
            gridTileFixtureCard(id: "medium", name: "Abstract Performance", collectorNumber: "3", imagePath: imageURL.path)
        ])
        let app = launchApp(databaseURL: databaseURL)

        let shortTile = app.buttons["open-card-short"]
        let longTile = app.buttons["open-card-long"]
        let mediumTile = app.buttons["open-card-medium"]
        XCTAssertTrue(shortTile.waitForExistence(timeout: 5))
        XCTAssertTrue(longTile.waitForExistence(timeout: 3))
        XCTAssertTrue(mediumTile.waitForExistence(timeout: 3))

        let heights = [shortTile.frame.height, longTile.frame.height, mediumTile.frame.height]
        let minHeight = heights.min() ?? 0
        let maxHeight = heights.max() ?? 0
        XCTAssertLessThanOrEqual(maxHeight - minHeight, 1)
    }

    func testRotatedSearchArtworkStaysInsideContentViewport() throws {
        let imageURL = try makeFixtureImage(named: "battle-rotated.png")
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "battle",
                name: "Invasion of Fixture",
                releasedAt: "2020-01-01",
                setCode: "mom",
                setName: "March of the Machine",
                setType: "expansion",
                collectorNumber: "42",
                collectorNumberNumber: 42,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "transform",
                typeLine: "Battle — Siege // Creature",
                oracleText: "When Invasion of Fixture enters, draw a card.",
                isRealCard: true,
                faces: [
                    CardFaceRecord(
                        cardID: "battle",
                        faceIndex: 0,
                        name: "Invasion of Fixture",
                        typeLine: "Battle — Siege",
                        oracleText: "When Invasion of Fixture enters, draw a card.",
                        normalImagePath: imageURL.path,
                        largeImagePath: imageURL.path
                    ),
                    CardFaceRecord(
                        cardID: "battle",
                        faceIndex: 1,
                        name: "Fixture Angel",
                        typeLine: "Creature — Angel",
                        oracleText: "Flying",
                        normalImagePath: imageURL.path,
                        largeImagePath: imageURL.path
                    )
                ]
            ),
            CardRecord(
                id: "normal-neighbor",
                name: "Fixture Angel",
                releasedAt: "2019-01-01",
                setCode: "fix",
                setName: "Fixture Set",
                setType: "expansion",
                collectorNumber: "7",
                collectorNumberNumber: 7,
                rarity: "uncommon",
                rarityRank: 1,
                colorSortKey: 0,
                layout: "normal",
                typeLine: "Creature — Angel",
                oracleText: "Flying",
                isRealCard: true,
                normalImagePath: imageURL.path,
                largeImagePath: imageURL.path
            )
        ])
        let app = launchApp(databaseURL: databaseURL, appearance: .dark)

        let card = app.buttons["open-card-battle"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let normalNeighbor = app.buttons["open-card-normal-neighbor"]
        XCTAssertTrue(normalNeighbor.waitForExistence(timeout: 3))
        let cardTile = app.descendants(matching: .any)["card-grid-item-battle"]
        XCTAssertTrue(cardTile.waitForExistence(timeout: 3))
        let normalNeighborTile = app.descendants(matching: .any)["card-grid-item-normal-neighbor"]
        XCTAssertTrue(normalNeighborTile.waitForExistence(timeout: 3))
        let identifiedScrollView = app.scrollViews["search-results-scroll"]
        let scrollView = identifiedScrollView.waitForExistence(timeout: 1)
            ? identifiedScrollView
            : app.scrollViews["results-grid"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(card.frame.minX, scrollView.frame.minX - 1)

        let cycleButton = firstElement(app, identifier: "card-artwork-cycle-battle")
        XCTAssertTrue(cycleButton.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: cycleButton, toEqual: "Showing face-0-rotation-90"))
        XCTAssertGreaterThanOrEqual(cardTile.frame.minX, scrollView.frame.minX - 1)
        XCTAssertLessThanOrEqual(cardTile.frame.maxX, scrollView.frame.maxX + 1)
        XCTAssertGreaterThan(cardTile.frame.width, normalNeighborTile.frame.width * 1.1)
        XCTAssertEqual(cardTile.frame.height, normalNeighborTile.frame.height, accuracy: 2.5)
        XCTAssertFalse(cardTile.frame.intersects(normalNeighborTile.frame))
        XCTAssertEqual(cardTile.frame.minY, normalNeighborTile.frame.minY, accuracy: 1.5)
        let initialBattleTileFrame = cardTile.frame

        cycleButton.click()
        XCTAssertTrue(waitForValue(of: cycleButton, toEqual: "Showing face-1-rotation-0"))
        XCTAssertLessThanOrEqual(cardTile.frame.height - initialBattleTileFrame.height, 14)
        XCTAssertEqual(cardTile.frame.minY, initialBattleTileFrame.minY, accuracy: 8)
        XCTAssertLessThanOrEqual(cardTile.frame.maxY, normalNeighborTile.frame.maxY + 14)
        XCTAssertFalse(firstElement(app, identifier: "card-detail").exists)
    }

    func testRotatedDetailArtworkDoesNotOverlapDetailText() throws {
        let imageURL = try makeFixtureImage(named: "battle-detail-rotated.png")
        let databaseURL = try seedDatabase(cards: [
            CardRecord(
                id: "battle",
                name: "Invasion of Fixture",
                releasedAt: "2020-01-01",
                setCode: "mom",
                setName: "March of the Machine",
                setType: "expansion",
                collectorNumber: "42",
                collectorNumberNumber: 42,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 1,
                layout: "transform",
                typeLine: "Battle — Siege // Creature",
                oracleText: "When Invasion of Fixture enters, draw a card.",
                isRealCard: true,
                faces: [
                    CardFaceRecord(
                        cardID: "battle",
                        faceIndex: 0,
                        name: "Invasion of Fixture",
                        typeLine: "Battle — Siege",
                        oracleText: "When Invasion of Fixture enters, draw a card.",
                        normalImagePath: imageURL.path,
                        largeImagePath: imageURL.path
                    ),
                    CardFaceRecord(
                        cardID: "battle",
                        faceIndex: 1,
                        name: "Fixture Angel",
                        typeLine: "Creature — Angel",
                        oracleText: "Flying",
                        normalImagePath: imageURL.path,
                        largeImagePath: imageURL.path
                    )
                ]
            )
        ])
        let app = launchApp(databaseURL: databaseURL, appearance: .dark)

        let card = app.buttons["open-card-battle"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.click()

        let detail = app.scrollViews["card-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        let artworkLayout = detail.descendants(matching: .any)
            .matching(identifier: "card-detail-artwork-layout")
            .firstMatch
        let detailText = detail.descendants(matching: .any)
            .matching(identifier: "card-detail-text")
            .firstMatch
        XCTAssertTrue(artworkLayout.waitForExistence(timeout: 3))
        XCTAssertTrue(detailText.waitForExistence(timeout: 3))
        XCTAssertFalse(artworkLayout.frame.intersects(detailText.frame))

        let cycleButton = detail.descendants(matching: .button)
            .matching(identifier: "card-artwork-cycle-battle")
            .firstMatch
        XCTAssertTrue(cycleButton.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: cycleButton, toEqual: "Showing face-0-rotation-90"))
        XCTAssertLessThan(artworkLayout.frame.height, artworkLayout.frame.width)
        cycleButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(waitForValue(of: cycleButton, toEqual: "Showing face-1-rotation-0"))
        XCTAssertFalse(artworkLayout.frame.intersects(detailText.frame))
    }

    func testEmptyLibraryStartsWithoutNetwork() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("empty.sqlite")
        _ = try CardDatabase(storage: .file(databaseURL))

        let app = launchApp(databaseURL: databaseURL)
        XCTAssertTrue(app.staticTexts["Set Up Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Download"].exists)
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["search-sort-menu"].exists)
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
        let list = try database.createCardList(named: "Drafts")
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
        _ = try database.createCardList(named: "Bulk Drops")

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

    func testCardListsCreateAddDuplicateQuantitiesRemoveAndClose() throws {
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

        let moveToCategoryButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "move-list-entry-"))
            .firstMatch
        XCTAssertTrue(moveToCategoryButton.waitForExistence(timeout: 3))
        moveToCategoryButton.click()
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Ramp"))
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
        XCTAssertTrue(contextMenuContains(app: app, named: "Create New List"))
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Add to Favourites"))

        let favouritesRow = app.buttons["card-list-row-Favourites"]
        XCTAssertTrue(favouritesRow.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: favouritesRow, toEqual: "1 card"))

        try openArtworkContextMenu(app: app, cardID: "alpha")
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Add to Favourites"))
        XCTAssertTrue(waitForValue(of: favouritesRow, toEqual: "1 card"))

        try openArtworkContextMenu(app: app, cardID: "alpha")
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Create New List"))

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeText("Context Picks")
        app.sheets.firstMatch.buttons["Create"].click()

        let contextRow = app.buttons["card-list-row-Context Picks"]
        XCTAssertTrue(contextRow.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: contextRow, toEqual: "1 card"))
    }

    func testCardListDirectSelectionClearsAndEntryActionsRemainAvailable() throws {
        let databaseURL = try seedDatabase(cards: makeZoomFixtureCards(count: 3))
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardList(named: "Drafts")
        try database.createCardListCategory(inList: list.id, named: "Ramp")
        let entries = [
            try database.appendCard("zoom-00", toList: list.id),
            try database.appendCard("zoom-01", toList: list.id),
            try database.appendCard("zoom-02", toList: list.id)
        ]

        let app = launchApp(databaseURL: databaseURL)
        let listRow = app.buttons["card-list-row-Drafts"]
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        listRow.click()

        let listCount = app.descendants(matching: .any)["card-list-entry-count"]
        XCTAssertTrue(listCount.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: listCount, toEqual: "3 cards"))

        XCTAssertFalse(app.buttons["select-list-entries-button"].exists)

        let checkboxQuery = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "select-list-entry-"))

        func listEntryButton(at index: Int) -> XCUIElement {
            app.buttons["open-list-entry-\(entries[index].id)"]
        }
        let firstCard = listEntryButton(at: 0)
        let secondCard = listEntryButton(at: 1)
        let thirdCard = listEntryButton(at: 2)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 3))
        XCTAssertTrue(secondCard.waitForExistence(timeout: 3))
        XCTAssertTrue(thirdCard.waitForExistence(timeout: 3))

        XCUIElement.perform(withKeyModifiers: [.command]) {
            listEntryButton(at: 0).click()
        }
        XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 2))
        XCTAssertTrue(checkboxQuery.firstMatch.waitForExistence(timeout: 3))

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["1 selected"], timeout: 2))

        XCUIElement.perform(withKeyModifiers: [.command]) {
            listEntryButton(at: 0).click()
        }
        XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 2))

        try clickToolbarMenuItem(
            app: app,
            menuIdentifier: "list-detail-more-menu",
            itemIdentifier: "clear-list-entry-selection-button"
        )
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["1 selected"], timeout: 2))

        listEntryButton(at: 0).click()
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            listEntryButton(at: 2).click()
        }
        XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 3))

        let moveToCategoryButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "move-list-entry-"))
            .firstMatch
        XCTAssertTrue(moveToCategoryButton.waitForExistence(timeout: 3))
        moveToCategoryButton.click()
        XCTAssertTrue(clickMenuItemOrButton(app: app, named: "Ramp"))
        XCTAssertTrue(app.descendants(matching: .any)["list-category-section-Ramp"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: listCount, toEqual: "3 cards"))

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["3 selected"], timeout: 2))

        for index in entries.indices {
            XCUIElement.perform(withKeyModifiers: [.command]) {
                listEntryButton(at: index).click()
            }
        }
        XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["3 selected"], timeout: 3))

        let removeButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "remove-list-entry-")).firstMatch
        XCTAssertTrue(removeButton.waitForExistence(timeout: 3))
        removeButton.click()
        XCTAssertTrue(waitForValue(of: app.descendants(matching: .any)["card-list-entry-count"], toEqual: "2 cards"))
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["3 selected"], timeout: 3))
    }

    func testCardListSelectionClearsWhenClickingBlankListSpace() throws {
        let databaseURL = try seedDatabase(cards: makeZoomFixtureCards(count: 1))
        let database = try CardDatabase(storage: .file(databaseURL))
        let list = try database.createCardList(named: "Drafts")
        try database.appendCard("zoom-00", toList: list.id)

        let app = launchApp(databaseURL: databaseURL)
        let listRow = app.buttons["card-list-row-Drafts"]
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        listRow.click()

        let listCount = app.descendants(matching: .any)["card-list-entry-count"]
        XCTAssertTrue(listCount.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: listCount, toEqual: "1 card"))

        let firstCard = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-list-entry-"))
            .firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 3))

        firstCard.click()
        XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 2))

        app.scrollViews["card-list-detail-scroll"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.82))
            .click()
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["1 selected"], timeout: 2))
    }

    func testSearchResultSelectionClearsWhenClickingBlankGridSpace() throws {
        let databaseURL = try seedDatabase(cards: makeZoomFixtureCards(count: 1))
        let app = launchApp(databaseURL: databaseURL)

        let resultTotal = app.staticTexts["search-results-total"]
        XCTAssertTrue(resultTotal.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "1 card"))

        let firstCard = app.buttons["open-card-zoom-00"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 3))

        firstCard.click()
        XCTAssertTrue(waitForValue(of: firstCard, containing: "Selected"))

        let identifiedScrollView = app.scrollViews["search-results-scroll"]
        let scrollView = identifiedScrollView.exists ? identifiedScrollView : app.scrollViews["results-grid"]
        scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.82)).click()
        XCTAssertTrue(waitForValue(of: firstCard, notContaining: "Selected"))
    }

    func testSearchResultSingleClickSelectsAndSpaceOpensDetail() throws {
        let databaseURL = try seedDatabase(cards: makeZoomFixtureCards(count: 1))
        let app = launchApp(databaseURL: databaseURL)

        let resultTotal = app.staticTexts["search-results-total"]
        XCTAssertTrue(resultTotal.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: resultTotal, toEqual: "1 card"))

        let firstCard = app.buttons["open-card-zoom-00"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 3))

        firstCard.click()
        XCTAssertTrue(waitForValue(of: firstCard, containing: "Selected"))

        let closeButton = app.buttons["card-detail-close-button"]
        XCTAssertFalse(closeButton.waitForExistence(timeout: 1.6))

        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
    }

    func testCardListDescriptionNotesShortcutsPersistPlainText() throws {
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
        static let searchInputMode = "Grimora.search.inputMode"
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
        searchInputMode: String = "scryfall",
        plainTextSearchResponses: [String: String] = [:],
        valueDisplayCurrency: CardValueDisplayCurrency? = nil,
        usdToAUDRate: Double? = nil
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
            "-\(DefaultSearchPreferenceKeys.searchInputMode)",
            searchInputMode,
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
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] = temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] = userDefaultsSuite
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        if !plainTextSearchResponses.isEmpty {
            app.launchEnvironment["GRIMORA_TEST_PLAIN_TEXT_SEARCH_RESPONSES"] =
                plainTextSearchResponses
                .map { "\($0.key)\t\($0.value)" }
                .joined(separator: "\n")
        }
        app.launchEnvironment["GRIMORA_TEST_RESET_VALUE_DEFAULTS"] = "1"
        if let usdToAUDRate {
            app.launchEnvironment["GRIMORA_TEST_USD_TO_AUD_RATE"] = "\(usdToAUDRate)"
            app.launchEnvironment["GRIMORA_TEST_USD_TO_AUD_RATE_DATE"] = "2026-05-19"
        }
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
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

    private func seedValueHistory(
        databaseURL: URL,
        cardID: String,
        uuid: String = "uuid-value"
    ) async throws {
        let directory = temporaryDirectory
            .appendingPathComponent("ValueHistory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let printingsURL = directory.appendingPathComponent("AllIdentifiers.json")
        let pricesURL = directory.appendingPathComponent("AllPrices.json")
        try valueHistoryPrintingsJSON(cardID: cardID, uuid: uuid).write(to: printingsURL, options: .atomic)
        try valueHistoryPricesJSON(uuid: uuid).write(to: pricesURL, options: .atomic)

        let database = try CardDatabase(storage: .file(databaseURL))
        let importer = MTGJSONPriceHistoryImporter(database: database)
        _ = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-19", version: "5.3.0-test"),
            allPrintingsJSONURL: printingsURL,
            allPricesJSONURL: pricesURL
        )
    }

    private func valueHistoryPrintingsJSON(cardID: String, uuid: String) -> Data {
        Data("""
        {
          "data": {
            "\(uuid)": {
              "identifiers": {"scryfallId": "\(cardID)"}
            }
          }
        }
        """.utf8)
    }

    private func valueHistoryPricesJSON(uuid: String) -> Data {
        Data("""
        {
          "data": {
            "\(uuid)": {
              "paper": {
                "tcgplayer": {
                  "retail": {
                    "normal": {
                      "2026-01-01": 1.00,
                      "2026-03-01": 2.25,
                      "2026-03-10": 5.00,
                      "2026-03-31": 3.00,
                      "2026-04-01": 3.25
                    }
                  }
                }
              }
            }
          }
        }
        """.utf8)
    }

    private func valueFixtureCard(id: String, name: String) -> CardRecord {
        CardRecord(
            id: id,
            name: name,
            releasedAt: "2026-04-01",
            setCode: "val",
            setName: "Value Set",
            setType: "expansion",
            collectorNumber: "1",
            collectorNumberNumber: 1,
            rarity: "rare",
            rarityRank: 2,
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Creature",
            oracleText: "Flying",
            isRealCard: true
        )
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

    private func gridTileFixtureCard(id: String, name: String, collectorNumber: String, imagePath: String) -> CardRecord {
        CardRecord(
            id: id,
            name: name,
            releasedAt: "2020-01-01",
            setCode: "eqh",
            setName: "Equal Heights",
            setType: "expansion",
            collectorNumber: collectorNumber,
            collectorNumberNumber: Int(collectorNumber) ?? 0,
            rarity: "common",
            rarityRank: 0,
            colorSortKey: Int(collectorNumber) ?? 0,
            layout: "normal",
            typeLine: "Instant",
            oracleText: "Fixture card.",
            isRealCard: true,
            normalImagePath: imagePath
        )
    }

    private func waitForFrameWidth(
        of element: XCUIElement,
        timeout: TimeInterval,
        matching predicate: (CGFloat) -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(element.frame.width) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return predicate(element.frame.width)
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

    private func accessibilityText(of element: XCUIElement) -> String {
        [element.label, element.value as? String]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func selectPickerOption(
        app: XCUIApplication,
        picker: XCUIElement,
        option: String
    ) -> Bool {
        picker.click()

        let menuItem = app.menuItems[option]
        if menuItem.waitForExistence(timeout: 2) {
            menuItem.click()
            return true
        }

        let button = app.buttons[option]
        if button.waitForExistence(timeout: 1) {
            button.click()
            return true
        }

        let text = app.staticTexts[option]
        if text.waitForExistence(timeout: 1) {
            text.click()
            return true
        }

        return false
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

            let scrollView = cardListScrollView(app: app)
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

    private func cardListScrollView(app: XCUIApplication) -> XCUIElement {
        let identifiedScrollView = app.scrollViews["card-list-detail-scroll"]
        return identifiedScrollView.exists ? identifiedScrollView : app.scrollViews.firstMatch
    }

    private func searchResultsScrollView(app: XCUIApplication) -> XCUIElement {
        let identifiedScrollView = app.scrollViews["search-results-scroll"]
        return identifiedScrollView.exists ? identifiedScrollView : app.scrollViews["results-grid"]
    }

    private func scrollPrimaryScrollView(app: XCUIApplication, down: Bool) {
        let scrollView = cardListScrollView(app: app)
        guard scrollView.waitForExistence(timeout: 1) else {
            return
        }

        let startY = down ? 0.82 : 0.24
        let endY = down ? 0.24 : 0.82
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func rapidlyScroll(_ scrollView: XCUIElement, passes: Int = 4) {
        guard scrollView.waitForExistence(timeout: 1) else {
            return
        }

        for index in 0..<passes {
            let deltaY: CGFloat = index.isMultiple(of: 2) ? -700 : 700
            scrollView.scroll(byDeltaX: 0, deltaY: deltaY)
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private func revealJumpToTopButton(
        app: XCUIApplication,
        identifier: String,
        scrollView: XCUIElement,
        topElement: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3), file: file, line: line)
        let button = app.buttons[identifier]
        _ = topElement

        for deltaY in [-300.0, 300.0] as [CGFloat] {
            for _ in 0..<12 {
                if button.exists {
                    return button
                }
                scrollView.scroll(byDeltaX: 0, deltaY: deltaY)
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
        }

        XCTAssertTrue(button.waitForExistence(timeout: 1), file: file, line: line)
        return button
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
