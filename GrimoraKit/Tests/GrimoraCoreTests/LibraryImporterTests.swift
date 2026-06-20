@testable import GrimoraCore
import XCTest

final class LibraryImporterTests: XCTestCase {
    func testImporterStoresCardsFacesMetadataAndImagePaths() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let manifest = BulkDataManifest(
            id: "manifest",
            type: "default_cards",
            updatedAt: "2026-04-25T09:09:59.477+00:00",
            name: "Default Cards",
            size: 10,
            downloadURI: URL(string: "https://data.scryfall.io/default-cards/default.json")!
        )
        let importer = LibraryImporter(database: database, imageResolver: StubImageResolver())

        let summary = try await importer.importDefaultCards(
            from: Fixtures.defaultCardsJSON(),
            manifest: manifest,
            imagePolicy: .downloadBeforeDatabaseWrite
        )

        XCTAssertEqual(summary.importedCards, 2)
        XCTAssertEqual(summary.failedImageURLs, [])
        XCTAssertEqual(try database.cardCount(), 2)
        XCTAssertEqual(try database.metadataValue(forKey: MetadataKey.defaultCardsUpdatedAt.rawValue), manifest.updatedAt)
        XCTAssertEqual(try database.metadataValue(forKey: MetadataKey.requiredImagesCached.rawValue), "true")

        let response = try database.search(CardSearchRequest(text: "dawn"))
        guard case .results(let cards, _) = response else {
            return XCTFail("Expected imported cards")
        }
        XCTAssertEqual(cards.first?.faces.first?.normalImagePath, "/tmp/json-dfc-face-0-normal.jpg")
    }

    func testImporterContinuesWhenImagesFail() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let failedURL = URL(string: "https://cards.scryfall.io/large/front/a/a/json-alpha.jpg")!
        let importer = LibraryImporter(database: database, imageResolver: StubImageResolver(failedURLs: [failedURL]))

        let summary = try await importer.importDefaultCards(
            from: Fixtures.defaultCardsJSON(),
            manifest: nil,
            imagePolicy: .downloadBeforeDatabaseWrite
        )

        XCTAssertEqual(summary.importedCards, 2)
        XCTAssertEqual(summary.failedImageURLs, [failedURL])
        XCTAssertEqual(try database.cardCount(), 2)
        XCTAssertEqual(try database.metadataValue(forKey: MetadataKey.requiredImagesCached.rawValue), "false")
    }

    func testStrictImporterDoesNotExposeCardsWhenImagesFail() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let failedURL = URL(string: "https://cards.scryfall.io/large/front/a/a/json-alpha.jpg")!
        let importer = LibraryImporter(database: database, imageResolver: StubImageResolver(failedURLs: [failedURL]))

        do {
            _ = try await importer.importDefaultCards(
                from: Fixtures.defaultCardsJSON(),
                manifest: nil,
                imagePolicy: .downloadBeforeDatabaseWriteStrict
            )
            XCTFail("Expected strict import to fail")
        } catch LibraryImportError.imageDownloadsFailed(let urls) {
            XCTAssertEqual(urls, [failedURL])
        }

        XCTAssertEqual(try database.cardCount(), 0)
        XCTAssertNil(try database.metadataValue(forKey: MetadataKey.requiredImagesCached.rawValue))
    }

    func testDisplayStrictImporterCachesOnlyPreferredSmallImages() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let resolver = RecordingImageResolver()
        let importer = LibraryImporter(database: database, imageResolver: resolver)
        let progressRecorder = ProgressEventRecorder()

        let summary = try await importer.importDefaultCards(
            from: preferredPrintingsJSON(),
            manifest: nil,
            imagePolicy: .downloadDisplayImagesBeforeDatabaseWriteStrict
        ) { progress in
            await progressRecorder.record(progress)
        }

        XCTAssertEqual(summary.importedCards, 8)
        XCTAssertEqual(summary.failedImageURLs, [])
        XCTAssertEqual(try database.cardCount(), 8)
        XCTAssertEqual(try database.metadataValue(forKey: MetadataKey.requiredImagesCached.rawValue), "true")

        let allPrintings = try search(database, text: "optimized", mode: .all)
        XCTAssertEqual(allPrintings.count, 7)
        XCTAssertEqual(allPrintings.filter { $0.smallImagePath != nil }.map(\.id), ["new-regular"])

        let preferred = try search(database, text: "optimized", mode: .preferred)
        XCTAssertEqual(preferred.map(\.id), ["new-regular"])

        let calls = await resolver.recordedCalls()
        XCTAssertEqual(Set(calls.map(\.cardID)), Set(["new-regular", "other-card"]))
        XCTAssertTrue(calls.allSatisfy { $0.qualities == [.small] })
        XCTAssertTrue(calls.allSatisfy { $0.remoteURLs.normal == nil && $0.remoteURLs.large == nil })

        let events = await progressRecorder.recordedEvents()
        XCTAssertTrue(events.contains(.downloadingImages(completedCards: 1, totalCards: 2, failedImageCount: 0)))
        XCTAssertTrue(events.contains(.downloadingImages(completedCards: 2, totalCards: 2, failedImageCount: 0)))
    }

    func testImporterReusesExistingImagesWithoutDownloading() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ImageStore(rootDirectory: directory)
        let existingSmallURL = URL(string: "https://cards.scryfall.io/small/front/a/a/json-alpha.jpg")!
        let existingSmallPath = store.localURL(
            for: existingSmallURL,
            cardID: "json-alpha",
            faceIndex: nil,
            quality: CardImageQuality.small.rawValue
        )
        try FileManager.default.createDirectory(at: existingSmallPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cached small".utf8).write(to: existingSmallPath, options: .atomic)

        let resolver = RecordingImageResolver(rootDirectory: directory)
        let importer = LibraryImporter(database: database, imageResolver: resolver)

        let summary = try await importer.importDefaultCards(
            from: Fixtures.defaultCardsJSON(),
            manifest: nil,
            imagePolicy: .reuseExistingImagesWithoutDownloading
        )

        XCTAssertEqual(summary.importedCards, 2)
        XCTAssertEqual(summary.failedImageURLs, [])
        let calls = await resolver.recordedCalls()
        XCTAssertTrue(calls.isEmpty)

        let response = try database.search(CardSearchRequest(text: "forest"))
        guard case .results(let cards, _) = response else {
            return XCTFail("Expected imported cards")
        }
        XCTAssertEqual(cards.first?.smallImagePath, existingSmallPath.path)
        XCTAssertNil(cards.first?.normalImagePath)
        XCTAssertNil(cards.first?.largeImagePath)
        XCTAssertEqual(try database.metadataValue(forKey: MetadataKey.requiredImagesCached.rawValue), "false")
    }

    func testImporterCanMakeCardsSearchableBeforeImageCachingFinishes() async throws {
        let database = try CardDatabase(storage: .inMemory)
        let importer = LibraryImporter(database: database, imageResolver: StubImageResolver())
        let recorder = ImportProgressRecorder(database: database)

        let summary = try await importer.importDefaultCards(
            from: Fixtures.defaultCardsJSON(),
            manifest: nil,
            imagePolicy: .downloadAfterDatabaseWrite
        ) { progress in
            await recorder.record(progress)
        }

        let recording = try await recorder.recording()
        XCTAssertTrue(recording.sawSearchableCardData)
        XCTAssertTrue(recording.events.contains(.decodingCardData))
        XCTAssertTrue(recording.events.contains(.storingSearchIndex(cardCount: 2)))
        XCTAssertTrue(recording.events.contains(.storingSearchIndexProgress(
            CardDatabaseWriteProgress(writtenCards: 1, totalCards: 2)
        )))
        XCTAssertTrue(recording.events.contains(.storingSearchIndexProgress(
            CardDatabaseWriteProgress(writtenCards: 2, totalCards: 2)
        )))
        XCTAssertTrue(recording.events.contains(.cardDataReady(cardCount: 2)))
        XCTAssertLessThan(
            try XCTUnwrap(recording.events.firstIndex(of: .storingSearchIndexProgress(
                CardDatabaseWriteProgress(writtenCards: 2, totalCards: 2)
            ))),
            try XCTUnwrap(recording.events.firstIndex(of: .cardDataReady(cardCount: 2)))
        )
        XCTAssertEqual(summary.importedCards, 2)

        let response = try database.search(CardSearchRequest(text: "forest"))
        guard case .results(let cards, _) = response else {
            return XCTFail("Expected searchable card data")
        }
        XCTAssertEqual(cards.first?.normalImagePath, "/tmp/json-alpha-normal.jpg")
    }

    private func search(
        _ database: CardDatabase,
        text: String,
        mode: PrintingDisplayMode
    ) throws -> [CardRecord] {
        let response = try database.search(CardSearchRequest(
            text: text,
            printingDisplayMode: mode,
            limit: 20
        ))
        guard case .results(let cards, _) = response else {
            XCTFail("Expected results")
            return []
        }
        return cards
    }

    private func preferredPrintingsJSON() -> Data {
        Data("""
        [
          {
            "object": "card",
            "id": "old-regular",
            "oracle_id": "optimized-oracle",
            "name": "Optimized Orc",
            "lang": "en",
            "released_at": "2020-01-01",
            "layout": "normal",
            "type_line": "Creature",
            "oracle_text": "Old.",
            "games": ["paper"],
            "digital": false,
            "oversized": false,
            "set": "old",
            "set_name": "Old Set",
            "set_type": "expansion",
            "collector_number": "1",
            "rarity": "rare",
            "image_uris": {"small": "https://example.test/old-small.jpg"}
          },
          {
            "object": "card",
            "id": "new-regular",
            "oracle_id": "optimized-oracle",
            "name": "Optimized Orc",
            "lang": "en",
            "released_at": "2024-01-01",
            "layout": "normal",
            "type_line": "Creature",
            "oracle_text": "New.",
            "games": ["paper"],
            "digital": false,
            "oversized": false,
            "set": "new",
            "set_name": "New Set",
            "set_type": "expansion",
            "collector_number": "1",
            "rarity": "rare",
            "image_uris": {"small": "https://example.test/new-small.jpg"}
          },
          {
            "object": "card",
            "id": "promo-newer",
            "oracle_id": "optimized-oracle",
            "name": "Optimized Orc",
            "lang": "en",
            "released_at": "2025-01-01",
            "layout": "normal",
            "type_line": "Creature",
            "oracle_text": "Promo.",
            "games": ["paper"],
            "digital": false,
            "oversized": false,
            "set": "pro",
            "set_name": "Promo Set",
            "set_type": "promo",
            "collector_number": "1",
            "rarity": "rare",
            "promo": true,
            "image_uris": {"small": "https://example.test/promo-small.jpg"}
          },
          {
            "object": "card",
            "id": "box-newer",
            "oracle_id": "optimized-oracle",
            "name": "Optimized Orc",
            "lang": "en",
            "released_at": "2025-01-02",
            "layout": "normal",
            "type_line": "Creature",
            "oracle_text": "Box.",
            "games": ["paper"],
            "digital": false,
            "oversized": false,
            "set": "box",
            "set_name": "Box Set",
            "set_type": "box",
            "collector_number": "1",
            "rarity": "rare",
            "image_uris": {"small": "https://example.test/box-small.jpg"}
          },
          {
            "object": "card",
            "id": "booster-newer",
            "oracle_id": "optimized-oracle",
            "name": "Optimized Orc",
            "lang": "en",
            "released_at": "2025-01-03",
            "layout": "normal",
            "type_line": "Creature",
            "oracle_text": "Showcase.",
            "games": ["paper"],
            "digital": false,
            "oversized": false,
            "set": "sho",
            "set_name": "Showcase Set",
            "set_type": "expansion",
            "collector_number": "1",
            "rarity": "rare",
            "promo_types": ["showcase"],
            "image_uris": {"small": "https://example.test/showcase-small.jpg"}
          },
          {
            "object": "card",
            "id": "variation-newer",
            "oracle_id": "optimized-oracle",
            "name": "Optimized Orc",
            "lang": "en",
            "released_at": "2025-01-04",
            "layout": "normal",
            "type_line": "Creature",
            "oracle_text": "Variation.",
            "games": ["paper"],
            "digital": false,
            "oversized": false,
            "set": "var",
            "set_name": "Variation Set",
            "set_type": "expansion",
            "collector_number": "1",
            "rarity": "rare",
            "variation": true,
            "image_uris": {"small": "https://example.test/variation-small.jpg"}
          },
          {
            "object": "card",
            "id": "foreign-newer",
            "oracle_id": "optimized-oracle",
            "name": "Optimized Orc",
            "lang": "fr",
            "released_at": "2026-01-01",
            "layout": "normal",
            "type_line": "Creature",
            "oracle_text": "Foreign.",
            "games": ["paper"],
            "digital": false,
            "oversized": false,
            "set": "for",
            "set_name": "Foreign Set",
            "set_type": "expansion",
            "collector_number": "1",
            "rarity": "rare",
            "image_uris": {"small": "https://example.test/foreign-small.jpg"}
          },
          {
            "object": "card",
            "id": "other-card",
            "oracle_id": "other-oracle",
            "name": "Other Spell",
            "lang": "en",
            "released_at": "2024-01-01",
            "layout": "normal",
            "type_line": "Instant",
            "oracle_text": "Other.",
            "games": ["paper"],
            "digital": false,
            "oversized": false,
            "set": "oth",
            "set_name": "Other Set",
            "set_type": "expansion",
            "collector_number": "1",
            "rarity": "common",
            "image_uris": {"small": "https://example.test/other-small.jpg"}
          }
        ]
        """.utf8)
    }
}

private actor ImportProgressRecorder {
    private let database: CardDatabase
    private var events: [ImportProgress] = []
    private var sawSearchableCardData = false
    private var capturedError: Error?

    init(database: CardDatabase) {
        self.database = database
    }

    func record(_ progress: ImportProgress) {
        events.append(progress)

        guard case .cardDataReady = progress else {
            return
        }

        do {
            guard try database.cardCount() == 2 else {
                return
            }
            let response = try database.search(CardSearchRequest(text: "forest"))
            guard case .results(let cards, _) = response,
                  cards.first?.name == "JSON Forest",
                  cards.first?.normalImagePath == nil else {
                return
            }
            sawSearchableCardData = true
        } catch {
            capturedError = error
        }
    }

    func recording() throws -> (events: [ImportProgress], sawSearchableCardData: Bool) {
        if let capturedError {
            throw capturedError
        }
        return (events, sawSearchableCardData)
    }
}

private struct RecordingImageCall: Equatable, Sendable {
    var cardID: String
    var faceIndex: Int?
    var qualities: Set<CardImageQuality>
    var remoteURLs: ImageURLPair
}

private actor RecordingImageResolver: ImageResolving {
    nonisolated let rootDirectory: URL?
    private var calls: [RecordingImageCall] = []

    init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
    }

    nonisolated func localPaths(for remoteURLs: ImageURLPair, cardID: String, faceIndex: Int?) -> LocalImagePair {
        guard let rootDirectory else {
            return LocalImagePair()
        }

        let store = ImageStore(rootDirectory: rootDirectory)
        return LocalImagePair(
            smallPath: remoteURLs.small.map {
                store.localURL(for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.small.rawValue).path
            },
            normalPath: remoteURLs.normal.map {
                store.localURL(for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.normal.rawValue).path
            },
            largePath: remoteURLs.large.map {
                store.localURL(for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.large.rawValue).path
            },
            artCropPath: remoteURLs.artCrop.map {
                store.localURL(for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.artCrop.rawValue).path
            }
        )
    }

    func resolve(
        _ remoteURLs: ImageURLPair,
        cardID: String,
        faceIndex: Int?,
        qualities: Set<CardImageQuality>
    ) async -> ImageResolution {
        calls.append(RecordingImageCall(
            cardID: cardID,
            faceIndex: faceIndex,
            qualities: qualities,
            remoteURLs: remoteURLs
        ))

        return ImageResolution(paths: LocalImagePair(
            smallPath: qualities.contains(.small) && remoteURLs.small != nil ? "/tmp/\(cardID)-small.jpg" : nil,
            normalPath: qualities.contains(.normal) && remoteURLs.normal != nil ? "/tmp/\(cardID)-normal.jpg" : nil,
            largePath: qualities.contains(.large) && remoteURLs.large != nil ? "/tmp/\(cardID)-large.jpg" : nil,
            artCropPath: qualities.contains(.artCrop) && remoteURLs.artCrop != nil ? "/tmp/\(cardID)-art-crop.jpg" : nil
        ))
    }

    func recordedCalls() -> [RecordingImageCall] {
        calls
    }
}

private actor ProgressEventRecorder {
    private var events: [ImportProgress] = []

    func record(_ progress: ImportProgress) {
        events.append(progress)
    }

    func recordedEvents() -> [ImportProgress] {
        events
    }
}
