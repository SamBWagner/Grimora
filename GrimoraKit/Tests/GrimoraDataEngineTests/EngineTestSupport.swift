import Foundation
import GrimoraCore

/// In-memory `NetworkClient` for the engine target's offline tests: serves canned bytes per URL for
/// both `data(from:)` and `download(from:to:)`, and records the request order so tests can assert the
/// engine hit the expected endpoints. Mirrors the `RecordingNetworkClient` used in GrimoraCoreTests
/// (the two test targets can't share helpers).
actor StubNetworkClient: NetworkClient {
  private let responses: [URL: Data]
  private(set) var requestedURLs: [URL] = []

  init(responses: [URL: Data]) {
    self.responses = responses
  }

  func data(from url: URL, purpose: NetworkPurpose) async throws -> Data {
    requestedURLs.append(url)
    guard let data = responses[url] else {
      throw StubNetworkError.noResponse(url)
    }
    return data
  }

  func download(
    from url: URL,
    to destination: URL,
    purpose: NetworkPurpose,
    progress: (@Sendable (NetworkDownloadProgress) async -> Void)?
  ) async throws {
    requestedURLs.append(url)
    guard let data = responses[url] else {
      throw StubNetworkError.noResponse(url)
    }
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: destination, options: .atomic)
    await progress?(NetworkDownloadProgress(completedBytes: Int64(data.count), totalBytes: Int64(data.count)))
  }

  func recordedURLs() -> [URL] { requestedURLs }
}

enum StubNetworkError: Error, CustomStringConvertible {
  case noResponse(URL)
  var description: String {
    switch self {
    case .noResponse(let url): "stub network client has no canned response for \(url)"
    }
  }
}

/// Builds the canned source data the engine fetches during a build, wiring the same URLs the
/// production clients hit. `cards` = 2, `priceSeries` = 1 (only one card has a price).
enum EngineFixtures {
  static let scryfallDownloadURL = URL(string: "https://data.scryfall.io/default-cards/fixture.json")!

  static func responses() throws -> [URL: Data] {
    [
      BulkDataClient.bulkDataURL: bulkManifestJSON(),
      scryfallDownloadURL: defaultCardsJSON(),
      MTGJSONPriceHistoryClient.metaURL: mtgjsonMetaJSON(),
      MTGJSONPriceHistoryClient.allPrintingsURL: try gzip(mtgjsonPrintingsJSON()),
      MTGJSONPriceHistoryClient.allPricesURL: try gzip(mtgjsonPricesJSON()),
    ]
  }

  static func bulkManifestJSON() -> Data {
    Data("""
    {
      "object": "list",
      "has_more": false,
      "data": [
        {
          "object": "bulk_data",
          "id": "bulk-default",
          "type": "default_cards",
          "updated_at": "2026-06-14T09:00:00.000+00:00",
          "uri": "https://api.scryfall.com/bulk-data/bulk-default",
          "name": "Default Cards",
          "description": "Engine fixture",
          "size": 123,
          "download_uri": "\(scryfallDownloadURL.absoluteString)",
          "content_type": "application/json",
          "content_encoding": "gzip"
        }
      ]
    }
    """.utf8)
  }

  static func defaultCardsJSON() -> Data {
    Data("""
    [
      {
        "object": "card",
        "id": "engine-forest",
        "oracle_id": "oracle-engine-forest",
        "name": "Engine Forest",
        "lang": "en",
        "released_at": "2024-01-01",
        "layout": "normal",
        "cmc": 1,
        "type_line": "Creature — Treefolk",
        "oracle_text": "Reach",
        "power": "1",
        "toughness": "2",
        "colors": ["G"],
        "color_identity": ["G"],
        "keywords": ["Reach"],
        "produced_mana": ["G"],
        "legalities": {"commander": "legal"},
        "games": ["paper"],
        "finishes": ["nonfoil"],
        "foil": false,
        "nonfoil": true,
        "digital": false,
        "set": "eng",
        "set_name": "Engine Fixture Set",
        "set_type": "expansion",
        "collector_number": "1",
        "rarity": "common",
        "prices": {"usd": "0.50"},
        "image_uris": {"normal": "https://cards.scryfall.io/normal/front/e/f/engine-forest.jpg"}
      },
      {
        "object": "card",
        "id": "engine-relic",
        "oracle_id": "oracle-engine-relic",
        "name": "Engine Relic",
        "lang": "en",
        "released_at": "2024-02-01",
        "layout": "normal",
        "cmc": 2,
        "type_line": "Artifact",
        "oracle_text": "{T}: Add {C}.",
        "colors": [],
        "color_identity": [],
        "games": ["paper"],
        "digital": false,
        "set": "eng",
        "set_name": "Engine Fixture Set",
        "set_type": "expansion",
        "collector_number": "2",
        "rarity": "rare"
      }
    ]
    """.utf8)
  }

  static func mtgjsonMetaJSON() -> Data {
    Data("""
    {"meta": {"date": "2026-06-14", "version": "5.3.0"}}
    """.utf8)
  }

  static func mtgjsonPrintingsJSON() -> Data {
    Data("""
    {
      "data": {
        "ENG": {
          "cards": [
            {"uuid": "uuid-engine-forest", "identifiers": {"scryfallId": "engine-forest"}}
          ]
        }
      }
    }
    """.utf8)
  }

  static func mtgjsonPricesJSON() -> Data {
    Data("""
    {
      "data": {
        "uuid-engine-forest": {
          "paper": {"tcgplayer": {"retail": {"normal": {"2026-06-13": 0.48, "2026-06-14": 0.50}}}}
        }
      }
    }
    """.utf8)
  }

  /// Gzip-compresses bytes the way MTGJSON serves `.json.gz` (the engine downloads these to disk and
  /// the importer gunzips them).
  static func gzip(_ data: Data) throws -> Data {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("EngineFixtures-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let plain = directory.appendingPathComponent("payload.json")
    let compressed = directory.appendingPathComponent("payload.json.gz")
    try data.write(to: plain)
    try GzipArchive.compressFile(at: plain, to: compressed)
    return try Data(contentsOf: compressed)
  }
}
