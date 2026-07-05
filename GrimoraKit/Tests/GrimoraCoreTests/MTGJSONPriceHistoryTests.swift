@testable import GrimoraCore
import XCTest

final class MTGJSONPriceHistoryTests: XCTestCase {
    func testValueTablesAndIndexesExistAfterMigration() throws {
        let database = try CardDatabase(storage: .inMemory)

        XCTAssertTrue(try sqliteObjectExists(in: database, type: "table", name: "card_value_mappings"))
        XCTAssertTrue(try sqliteObjectExists(in: database, type: "table", name: "card_price_points"))
        XCTAssertTrue(try sqliteObjectExists(in: database, type: "table", name: "card_value_summaries"))
        XCTAssertTrue(try sqliteObjectExists(in: database, type: "table", name: "value_history_background_jobs"))
        XCTAssertTrue(try sqliteObjectExists(in: database, type: "table", name: "staging_card_value_mappings"))
        XCTAssertTrue(try sqliteObjectExists(in: database, type: "table", name: "staging_card_price_points"))
        XCTAssertTrue(try sqliteObjectExists(in: database, type: "index", name: "idx_card_price_points_card_finish_date"))
        XCTAssertTrue(try sqliteObjectExists(in: database, type: "index", name: "idx_card_value_summaries_current_price"))
        XCTAssertTrue(try sqliteObjectExists(in: database, type: "index", name: "idx_value_history_background_jobs_status"))
        XCTAssertTrue(try sqliteObjectExists(in: database, type: "index", name: "idx_staging_card_price_points_job_card_finish_date"))
    }

    func testImporterMapsScryfallIDsImportsTCGplayerRetailHistoryAndBuildsGuide() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "scry-one", name: "Value Spell"),
            testCard(id: "scry-two", name: "Etched Spell")
        ])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let printingsURL = directory.appendingPathComponent("AllPrintings.json")
        let pricesURL = directory.appendingPathComponent("AllPrices.json")
        try allPrintingsJSON().write(to: printingsURL, options: .atomic)
        try allPricesJSON().write(to: pricesURL, options: .atomic)

        let importer = MTGJSONPriceHistoryImporter(database: database)
        let summary = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsJSONURL: printingsURL,
            allPricesJSONURL: pricesURL
        )

        XCTAssertEqual(summary.mappedCards, 2)
        XCTAssertEqual(summary.importedPricePoints, 7)
        XCTAssertEqual(try countRows(in: database, table: "card_value_mappings"), 2)
        XCTAssertEqual(try countRows(in: database, table: "card_price_points"), 7)
        XCTAssertEqual(
            try database.metadataValue(forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue),
            "2026-05-13"
        )
        XCTAssertEqual(
            try database.metadataValue(forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue),
            "5.2.1"
        )
        let guide = try database.valueGuide(forCardID: "scry-one")
        XCTAssertEqual(guide.sourceName, "TCGplayer via MTGJSON")
        XCTAssertEqual(guide.entries.map(\.finish), [.normal, .foil])

        let normal = try XCTUnwrap(guide.entries.first { $0.finish == .normal })
        XCTAssertEqual(normal.currentDate, "2026-04-01")
        XCTAssertEqual(normal.currentPrice, 2.50)
        XCTAssertEqual(normal.oneDay?.previousPrice, 2.00)
        XCTAssertEqual(try XCTUnwrap(normal.oneDay).delta, 0.50, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(normal.oneDay).percent ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(normal.sevenDay?.previousPrice, 1.80)
        XCTAssertEqual(normal.thirtyDay?.previousPrice, 1.25)
        XCTAssertNil(normal.ninetyDay)
        XCTAssertEqual(normal.highestPrice, 4.00)
        XCTAssertEqual(
            normal.history,
            [
                CardValueHistoryPoint(date: "2026-03-02", price: 1.25),
                CardValueHistoryPoint(date: "2026-03-10", price: 4.00),
                CardValueHistoryPoint(date: "2026-03-25", price: 1.80),
                CardValueHistoryPoint(date: "2026-03-31", price: 2.00),
                CardValueHistoryPoint(date: "2026-04-01", price: 2.50)
            ]
        )

        let foil = try XCTUnwrap(guide.entries.first { $0.finish == .foil })
        XCTAssertEqual(foil.currentPrice, 5.00)
        XCTAssertNil(foil.oneDay)
        XCTAssertEqual(foil.highestPrice, 5.00)
        XCTAssertEqual(foil.history, [CardValueHistoryPoint(date: "2026-04-01", price: 5.00)])

        let etchedGuide = try database.valueGuide(forCardID: "scry-two")
        XCTAssertEqual(etchedGuide.entries.map(\.finish), [.etched])
        XCTAssertEqual(etchedGuide.entries.first?.currentPrice, 7.00)
    }

    func testCurrentValuePricesReadsFinishPricesWithoutHistory() async throws {
        // The lean read behind foil-aware Scry value-tiering: a foil-only card must
        // surface its foil price (the fix for a foil-only legend scanning as "$0").
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "scry-one", name: "Value Spell"),
            testCard(id: "scry-two", name: "Etched Spell")
        ])
        let fixtures = try writePriceFixtures(printings: allPrintingsJSON(), prices: allPricesJSON())
        let importer = MTGJSONPriceHistoryImporter(database: database)
        _ = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsJSONURL: fixtures.printingsURL,
            allPricesJSONURL: fixtures.pricesURL
        )

        XCTAssertEqual(try database.currentValuePricesUSD(forCardID: "scry-one"), [.normal: 2.50, .foil: 5.00])
        XCTAssertEqual(try database.currentValuePricesUSD(forCardID: "scry-two"), [.etched: 7.00])
        // No value summaries → empty, so the caller falls back to the Scryfall priceUSD.
        XCTAssertEqual(try database.currentValuePricesUSD(forCardID: "no-such-card"), [:])
    }

    func testImporterMapsAllIdentifiersShapeUsedByPricingDownloads() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])
        let fixtures = try writePriceFixtures(
            printings: allIdentifiersJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: replacementPricesJSON(uuid: "uuid-one", date: "2026-04-01", price: 2.50)
        )

        let importer = MTGJSONPriceHistoryImporter(database: database)
        let summary = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsJSONURL: fixtures.printingsURL,
            allPricesJSONURL: fixtures.pricesURL
        )

        XCTAssertEqual(summary, MTGJSONPriceImportSummary(mappedCards: 1, importedPricePoints: 1))
        XCTAssertEqual(try database.valueGuide(forCardID: "scry-one").entries.first?.currentPrice, 2.50)
    }

    func testImporterReturnsZeroCountsForEmptyLocalDatabase() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let fixtures = try writePriceFixtures(printings: allPrintingsJSON(), prices: allPricesJSON())

        let importer = MTGJSONPriceHistoryImporter(database: database)
        let summary = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsJSONURL: fixtures.printingsURL,
            allPricesJSONURL: fixtures.pricesURL
        )

        XCTAssertEqual(summary, MTGJSONPriceImportSummary(mappedCards: 0, importedPricePoints: 0))
        XCTAssertEqual(try database.valueSummaryCount(), 0)
        XCTAssertNil(try database.metadataValue(forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue))
    }

    func testValueGuideFallsBackToScryfallSnapshotPriceWhenHistoryIsMissing() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "scry-one", name: "Value Spell", priceUSD: 1.25)
        ])
        try database.saveMetadataValue("2026-05-12T09:10:16.801+00:00", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)

        let guide = try database.valueGuide(forCardID: "scry-one")

        XCTAssertEqual(guide.sourceName, "Scryfall local price snapshot")
        XCTAssertEqual(guide.entries.map(\.finish), [.normal])
        XCTAssertEqual(guide.entries.first?.currentPrice, 1.25)
        XCTAssertEqual(guide.entries.first?.currentDate, "2026-05-12")
        XCTAssertNil(guide.entries.first?.oneDay)
        XCTAssertEqual(guide.entries.first?.highestPrice, 1.25)
        XCTAssertEqual(guide.entries.first?.history, [])
    }

    func testValueGuidePrefersMTGJSONHistoryOverScryfallSnapshotPrice() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([
            testCard(id: "scry-one", name: "Value Spell", priceUSD: 1.25)
        ])
        let fixtures = try writePriceFixtures(
            printings: singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: replacementPricesJSON(uuid: "uuid-one", date: "2026-04-01", price: 2.50)
        )

        let importer = MTGJSONPriceHistoryImporter(database: database)
        _ = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsJSONURL: fixtures.printingsURL,
            allPricesJSONURL: fixtures.pricesURL
        )

        let guide = try database.valueGuide(forCardID: "scry-one")
        XCTAssertEqual(guide.sourceName, "TCGplayer via MTGJSON")
        XCTAssertEqual(guide.entries.first?.currentPrice, 2.50)
    }

    func testValueGuideReturnsFinishesInDisplayOrder() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])

        let fixtures = try writePriceFixtures(
            printings: singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: allFinishPricesJSON(uuid: "uuid-one")
        )
        let importer = MTGJSONPriceHistoryImporter(database: database)
        _ = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsJSONURL: fixtures.printingsURL,
            allPricesJSONURL: fixtures.pricesURL
        )

        let guide = try database.valueGuide(forCardID: "scry-one")
        XCTAssertEqual(guide.entries.map(\.finish), [.normal, .foil, .etched])
        XCTAssertEqual(guide.entries.map(\.currentPrice), [1.25, 2.50, 3.75])
        XCTAssertEqual(guide.entries.map(\.highestPrice), [1.25, 2.50, 3.75])
    }

    func testCurrentPriceImportUsesAllPricesTodayAndPreservesExistingHistory() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])

        let importer = MTGJSONPriceHistoryImporter(database: database)
        let historyFixtures = try writePriceFixtures(
            printings: singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: replacementPricesJSON(uuid: "uuid-one", date: "2026-04-01", price: 2.50)
        )
        _ = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsJSONURL: historyFixtures.printingsURL,
            allPricesJSONURL: historyFixtures.pricesURL
        )

        let todayFixtures = try writePriceFixtures(
            printings: singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: allFinishPricesTodayJSON(uuid: "uuid-one")
        )
        let summary = try await importer.importCurrentPrices(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-14", version: "5.2.2"),
            allPrintingsJSONURL: todayFixtures.printingsURL,
            allPricesTodayJSONURL: todayFixtures.pricesURL
        )

        XCTAssertEqual(summary, MTGJSONPriceImportSummary(mappedCards: 1, importedPricePoints: 3))
        let guide = try database.valueGuide(forCardID: "scry-one")
        XCTAssertEqual(guide.entries.map(\.finish), [.normal, .foil, .etched])
        XCTAssertEqual(guide.entries.map(\.currentPrice), [3.00, 6.00, 8.00])
        XCTAssertEqual(
            guide.entries.first?.history,
            [
                CardValueHistoryPoint(date: "2026-04-01", price: 2.50),
                CardValueHistoryPoint(date: "2026-05-14", price: 3.00)
            ]
        )
        XCTAssertEqual(
            try database.metadataValue(forKey: MetadataKey.mtgjsonCurrentPricesDate.rawValue),
            "2026-05-14"
        )
        XCTAssertEqual(
            try database.metadataValue(forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue),
            "2026-05-13"
        )
    }

    func testCurrentPriceImportReportsProgressWhileScanningLargeIdentifierFile() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])

        let importer = MTGJSONPriceHistoryImporter(database: database)
        let identifiers = largeAllIdentifiersJSON(cardID: "scry-one", uuid: "uuid-one")
        let fixtures = try writePriceFixtures(
            printings: identifiers,
            prices: allFinishPricesTodayJSON(uuid: "uuid-one")
        )
        let identifierSize = Int64(identifiers.count)
        let recorder = PriceMappingProgressRecorder()

        let summary = try await importer.importCurrentPrices(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-14", version: "5.2.2"),
            allPrintingsJSONURL: fixtures.printingsURL,
            allPricesTodayJSONURL: fixtures.pricesURL
        ) { progress in
            if case .buildingPriceIDMapProgress(let scannedBytes, let totalBytes, let mappedCards) = progress {
                await recorder.record(scannedBytes: scannedBytes, totalBytes: totalBytes, mappedCards: mappedCards)
            }
        }
        let mappingProgress = await recorder.events()

        XCTAssertEqual(summary, MTGJSONPriceImportSummary(mappedCards: 1, importedPricePoints: 3))
        XCTAssertTrue(
            mappingProgress.contains {
                $0.scannedBytes > 0 && $0.scannedBytes < identifierSize && $0.mappedCards == 0
            }
        )
        XCTAssertTrue(
            mappingProgress.contains {
                $0.scannedBytes == identifierSize && $0.totalBytes == identifierSize && $0.mappedCards == 1
            }
        )
    }

    func testCurrentPriceImportReportsProgressWhileScanningLargePriceFile() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])

        let prices = largeAllPricesJSON(uuid: "uuid-one")
        let fixtures = try writePriceFixtures(
            printings: allIdentifiersJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: prices
        )
        let pricesSize = Int64(prices.count)
        let recorder = PriceMappingProgressRecorder()

        let summary = try await MTGJSONPriceHistoryImporter(database: database).importCurrentPrices(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-14", version: "5.2.2"),
            allPrintingsJSONURL: fixtures.printingsURL,
            allPricesTodayJSONURL: fixtures.pricesURL
        ) { progress in
            if case .importingPriceHistoryProgress(
                let scannedBytes,
                let totalBytes,
                let importedPricePoints
            ) = progress {
                await recorder.record(
                    scannedBytes: scannedBytes,
                    totalBytes: totalBytes,
                    mappedCards: importedPricePoints
                )
            }
        }
        let priceProgress = await recorder.events()

        XCTAssertEqual(summary, MTGJSONPriceImportSummary(mappedCards: 1, importedPricePoints: 1))
        XCTAssertTrue(
            priceProgress.contains {
                $0.scannedBytes > 0 && $0.scannedBytes < pricesSize && $0.mappedCards == 0
            }
        )
        XCTAssertTrue(
            priceProgress.contains {
                $0.scannedBytes == pricesSize && $0.totalBytes == pricesSize && $0.mappedCards == 1
            }
        )
    }

    func testCurrentPriceImportFallsBackToScryfallSnapshotWhenTodayPriceIsMissing() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell", priceUSD: 1.25)])
        try database.saveMetadataValue("2026-05-14T09:10:16.801+00:00", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        let fixtures = try writePriceFixtures(
            printings: singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: replacementPricesJSON(uuid: "uuid-other", date: "2026-05-14", price: 9.99)
        )

        let importer = MTGJSONPriceHistoryImporter(database: database)
        let summary = try await importer.importCurrentPrices(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-14", version: "5.2.2"),
            allPrintingsJSONURL: fixtures.printingsURL,
            allPricesTodayJSONURL: fixtures.pricesURL
        )

        XCTAssertEqual(summary, MTGJSONPriceImportSummary(mappedCards: 1, importedPricePoints: 0))
        let guide = try database.valueGuide(forCardID: "scry-one")
        XCTAssertEqual(guide.sourceName, "Scryfall local price snapshot")
        XCTAssertEqual(guide.entries.first?.currentPrice, 1.25)
    }

    func testBackgroundCommitPreservesNewerCurrentPricesAndCleansStaging() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])
        let importer = MTGJSONPriceHistoryImporter(database: database)

        let currentFixtures = try writePriceFixtures(
            printings: singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: replacementPricesJSON(uuid: "uuid-one", date: "2026-05-15", price: 3.00)
        )
        _ = try await importer.importCurrentPrices(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-15", version: "5.2.3"),
            allPrintingsJSONURL: currentFixtures.printingsURL,
            allPricesTodayJSONURL: currentFixtures.pricesURL
        )

        let identity = try database.valueHistoryCardDatabaseIdentity()
        let job = try database.prepareValueHistoryBackgroundJob(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-14", version: "5.2.2"),
            cardDatabaseIdentity: identity
        )
        let historyFixtures = try writePriceFixtures(
            printings: singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: twoPointHistoryJSON(uuid: "uuid-one")
        )
        let staged = try await importer.importHistoryToStaging(
            meta: job.meta,
            mappingsByMTGJSONUUID: try database.valueMappingsByMTGJSONUUID(),
            allPricesJSONURL: historyFixtures.pricesURL,
            jobID: job.id
        )

        XCTAssertEqual(staged.importedPricePoints, 2)
        XCTAssertEqual(try database.valueGuide(forCardID: "scry-one").entries.first?.currentPrice, 3.00)

        let committed = try database.commitStagedValueHistory(jobID: job.id, meta: job.meta)
        XCTAssertEqual(committed.importedPricePoints, 3)
        let guide = try database.valueGuide(forCardID: "scry-one")
        XCTAssertEqual(guide.entries.first?.currentPrice, 3.00)
        XCTAssertEqual(
            guide.entries.first?.history,
            [
                CardValueHistoryPoint(date: "2026-03-01", price: 2.00),
                CardValueHistoryPoint(date: "2026-05-14", price: 4.00),
                CardValueHistoryPoint(date: "2026-05-15", price: 3.00)
            ]
        )
        XCTAssertEqual(
            try database.metadataValue(forKey: MetadataKey.mtgjsonCurrentPricesDate.rawValue),
            "2026-05-15"
        )
        XCTAssertEqual(try countRows(in: database, table: "staging_card_value_mappings"), 0)
        XCTAssertEqual(try countRows(in: database, table: "staging_card_price_points"), 0)
    }

    func testBackgroundHistoryImportReportsIncrementalProgressForLargePriceFile() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])
        let importer = MTGJSONPriceHistoryImporter(database: database)

        let currentFixtures = try writePriceFixtures(
            printings: allIdentifiersJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: replacementPricesJSON(uuid: "uuid-one", date: "2026-05-14", price: 3.00)
        )
        _ = try await importer.importCurrentPrices(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-14", version: "5.2.2"),
            allPrintingsJSONURL: currentFixtures.printingsURL,
            allPricesTodayJSONURL: currentFixtures.pricesURL
        )

        let job = try database.prepareValueHistoryBackgroundJob(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-14", version: "5.2.2"),
            cardDatabaseIdentity: try database.valueHistoryCardDatabaseIdentity()
        )
        let prices = largeAllPricesJSON(uuid: "uuid-one")
        let fixtures = try writePriceFixtures(
            printings: Data(),
            prices: prices
        )
        let pricesSize = Int64(prices.count)
        let recorder = PriceMappingProgressRecorder()

        let summary = try await importer.importHistoryToStaging(
            meta: job.meta,
            mappingsByMTGJSONUUID: try database.valueMappingsByMTGJSONUUID(),
            allPricesJSONURL: fixtures.pricesURL,
            jobID: job.id
        ) { progress in
            if case .importingPriceHistoryProgress(
                let scannedBytes,
                let totalBytes,
                let importedPricePoints
            ) = progress {
                await recorder.record(
                    scannedBytes: scannedBytes,
                    totalBytes: totalBytes,
                    mappedCards: importedPricePoints
                )
            }
        }
        let priceProgress = await recorder.events()

        XCTAssertEqual(summary, MTGJSONPriceImportSummary(mappedCards: 1, importedPricePoints: 1))
        XCTAssertTrue(
            priceProgress.contains {
                $0.scannedBytes > 0 && $0.scannedBytes < pricesSize && $0.mappedCards == 0
            }
        )
        XCTAssertTrue(
            priceProgress.contains {
                $0.scannedBytes == pricesSize && $0.totalBytes == pricesSize && $0.mappedCards == 1
            }
        )
    }

    func testBackgroundJobCardDatabaseIdentityChangesWhenCardsChange() throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])
        let firstIdentity = try database.valueHistoryCardDatabaseIdentity()
        let job = try database.prepareValueHistoryBackgroundJob(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-14", version: "5.2.2"),
            cardDatabaseIdentity: firstIdentity
        )

        try database.replaceAllCards([testCard(id: "scry-two", name: "Other Spell")], preservesCardValueHistory: true)

        XCTAssertNotEqual(firstIdentity, try database.valueHistoryCardDatabaseIdentity())
        XCTAssertEqual(try database.incompleteValueHistoryBackgroundJob()?.id, job.id)
    }

    func testReimportReplacesOldPriceHistoryAndSummaries() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])

        let importer = MTGJSONPriceHistoryImporter(database: database)
        let first = try writePriceFixtures(
            printings: singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: replacementPricesJSON(uuid: "uuid-one", date: "2026-04-01", price: 2.50)
        )
        _ = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsJSONURL: first.printingsURL,
            allPricesJSONURL: first.pricesURL
        )
        XCTAssertEqual(try database.valueGuide(forCardID: "scry-one").entries.first?.currentPrice, 2.50)

        let second = try writePriceFixtures(
            printings: singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: replacementPricesJSON(uuid: "uuid-one", date: "2026-04-02", price: 4.00)
        )
        let summary = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-14", version: "5.2.2"),
            allPrintingsJSONURL: second.printingsURL,
            allPricesJSONURL: second.pricesURL
        )

        let guide = try database.valueGuide(forCardID: "scry-one")
        XCTAssertEqual(summary.importedPricePoints, 1)
        XCTAssertEqual(try countRows(in: database, table: "card_price_points"), 1)
        XCTAssertEqual(guide.entries.first?.currentDate, "2026-04-02")
        XCTAssertEqual(guide.entries.first?.currentPrice, 4.00)
        XCTAssertEqual(
            try database.metadataValue(forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue),
            "5.2.2"
        )
    }

    func testReplacingCardsClearsStoredValueHistory() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let printingsURL = directory.appendingPathComponent("AllPrintings.json")
        let pricesURL = directory.appendingPathComponent("AllPrices.json")
        try allPrintingsJSON().write(to: printingsURL, options: .atomic)
        try allPricesJSON().write(to: pricesURL, options: .atomic)

        let importer = MTGJSONPriceHistoryImporter(database: database)
        _ = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsJSONURL: printingsURL,
            allPricesJSONURL: pricesURL
        )
        XCTAssertGreaterThan(try database.valueSummaryCount(), 0)

        try database.replaceAllCards([testCard(id: "new-card", name: "New Spell")])
        XCTAssertEqual(try database.valueSummaryCount(), 0)
        XCTAssertNil(try database.metadataValue(forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue))
    }

    func testDeletingCardDataClearsValueHistoryAndMetadata() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])
        let fixtures = try writePriceFixtures(
            printings: singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one"),
            prices: replacementPricesJSON(uuid: "uuid-one", date: "2026-04-01", price: 2.50)
        )

        let importer = MTGJSONPriceHistoryImporter(database: database)
        _ = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsJSONURL: fixtures.printingsURL,
            allPricesJSONURL: fixtures.pricesURL
        )
        XCTAssertGreaterThan(try database.valueSummaryCount(), 0)

        try database.deleteAllCardsPreservingLists()

        XCTAssertEqual(try database.valueSummaryCount(), 0)
        XCTAssertEqual(try countRows(in: database, table: "card_price_points"), 0)
        XCTAssertEqual(try countRows(in: database, table: "card_value_mappings"), 0)
        XCTAssertNil(try database.metadataValue(forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue))
        XCTAssertNil(try database.metadataValue(forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue))
    }

    func testGzipImportPathCleansUpDecompressedFixturesAndScansPrices() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let printingsGzipURL = directory.appendingPathComponent("AllPrintings.json.gz")
        let pricesGzipURL = directory.appendingPathComponent("AllPrices.json.gz")
        try gzipData(singleCardPrintingsJSON(cardID: "scry-one", uuid: "uuid-one")).write(to: printingsGzipURL)
        try gzipData(replacementPricesJSON(uuid: "uuid-one", date: "2026-04-01", price: 2.50)).write(to: pricesGzipURL)

        let importer = MTGJSONPriceHistoryImporter(database: database)
        let summary = try await importer.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsGzipURL: printingsGzipURL,
            allPricesGzipURL: pricesGzipURL,
            temporaryDirectory: directory
        )

        XCTAssertEqual(summary, MTGJSONPriceImportSummary(mappedCards: 1, importedPricePoints: 1))
        XCTAssertEqual(try database.valueGuide(forCardID: "scry-one").entries.first?.currentPrice, 2.50)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("mtgjson-all-printings-2026-05-13.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("mtgjson-all-prices-2026-05-13.json").path
            )
        )
    }

    func testCompactGzipImportStreamsMappingsAndSkipsUnknownCards() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([testCard(id: "scry-one", name: "Value Spell")])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let printingsGzipURL = directory.appendingPathComponent("AllIdentifiers.json.gz")
        let pricesGzipURL = directory.appendingPathComponent("AllPrices.json.gz")
        let printings = Data(
            """
            {"data":{
              "uuid-one":{"identifiers":{"scryfallId":"scry-one"}},
              "uuid-missing":{"identifiers":{"scryfallId":"not-local"}}
            }}
            """.utf8
        )
        let prices = Data(
            """
            {"data":{
              "uuid-one":{"paper":{"tcgplayer":{"retail":{"normal":{"2026-06-14":2.5}}}}},
              "uuid-missing":{"paper":{"tcgplayer":{"retail":{"normal":{"2026-06-14":99.0}}}}}
            }}
            """.utf8
        )
        try gzipData(printings).write(to: printingsGzipURL)
        try gzipData(prices).write(to: pricesGzipURL)

        let summary = try await MTGJSONPriceHistoryImporter(database: database).importCompactHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-06-14", version: "5.3.0"),
            allPrintingsGzipURL: printingsGzipURL,
            allPricesGzipURL: pricesGzipURL,
            temporaryDirectory: directory
        )

        XCTAssertEqual(summary.mappedCards, 1)
        XCTAssertEqual(try countRows(in: database, table: "card_value_mappings"), 1)
        XCTAssertEqual(try database.valueGuide(forCardID: "scry-one").entries.first?.currentPrice, 2.50)
    }

    func testLiveMTGJSONKnownCardsHaveUsableCurrentAndHistoryPricesWhenEnabled() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GRIMORA_RUN_LIVE_MTGJSON_PRICE_TESTS"] == "1",
            "Set GRIMORA_RUN_LIVE_MTGJSON_PRICE_TESTS=1 to run the live MTGJSON verification."
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let client = MTGJSONPriceHistoryClient(network: URLSessionNetworkClient())
        let meta = try await client.fetchMeta()
        let identifiersGzipURL = directory.appendingPathComponent("AllIdentifiers.json.gz")
        let pricesGzipURL = directory.appendingPathComponent("AllPrices.json.gz")
        let identifiersJSONURL = directory.appendingPathComponent("AllIdentifiers.json")
        let pricesJSONURL = directory.appendingPathComponent("AllPrices.json")

        try await client.downloadAllPrintings(to: identifiersGzipURL)
        try await client.downloadAllPrices(to: pricesGzipURL)
        try MTGJSONGzip.decompressFile(at: identifiersGzipURL, to: identifiersJSONURL)
        try MTGJSONGzip.decompressFile(at: pricesGzipURL, to: pricesJSONURL)

        let targets = [
            LiveKnownMTGJSONCard(name: "Volcanic Island", preferredSetCode: "3ED"),
            LiveKnownMTGJSONCard(name: "Kiki-Jiki, Mirror Breaker", preferredSetCode: "CHK"),
            LiveKnownMTGJSONCard(name: "Steal the Show", preferredSetCode: "SOS")
        ]
        let identities = try liveKnownCardIdentities(in: identifiersJSONURL, targets: targets)
        XCTAssertEqual(Set(identities.keys), Set(targets.map(\.id)))

        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards(
            targets.map { target in
                let identity = identities[target.id]!
                return testCard(id: identity.scryfallID, name: target.name)
            }
        )

        let importer = MTGJSONPriceHistoryImporter(database: database)
        let summary = try await importer.importHistory(
            meta: meta,
            allPrintingsJSONURL: identifiersJSONURL,
            allPricesJSONURL: pricesJSONURL
        )

        XCTAssertEqual(summary.mappedCards, targets.count)
        XCTAssertGreaterThan(summary.importedPricePoints, targets.count)

        for target in targets {
            let identity = try XCTUnwrap(identities[target.id])
            let guide = try database.valueGuide(forCardID: identity.scryfallID)
            let entry = try XCTUnwrap(guide.entries.first)
            XCTAssertGreaterThan(entry.currentPrice, 0, target.name)
            XCTAssertGreaterThan(entry.highestPrice, 0, target.name)
            XCTAssertGreaterThan(entry.history.count, 0, target.name)
            XCTAssertFalse(entry.currentDate.isEmpty, target.name)
        }
    }

    private func writePriceFixtures(printings: Data, prices: Data) throws -> (printingsURL: URL, pricesURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let printingsURL = directory.appendingPathComponent("AllPrintings.json")
        let pricesURL = directory.appendingPathComponent("AllPrices.json")
        try printings.write(to: printingsURL, options: .atomic)
        try prices.write(to: pricesURL, options: .atomic)
        return (printingsURL, pricesURL)
    }

    private func sqliteObjectExists(in database: CardDatabase, type: String, name: String) throws -> Bool {
        let statement = try database.database.prepare(
            """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = ? AND name = ?
            """)
        try statement.bind(type, at: 1)
        try statement.bind(name, at: 2)
        _ = try statement.step()
        return (statement.int(at: 0) ?? 0) > 0
    }

    private func countRows(in database: CardDatabase, table: String) throws -> Int {
        let statement = try database.database.prepare("SELECT COUNT(*) FROM \(table)")
        _ = try statement.step()
        return statement.int(at: 0) ?? 0
    }

    private func allPrintingsJSON() -> Data {
        Data("""
        {
          "meta": {"date": "2026-05-13", "version": "5.2.1"},
          "data": {
            "TST": {
              "cards": [
                {"uuid": "uuid-one", "identifiers": {"scryfallId": "scry-one"}},
                {"uuid": "uuid-two", "identifiers": {"scryfallId": "scry-two"}},
                {"uuid": "uuid-ignored", "identifiers": {"scryfallId": "not-local"}}
              ]
            }
          }
        }
        """.utf8)
    }

    private func allPricesJSON() -> Data {
        Data("""
        {
          "meta": {"date": "2026-05-13", "version": "5.2.1"},
          "data": {
            "uuid-one": {
              "paper": {
                "cardkingdom": {"retail": {"normal": {"2026-04-01": 999.0}}},
                "tcgplayer": {
                  "buylist": {"normal": {"2026-04-01": 0.01}},
                  "retail": {
                    "normal": {
                      "2026-01-01": 1.00,
                      "2026-03-02": 1.25,
                      "2026-03-10": 4.00,
                      "2026-03-25": 1.80,
                      "2026-03-31": 2.00,
                      "2026-04-01": 2.50,
                      "2026-04-02": -5.00
                    },
                    "foil": {
                      "2026-04-01": 5.00
                    }
                  }
                }
              },
              "online": {
                "tcgplayer": {
                  "retail": {
                    "normal": {
                      "2026-04-01": 123.00
                    }
                  }
                }
              }
            },
            "uuid-two": {
              "paper": {
                "tcgplayer": {
                  "retail": {
                    "etched": {
                      "2026-04-01": 7.00
                    }
                  }
                }
              }
            },
            "uuid-ignored": {
              "paper": {
                "tcgplayer": {
                  "retail": {
                    "normal": {
                      "2026-04-01": 10.00
                    }
                  }
                }
              }
            }
          }
        }
        """.utf8)
    }

    private func singleCardPrintingsJSON(cardID: String, uuid: String) -> Data {
        Data("""
        {
          "data": {
            "TST": {
              "cards": [
                {"uuid": "\(uuid)", "identifiers": {"scryfallId": "\(cardID)"}}
              ]
            }
          }
        }
        """.utf8)
    }

    private func allIdentifiersJSON(cardID: String, uuid: String) -> Data {
        Data("""
        {
          "data": {
            "\(uuid)": {
              "identifiers": {"scryfallId": "\(cardID)"}
            },
            "uuid-ignored": {
              "identifiers": {"scryfallId": "not-local"}
            }
          }
        }
        """.utf8)
    }

    private func largeAllIdentifiersJSON(cardID: String, uuid: String) -> Data {
        let padding = String(repeating: "x", count: 480)
        var json = #"{"data":{"#
        for index in 0..<9_000 {
            json += #""ignored-\#(index)":{"identifiers":{"scryfallId":"not-local-\#(index)"},"pad":"\#(padding)"},"#
        }
        json += #""\#(uuid)":{"identifiers":{"scryfallId":"\#(cardID)"}}}}"#
        return Data(json.utf8)
    }

    private func largeAllPricesJSON(uuid: String) -> Data {
        let padding = String(repeating: "x", count: 480)
        var json = #"{"data":{"#
        for index in 0..<9_000 {
            json += #""ignored-\#(index)":{"paper":{"tcgplayer":{"retail":{"normal":{"2026-05-14":1.0}}}},"pad":"\#(padding)"},"#
        }
        json += #""\#(uuid)":{"paper":{"tcgplayer":{"retail":{"normal":{"2026-05-14":3.0}}}}}}}"#
        return Data(json.utf8)
    }

    private func allFinishPricesJSON(uuid: String) -> Data {
        Data("""
        {
          "data": {
            "\(uuid)": {
              "paper": {
                "tcgplayer": {
                  "retail": {
                    "etched": {"2026-04-01": 3.75},
                    "foil": {"2026-04-01": 2.50},
                    "normal": {"2026-04-01": 1.25}
                  }
                }
              }
            }
          }
        }
        """.utf8)
    }

    private func allFinishPricesTodayJSON(uuid: String) -> Data {
        Data("""
        {
          "data": {
            "\(uuid)": {
              "paper": {
                "tcgplayer": {
                  "retail": {
                    "etched": {"2026-05-14": 8.00},
                    "foil": {"2026-05-14": 6.00},
                    "normal": {
                      "2026-05-13": 2.75,
                      "2026-05-14": 3.00
                    }
                  }
                }
              }
            }
          }
        }
        """.utf8)
    }

    private func twoPointHistoryJSON(uuid: String) -> Data {
        Data("""
        {
          "data": {
            "\(uuid)": {
              "paper": {
                "tcgplayer": {
                  "retail": {
                    "normal": {
                      "2026-01-01": 1.00,
                      "2026-03-01": 2.00,
                      "2026-05-14": 4.00
                    }
                  }
                }
              }
            }
          }
        }
        """.utf8)
    }

    private func replacementPricesJSON(uuid: String, date: String, price: Double) -> Data {
        Data("""
        {
          "data": {
            "\(uuid)": {
              "paper": {
                "tcgplayer": {
                  "retail": {
                    "normal": {
                      "\(date)": \(price)
                    }
                  }
                }
              }
            }
          }
        }
        """.utf8)
    }

    private func gzipData(_ data: Data) -> Data {
        var output = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        output.append(0x01)
        let length = UInt16(data.count)
        appendLittleEndian(length, to: &output)
        appendLittleEndian(~length, to: &output)
        output.append(data)
        appendLittleEndian(crc32(data), to: &output)
        appendLittleEndian(UInt32(data.count), to: &output)
        return output
    }

    private func appendLittleEndian(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    private func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                if value & 1 == 1 {
                    value = 0xedb8_8320 ^ (value >> 1)
                } else {
                    value >>= 1
                }
            }
            table[index] = value
        }

        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffff_ffff
    }

    private func testCard(id: String, name: String, priceUSD: Double? = nil) -> CardRecord {
        CardRecord(
            id: id,
            name: name,
            setCode: "tst",
            setName: "Test Set",
            setType: "expansion",
            collectorNumber: "1",
            rarity: "rare",
            priceUSD: priceUSD,
            colorSortKey: 0,
            layout: "normal",
            typeLine: "Instant",
            oracleText: ""
        )
    }

    private struct LiveKnownMTGJSONCard: Hashable {
        var name: String
        var preferredSetCode: String?

        var id: String {
            "\(name)|\(preferredSetCode ?? "")"
        }
    }

    private struct LiveKnownMTGJSONIdentity {
        var scryfallID: String
    }

    private struct LiveMTGJSONIdentifierCard: Decodable {
        var name: String?
        var setCode: String?
        var identifiers: Identifiers?

        struct Identifiers: Decodable {
            var scryfallID: String?

            enum CodingKeys: String, CodingKey {
                case scryfallID = "scryfallId"
            }
        }
    }

    private func liveKnownCardIdentities(
        in url: URL,
        targets: [LiveKnownMTGJSONCard]
    ) throws -> [String: LiveKnownMTGJSONIdentity] {
        let decoder = JSONDecoder()
        var identities: [String: LiveKnownMTGJSONIdentity] = [:]

        try MTGJSONDataObjectScanner.forEachObject(in: url) { _, objectData in
            guard identities.count < targets.count else {
                return
            }
            let card = try decoder.decode(LiveMTGJSONIdentifierCard.self, from: objectData)
            guard let name = card.name,
                  let scryfallID = card.identifiers?.scryfallID
            else {
                return
            }

            for target in targets where identities[target.id] == nil && target.name == name {
                guard target.preferredSetCode == nil
                    || card.setCode?.caseInsensitiveCompare(target.preferredSetCode ?? "") == .orderedSame
                else {
                    continue
                }
                identities[target.id] = LiveKnownMTGJSONIdentity(scryfallID: scryfallID)
            }
        }

        return identities
    }
}

private actor PriceMappingProgressRecorder {
    private var recordedEvents: [(scannedBytes: Int64, totalBytes: Int64?, mappedCards: Int)] = []

    func record(scannedBytes: Int64, totalBytes: Int64?, mappedCards: Int) {
        recordedEvents.append((scannedBytes, totalBytes, mappedCards))
    }

    func events() -> [(scannedBytes: Int64, totalBytes: Int64?, mappedCards: Int)] {
        recordedEvents
    }
}
