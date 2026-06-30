import Foundation
import GrimoraCore
import GrimoraEngineKit
import Testing

/// Offline, deterministic end-to-end tests of the engine's build/run orchestration. A stub network
/// client serves canned Scryfall + MTGJSON source data, and the engine is pointed at a temp state
/// directory, so these run in CI with no network and exercise the full pipeline glue: fetch sources,
/// download, build the SQLite catalog, write the manifest, and record run history/state.
struct EngineBuildIntegrationTests {
  private func makeEngine() throws -> (engine: GrimoraDataEngine, root: URL, network: StubNetworkClient) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EngineBuildTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": root.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": root.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": root.appendingPathComponent("logs").path,
      "GRIMORA_CATALOG_PUBLIC_BASE_URL": "https://example.test/v1/catalog",
    ]
    let network = StubNetworkClient(responses: try EngineFixtures.responses())
    let engine = try GrimoraDataEngine(environment: environment, network: network)
    return (engine, root, network)
  }

  @Test
  func buildProducesValidCatalogAndRecordsRun() async throws {
    let (engine, root, _) = try makeEngine()
    defer { try? FileManager.default.removeItem(at: root) }

    let result = try await engine.build(force: true)

    #expect(result.manifest.counts.cards == 2)
    #expect(result.manifest.counts.priceSeries == 1)
    #expect(result.manifest.version.hasPrefix("v"))
    #expect(result.manifest.sources.mtgjsonDate == "2026-06-14")
    #expect(result.manifest.sources.mtgjsonVersion == "5.3.0")

    // The built artifact validates and its counts match the manifest the engine wrote.
    let catalogURL = result.directory.appendingPathComponent("catalog.sqlite")
    let counts = try CardDatabase.validateCatalog(at: catalogURL)
    #expect(counts == result.manifest.counts)

    // The priced card round-trips its value history into the catalog.
    let database = try CardDatabase(
      userDatabaseURL: root.appendingPathComponent("user.sqlite"),
      catalogURL: catalogURL
    )
    #expect(try database.card(id: "engine-forest")?.name == "Engine Forest")
    #expect(try database.valueGuide(forCardID: "engine-forest").entries.first?.currentPrice == 0.50)

    // Run history + persisted state reflect the successful build.
    let history = engine.loadRunHistory()
    #expect(history.first?.operation == .build)
    #expect(history.first?.outcome == .succeeded)
    #expect(history.first?.counts == result.manifest.counts)
    #expect(engine.loadState().lastSuccessfulSources == result.manifest.sources)
    #expect(engine.lastLocalBuild()?.manifest.version == result.manifest.version)
  }

  @Test
  func runSkipsWhenSourcesUnchanged() async throws {
    let (engine, root, _) = try makeEngine()
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try await engine.build(force: true) // seeds lastSuccessfulSources
    let outcome = try await engine.run(force: false)

    #expect(outcome == .skippedUnchanged)
    let history = engine.loadRunHistory()
    #expect(history.first?.operation == .run)
    #expect(history.first?.outcome == .skippedUnchanged)
  }

  @Test
  func checkForUpdateReportsCurrentSourcesAgainstEmptyState() async throws {
    let (engine, root, _) = try makeEngine()
    defer { try? FileManager.default.removeItem(at: root) }

    let check = try await engine.checkForUpdate()
    #expect(check.current.mtgjsonVersion == "5.3.0")
    #expect(check.current.mtgjsonDate == "2026-06-14")
    #expect(check.lastBuilt == nil)
  }
}
