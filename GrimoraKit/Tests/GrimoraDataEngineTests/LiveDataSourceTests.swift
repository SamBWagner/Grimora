import Foundation
import GrimoraCore
import GrimoraEngineKit
import Testing

/// "Real pull" golden tests that hit the live Scryfall + MTGJSON sources. They are opt-in (skipped
/// by default) because live data changes daily and the heavy build downloads hundreds of MB — so
/// they assert *stable facts*, not byte-for-byte snapshots.
///
/// - `GRIMORA_LIVE_TESTS=1` enables the lightweight checks (source manifests parse + a few immutable
///   cards via the Scryfall API).
/// - `GRIMORA_LIVE_FULL_BUILD=1` additionally enables the full real build (downloads the actual
///   sources, builds the catalog, asserts a plausible card-count floor + a known card present).
///
/// Run them with `Tools/run_engine_tests.sh --live` / `--full`.
private let liveEnabled = ProcessInfo.processInfo.environment["GRIMORA_LIVE_TESTS"] != nil
private let fullBuildEnabled = ProcessInfo.processInfo.environment["GRIMORA_LIVE_FULL_BUILD"] != nil

struct LiveDataSourceTests {
  @Test(.enabled(if: liveEnabled))
  func sourceManifestsFetchAndParse() async throws {
    let network = URLSessionNetworkClient(userAgent: "GrimoraDataEngineTests/1.0")

    let scryfall = try await BulkDataClient(network: network).fetchDefaultCardsManifest()
    #expect(scryfall.type == "default_cards")
    #expect(!scryfall.updatedAt.isEmpty)
    #expect(scryfall.downloadURI.absoluteString.contains("scryfall"))

    let mtgjson = try await MTGJSONPriceHistoryClient(network: network).fetchMeta()
    #expect(!mtgjson.date.isEmpty)
    #expect(!mtgjson.version.isEmpty)
  }

  @Test(.enabled(if: liveEnabled))
  func knownCardsMatchImmutableGolden() async throws {
    let network = URLSessionNetworkClient(userAgent: "GrimoraDataEngineTests/1.0")

    let lotus = try await fetchCard(named: "Black Lotus", network: network)
    #expect(lotus.name == "Black Lotus")
    #expect(lotus.typeLine == "Artifact")
    #expect(lotus.manaValue == 0)
    #expect(lotus.colorIdentity.isEmpty)
    #expect(lotus.oracleText.contains("Add three mana of any one color"))

    try await Task.sleep(for: .milliseconds(150)) // be polite to Scryfall's rate limit
    let elves = try await fetchCard(named: "Llanowar Elves", network: network)
    #expect(elves.name == "Llanowar Elves")
    // The normalizer preserves Scryfall's uppercase color codes; the DB storage layer is what
    // lowercases them (see the lowercase values in the golden-catalog snapshot).
    #expect(elves.colorIdentity == ["G"])
    #expect(elves.manaValue == 1)
    #expect(elves.producedMana.contains("G"))
  }

  @Test(.enabled(if: fullBuildEnabled))
  func fullRealBuildProducesPlausibleCatalog() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EngineLiveFullBuild-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": root.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": root.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": root.appendingPathComponent("logs").path,
      "GRIMORA_CATALOG_PUBLIC_BASE_URL": "https://example.test/v1/catalog",
    ]
    // Default network = real URLSessionNetworkClient: this performs the actual ~hundreds-of-MB pull.
    let engine = try GrimoraDataEngine(environment: environment)

    let result = try await engine.build(force: true)
    #expect(result.manifest.counts.cards > 90_000)
    #expect(result.manifest.counts.priceSeries > 0)
    #expect(result.manifest.version.hasPrefix("v"))

    let catalogURL = result.directory.appendingPathComponent("catalog.sqlite")
    let database = try CardDatabase(
      userDatabaseURL: root.appendingPathComponent("user.sqlite"),
      catalogURL: catalogURL
    )
    let response = try database.search(CardSearchRequest(text: "Black Lotus"))
    guard case .results(let cards, _) = response else {
      Issue.record("Expected search results from the freshly built live catalog")
      return
    }
    #expect(cards.contains { $0.name == "Black Lotus" })
  }

  private func fetchCard(
    named name: String,
    network: URLSessionNetworkClient
  ) async throws -> CardRecord {
    var components = URLComponents(string: "https://api.scryfall.com/cards/named")!
    components.queryItems = [URLQueryItem(name: "exact", value: name)]
    let data = try await network.data(from: components.url!, purpose: .manifestCheck)
    return try ScryfallCatalogDecoder.decodeRecord(from: data)
  }
}
