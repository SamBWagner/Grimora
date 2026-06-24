import Foundation
import GrimoraCore
import XCTest

#if os(iOS)
import UIKit
#endif

final class ArtworkPresentationUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraArtworkUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testArtworkControlsCycleVariantsInSearchGridAndDetail() throws {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom != .phone else {
            return
        }
        #endif

        let app = try launchSeededApp()
        let searchResults = firstElement(app, identifier: "search-results-scroll")
        XCTAssertTrue(searchResults.waitForExistence(timeout: 8))
        XCTAssertTrue(firstElement(app, identifier: "open-card-fable-main").waitForExistence(timeout: 8))

        try assertCycle(
            app: app,
            cardID: "fable-main",
            initialVariantID: "face-0-rotation-0",
            variantsAfterTaps: ["face-1-rotation-0"],
            scrollingIn: searchResults
        )
        XCTAssertFalse(firstElement(app, identifier: "card-detail").exists)

        try assertCycle(
            app: app,
            cardID: "wax",
            initialVariantID: "card-rotation-0",
            variantsAfterTaps: ["card-rotation-90"],
            scrollingIn: searchResults
        )
        XCTAssertFalse(firstElement(app, identifier: "card-detail").exists)

        try assertCycle(
            app: app,
            cardID: "budoka",
            initialVariantID: "card-rotation-0",
            variantsAfterTaps: ["card-rotation-180"],
            scrollingIn: searchResults
        )
        XCTAssertFalse(firstElement(app, identifier: "card-detail").exists)

        try assertCycle(
            app: app,
            cardID: "battle",
            initialVariantID: "face-0-rotation-90",
            variantsAfterTaps: ["face-1-rotation-0"],
            scrollingIn: searchResults
        )
        XCTAssertFalse(firstElement(app, identifier: "card-detail").exists)

        openSearchResult(visibleElement(app, identifier: "open-card-fable-main", scrollingIn: searchResults))
        let detail = firstElement(app, identifier: "card-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))

        try assertCycle(
            in: detail,
            cardID: "fable-main",
            initialVariantID: "face-0-rotation-0",
            variantsAfterTaps: ["face-1-rotation-0"]
        )
    }

    @MainActor
    func testArtworkContextMenuExposesCardActions() throws {
        let app = try launchSeededApp()
        let card = firstElement(app, identifier: "open-card-fable-main")
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        revealContextMenu(on: card)
        XCTAssertTrue(waitForContextMenuItem(app: app, identifier: "card-artwork-share-menu-fable-main", label: "Share"))
        XCTAssertTrue(
            waitForContextMenuItem(app: app, identifier: "card-artwork-add-favourites-fable-main", label: "Add to Favourites")
        )
        XCTAssertTrue(waitForContextMenuItem(app: app, identifier: "card-artwork-create-list-fable-main", label: "Create New List"))
        XCTAssertTrue(
            waitForContextMenuItem(
                app: app,
                identifier: "card-artwork-refine-search-fable-main",
                label: "Refine Search"
            )
        )
        XCTAssertTrue(
            waitForContextMenuItem(
                app: app,
                identifier: "card-artwork-always-hide-fable-main",
                label: "Always Hide"
            )
        )

        try activateContextMenuItem(
            app: app,
            identifier: "card-artwork-create-list-fable-main",
            label: "Create New List"
        )
        try submitNamePrompt(app: app, name: "Context Picks", buttonTitle: "Create")

        revealContextMenu(on: card)
        XCTAssertTrue(waitForContextMenuItem(app: app, identifier: "card-artwork-add-to-list-menu-fable-main", label: "Add to List"))
    }

    @MainActor
    func testCardDetailUsesOneTriStateRefineControl() throws {
        let app = try launchSeededApp()
        let card = firstElement(app, identifier: "open-card-fable-main")
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        openSearchResult(card)

        let detail = firstElement(app, identifier: "card-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let refine = visibleElement(
            detail,
            identifier: "card-detail-refine-button",
            scrollingIn: detail
        )
        XCTAssertTrue(refine.isHittable)
        XCTAssertFalse(firstElement(detail, identifier: "card-detail-refinement-facets").exists)
        XCTAssertFalse(firstElement(detail, identifier: "card-detail-oracle-refinement").exists)
        XCTAssertTrue(firstElement(detail, identifier: "card-detail-oracle-text").exists)

        activate(refine)
        let panel = firstElement(app, identifier: "search-refinement-panel")
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        let enchantment = app.buttons
            .matching(NSPredicate(format: "label == %@", "Enchantment"))
            .firstMatch
        XCTAssertTrue(enchantment.waitForExistence(timeout: 3))
        XCTAssertEqual(enchantment.value as? String, "Neutral")

        activate(enchantment)
        XCTAssertEqual(enchantment.value as? String, "Include")
        activate(enchantment)
        XCTAssertEqual(enchantment.value as? String, "Exclude")

        activate(app.buttons["Clear"])
        XCTAssertEqual(enchantment.value as? String, "Neutral")
        activate(app.buttons["Cancel"])
        XCTAssertTrue(waitForNonExistence(of: panel))
    }

    #if os(iOS) || os(visionOS)
    @MainActor
    func testOracleSelectionMenuOffersTransientRefinements() throws {
        #if os(visionOS)
        throw XCTSkip(
            "The visionOS 26.5 simulator does not expose UITextView edit-menu actions to XCTest."
        )
        #else
        let app = try launchSeededApp()
        let card = firstElement(app, identifier: "open-card-fable-main")
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        openSearchResult(card)

        let detail = firstElement(app, identifier: "card-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let oracleText = visibleElement(
            detail,
            identifier: "card-detail-oracle-text",
            scrollingIn: detail
        )
        XCTAssertTrue(oracleText.isHittable)
        #if os(visionOS)
        oracleText.doubleTap()
        #else
        oracleText.press(forDuration: 1.0)
        #endif

        let includeAction = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "More cards with"))
            .firstMatch
        let excludeAction = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Exclude"))
            .firstMatch
        if !includeAction.waitForExistence(timeout: 0.5) {
            let forward = app.buttons["Forward"]
            if forward.waitForExistence(timeout: 2) {
                activate(forward)
            }
        }
        XCTAssertTrue(includeAction.waitForExistence(timeout: 3))
        XCTAssertTrue(excludeAction.exists)
        XCTAssertFalse(app.descendants(matching: .any)["Always Hide"].exists)
        #endif
    }
    #endif

    #if os(iOS)
    @MainActor
    func testPhoneCompactPrintingsKeepArtworkControlsIndependent() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return
        }

        let app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-fable-main").waitForExistence(timeout: 8))
        activate(firstElement(app, identifier: "open-card-fable-main"))

        let detail = firstElement(app, identifier: "card-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(firstElement(app, identifier: "card-printings-gallery").waitForExistence(timeout: 5))

        try assertCycle(
            in: detail,
            cardID: "fable-main",
            initialVariantID: "face-0-rotation-0",
            variantsAfterTaps: ["face-1-rotation-0"]
        )
        XCTAssertFalse(firstElement(app, identifier: "card-printing-full-screen-image").exists)

        activate(firstElement(app, identifier: "card-printing-fable-main-page"))
        let fullScreenArtwork = firstElement(app, identifier: "card-printing-full-screen-image")
        XCTAssertTrue(fullScreenArtwork.waitForExistence(timeout: 3))
        XCTAssertFalse(firstElement(app, identifier: "card-printing-full-screen-close-button").exists)
        dismissArtworkSheet(fullScreenArtwork)
        XCTAssertTrue(waitForNonExistence(of: fullScreenArtwork))

        activate(firstElement(app, identifier: "card-printings-show-all-button"))
        XCTAssertTrue(firstElement(app, identifier: "card-printings-grid").waitForExistence(timeout: 3))
        try assertCycle(
            app: app,
            cardID: "fable-alt-1",
            initialVariantID: "face-0-rotation-0",
            variantsAfterTaps: ["face-1-rotation-0"]
        )
    }

    @MainActor
    func testPhoneCardDetailUsesNativeSheetDismissal() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return
        }

        let app = try launchSeededApp()
        let card = firstElement(app, identifier: "open-card-fable-main")
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        activate(card)

        let detail = firstElement(app, identifier: "card-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(firstElement(app, identifier: "card-detail-add-to-list-button").waitForExistence(timeout: 3))
        XCTAssertTrue(firstElement(app, identifier: "card-share-button").waitForExistence(timeout: 3))
        XCTAssertFalse(firstElement(app, identifier: "card-detail-close-button").exists)

        dismissSheet(detail)

        XCTAssertTrue(waitForNonExistence(of: detail, timeout: 5))
        XCTAssertTrue(firstElement(app, identifier: "open-card-fable-main").waitForExistence(timeout: 3))
    }

    @MainActor
    func testPadCardDetailInspectorActionsUseTopTrailingToolbar() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            return
        }

        let app = try launchSeededApp()
        let card = firstElement(app, identifier: "open-card-fable-main")
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        activate(card)

        let detail = firstElement(app, identifier: "card-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))

        let addButton = firstElement(app, identifier: "card-detail-add-to-list-button")
        let shareButton = firstElement(app, identifier: "card-share-button")
        let closeButton = firstElement(app, identifier: "card-detail-close-button")
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        XCTAssertTrue(shareButton.waitForExistence(timeout: 3))
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))

        let toolbarMidYValues = [addButton.frame.midY, shareButton.frame.midY, closeButton.frame.midY]
        XCTAssertLessThanOrEqual((toolbarMidYValues.max() ?? 0) - (toolbarMidYValues.min() ?? 0), 36)
        XCTAssertLessThan(closeButton.frame.midY, detail.frame.minY + 160)
        XCTAssertGreaterThan(closeButton.frame.midX, detail.frame.midX)
    }

    @MainActor
    func testPadListToolbarKeepsGalleryListPickerAndActionsMenu() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            return
        }

        let app = try launchListSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "search-options-menu").waitForExistence(timeout: 8))
        let listsTab = firstButton(app, labeled: "Lists")
        XCTAssertTrue(listsTab.waitForExistence(timeout: 3))
        activate(listsTab)

        let draftsRow = firstElement(app, identifier: "card-list-row-Drafts")
        if draftsRow.waitForExistence(timeout: 1) {
            activate(draftsRow)
        } else {
            let draftsTile = firstElement(app, identifier: "card-list-overview-tile-Drafts")
            XCTAssertTrue(draftsTile.waitForExistence(timeout: 3))
            activate(draftsTile)
        }

        let viewModePicker = firstElement(app, identifier: "card-list-view-mode-picker")
        XCTAssertTrue(viewModePicker.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: viewModePicker, toEqual: "Gallery"))
        XCTAssertTrue(firstElement(app, identifier: "list-detail-actions-menu").waitForExistence(timeout: 3))

        let listSegment = segmentedControlButton(in: viewModePicker, labeled: "List")
        XCTAssertTrue(listSegment.waitForExistence(timeout: 3))
        activate(listSegment)
        XCTAssertTrue(waitForValue(of: viewModePicker, toEqual: "List"))

        let gallerySegment = segmentedControlButton(in: viewModePicker, labeled: "Gallery")
        XCTAssertTrue(gallerySegment.waitForExistence(timeout: 3))
        activate(gallerySegment)
        XCTAssertTrue(waitForValue(of: viewModePicker, toEqual: "Gallery"))
    }

    @MainActor
    func testPhoneSearchChromeStaysVisibleWhileScrollingResults() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return
        }

        let app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-fable-main").waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(app.searchFields.firstMatch))
        XCTAssertTrue(waitForHittable(firstElement(app, identifier: "search-options-menu")))

        for _ in 0..<3 {
            app.swipeUp()
        }

        XCTAssertTrue(waitForHittable(app.searchFields.firstMatch))
        XCTAssertTrue(waitForHittable(firstElement(app, identifier: "search-options-menu")))
    }

    @MainActor
    func testPhoneSearchOptionsStayAvailableDuringActiveSearch() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return
        }

        let app = try launchPhoneSearchOptionsApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-beta-mage").waitForExistence(timeout: 8))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("mage")

        XCTAssertTrue(firstElement(app, identifier: "search-options-menu").waitForExistence(timeout: 3))
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))

        try activateMenuItem(
            app: app,
            menuIdentifier: "search-options-menu",
            itemIdentifier: "search-view-options-menu"
        )
        activateMenuOverlayElement(firstElement(app, identifier: "search-sort-direction-option-descending"))
        XCTAssertTrue(waitForCard("alpha-mage", toAppearBefore: "beta-mage", in: app))

        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))
    }

    @MainActor
    func testTouchSearchWaitsForSubmit() throws {
        let app = try launchPhoneSearchOptionsApp()
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("alpha")

        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))
        XCTAssertTrue(firstElement(app, identifier: "open-card-beta-mage").exists)

        let searchButton = app.keyboards.buttons["Search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 3))
        searchButton.tap()

        XCTAssertTrue(waitForValue(of: total, toEqual: "1 card"))
        XCTAssertTrue(firstElement(app, identifier: "open-card-alpha-mage").exists)
        XCTAssertFalse(firstElement(app, identifier: "open-card-beta-mage").exists)
    }

    @MainActor
    func testTouchSearchOptionsDoNotExposeLegacyFilters() throws {
        let app = try launchPhoneSearchOptionsApp()
        XCTAssertTrue(firstElement(app, identifier: "open-card-beta-mage").waitForExistence(timeout: 8))

        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards"))

        activateMenuOverlayElement(firstElement(app, identifier: "search-options-menu"))
        XCTAssertTrue(firstElement(app, identifier: "search-view-options-menu").waitForExistence(timeout: 3))
        XCTAssertFalse(firstElement(app, identifier: "search-filter-menu").exists)
        XCTAssertFalse(firstElement(app, identifier: "filter-universes-beyond").exists)
        XCTAssertFalse(firstElement(app, identifier: "filter-alchemy").exists)
        XCTAssertFalse(firstElement(app, identifier: "filter-real-cards").exists)
    }

    @MainActor
    func testTouchSearchSupportsFirstPrintSyntax() throws {
        let app = try launchPhoneSearchOptionsApp(defaultSearchText: "is:first-print")
        let total = app.staticTexts["search-results-total"]

        XCTAssertTrue(total.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue(of: total, toEqual: "2 cards"))
        XCTAssertTrue(firstElement(app, identifier: "open-card-alpha-mage").exists)
        XCTAssertTrue(firstElement(app, identifier: "open-card-token-mage").exists)
        XCTAssertFalse(firstElement(app, identifier: "open-card-beta-mage").exists)
    }
    #endif

    @MainActor
    private func launchSeededApp() throws -> XCUIApplication {
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
            "scryfall"
        ]
        let fixtureData = try JSONEncoder().encode(Self.fixtureCards)
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] =
            temporaryDirectory.appendingPathComponent("artwork-fixture.sqlite").path
        app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] = String(decoding: fixtureData, as: Unicode.UTF8.self)
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] = temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] = "GrimoraArtworkUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    #if os(iOS)
    @MainActor
    private func launchListSeededApp() throws -> XCUIApplication {
        let databaseURL = try seedListDatabase()
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
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] = "GrimoraPadListUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    private func seedListDatabase() throws -> URL {
        let databaseURL = temporaryDirectory.appendingPathComponent("pad-list-fixture.sqlite")
        let database = try CardDatabase(storage: .file(databaseURL))
        try database.replaceAllCards(Self.fixtureCards)
        try database.saveMetadataValue("2026-04-25T09:09:59.477+00:00", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        try database.saveMetadataValue(CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
        try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)

        let list = try database.createCardList(named: "Drafts")
        try database.appendCard("fable-main", toList: list.id)
        return databaseURL
    }

    @MainActor
    private func launchPhoneSearchOptionsApp(defaultSearchText: String = "") throws -> XCUIApplication {
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
            "scryfall"
        ]
        let fixtureData = try JSONEncoder().encode(Self.phoneSearchFixtureCards)
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] =
            temporaryDirectory.appendingPathComponent("phone-search-fixture.sqlite").path
        app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] = String(decoding: fixtureData, as: Unicode.UTF8.self)
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] = temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] = "GrimoraPhoneSearchUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }
    #endif

    @MainActor
    private func assertCycle(
        app: XCUIApplication,
        cardID: String,
        initialVariantID: String,
        variantsAfterTaps: [String],
        scrollingIn scrollView: XCUIElement? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try assertCycle(
            in: app,
            cardID: cardID,
            initialVariantID: initialVariantID,
            variantsAfterTaps: variantsAfterTaps,
            scrollingIn: scrollView,
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertCycle(
        in root: XCUIElement,
        cardID: String,
        initialVariantID: String,
        variantsAfterTaps: [String],
        scrollingIn scrollView: XCUIElement? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let button = visibleElement(
            root,
            identifier: "card-artwork-cycle-\(cardID)",
            scrollingIn: scrollView
        )
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(
            waitForValue(of: button, toEqual: "Showing \(initialVariantID)"),
            "Expected \(cardID) to start on \(initialVariantID), found \(String(describing: button.value))",
            file: file,
            line: line
        )

        for variantID in variantsAfterTaps {
            activate(button)
            XCTAssertTrue(
                waitForValue(of: button, toEqual: "Showing \(variantID)"),
                "Expected \(cardID) to show \(variantID), found \(String(describing: button.value))",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func firstButton(_ app: XCUIApplication, labeled label: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    @MainActor
    private func visibleElement(
        _ root: XCUIElement,
        identifier: String,
        scrollingIn scrollView: XCUIElement?
    ) -> XCUIElement {
        if let element = visibleElementIfPresent(root, identifier: identifier) {
            return element
        }

        guard let scrollView else {
            return firstElement(root, identifier: identifier)
        }

        for _ in 0..<8 {
            scrollView.swipeUp()
            if let element = visibleElementIfPresent(root, identifier: identifier) {
                return element
            }
        }

        for _ in 0..<8 {
            scrollView.swipeDown()
            if let element = visibleElementIfPresent(root, identifier: identifier) {
                return element
            }
        }

        return firstElement(root, identifier: identifier)
    }

    @MainActor
    private func visibleElementIfPresent(_ root: XCUIElement, identifier: String) -> XCUIElement? {
        let element = firstElement(root, identifier: identifier)
        guard element.waitForExistence(timeout: 0.4), element.isHittable else {
            return nil
        }
        return element
    }

    @MainActor
    private func segmentedControlButton(in root: XCUIElement, labeled label: String) -> XCUIElement {
        let button = root.buttons
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        if button.exists {
            return button
        }

        return root.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    @MainActor
    private func openSearchResult(_ element: XCUIElement) {
        #if os(macOS)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).doubleClick()
        #else
        activate(element)
        #endif
    }

    @MainActor
    private func revealContextMenu(on element: XCUIElement) {
        #if os(macOS)
        element.rightClick()
        #else
        element.press(forDuration: 1.0)
        #endif
    }

    @MainActor
    private func dismissArtworkSheet(_ element: XCUIElement) {
        dismissSheet(element)
    }

    @MainActor
    private func dismissSheet(_ element: XCUIElement) {
        #if os(iOS)
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.05, thenDragTo: end)
        #else
        activate(element)
        #endif
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
        activateMenuOverlayElement(menu)

        let item = firstElement(app, identifier: itemIdentifier)
        XCTAssertTrue(item.waitForExistence(timeout: 3), file: file, line: line)
        activateMenuOverlayElement(item)
    }

    @MainActor
    private func activateContextMenuItem(
        app: XCUIApplication,
        identifier: String,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let item = contextMenuItem(app: app, identifier: identifier, label: label)
        XCTAssertTrue(item.waitForExistence(timeout: 3), file: file, line: line)
        activateMenuOverlayElement(item)
    }

    @MainActor
    private func waitForContextMenuItem(
        app: XCUIApplication,
        identifier: String,
        label: String,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if contextMenuItem(app: app, identifier: identifier, label: label).exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return contextMenuItem(app: app, identifier: identifier, label: label).exists
    }

    @MainActor
    private func contextMenuItem(
        app: XCUIApplication,
        identifier: String,
        label: String
    ) -> XCUIElement {
        let identified = firstElement(app, identifier: identifier)
        if identified.exists {
            return identified
        }

        let button = app.buttons[label]
        if button.exists {
            return button
        }

        let menuItem = app.menuItems[label]
        if menuItem.exists {
            return menuItem
        }

        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    @MainActor
    private func activateMenuOverlayElement(_ element: XCUIElement) {
        #if os(iOS)
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        #else
        activate(element)
        #endif
    }

    @MainActor
    private func submitNamePrompt(
        app: XCUIApplication,
        name: String,
        buttonTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), file: file, line: line)
        activate(field)
        field.typeText(name)

        let button = app.buttons[buttonTitle]
        XCTAssertTrue(button.waitForExistence(timeout: 3), file: file, line: line)
        activate(button)
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
    private func waitForCard(
        _ lhsID: String,
        toAppearBefore rhsID: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if card(lhsID, appearsBefore: rhsID, in: app) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return card(lhsID, appearsBefore: rhsID, in: app)
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
    private func waitForValue(
        of element: XCUIElement,
        toEqual expectedValue: String,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.value as? String == expectedValue || element.label == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.value as? String == expectedValue || element.label == expectedValue
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

private extension ArtworkPresentationUITests {
    static var fixtureCards: [CardRecord] {
        [
            fablePrinting(id: "fable-main", collectorNumber: "141"),
            fablePrinting(id: "fable-alt-1", collectorNumber: "142"),
            fablePrinting(id: "fable-alt-2", collectorNumber: "143"),
            fablePrinting(id: "fable-alt-3", collectorNumber: "144"),
            fablePrinting(id: "fable-alt-4", collectorNumber: "145"),
            topLevelImageCard(
                id: "wax",
                name: "Wax // Wane",
                layout: "split",
                typeLine: "Instant // Instant",
                collectorNumber: "1"
            ),
            topLevelImageCard(
                id: "budoka",
                name: "Budoka Gardener // Dokai, Weaver of Life",
                layout: "flip",
                typeLine: "Creature — Human Monk // Legendary Creature — Human Monk",
                collectorNumber: "2"
            ),
            battleCard,
            topLevelImageCard(
                id: "room",
                name: "Dollmaker's Shop // Porcelain Gallery",
                layout: "split",
                typeLine: "Enchantment — Room // Enchantment — Room",
                collectorNumber: "4"
            )
        ]
    }

    static var phoneSearchFixtureCards: [CardRecord] {
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
                priceUSD: nil,
                isRealCard: false
            )
        ]
    }

    static func fablePrinting(id: String, collectorNumber: String) -> CardRecord {
        CardRecord(
            id: id,
            oracleID: "fable-oracle",
            name: "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki",
            releasedAt: "2022-02-18",
            setCode: "neo",
            setName: "Kamigawa: Neon Dynasty",
            setType: "expansion",
            collectorNumber: collectorNumber,
            collectorNumberNumber: Int(collectorNumber),
            rarity: "rare",
            rarityRank: 2,
            colorSortKey: 3,
            layout: "transform",
            typeLine: "Enchantment — Saga // Enchantment Creature — Goblin Shaman",
            oracleText: "",
            keywords: ["Reflection"],
            faces: [
                CardFaceRecord(
                    cardID: id,
                    faceIndex: 0,
                    name: "Fable of the Mirror-Breaker",
                    typeLine: "Enchantment — Saga",
                    oracleText: "Create a Goblin Shaman token.",
                    normalImageURL: "https://example.test/\(id)-front.jpg"
                ),
                CardFaceRecord(
                    cardID: id,
                    faceIndex: 1,
                    name: "Reflection of Kiki-Jiki",
                    typeLine: "Enchantment Creature — Goblin Shaman",
                    oracleText: "",
                    normalImageURL: "https://example.test/\(id)-back.jpg"
                )
            ]
        )
    }

    static var battleCard: CardRecord {
        CardRecord(
            id: "battle",
            name: "Invasion of Tolvada // The Broken Sky",
            releasedAt: "2023-04-21",
            setCode: "mom",
            setName: "March of the Machine",
            setType: "expansion",
            collectorNumber: "3",
            collectorNumberNumber: 3,
            rarity: "rare",
            rarityRank: 2,
            colorSortKey: 5,
            layout: "transform",
            typeLine: "Battle — Siege // Enchantment",
            oracleText: "",
            faces: [
                CardFaceRecord(
                    cardID: "battle",
                    faceIndex: 0,
                    name: "Invasion of Tolvada",
                    typeLine: "Battle — Siege",
                    oracleText: "",
                    normalImageURL: "https://example.test/battle-front.jpg"
                ),
                CardFaceRecord(
                    cardID: "battle",
                    faceIndex: 1,
                    name: "The Broken Sky",
                    typeLine: "Enchantment",
                    oracleText: "",
                    normalImageURL: "https://example.test/battle-back.jpg"
                )
            ]
        )
    }

    static func topLevelImageCard(
        id: String,
        name: String,
        layout: String,
        typeLine: String,
        collectorNumber: String
    ) -> CardRecord {
        CardRecord(
            id: id,
            name: name,
            releasedAt: "2021-01-01",
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: collectorNumber,
            collectorNumberNumber: Int(collectorNumber),
            rarity: "uncommon",
            rarityRank: 1,
            colorSortKey: 0,
            layout: layout,
            typeLine: typeLine,
            oracleText: "",
            normalImageURL: "https://example.test/\(id).jpg"
        )
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
        priceUSD: Double?,
        isRealCard: Bool,
        isReprint: Bool = false
    ) -> CardRecord {
        CardRecord(
            id: id,
            oracleID: oracleID,
            name: name,
            releasedAt: releasedAt,
            setCode: "phn",
            setName: "Phone Fixture",
            setType: "expansion",
            collectorNumber: collectorNumber,
            collectorNumberNumber: Int(collectorNumber),
            rarity: rarity,
            rarityRank: rarity == "rare" ? 2 : 0,
            artist: "Phone Artist",
            manaCost: "{1}{U}",
            manaValue: 2,
            priceUSD: priceUSD,
            colorSortKey: colorSortKey,
            colors: ["U"],
            colorIdentity: ["U"],
            layout: "normal",
            typeLine: "Creature - Wizard",
            oracleText: oracleText,
            games: ["paper"],
            finishes: ["nonfoil"],
            isRealCard: isRealCard,
            isReprint: isReprint
        )
    }
}
