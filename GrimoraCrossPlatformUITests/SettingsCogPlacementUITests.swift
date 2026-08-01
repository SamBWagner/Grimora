import Foundation
import GrimoraCore
import XCTest

/// Guards the Cards-tab floating controls against the iPad regression where the
/// bottom settings cog and the jump-to-top button both docked in the bottom-**trailing**
/// corner and overlapped. The cog now parks bottom-**leading** on every size class, so the
/// two must never share horizontal space.
///
/// The jump-to-top button only appears after scrolling past its reveal threshold
/// (`max(320, viewportHeight * 0.75)`), so the test seeds enough cards to scroll well past
/// it, flicks down, then asserts both controls are present and their frames don't intersect.
///
/// iOS-only: the regular-width trailing placement that caused the overlap is shared with
/// visionOS, but the visionOS *simulator* can't reliably flick the lazily-rendered result
/// grid (its cells aren't consistently hittable for XCUITest tap synthesis) — the same
/// tooling limit the rest of this suite gates around.
final class SettingsCogPlacementUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraSettingsCogPlacementUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    #if os(iOS)
    @MainActor
    func testSettingsCogAndJumpToTopButtonDoNotOverlap() throws {
        let app = try launchSeededApp()

        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 15), "results grid never populated")

        // The cog rests in a bottom corner from launch — it is not scroll-gated.
        let cog = firstElement(app, identifier: "search-options-menu")
        XCTAssertTrue(cog.waitForExistence(timeout: 5), "settings cog not found")

        // Flick down far enough to cross the jump-to-top reveal threshold.
        let scroll = firstElement(app, identifier: "search-results-scroll")
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "results scroll view not found")
        let jump = firstElement(app, identifier: "search-results-jump-to-top-button")
        for _ in 0..<12 where !jump.exists {
            scroll.swipeUp(velocity: .fast)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(jump.waitForExistence(timeout: 5), "jump-to-top button never appeared after scrolling")

        // Capture the corner layout for a visual record.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "cards-tab-floating-controls"
        shot.lifetime = .keepAlways
        add(shot)

        // The regression: both controls sharing the trailing corner. Assert they don't
        // intersect and that the cog sits entirely to the left of the jump-to-top button.
        let cogFrame = cog.frame
        let jumpFrame = jump.frame
        XCTAssertFalse(
            cogFrame.intersects(jumpFrame),
            "settings cog \(cogFrame) overlaps jump-to-top button \(jumpFrame)"
        )
        XCTAssertLessThanOrEqual(
            cogFrame.maxX, jumpFrame.minX,
            "settings cog should rest to the left of the jump-to-top button"
        )
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
            temporaryDirectory.appendingPathComponent("cog-placement-fixture.sqlite").path
        app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] =
            String(decoding: fixtureData, as: Unicode.UTF8.self)
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] =
            temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
            "GrimoraSettingsCogPlacementUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_ONBOARDING"] = "1"
        app.launch()
        return app
    }

    /// 80 text-only cards — enough rows to scroll well past the jump-to-top threshold on
    /// any iPad size. No image paths are needed; the layout under test is the floating
    /// chrome, not the tiles.
    static var fixtureCards: [CardRecord] {
        (1...80).map { index in
            CardRecord(
                id: "cog-fixture-\(index)",
                name: "Fixture Card \(index)",
                releasedAt: String(format: "2026-01-%02d", (index % 28) + 1),
                setCode: "tst",
                setName: "Test Set",
                setType: "expansion",
                collectorNumber: "\(index)",
                rarity: "common",
                colorSortKey: 0,
                layout: "normal",
                typeLine: "Creature — Elemental",
                oracleText: "Fixture card number \(index).",
                isRealCard: true
            )
        }
    }
}

private enum DefaultSearchPreferenceKeys {
    static let text = "Grimora.defaultSearch.text"
    static let alwaysIncludedText = "Grimora.search.alwaysIncludedText"
    static let sortMode = "Grimora.defaultSearch.sortMode"
    static let sortDirection = "Grimora.defaultSearch.sortDirection"
    static let cloudSyncMode = "Grimora.cloudSync.mode"
}
