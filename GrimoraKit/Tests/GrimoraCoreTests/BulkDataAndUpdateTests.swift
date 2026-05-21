@testable import GrimoraCore
import XCTest

final class BulkDataAndUpdateTests: XCTestCase {
    func testBulkDataClientReadsDefaultCardsManifestAndDownloadsFile() async throws {
        let manifestURL = BulkDataClient.bulkDataURL
        let downloadURL = URL(string: "https://data.scryfall.io/default-cards/default.json")!
        let network = RecordingNetworkClient(dataResponses: [
            manifestURL: manifestListJSON(type: "default_cards", downloadURL: downloadURL),
            downloadURL: Data("[]".utf8)
        ])
        let client = BulkDataClient(network: network)

        let manifest = try await client.fetchDefaultCardsManifest()
        XCTAssertEqual(manifest.type, "default_cards")
        XCTAssertEqual(manifest.downloadURI, downloadURL)

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try await client.downloadDefaultCards(manifest: manifest, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data("[]".utf8))
        let requests = await network.requests()
        let purposes = requests.map(\.1)
        XCTAssertEqual(purposes, [.manifestCheck, .bulkDownload])
    }

    func testBulkDataClientFailsWhenDefaultCardsManifestIsMissing() async throws {
        let network = RecordingNetworkClient(dataResponses: [
            BulkDataClient.bulkDataURL: manifestListJSON(type: "oracle_cards", downloadURL: URL(string: "https://example.test/oracle.json")!)
        ])
        let client = BulkDataClient(network: network)

        do {
            _ = try await client.fetchDefaultCardsManifest()
            XCTFail("Expected missing default cards error")
        } catch BulkDataClientError.defaultCardsMissing {
        }
    }

    func testUpdateServiceSkipsAutomaticChecksWithinWeeklyWindow() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let network = RecordingNetworkClient(dataResponses: [
            BulkDataClient.bulkDataURL: manifestListJSON(type: "default_cards", downloadURL: URL(string: "https://example.test/default.json")!)
        ])
        let service = LibraryUpdateService(
            database: database,
            bulkDataClient: BulkDataClient(network: network),
            minimumAutomaticCheckInterval: 60
        )
        let now = Date(timeIntervalSince1970: 10_000)

        let first = try await service.checkForUpdates(now: now, manual: true)
        guard case .noLocalLibrary = first else {
            return XCTFail("Expected no local library")
        }

        let skipped = try await service.checkForUpdates(now: now.addingTimeInterval(30), manual: false)
        guard case .skipped = skipped else {
            return XCTFail("Expected skipped automatic check")
        }
        let requests = await network.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testUpdateServiceComparesRemoteAndLocalManifestDates() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards([Fixtures.records()[0]])
        try database.saveMetadataValue("old", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)

        let downloadURL = URL(string: "https://example.test/default.json")!
        let network = RecordingNetworkClient(dataResponses: [
            BulkDataClient.bulkDataURL: manifestListJSON(type: "default_cards", updatedAt: "new", downloadURL: downloadURL),
            downloadURL: Fixtures.defaultCardsJSON()
        ])
        let service = LibraryUpdateService(database: database, bulkDataClient: BulkDataClient(network: network))

        let result = try await service.checkForUpdates(manual: true)
        guard case .updateAvailable(let manifest) = result else {
            return XCTFail("Expected update available")
        }
        XCTAssertEqual(manifest.updatedAt, "new")

        try database.saveMetadataValue("new", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        let current = try await service.checkForUpdates(manual: true)
        guard case .upToDate = current else {
            return XCTFail("Expected up to date")
        }
    }

    func testDownloadAndImportUsesBulkDownloadPurpose() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let downloadURL = URL(string: "https://example.test/default.json")!
        let manifest = BulkDataManifest(
            id: "id",
            type: "default_cards",
            updatedAt: "new",
            name: "Default Cards",
            size: Fixtures.defaultCardsJSON().count,
            downloadURI: downloadURL
        )
        let network = RecordingNetworkClient(dataResponses: [downloadURL: Fixtures.defaultCardsJSON()])
        let service = LibraryUpdateService(database: database, bulkDataClient: BulkDataClient(network: network))
        let importer = LibraryImporter(database: database, imageResolver: NoImageResolver())

        let summary = try await service.downloadAndImport(
            manifest: manifest,
            temporaryDirectory: FileManager.default.temporaryDirectory,
            importer: importer
        )

        XCTAssertEqual(summary.importedCards, 2)
        let requests = await network.requests()
        let purposes = requests.map(\.1)
        XCTAssertEqual(purposes, [.bulkDownload])
    }

    func testDownloadAndImportCanDeferPriceHistoryAndStillPrepareReadyLibrary() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let downloadURL = URL(string: "https://example.test/default.json")!
        let manifest = defaultCardsManifest(downloadURL: downloadURL)
        let network = RecordingNetworkClient(dataResponses: [downloadURL: Fixtures.defaultCardsJSON()])
        let service = LibraryUpdateService(
            database: database,
            bulkDataClient: BulkDataClient(network: network),
            priceHistoryClient: MTGJSONPriceHistoryClient(network: network),
            priceHistoryImporter: MTGJSONPriceHistoryImporter(database: database)
        )
        let importer = LibraryImporter(database: database, imageResolver: NoImageResolver())

        let summary = try await service.downloadAndImport(
            manifest: manifest,
            temporaryDirectory: try temporaryDirectory(),
            importer: importer,
            refreshesPriceHistory: false
        )

        XCTAssertEqual(summary.importedCards, 2)
        XCTAssertEqual(summary.priceHistoryStatus, .deferred)
        XCTAssertTrue(try database.isLibraryReady())
        let requests = await network.requests()
        XCTAssertEqual(requests.map(\.1), [.bulkDownload])
    }

    func testLiveDefaultCardsImportCompletesWhenConfigured() async throws {
        guard let path = ProcessInfo.processInfo.environment["GRIMORA_LIVE_DEFAULT_CARDS_JSON"] else {
            throw XCTSkip("Set GRIMORA_LIVE_DEFAULT_CARDS_JSON to run the live default-cards import check.")
        }

        let database = try CardDatabase(storage: .file(try temporaryDirectory().appendingPathComponent("live.sqlite")))
        let importer = LibraryImporter(database: database, imageResolver: NoImageResolver())
        let fileURL = URL(fileURLWithPath: path)
        let manifest = BulkDataManifest(
            id: "live-default-cards",
            type: "default_cards",
            updatedAt: "live",
            name: "Default Cards",
            size: (try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0,
            downloadURI: fileURL
        )

        let summary = try await importer.importDefaultCards(
            from: fileURL,
            manifest: manifest,
            imagePolicy: .reuseExistingImagesWithoutDownloading,
            preservesCardValueHistory: true
        )

        XCTAssertGreaterThan(summary.importedCards, 90_000)
        XCTAssertTrue(try database.isLibraryReady())
        XCTAssertEqual(try database.cardCount(), summary.importedCards)
    }

    func testPriceHistoryFailureDoesNotFailCardImport() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let downloadURL = URL(string: "https://example.test/default.json")!
        let manifest = defaultCardsManifest(downloadURL: downloadURL)
        let network = RecordingNetworkClient(dataResponses: [downloadURL: Fixtures.defaultCardsJSON()])
        let service = LibraryUpdateService(
            database: database,
            bulkDataClient: BulkDataClient(network: network),
            priceHistoryClient: MTGJSONPriceHistoryClient(network: network),
            priceHistoryImporter: MTGJSONPriceHistoryImporter(database: database)
        )
        let importer = LibraryImporter(database: database, imageResolver: NoImageResolver())

        let summary = try await service.downloadAndImport(
            manifest: manifest,
            temporaryDirectory: FileManager.default.temporaryDirectory,
            importer: importer
        )

        XCTAssertEqual(summary.importedCards, 2)
        XCTAssertEqual(summary.priceHistoryStatus, .failed)
        XCTAssertEqual(try database.cardCount(), 2)
        let requests = await network.requests()
        let purposes = requests.map(\.1)
        XCTAssertEqual(purposes, [.bulkDownload, .priceHistoryDownload])
    }

    func testPriceHistoryDownloadFailureDoesNotFailCardImport() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let downloadURL = URL(string: "https://example.test/default.json")!
        let manifest = defaultCardsManifest(downloadURL: downloadURL)
        let network = RecordingNetworkClient(
            dataResponses: [
                downloadURL: Fixtures.defaultCardsJSON(),
                MTGJSONPriceHistoryClient.metaURL: mtgjsonMetaJSON()
            ],
            errors: [MTGJSONPriceHistoryClient.allPrintingsURL: TestNetworkError()]
        )
        let service = LibraryUpdateService(
            database: database,
            bulkDataClient: BulkDataClient(network: network),
            priceHistoryClient: MTGJSONPriceHistoryClient(network: network),
            priceHistoryImporter: MTGJSONPriceHistoryImporter(database: database)
        )
        let importer = LibraryImporter(database: database, imageResolver: NoImageResolver())

        let summary = try await service.downloadAndImport(
            manifest: manifest,
            temporaryDirectory: try temporaryDirectory(),
            importer: importer
        )

        XCTAssertEqual(summary.importedCards, 2)
        XCTAssertEqual(summary.priceHistoryStatus, .failed)
        XCTAssertEqual(try database.cardCount(), 2)
        let requests = await network.requests()
        XCTAssertEqual(requests.map(\.1), [.bulkDownload, .priceHistoryDownload, .priceHistoryDownload])
    }

    func testPriceImportIsSkippedWhenMTGJSONMetadataMatchesAndSummariesExist() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let importer = LibraryImporter(database: database, imageResolver: NoImageResolver())
        _ = try await importer.importDefaultCards(
            from: Fixtures.defaultCardsJSON(),
            manifest: nil,
            imagePolicy: .skipImageDownloads
        )
        let seededFixtures = try writeGzipPriceFixtures()
        let priceImporter = MTGJSONPriceHistoryImporter(database: database)
        _ = try await priceImporter.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsGzipURL: seededFixtures.printingsURL,
            allPricesGzipURL: seededFixtures.pricesURL,
            temporaryDirectory: seededFixtures.directory
        )
        XCTAssertGreaterThan(try database.valueSummaryCount(), 0)

        let downloadURL = URL(string: "https://example.test/default.json")!
        let network = RecordingNetworkClient(dataResponses: [
            downloadURL: Fixtures.defaultCardsJSON(),
            MTGJSONPriceHistoryClient.metaURL: mtgjsonMetaJSON(),
            MTGJSONPriceHistoryClient.allPrintingsURL: try Data(contentsOf: seededFixtures.printingsURL),
            MTGJSONPriceHistoryClient.allPricesTodayURL: try Data(contentsOf: seededFixtures.pricesURL)
        ])
        let service = LibraryUpdateService(
            database: database,
            bulkDataClient: BulkDataClient(network: network),
            priceHistoryClient: MTGJSONPriceHistoryClient(network: network),
            priceHistoryImporter: priceImporter
        )

        let summary = try await service.downloadAndImport(
            manifest: defaultCardsManifest(downloadURL: downloadURL),
            temporaryDirectory: try temporaryDirectory(),
            importer: importer
        )

        XCTAssertEqual(summary.importedCards, 2)
        XCTAssertEqual(summary.priceHistoryStatus, .imported(MTGJSONPriceImportSummary(mappedCards: 1, importedPricePoints: 1)))
        XCTAssertEqual(try database.valueSummaryCount(), 1)
        XCTAssertEqual(try database.valueGuide(forCardID: "json-alpha").entries.first?.currentPrice, 2.50)
        let requests = await network.requests()
        XCTAssertEqual(requests.map(\.0), [
            downloadURL,
            MTGJSONPriceHistoryClient.metaURL,
            MTGJSONPriceHistoryClient.allPrintingsURL,
            MTGJSONPriceHistoryClient.allPricesTodayURL
        ])
        XCTAssertEqual(requests.map(\.1), [
            .bulkDownload,
            .priceHistoryDownload,
            .priceHistoryDownload,
            .priceHistoryDownload
        ])
    }

    func testPriceImportRunsWhenMetadataMatchesButSummariesAreEmpty() async throws {
        let database = try CardDatabase(storage: .inMemory)
        try database.saveMetadataValue("2026-05-13", forKey: MetadataKey.mtgjsonPriceHistoryDate.rawValue)
        try database.saveMetadataValue("5.2.1", forKey: MetadataKey.mtgjsonPriceHistoryVersion.rawValue)

        let downloadURL = URL(string: "https://example.test/default.json")!
        let priceFixtures = try writeGzipPriceFixtures()
        let network = RecordingNetworkClient(dataResponses: [
            downloadURL: Fixtures.defaultCardsJSON(),
            MTGJSONPriceHistoryClient.metaURL: mtgjsonMetaJSON(),
            MTGJSONPriceHistoryClient.allPrintingsURL: try Data(contentsOf: priceFixtures.printingsURL),
            MTGJSONPriceHistoryClient.allPricesTodayURL: try Data(contentsOf: priceFixtures.pricesURL),
            MTGJSONPriceHistoryClient.allPricesURL: try Data(contentsOf: priceFixtures.pricesURL)
        ])
        let service = LibraryUpdateService(
            database: database,
            bulkDataClient: BulkDataClient(network: network),
            priceHistoryClient: MTGJSONPriceHistoryClient(network: network),
            priceHistoryImporter: MTGJSONPriceHistoryImporter(database: database)
        )
        let importer = LibraryImporter(database: database, imageResolver: NoImageResolver())

        let summary = try await service.downloadAndImport(
            manifest: defaultCardsManifest(downloadURL: downloadURL),
            temporaryDirectory: try temporaryDirectory(),
            importer: importer
        )

        XCTAssertEqual(summary.priceHistoryStatus, .imported(MTGJSONPriceImportSummary(mappedCards: 1, importedPricePoints: 1)))
        XCTAssertEqual(try database.valueGuide(forCardID: "json-alpha").entries.first?.currentPrice, 2.50)
        let requests = await network.requests()
        XCTAssertEqual(requests.map(\.1), [
            .bulkDownload,
            .priceHistoryDownload,
            .priceHistoryDownload,
            .priceHistoryDownload
        ])
    }

    func testPriceImportProgressEmitsPricingPhasesInOrder() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let downloadURL = URL(string: "https://example.test/default.json")!
        let priceFixtures = try writeGzipPriceFixtures()
        let network = RecordingNetworkClient(dataResponses: [
            downloadURL: Fixtures.defaultCardsJSON(),
            MTGJSONPriceHistoryClient.metaURL: mtgjsonMetaJSON(),
            MTGJSONPriceHistoryClient.allPrintingsURL: try Data(contentsOf: priceFixtures.printingsURL),
            MTGJSONPriceHistoryClient.allPricesTodayURL: try Data(contentsOf: priceFixtures.pricesURL),
            MTGJSONPriceHistoryClient.allPricesURL: try Data(contentsOf: priceFixtures.pricesURL)
        ])
        let service = LibraryUpdateService(
            database: database,
            bulkDataClient: BulkDataClient(network: network),
            priceHistoryClient: MTGJSONPriceHistoryClient(network: network),
            priceHistoryImporter: MTGJSONPriceHistoryImporter(database: database)
        )
        let importer = LibraryImporter(database: database, imageResolver: NoImageResolver())
        let progressRecorder = ImportProgressRecorder()

        _ = try await service.downloadAndImport(
            manifest: defaultCardsManifest(downloadURL: downloadURL),
            temporaryDirectory: try temporaryDirectory(),
            importer: importer
        ) { event in
            await progressRecorder.record(event)
        }

        let progressEvents = await progressRecorder.events()
        let pricingEvents = progressEvents.filter { event in
            switch event {
            case .downloadingPriceHistoryData, .buildingPriceIDMap, .importingPriceHistory, .priceHistoryReady:
                true
            default:
                false
            }
        }
        XCTAssertEqual(pricingEvents, [
            .downloadingPriceHistoryData,
            .buildingPriceIDMap,
            .importingPriceHistory,
            .priceHistoryReady(pricePointCount: 1)
        ])
    }

    func testRefreshPriceHistoryImportsValuesWithoutScryfallBulkNetwork() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let cardImporter = LibraryImporter(database: database, imageResolver: NoImageResolver())
        _ = try await cardImporter.importDefaultCards(
            from: Fixtures.defaultCardsJSON(),
            manifest: nil,
            imagePolicy: .skipImageDownloads
        )
        let priceFixtures = try writeGzipPriceFixtures()
        let network = RecordingNetworkClient(dataResponses: [
            MTGJSONPriceHistoryClient.metaURL: mtgjsonMetaJSON(),
            MTGJSONPriceHistoryClient.allPrintingsURL: try Data(contentsOf: priceFixtures.printingsURL),
            MTGJSONPriceHistoryClient.allPricesTodayURL: try Data(contentsOf: priceFixtures.pricesURL),
            MTGJSONPriceHistoryClient.allPricesURL: try Data(contentsOf: priceFixtures.pricesURL)
        ])
        let service = LibraryUpdateService(
            database: database,
            bulkDataClient: BulkDataClient(network: network),
            priceHistoryClient: MTGJSONPriceHistoryClient(network: network),
            priceHistoryImporter: MTGJSONPriceHistoryImporter(database: database)
        )

        let status = await service.refreshPriceHistory(temporaryDirectory: try temporaryDirectory())

        XCTAssertEqual(status, .imported(MTGJSONPriceImportSummary(mappedCards: 1, importedPricePoints: 1)))
        XCTAssertEqual(try database.cardCount(), 2)
        XCTAssertEqual(try database.valueGuide(forCardID: "json-alpha").entries.first?.currentPrice, 2.50)
        let requests = await network.requests()
        XCTAssertEqual(requests.map(\.0), [
            MTGJSONPriceHistoryClient.metaURL,
            MTGJSONPriceHistoryClient.allPrintingsURL,
            MTGJSONPriceHistoryClient.allPricesTodayURL
        ])
        XCTAssertEqual(requests.map(\.1), [
            .priceHistoryDownload,
            .priceHistoryDownload,
            .priceHistoryDownload
        ])
        XCTAssertFalse(requests.contains { $0.1 == .bulkDownload })
    }

    func testRefreshPriceHistorySkipsWhenMTGJSONMetadataMatchesAndSummariesExist() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let cardImporter = LibraryImporter(database: database, imageResolver: NoImageResolver())
        _ = try await cardImporter.importDefaultCards(
            from: Fixtures.defaultCardsJSON(),
            manifest: nil,
            imagePolicy: .skipImageDownloads
        )
        let seededFixtures = try writeGzipPriceFixtures()
        let priceImporter = MTGJSONPriceHistoryImporter(database: database)
        _ = try await priceImporter.importHistory(
            meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
            allPrintingsGzipURL: seededFixtures.printingsURL,
            allPricesGzipURL: seededFixtures.pricesURL,
            temporaryDirectory: seededFixtures.directory
        )
        let network = RecordingNetworkClient(dataResponses: [
            MTGJSONPriceHistoryClient.metaURL: mtgjsonMetaJSON()
        ])
        let service = LibraryUpdateService(
            database: database,
            bulkDataClient: BulkDataClient(network: network),
            priceHistoryClient: MTGJSONPriceHistoryClient(network: network),
            priceHistoryImporter: priceImporter
        )

        let status = await service.refreshPriceHistory(temporaryDirectory: try temporaryDirectory())

        XCTAssertEqual(status, .skipped)
        XCTAssertEqual(try database.valueSummaryCount(), 1)
        let requests = await network.requests()
        XCTAssertEqual(requests.map(\.0), [MTGJSONPriceHistoryClient.metaURL])
        XCTAssertEqual(requests.map(\.1), [.priceHistoryDownload])
    }

    func testRefreshPriceHistoryFailureLeavesExistingLibraryUsable() async throws {
        let database = try CardDatabase(storage: .inMemory)
        var records = Fixtures.records()
        records[0].normalImagePath = "/tmp/alpha-normal.jpg"
        try database.replaceAllCards(records)
        try Fixtures.markLibraryReady(database)
        let list = try database.createCardList(named: "Favorites")
        try database.appendCard("alpha", toList: list.id, quantity: 2)
        let network = RecordingNetworkClient(dataResponses: [
            MTGJSONPriceHistoryClient.metaURL: Data()
        ])
        let service = LibraryUpdateService(
            database: database,
            bulkDataClient: BulkDataClient(network: network),
            priceHistoryClient: MTGJSONPriceHistoryClient(network: network),
            priceHistoryImporter: MTGJSONPriceHistoryImporter(database: database)
        )

        let status = await service.refreshPriceHistory(temporaryDirectory: try temporaryDirectory())

        XCTAssertEqual(status, .failed)
        XCTAssertEqual(try database.cardCount(), records.count)
        XCTAssertEqual(try database.cardLists().map(\.name), ["Favorites"])
        XCTAssertEqual(try database.cardListEntries(forListID: list.id).map(\.cardID), ["alpha"])
        XCTAssertEqual(
            try database.metadataValue(forKey: MetadataKey.defaultCardsUpdatedAt.rawValue),
            "2026-04-25T09:09:59.477+00:00"
        )
        let response = try database.search(CardSearchRequest(text: "forest", activeFilters: []))
        guard case .results(let cards, _) = response else {
            return XCTFail("Expected search results after failed value refresh.")
        }
        XCTAssertEqual(cards.first?.id, "alpha")
        XCTAssertEqual(cards.first?.normalImagePath, "/tmp/alpha-normal.jpg")
        let requests = await network.requests()
        XCTAssertEqual(requests.map(\.1), [.priceHistoryDownload])
    }

    func testSearchOnlyUpdateUsesNoPriceHistoryNetworkPurposeWhenPricingIsNotConfigured() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let downloadURL = URL(string: "https://example.test/default.json")!
        let network = RecordingNetworkClient(dataResponses: [downloadURL: Fixtures.defaultCardsJSON()])
        let service = LibraryUpdateService(database: database, bulkDataClient: BulkDataClient(network: network))
        let importer = LibraryImporter(database: database, imageResolver: NoImageResolver())

        let summary = try await service.downloadAndImport(
            manifest: defaultCardsManifest(downloadURL: downloadURL),
            temporaryDirectory: try temporaryDirectory(),
            importer: importer
        )

        XCTAssertEqual(summary.priceHistoryStatus, .notConfigured)
        let requests = await network.requests()
        XCTAssertFalse(requests.contains { $0.1 == .priceHistoryDownload })
    }

    private func defaultCardsManifest(downloadURL: URL) -> BulkDataManifest {
        BulkDataManifest(
            id: "id",
            type: "default_cards",
            updatedAt: "new",
            name: "Default Cards",
            size: Fixtures.defaultCardsJSON().count,
            downloadURI: downloadURL
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeGzipPriceFixtures() throws -> (directory: URL, printingsURL: URL, pricesURL: URL) {
        let directory = try temporaryDirectory()
        let printingsURL = directory.appendingPathComponent("AllPrintings.json.gz")
        let pricesURL = directory.appendingPathComponent("AllPrices.json.gz")
        try gzipData(mtgjsonPrintingsJSON()).write(to: printingsURL, options: .atomic)
        try gzipData(mtgjsonPricesJSON()).write(to: pricesURL, options: .atomic)
        return (directory, printingsURL, pricesURL)
    }

    private func mtgjsonMetaJSON(date: String = "2026-05-13", version: String = "5.2.1") -> Data {
        Data("""
        {
          "meta": {
            "date": "\(date)",
            "version": "\(version)"
          }
        }
        """.utf8)
    }

    private func mtgjsonPrintingsJSON() -> Data {
        Data("""
        {
          "data": {
            "JFS": {
              "cards": [
                {"uuid": "uuid-json-alpha", "identifiers": {"scryfallId": "json-alpha"}},
                {"uuid": "uuid-remote-only", "identifiers": {"scryfallId": "remote-only"}}
              ]
            }
          }
        }
        """.utf8)
    }

    private func mtgjsonPricesJSON() -> Data {
        Data("""
        {
          "data": {
            "uuid-json-alpha": {
              "paper": {
                "tcgplayer": {
                  "retail": {
                    "normal": {
                      "2026-04-01": 2.50
                    }
                  }
                }
              }
            },
            "uuid-remote-only": {
              "paper": {
                "tcgplayer": {
                  "retail": {
                    "normal": {
                      "2026-04-01": 9.99
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

    private func manifestListJSON(
        type: String,
        updatedAt: String = "2026-04-25T09:09:59.477+00:00",
        downloadURL: URL
    ) -> Data {
        Data("""
        {
          "object": "list",
          "has_more": false,
          "data": [
            {
              "object": "bulk_data",
              "id": "bulk-id",
              "type": "\(type)",
              "updated_at": "\(updatedAt)",
              "uri": "https://api.scryfall.com/bulk-data/bulk-id",
              "name": "Default Cards",
              "description": "Fixture",
              "size": 123,
              "download_uri": "\(downloadURL.absoluteString)",
              "content_type": "application/json",
              "content_encoding": "gzip"
            }
          ]
        }
        """.utf8)
    }
}

private struct TestNetworkError: Error {}

private actor ImportProgressRecorder {
    private var recordedEvents: [ImportProgress] = []

    func record(_ event: ImportProgress) {
        recordedEvents.append(event)
    }

    func events() -> [ImportProgress] {
        recordedEvents
    }
}
