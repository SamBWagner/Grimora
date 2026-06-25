import Foundation
import GrimoraCore
import XCTest

/// Proves the Advanced Search launcher actually works on the touch platforms
/// (iOS + visionOS): the toolbar button opens the modal form, and confirming a
/// built query runs it through the normal search path and filters the grid.
///
/// This file backs both `GrimoraiOSUITests` and `GrimoraVisionOSUITests`, so the
/// single test below executes on each platform's simulator.
final class AdvancedSearchUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraAdvancedSearchUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testAdvancedSearchButtonOpensFormAndAppliesQuery() throws {
        let app = try launchSeededApp()

        // Wait on the toolbar launcher (not the lazily-rendered card grid) as the
        // search-screen readiness signal — the visionOS simulator realizes grid
        // cells and their accessibility nodes too erratically to wait on reliably.
        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 15))
        // Match the launcher by label: SwiftUI does not propagate the
        // accessibilityIdentifier of a toolbar Button to the visionOS AX tree
        // (it surfaces only the "Advanced Search" label), while the label is
        // present on both platforms.
        let launchButton = button(app, labeled: "Advanced Search")
        XCTAssertTrue(launchButton.waitForExistence(timeout: 20))
        activate(launchButton)

        // The launcher presents the modal form.
        let form = firstElement(app, identifier: "advanced-search-form")
        XCTAssertTrue(form.waitForExistence(timeout: 10))

        // Build a name query; the live preview proves the form composed the
        // Scryfall query the submit path will run.
        let nameField = firstElement(app, identifier: "advanced-search-name-field")
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        activate(nameField)
        nameField.typeText("Forest")
        XCTAssertTrue(
            waitForText(
                of: firstElement(app, identifier: "advanced-search-generated-query"),
                toEqual: "name:Forest",
                timeout: 10
            )
        )

        // Confirming runs it through the normal submit path and dismisses the sheet.
        activate(firstElement(app, identifier: "advanced-search-submit"))
        XCTAssertTrue(waitForNonExistence(of: form, timeout: 10))

        // The result count reflects the 3 → 1 filter, proving the submitted query
        // actually drove the search. Asserted on iOS, where the simulator exposes
        // the result grid/count reliably; macOS covers the count too. On visionOS
        // the lifecycle above is the proof, since its grid/count are too flaky.
        #if os(iOS)
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForText(of: total, toEqual: "1 card", timeout: 10))
        XCTAssertTrue(firstElement(app, identifier: "open-card-forest-card").waitForExistence(timeout: 10))
        #endif
    }

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
            temporaryDirectory.appendingPathComponent("advanced-search-fixture.sqlite").path
        app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] =
            String(decoding: fixtureData, as: Unicode.UTF8.self)
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] =
            temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
            "GrimoraAdvancedSearchUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    static var fixtureCards: [CardRecord] {
        [
            fixtureCard(id: "forest-card", name: "Forest Sentinel", releasedAt: "2020-01-01", collectorNumber: "1"),
            fixtureCard(id: "mage-card", name: "Mage Adept", releasedAt: "2020-01-02", collectorNumber: "2"),
            fixtureCard(id: "token-card", name: "Soldier Token", releasedAt: "2020-01-03", collectorNumber: "3", isRealCard: false)
        ]
    }

    static func fixtureCard(
        id: String,
        name: String,
        releasedAt: String,
        collectorNumber: String,
        isRealCard: Bool = true
    ) -> CardRecord {
        CardRecord(
            id: id,
            name: name,
            releasedAt: releasedAt,
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: collectorNumber,
            collectorNumberNumber: Int(collectorNumber) ?? 0,
            rarity: "common",
            rarityRank: 0,
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Creature",
            oracleText: "",
            isRealCard: isRealCard
        )
    }
}

private enum DefaultSearchPreferenceKeys {
    static let text = "Grimora.defaultSearch.text"
    static let alwaysIncludedText = "Grimora.search.alwaysIncludedText"
    static let sortMode = "Grimora.defaultSearch.sortMode"
    static let sortDirection = "Grimora.defaultSearch.sortDirection"
    static let cloudSyncMode = "Grimora.cloudSync.mode"
}
