import Foundation
import GrimoraCore
import XCTest

final class RelatedCardsUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrimoraRelatedCardsUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testSelectingRelatedCardOpensFreshDetailAtTheTop() throws {
        let app = try launchSeededApp()
        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 15))

        let sourceButton = firstElement(app, identifier: "open-card-source-card")
        XCTAssertTrue(sourceButton.waitForExistence(timeout: 15))
        activate(sourceButton)

        let detail = firstElement(app, identifier: "card-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let relatedButton = firstElement(app, identifier: "card-related-card-related-card")
        for _ in 0..<14 where !relatedButton.isHittable {
            detail.swipeUp()
        }
        XCTAssertTrue(relatedButton.waitForExistence(timeout: 10))
        XCTAssertTrue(relatedButton.isHittable)

        activate(relatedButton)

        let relatedOracleText = firstElement(app, identifier: "card-detail-oracle-text")
        XCTAssertTrue(relatedOracleText.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue(
            of: relatedOracleText,
            toEqual: "Related oracle text at the top.",
            timeout: 10
        ))
        let detailFrame = detail.frame
        let visibleArtworkTitle = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "Related Card"))
            .allElementsBoundByIndex
            .first { element in
                element.isHittable
                    && element.frame.minY > detailFrame.minY + 60
                    && element.frame.maxY < detailFrame.maxY
            }
        XCTAssertNotNil(visibleArtworkTitle)
        XCTAssertTrue(app.staticTexts["Related Card"].exists)
    }

    @MainActor
    func testRelatedCardLookupPerformanceOnSeededSimulator() throws {
        guard ProcessInfo.processInfo.environment["GRIMORA_RUN_RELATED_CARD_BENCHMARK"] == "1" else {
            throw XCTSkip("Set GRIMORA_RUN_RELATED_CARD_BENCHMARK=1 to run the seeded simulator benchmark.")
        }

        let databaseURL = temporaryDirectory.appendingPathComponent("related-cards-performance.sqlite")
        try Self.seedPerformanceDatabase(at: databaseURL)
        let app = launchPreparedApp(databaseURL: databaseURL)
        XCTAssertTrue(firstElement(app, identifier: "touch-root-tab-view").waitForExistence(timeout: 20))

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)],
            options: options
        ) {
            let sourceButton = firstElement(app, identifier: "open-card-benchmark-source")
            XCTAssertTrue(sourceButton.waitForExistence(timeout: 15))
            activate(sourceButton)
            let detail = firstElement(app, identifier: "card-detail")
            XCTAssertTrue(detail.waitForExistence(timeout: 10))
            XCTAssertTrue(
                firstElementWithPrefix(app, identifierPrefix: "card-related-card-")
                    .waitForExistence(timeout: 10)
            )
        }
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
            temporaryDirectory.appendingPathComponent("related-cards-fixture.sqlite").path
        app.launchEnvironment["GRIMORA_TEST_RESET_DATABASE"] = "1"
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_CARDS_JSON"] =
            String(decoding: try JSONEncoder().encode(Self.fixtureCards), as: Unicode.UTF8.self)
        app.launchEnvironment["GRIMORA_TEST_FIXTURE_SEMANTIC_CATALOG_JSON"] =
            String(decoding: try JSONEncoder().encode(Self.semanticCatalog), as: Unicode.UTF8.self)
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] =
            temporaryDirectory.appendingPathComponent("Images", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
            "GrimoraRelatedCardsUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func launchPreparedApp(databaseURL: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-Grimora.defaultSearch.text",
            "",
            "-Grimora.search.alwaysIncludedText",
            "",
            "-Grimora.cloudSync.mode",
            "disabled"
        ]
        app.launchEnvironment["GRIMORA_TEST_DATABASE_PATH"] = databaseURL.path
        app.launchEnvironment["GRIMORA_TEST_IMAGE_DIR"] =
            temporaryDirectory.appendingPathComponent("PerformanceImages", isDirectory: true).path
        app.launchEnvironment["GRIMORA_TEST_USER_DEFAULTS_SUITE"] =
            "GrimoraRelatedCardsPerformanceUITests-\(UUID().uuidString)"
        app.launchEnvironment["GRIMORA_TEST_SEARCH_DEBOUNCE_NANOSECONDS"] = "0"
        app.launchEnvironment["GRIMORA_DISABLE_NETWORK"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_CLOUD_SYNC"] = "1"
        app.launchEnvironment["GRIMORA_DISABLE_AUTO_UPDATE"] = "1"
        app.launch()
        return app
    }

    private static var fixtureCards: [CardRecord] {
        var source = fixtureCard(
            id: "source-card",
            name: "Source Card",
            collectorNumber: "1",
            oracleText: Array(repeating: "Source ability text.", count: 60).joined(separator: "\n")
        )
        source.oracleID = "oracle-source"
        var related = fixtureCard(
            id: "related-card",
            name: "Related Card",
            collectorNumber: "2",
            oracleText: "Related oracle text at the top."
        )
        related.oracleID = "oracle-related"
        return [source, related]
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
                    cardKey: SemanticCardKey(oracleID: "oracle-source", printingID: "source-card"),
                    tagID: "tag-draw-engine",
                    weightMillis: 1_500,
                    annotation: "repeatable",
                    source: "scryfall-oracle-tags@2026-06-14"
                ),
                SemanticCardTagRecord(
                    cardKey: SemanticCardKey(oracleID: "oracle-related", printingID: "related-card"),
                    tagID: "tag-draw-engine",
                    weightMillis: 1_500,
                    annotation: "repeatable",
                    source: "scryfall-oracle-tags@2026-06-14"
                )
            ],
            stats: [
                SemanticTagStatsRecord(
                    tagID: "tag-draw-engine",
                    directCardCount: 2,
                    effectiveCardCount: 2,
                    inverseFrequencyMillis: 1_000
                )
            ]
        )
    }

    private static func seedPerformanceDatabase(at url: URL) throws {
        let cardCount = 5_000
        let relatedCardCount = 500
        let tagCount = 1_000
        let membershipsPerCard = 8
        var database: CardDatabase? = try CardDatabase(storage: .file(url))
        let cards = (0..<cardCount).map { index in
            CardRecord(
                id: index == 0 ? "benchmark-source" : "benchmark-card-\(index)",
                oracleID: "benchmark-oracle-\(index)",
                name: index == 0 ? "A Benchmark Source" : String(format: "Benchmark Card %05d", index),
                releasedAt: "2020-01-01",
                setCode: "tst",
                setName: "Test Set",
                setType: "expansion",
                collectorNumber: String(index + 1),
                collectorNumberNumber: index + 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 6,
                layout: "normal",
                typeLine: "Artifact",
                oracleText: "Benchmark card.",
                isRealCard: true
            )
        }
        try database?.replaceAllCards(cards)

        let tags = (0..<tagCount).map { index in
            SemanticTagRecord(
                id: "benchmark-tag-\(index)",
                namespace: "oracle",
                slug: "benchmark-tag-\(index)",
                label: "Benchmark Tag \(index)",
                description: nil,
                similarityEnabled: true,
                source: "synthetic-related-card-benchmark"
            )
        }
        var memberships: [SemanticCardTagRecord] = []
        memberships.reserveCapacity(cardCount * membershipsPerCard)
        for index in 0..<cardCount {
            let tagIDs: [Int]
            if index < relatedCardCount {
                tagIDs = [0, 100, 101, 102, 103, 104, 105, 106]
            } else {
                let start = 200 + ((index * membershipsPerCard) % (tagCount - 208))
                tagIDs = (0..<membershipsPerCard).map { start + $0 }
            }
            let printingID = index == 0 ? "benchmark-source" : "benchmark-card-\(index)"
            let cardKey = SemanticCardKey(
                oracleID: "benchmark-oracle-\(index)",
                printingID: printingID
            )
            memberships.append(contentsOf: tagIDs.map { tagID in
                SemanticCardTagRecord(
                    cardKey: cardKey,
                    tagID: "benchmark-tag-\(tagID)",
                    weightMillis: 1_000 + (tagID % 7),
                    annotation: nil,
                    source: "synthetic-related-card-benchmark"
                )
            })
        }
        let stats = (0..<tagCount).map { index in
            SemanticTagStatsRecord(
                tagID: "benchmark-tag-\(index)",
                directCardCount: 1,
                effectiveCardCount: cardCount,
                inverseFrequencyMillis: 1_000 + (index % 500)
            )
        }
        try database?.replaceSemanticCatalog(
            with: SemanticCatalogSnapshot(
                tags: tags,
                aliases: [],
                edges: [],
                cardTags: memberships,
                stats: stats
            )
        )
        try database?.saveMetadataValue(
            "2026-09-28T00:00:00Z",
            forKey: MetadataKey.defaultCardsUpdatedAt.rawValue
        )
        try database?.saveMetadataValue(
            CardDatabase.currentSearchSchemaVersion,
            forKey: MetadataKey.searchSchemaVersion.rawValue
        )
        try database?.saveMetadataValue(
            "true",
            forKey: MetadataKey.requiredImagesCached.rawValue
        )
        database = nil
    }

    private static func fixtureCard(
        id: String,
        name: String,
        collectorNumber: String,
        oracleText: String
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
            oracleText: oracleText,
            isRealCard: true
        )
    }
}
