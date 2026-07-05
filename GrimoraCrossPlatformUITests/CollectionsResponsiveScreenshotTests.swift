import Foundation
import GrimoraCore
import XCTest

/// Screen-to-screen layout capture for the Collections overview on small iPhones.
///
/// This file backs `GrimoraiOSUITests` (and, trivially, `GrimoraVisionOSUITests`). The
/// capture is iOS-only: it seeds a user list alongside the system lists, taps the
/// Collections tab, and attaches a full-screen screenshot so the header action and the
/// tile grid can be eyeballed per device and Dynamic Type size. Run it per destination
/// (iPhone 13 mini / 17 / 17 Pro Max) and pull the PNG attachments from the `.xcresult`.
///
/// It is a review/regression artifact, not an assertion-heavy test — the only assertions
/// guard that navigation reached the overview so a blank shot can't pass silently.
final class CollectionsResponsiveScreenshotTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraCollectionsResponsive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    #if os(iOS)
    /// Collections overview at the default Dynamic Type size.
    @MainActor
    func testCollectionsOverviewDefaultType() throws {
        try captureCollections(contentSizeCategory: nil, label: "default")
    }

    /// Collections overview at an enlarged (XXXL) Dynamic Type size — stresses the header
    /// action, which is the most likely thing to wrap when the title grows.
    @MainActor
    func testCollectionsOverviewExtraLargeType() throws {
        try captureCollections(contentSizeCategory: "UICTContentSizeCategoryXXXL", label: "xxxl")
    }

    /// Collections overview in landscape. On a standard iPhone the landscape width is still
    /// a compact size class, so this proves the grid forms several columns there rather than
    /// stretching to one giant full-width banner.
    @MainActor
    func testCollectionsOverviewLandscape() throws {
        let device = XCUIDevice.shared
        device.orientation = .landscapeLeft
        defer { device.orientation = .portrait }
        try captureCollections(contentSizeCategory: nil, label: "landscape")
    }

    @MainActor
    private func captureCollections(contentSizeCategory: String?, label: String) throws {
        let app = try launchSeededApp(contentSizeCategory: contentSizeCategory)

        // Land on the Collections tab (the app opens on the Cards/search tab).
        // Use the label-matching helper (first match) rather than the `buttons["Collections"]`
        // subscript: on the iPadOS 26 floating tab bar the tab item nests two "Collections"
        // buttons (_UIFloatingTabBarItemCell), so the subscript resolves to multiple elements
        // and `.tap()` throws on ambiguity. This mirrors how AdvancedSearchUITests taps.
        let collectionsTab = button(app, labeled: "Collections")
        XCTAssertTrue(collectionsTab.waitForExistence(timeout: 20), "Collections tab button not found")
        activate(collectionsTab)

        let overview = firstElement(app, identifier: "card-lists-overview")
        XCTAssertTrue(overview.waitForExistence(timeout: 15), "Collections overview did not appear")
        // The create-list action is the header control we care about; waiting on it also
        // confirms the header laid out before the shot.
        _ = firstElement(app, identifier: "create-list-button").waitForExistence(timeout: 5)
        // Give async artwork tasks and layout a beat to settle so the shot is stable.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "collections-overview-\(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launchSeededApp(contentSizeCategory: String?) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-Grimora.cloudSync.mode", "disabled"]
        if let contentSizeCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }

        let fixtureData = try JSONEncoder().encode(Self.fixtureCards)
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] =
            temporaryDirectory.appendingPathComponent("collections-fixture.sqlite").path
        app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] =
            String(decoding: fixtureData, as: Unicode.UTF8.self)
        // Seed one user collection so the grid shows a user tile beside the system lists.
        app.launchEnvironment["GRIMORA_TEST_CATEGORIZED_LIST_NAME"] = "Mono-Red Aggro"
        app.launchEnvironment["GRIMORA_TEST_CATEGORY_NAMES"] = "Creatures\nBurn"
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] =
            temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
            "GrimoraCollectionsResponsive-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_ONBOARDING"] = "1"
        app.launch()
        return app
    }

    /// A small card fixture; only enough to give the seeded list some entries. The exact
    /// cards don't matter for layout — the header and tile grid are what we're capturing.
    static var fixtureCards: [CardRecord] {
        [
            CardRecord(
                id: "aggro-1",
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
                oracleText: "Haste.",
                isRealCard: true
            ),
            CardRecord(
                id: "aggro-2",
                name: "Brutal Striker",
                releasedAt: "2026-01-02",
                setCode: "tst",
                setName: "Test Set",
                setType: "expansion",
                collectorNumber: "2",
                collectorNumberNumber: 2,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 2,
                layout: "normal",
                typeLine: "Creature — Warrior",
                oracleText: "Deals combat damage to any opponent.",
                isRealCard: true
            ),
            CardRecord(
                id: "aggro-3",
                name: "Ember Bolt",
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
                typeLine: "Instant",
                oracleText: "Ember Bolt deals 3 damage to any target.",
                isRealCard: true
            )
        ]
    }
    #endif
}
