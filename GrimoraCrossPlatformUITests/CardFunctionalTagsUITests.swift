import Foundation
import GrimoraCore
import XCTest

final class CardFunctionalTagsUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraCardFunctionalTagsUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testCardDetailShowsProvenanceAndTagRunsOracleTagSearch() throws {
        let app = try launchSeededApp()

        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 15))
        let cardButton = firstElement(app, identifier: "open-card-functional-card")
        XCTAssertTrue(cardButton.waitForExistence(timeout: 15))
        activate(cardButton)

        let detail = firstElement(app, identifier: "card-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let tagButton = firstElement(app, identifier: "card-function-tag-draw-engine")
        for _ in 0..<8 where !tagButton.isHittable {
            detail.swipeUp()
        }
        XCTAssertTrue(tagButton.waitForExistence(timeout: 5))
        XCTAssertTrue(tagButton.isHittable)
        XCTAssertTrue(firstElement(app, identifier: "card-functions-provenance").exists)

        activate(tagButton)

        XCTAssertTrue(waitForNonExistence(of: detail, timeout: 10))
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue(of: searchField, toEqual: "otag:draw-engine", timeout: 10))
        let total = app.staticTexts["search-results-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForText(of: total, toEqual: "1 card", timeout: 10))
        XCTAssertTrue(firstElement(app, identifier: "open-card-functional-card").exists)
    }

    @MainActor
    func testCollectionCardTagNavigatesToVisibleGlobalSearchResults() throws {
        #if os(visionOS)
        throw XCTSkip("The visionOS simulator does not reliably activate collection card rows; the shared navigation contract is covered by model, iPhone, and iPad tests.")
        #else
        let app = try launchSeededApp()
        let collectionsTab = button(app, labeled: "Collections")
        XCTAssertTrue(collectionsTab.waitForExistence(timeout: 15))
        activate(collectionsTab)
        let tile = firstElement(app, identifier: "card-list-overview-tile-Functional Tags")
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        activate(tile)

        let cardButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "open-list-entry-")
        ).firstMatch
        XCTAssertTrue(cardButton.waitForExistence(timeout: 15))
        activate(cardButton)
        let detail = firstElement(app, identifier: "card-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let tagButton = firstElement(app, identifier: "card-function-tag-draw-engine")
        for _ in 0..<8 where !tagButton.isHittable {
            detail.swipeUp()
        }
        XCTAssertTrue(tagButton.isHittable)

        activate(tagButton)

        XCTAssertTrue(waitForNonExistence(of: detail, timeout: 10))
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue(of: searchField, toEqual: "otag:draw-engine", timeout: 10))
        XCTAssertTrue(waitForText(
            of: app.staticTexts["search-results-total"],
            toEqual: "1 card",
            timeout: 10
        ))
        #endif
    }

    @MainActor
    private func launchSeededApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-Grimora.defaultSearch.text",
            "",
            "-Grimora.search.alwaysIncludedText",
            "",
            "-Grimora.cloudSync.mode",
            "disabled"
        ]
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] =
            temporaryDirectory.appendingPathComponent("functional-tags-fixture.sqlite").path
        app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] =
            String(decoding: try JSONEncoder().encode(Self.fixtureCards), as: Unicode.UTF8.self)
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_SEMANTIC_CATALOG_JSON"] =
            String(decoding: try JSONEncoder().encode(Self.semanticCatalog), as: Unicode.UTF8.self)
        app.launchEnvironment["GRIMORA_TEST_CATEGORIZED_LIST_NAME"] = "Functional Tags"
        app.launchEnvironment["GRIMORA_TEST_CATEGORY_NAMES"] = "Cards"
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] =
            temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
            "GrimoraCardFunctionalTagsUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    private static var fixtureCards: [CardRecord] {
        var matching = fixtureCard(id: "functional-card", name: "Functional Adept", collectorNumber: "1")
        matching.oracleID = "oracle-functional"
        var other = fixtureCard(id: "other-card", name: "Ordinary Adept", collectorNumber: "2")
        other.oracleID = "oracle-other"
        return [matching, other]
    }

    private static var semanticCatalog: SemanticCatalogSnapshot {
        SemanticCatalogSnapshot(
            tags: [
                SemanticTagRecord(
                    id: "tag-draw-engine",
                    namespace: "oracle",
                    slug: "draw-engine",
                    label: "Draw Engine",
                    description: "Provides repeatable card draw.",
                    similarityEnabled: true,
                    source: "scryfall-oracle-tags@2026-06-14"
                )
            ],
            aliases: [],
            edges: [],
            cardTags: [
                SemanticCardTagRecord(
                    cardKey: SemanticCardKey(oracleID: "oracle-functional", printingID: "functional-card"),
                    tagID: "tag-draw-engine",
                    weightMillis: 1_500,
                    annotation: "repeatable",
                    source: "scryfall-oracle-tags@2026-06-14"
                )
            ],
            stats: []
        )
    }

    private static func fixtureCard(
        id: String,
        name: String,
        collectorNumber: String
    ) -> CardRecord {
        CardRecord(
            id: id,
            name: name,
            releasedAt: "2020-01-01",
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: collectorNumber,
            collectorNumberNumber: Int(collectorNumber) ?? 0,
            rarity: "common",
            rarityRank: 0,
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Creature — Wizard",
            oracleText: "Draw a card.",
            isRealCard: true
        )
    }
}
