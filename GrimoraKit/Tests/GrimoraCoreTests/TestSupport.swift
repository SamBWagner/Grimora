@testable import GrimoraCore
import Foundation

actor RecordingNetworkClient: NetworkClient {
    var dataResponses: [URL: Data]
    var errors: [URL: Error]
    private var recordedRequests: [(URL, NetworkPurpose)] = []

    init(dataResponses: [URL: Data] = [:], errors: [URL: Error] = [:]) {
        self.dataResponses = dataResponses
        self.errors = errors
    }

    func data(from url: URL, purpose: NetworkPurpose) async throws -> Data {
        recordedRequests.append((url, purpose))
        if let error = errors[url] {
            throw error
        }
        return dataResponses[url] ?? Data()
    }

    func download(
        from url: URL,
        to destination: URL,
        purpose: NetworkPurpose,
        progress: (@Sendable (NetworkDownloadProgress) async -> Void)? = nil
    ) async throws {
        recordedRequests.append((url, purpose))
        if let error = errors[url] {
            throw error
        }
        let data = dataResponses[url] ?? Data()
        await progress?(NetworkDownloadProgress(completedBytes: 0, totalBytes: Int64(data.count)))
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        await progress?(NetworkDownloadProgress(completedBytes: Int64(data.count), totalBytes: Int64(data.count)))
    }

    func requests() -> [(URL, NetworkPurpose)] {
        recordedRequests
    }
}

struct StubImageResolver: ImageResolving {
    var failedURLs: Set<URL> = []

    func resolve(
        _ remoteURLs: ImageURLPair,
        cardID: String,
        faceIndex: Int?,
        qualities: Set<CardImageQuality>
    ) async -> ImageResolution {
        let urls = imageURLs(from: remoteURLs, qualities: qualities)
        let failures = urls.filter { failedURLs.contains($0) }
        let suffix = faceIndex.map { "-face-\($0)" } ?? ""
        return ImageResolution(
            paths: LocalImagePair(
                smallPath: qualities.contains(.small) && remoteURLs.small.map({ !failedURLs.contains($0) }) == true ? "/tmp/\(cardID)\(suffix)-small.jpg" : nil,
                normalPath: qualities.contains(.normal) && remoteURLs.normal.map({ !failedURLs.contains($0) }) == true ? "/tmp/\(cardID)\(suffix)-normal.jpg" : nil,
                largePath: qualities.contains(.large) && remoteURLs.large.map({ !failedURLs.contains($0) }) == true ? "/tmp/\(cardID)\(suffix)-large.jpg" : nil,
                artCropPath: qualities.contains(.artCrop) && remoteURLs.artCrop.map({ !failedURLs.contains($0) }) == true ? "/tmp/\(cardID)\(suffix)-art-crop.jpg" : nil
            ),
            failedURLs: failures
        )
    }
}

struct FileWritingImageResolver: ImageResolving {
    var rootDirectory: URL
    var failedURLs: Set<URL> = []

    func localPaths(for remoteURLs: ImageURLPair, cardID: String, faceIndex: Int?) -> LocalImagePair {
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
        let store = ImageStore(rootDirectory: rootDirectory)
        var paths = LocalImagePair()
        var failures: [URL] = []

        for quality in CardImageQuality.allCases where qualities.contains(quality) {
            guard let remoteURL = remoteURL(for: quality, in: remoteURLs, requestedQualities: qualities) else {
                continue
            }

            let localURL = store.localURL(for: remoteURL, cardID: cardID, faceIndex: faceIndex, quality: quality.rawValue)
            if failedURLs.contains(remoteURL) {
                failures.append(remoteURL)
                continue
            }

            try? FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Fixtures.imageData().write(to: localURL, options: .atomic)

            switch quality {
            case .small:
                paths.smallPath = localURL.path
            case .normal:
                paths.normalPath = localURL.path
            case .large:
                paths.largePath = localURL.path
            case .artCrop:
                paths.artCropPath = localURL.path
            }
        }

        return ImageResolution(paths: paths, failedURLs: failures)
    }
}

private func imageURLs(from remoteURLs: ImageURLPair, qualities: Set<CardImageQuality>) -> [URL] {
    CardImageQuality.allCases.compactMap { quality in
        qualities.contains(quality) ? remoteURL(for: quality, in: remoteURLs, requestedQualities: qualities) : nil
    }
}

private func remoteURL(
    for quality: CardImageQuality,
    in remoteURLs: ImageURLPair,
    requestedQualities: Set<CardImageQuality>
) -> URL? {
    switch quality {
    case .small:
        remoteURLs.small
    case .normal:
        remoteURLs.normal
    case .large:
        remoteURLs.large
    case .artCrop:
        remoteURLs.artCrop
    }
}

enum Fixtures {
    static func imageData() -> Data {
        Data([0xff, 0xd8, 0xff, 0xd9])
    }

    static func database() throws -> CardDatabase {
        let database = try CardDatabase(storage: .inMemory)
        try database.replaceAllCards(records())
        return database
    }

    static func markLibraryReady(_ database: CardDatabase, updatedAt: String = "2026-04-25T09:09:59.477+00:00") throws {
        try database.saveMetadataValue(updatedAt, forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
        try database.saveMetadataValue(CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
        try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)
    }

    static func bulkManifestListJSON(
        type: String = "default_cards",
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

    static func records() -> [CardRecord] {
        [
            CardRecord(
                id: "alpha",
                oracleID: "oracle-alpha",
                name: "Alpha Forest",
                releasedAt: "2020-01-01",
                setCode: "abc",
                setName: "Alpha Set",
                setType: "expansion",
                collectorNumber: "2",
                collectorNumberNumber: 2,
                rarity: "common",
                rarityRank: 0,
                artist: "Zed Artist",
                edhrecRank: 20,
                pennyRank: 30,
                manaCost: "{G}",
                manaValue: 1,
                power: "1",
                powerValue: 1,
                toughness: "1",
                toughnessValue: 1,
                priceUSD: 1,
                priceTIX: 1,
                priceEUR: 1,
                colorSortKey: 0,
                colors: ["G"],
                colorIdentity: ["G"],
                producedMana: ["G"],
                layout: "normal",
                typeLine: "Creature — Treefolk",
                oracleText: "Café sentinel",
                keywords: ["reach"],
                legalities: ["commander": "legal", "modern": "legal"],
                games: ["paper"],
                finishes: ["nonfoil"],
                borderColor: "black",
                frame: "2015",
                isRealCard: true,
                isNonfoil: true,
                normalImagePath: "/tmp/alpha-normal.jpg",
                largeImagePath: "/tmp/alpha-large.jpg"
            ),
            CardRecord(
                id: "beta",
                oracleID: "oracle-beta",
                name: "Beta Mage",
                releasedAt: "2021-01-01",
                setCode: "abc",
                setName: "Beta Set",
                setType: "expansion",
                collectorNumber: "10",
                collectorNumberNumber: 10,
                rarity: "mythic",
                rarityRank: 3,
                artist: "Amy Artist",
                edhrecRank: 10,
                pennyRank: 20,
                manaCost: "{1}{U}",
                manaValue: 2,
                power: "3",
                powerValue: 3,
                toughness: "2",
                toughnessValue: 2,
                priceUSD: 2,
                priceTIX: 2,
                priceEUR: 2,
                colorSortKey: 1,
                colors: ["U"],
                colorIdentity: ["U"],
                layout: "normal",
                typeLine: "Creature — Wizard",
                oracleText: "Draw a card.",
                keywords: ["flying"],
                legalities: ["commander": "legal", "modern": "legal"],
                games: ["paper", "mtgo"],
                finishes: ["foil", "nonfoil"],
                borderColor: "black",
                frame: "2015",
                isRealCard: true,
                isFoil: true,
                isNonfoil: true
            ),
            CardRecord(
                id: "gamma",
                name: "Gamma Relic",
                releasedAt: nil,
                setCode: "aaa",
                setName: "Gamma Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "special",
                rarityRank: nil,
                artist: nil,
                edhrecRank: nil,
                pennyRank: nil,
                manaCost: "{3}",
                manaValue: nil,
                power: nil,
                powerValue: nil,
                toughness: nil,
                toughnessValue: nil,
                priceUSD: nil,
                priceTIX: nil,
                priceEUR: nil,
                colorSortKey: 6,
                colors: [],
                colorIdentity: [],
                layout: "normal",
                typeLine: "Artifact",
                oracleText: "Ancient tool.",
                legalities: ["commander": "legal"],
                games: ["paper"],
                isRealCard: true
            ),
            CardRecord(
                id: "ub",
                name: "Beyond Hero",
                releasedAt: "2022-01-01",
                setCode: "ubx",
                setName: "Beyond Set",
                setType: "expansion",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 5,
                colors: ["W", "B"],
                colorIdentity: ["W", "B"],
                layout: "normal",
                typeLine: "Legendary Creature",
                oracleText: "Universes beyond sample.",
                legalities: ["commander": "legal"],
                games: ["paper"],
                isUniversesBeyond: true,
                isRealCard: true
            ),
            CardRecord(
                id: "alchemy",
                name: "Digital Conjurer",
                releasedAt: "2022-02-01",
                setCode: "yabc",
                setName: "Alchemy Set",
                setType: "alchemy",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 2,
                colors: ["B"],
                colorIdentity: ["B"],
                layout: "normal",
                typeLine: "Creature",
                oracleText: "Conjure a duplicate.",
                games: ["arena"],
                isDigital: true,
                isAlchemy: true,
                isRealCard: false
            ),
            CardRecord(
                id: "token",
                name: "Soldier Token",
                releasedAt: "2022-03-01",
                setCode: "tok",
                setName: "Token Set",
                setType: "token",
                collectorNumber: "1",
                collectorNumberNumber: 1,
                rarity: "common",
                rarityRank: 0,
                colorSortKey: 0,
                colors: ["W"],
                colorIdentity: ["W"],
                layout: "token",
                typeLine: "Token Creature — Soldier",
                oracleText: "",
                games: ["paper"],
                isRealCard: false
            ),
            CardRecord(
                id: "mdfc",
                name: "Daybreak // Nightfall",
                releasedAt: "2023-01-01",
                setCode: "dfc",
                setName: "Face Set",
                setType: "expansion",
                collectorNumber: "5",
                collectorNumberNumber: 5,
                rarity: "rare",
                rarityRank: 2,
                colorSortKey: 5,
                colors: ["W", "B"],
                colorIdentity: ["W", "B"],
                layout: "modal_dfc",
                typeLine: "",
                oracleText: "",
                legalities: ["commander": "legal"],
                games: ["paper"],
                isRealCard: true,
                faces: [
                    CardFaceRecord(cardID: "mdfc", faceIndex: 0, name: "Daybreak", typeLine: "Sorcery", oracleText: "Create light."),
                    CardFaceRecord(cardID: "mdfc", faceIndex: 1, name: "Nightfall", typeLine: "Instant", oracleText: "Create shadow.")
                ]
            )
        ]
    }

    static func defaultCardsJSON() -> Data {
        Data("""
        [
          {
            "object": "card",
            "id": "json-alpha",
            "oracle_id": "oracle-json-alpha",
            "name": "JSON Forest",
            "lang": "en",
            "released_at": "2024-01-01",
            "layout": "normal",
            "cmc": 2,
            "type_line": "Creature — Treefolk",
            "oracle_text": "Reach",
            "power": "2",
            "toughness": "3",
            "colors": ["G"],
            "color_identity": ["G"],
            "keywords": ["Reach"],
            "produced_mana": ["G"],
            "legalities": {"commander": "legal", "modern": "legal"},
            "games": ["paper", "arena"],
            "finishes": ["nonfoil"],
            "foil": false,
            "nonfoil": true,
            "reserved": false,
            "game_changer": false,
            "reprint": false,
            "booster": true,
            "story_spotlight": false,
            "highres_image": true,
            "digital": false,
            "oversized": false,
            "set": "jfs",
            "set_name": "JSON Fixture Set",
            "set_type": "expansion",
            "collector_number": "12a",
            "rarity": "uncommon",
            "artist": "Fixture Artist",
            "artist_ids": ["artist-fixture"],
            "illustration_id": "illustration-fixture",
            "flavor_text": "Fixture flavor.",
            "watermark": "simic",
            "border_color": "black",
            "frame": "2015",
            "edhrec_rank": 123,
            "penny_rank": 456,
            "mtgo_id": 78901,
            "prices": {"usd": "1.25", "eur": "0.75", "tix": "0.03"},
            "image_uris": {
              "small": "https://cards.scryfall.io/small/front/a/a/json-alpha.jpg",
              "normal": "https://cards.scryfall.io/normal/front/a/a/json-alpha.jpg",
              "large": "https://cards.scryfall.io/large/front/a/a/json-alpha.jpg",
              "art_crop": "https://cards.scryfall.io/art_crop/front/a/a/json-alpha.jpg"
            }
          },
          {
            "object": "card",
            "id": "json-dfc",
            "name": "JSON Dawn // JSON Dusk",
            "released_at": "2024-02-01",
            "layout": "modal_dfc",
            "cmc": 3,
            "colors": ["W", "B"],
            "color_identity": ["W", "B"],
            "games": ["paper"],
            "digital": false,
            "set": "jfs",
            "set_name": "JSON Fixture Set",
            "set_type": "expansion",
            "collector_number": "13",
            "rarity": "rare",
            "card_faces": [
              {
                "name": "JSON Dawn",
                "type_line": "Sorcery",
                "oracle_text": "Return a card.",
                "image_uris": {
                  "small": "https://cards.scryfall.io/small/front/d/d/json-dawn.jpg",
                  "normal": "https://cards.scryfall.io/normal/front/d/d/json-dawn.jpg",
                  "large": "https://cards.scryfall.io/large/front/d/d/json-dawn.jpg",
                  "art_crop": "https://cards.scryfall.io/art_crop/front/d/d/json-dawn.jpg"
                }
              },
              {
                "name": "JSON Dusk",
                "type_line": "Instant",
                "oracle_text": "Destroy a card."
              }
            ]
          }
        ]
        """.utf8)
    }
}
