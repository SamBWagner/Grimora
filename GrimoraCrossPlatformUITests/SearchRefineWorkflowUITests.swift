import Foundation
import GrimoraCore
import XCTest

/// Proves the search-refinement journey on the touch platforms: search oracle text,
/// open a result, and refine on its oracle text via "More cards with …", which appends
/// an `o:"…"` clause to the search query and re-runs the search in one step (no manual
/// submit). The iOS branch asserts both that the field gained the clause and that the
/// results narrowed.
///
/// This file backs both `GrimoraiOSUITests` and `GrimoraVisionOSUITests`. The search +
/// filtering assertions run on both; the open + oracle-refine steps are gated to iOS
/// because the visionOS *simulator* can't reliably tap the lazily-rendered result grid
/// (its cells aren't consistently hittable for XCUITest tap synthesis) — a tooling limit,
/// not an app one, that the rest of the suite gates around the same way.
final class SearchRefineWorkflowUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraSearchRefineWorkflowUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testOracleSelectionRefineAppendsOracleClauseToSearch() throws {
        let app = try launchSeededApp()
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 15))

        // Step 1 — type the oracle search and submit. The flyer-only distractor,
        // which lacks "Deals combat damage", is filtered out.
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        activate(searchField)
        searchField.typeText("o:\"Deals combat damage\"")
        submitSearch(app: app, searchField: searchField)
        XCTAssertTrue(waitForValue(of: total, toEqual: "3 cards", timeout: 10))
        XCTAssertTrue(firstElement(app, identifier: "open-card-goad-combat").exists)
        XCTAssertTrue(firstElement(app, identifier: "open-card-goad-flyer").exists)
        XCTAssertTrue(firstElement(app, identifier: "open-card-combat-only").exists)
        XCTAssertFalse(firstElement(app, identifier: "open-card-flyer-only").exists)

        // Opening a result and driving its oracle-text edit menu both require tapping a
        // lazily-rendered grid cell. The visionOS *simulator* can't do that reliably:
        // those cells aren't consistently hittable for XCUITest's tap synthesis, so a
        // result card cannot be opened there (real Vision Pro taps the grid fine). The
        // codebase already gates grid interaction to iOS for this reason — see
        // `AdvancedSearchUITests`, which waits on the tab view and asserts the grid only
        // on iOS. The open + refine below therefore runs on iOS; the search + filtering
        // above is the visionOS coverage.
        #if os(iOS)
        // Step 2 — open the goad card.
        activate(firstElement(app, identifier: "open-card-goad-combat"))
        let detail = firstElement(app, identifier: "card-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 10))

        // Step 3 — long-press the goad sentence to select a word, then choose "More
        // cards with …". The goad sentence is the long first paragraph (it dominates
        // the text view's height); pressing at dy 0.3 lands on a goad-distinctive word
        // that is absent from the combat-only distractor, so the appended clause is the
        // one that would narrow the results. (The short "Deals combat damage." line —
        // shared with combat-only — sits at the very bottom, well clear of the press.)
        let oracle = oracleText(in: detail)
        XCTAssertTrue(oracle.waitForExistence(timeout: 5))
        oracle.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3))
            .press(forDuration: 1.0)
        let moreCards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "More cards with"))
            .firstMatch
        if !moreCards.waitForExistence(timeout: 0.5) {
            // The custom actions can sit behind the edit menu's "Forward" arrow.
            let forward = app.buttons["Forward"]
            if forward.waitForExistence(timeout: 2) {
                activate(forward)
            }
        }
        XCTAssertTrue(moreCards.waitForExistence(timeout: 3))
        activate(moreCards)

        // Return to the results so the refined search field is reachable (on iPhone
        // the detail is a fullScreenCover over the results).
        dismissDetail(app: app, detail: detail)
        XCTAssertTrue(firstElement(app, identifier: "open-card-goad-combat").waitForExistence(timeout: 5))

        // "More cards with …" appends an `o:"<selected text>"` clause to the search
        // query. Verify the refine populated the field with that extra oracle clause —
        // whichever goad-distinctive word the long-press landed on.
        let refinedField = app.searchFields.firstMatch
        XCTAssertTrue(refinedField.waitForExistence(timeout: 5))
        let baseQuery = "o:\"Deals combat damage\""
        let refinedValue = (refinedField.value as? String) ?? ""
        XCTAssertTrue(
            refinedValue.hasPrefix(baseQuery)
                && refinedValue.dropFirst(baseQuery.count).contains("o:"),
            "refine did not append an oracle clause; value=\(refinedValue)"
        )

        // The refine fires the re-query immediately: the two goad cards remain while
        // the combat-only distractor (which lacks the goad-distinctive word) drops out.
        XCTAssertTrue(waitForValue(of: total, toEqual: "2 cards", timeout: 10))
        XCTAssertTrue(firstElement(app, identifier: "open-card-goad-combat").exists)
        XCTAssertTrue(firstElement(app, identifier: "open-card-goad-flyer").exists)
        XCTAssertFalse(firstElement(app, identifier: "open-card-combat-only").exists)
        #endif
    }

    /// Submit the search field via the keyboard's Search key, falling back to a
    /// hardware return when the software keyboard is not presented.
    @MainActor
    private func submitSearch(app: XCUIApplication, searchField: XCUIElement) {
        let searchKey = app.keyboards.buttons["Search"]
        if searchKey.waitForExistence(timeout: 5) {
            searchKey.tap()
        } else if app.keyboards.buttons["return"].waitForExistence(timeout: 1) {
            app.keyboards.buttons["return"].tap()
        } else {
            searchField.typeText("\n")
        }
    }

    // The oracle/detail helpers below are only reachable from the iOS branch of the test
    // (the visionOS simulator can't tap the result grid to open a card), so they are
    // gated to iOS to keep the visionOS build free of unused-symbol warnings.
    #if os(iOS)
    /// The selectable oracle text, scrolling the detail into view if needed.
    @MainActor
    private func oracleText(in detail: XCUIElement) -> XCUIElement {
        let oracle = firstElement(detail, identifier: "card-detail-oracle-text")
        if oracle.waitForExistence(timeout: 2), oracle.isHittable {
            return oracle
        }
        for _ in 0..<6 where !oracle.isHittable {
            detail.swipeUp()
        }
        return oracle
    }

    /// Dismiss the card detail and return to the results grid. A dedicated close
    /// button is used when one is present and hittable (visionOS); otherwise the
    /// fly-up sheet is dragged down, which is how iPhone and iPad both dismiss it.
    @MainActor
    private func dismissDetail(app: XCUIApplication, detail: XCUIElement) {
        let closeButton = firstElement(app, identifier: "card-detail-close-button")
        if closeButton.waitForExistence(timeout: 2), closeButton.isHittable {
            activate(closeButton)
        } else {
            let start = detail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            let end = detail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        _ = waitForNonExistence(of: detail, timeout: 3)
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
            "-\(DefaultSearchPreferenceKeys.cloudSyncMode)",
            "disabled"
        ]
        let fixtureData = try JSONEncoder().encode(Self.fixtureCards)
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] =
            temporaryDirectory.appendingPathComponent("search-refine-fixture.sqlite").path
        app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] =
            String(decoding: fixtureData, as: Unicode.UTF8.self)
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] =
            temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
            "GrimoraSearchRefineWorkflowUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        // Keep the first-run onboarding tour from overlaying the search UI.
        app.launchEnvironment["GRIMORA_DISABLE_ONBOARDING"] = "1"
        app.launch()
        return app
    }

    /// The two goad cards lead with "Goad target …" on the first oracle line and carry
    /// "Deals combat damage" on the second, so a first-line word selection refines on a
    /// goad-only substring. `combat-only` matches the initial search but not the goad
    /// refine; `flyer-only` matches neither and proves the initial search filters.
    static var fixtureCards: [CardRecord] {
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
}

private enum DefaultSearchPreferenceKeys {
    static let text = "Grimora.defaultSearch.text"
    static let alwaysIncludedText = "Grimora.search.alwaysIncludedText"
    static let sortMode = "Grimora.defaultSearch.sortMode"
    static let sortDirection = "Grimora.defaultSearch.sortDirection"
    static let cloudSyncMode = "Grimora.cloudSync.mode"
}
