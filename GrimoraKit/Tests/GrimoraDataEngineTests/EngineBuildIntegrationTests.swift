import Foundation
import GrimoraCore
import GrimoraDataPipeline
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
    #expect(result.manifest.enrichments == [
      CatalogEnrichmentVersion(identifier: "scryfall-oracle-tags", version: 1),
    ])

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

  /// A finished build directory should hold the catalog and its published sidecars — not SQLite's
  /// WAL scratch files. Those used to survive every build, leaking ~1 MB per build directory.
  @Test
  func buildLeavesNoSQLiteWALScratchBehind() async throws {
    let (engine, root, _) = try makeEngine()
    defer { try? FileManager.default.removeItem(at: root) }

    let result = try await engine.build(force: true)

    let leftovers = try FileManager.default.contentsOfDirectory(
      at: result.directory,
      includingPropertiesForKeys: nil
    )
    .map(\.lastPathComponent)
    .filter { $0.hasSuffix("-wal") || $0.hasSuffix("-shm") }
    #expect(leftovers.isEmpty, "build directory retained SQLite scratch files: \(leftovers)")
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
    #expect(check.current.oracleTagsUpdatedAt == "2026-06-14T21:00:00.000+00:00")
    #expect(check.current.oracleTagsDownloadURI == EngineFixtures.oracleTagsDownloadURL)
    #expect(check.lastBuilt == nil)
  }

  @Test
  func buildCachesExpandedOracleTagsAndReportsDistinctProgress() async throws {
    let (engine, root, network) = try makeEngine()
    defer { try? FileManager.default.removeItem(at: root) }
    let progressRecorder = EngineProgressRecorder()

    let result = try await engine.build(force: true) { progress in
      await progressRecorder.record(progress)
    }

    let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
    let sourceDirectory = try #require(
      FileManager.default.contentsOfDirectory(
        at: cacheRoot,
        includingPropertiesForKeys: [.isDirectoryKey]
      ).first
    )
    let oracleTagsURL = sourceDirectory.appendingPathComponent("scryfall-oracle-tags.jsonl")
    #expect(FileManager.default.fileExists(atPath: oracleTagsURL.path))
    #expect(!FileManager.default.fileExists(
      atPath: sourceDirectory.appendingPathComponent("scryfall-oracle-tags.download").path
    ))
    #expect(!FileManager.default.fileExists(
      atPath: sourceDirectory.appendingPathComponent("scryfall-oracle-tags.expanding").path
    ))

    var tags: [ScryfallOracleTagDTO] = []
    try await ScryfallOracleTagStreamScanner.scan(url: oracleTagsURL) { tags.append($0) }
    #expect(tags.map(\.slug) == ["draw-engine"])

    let progressDetails = await progressRecorder.values().compactMap(\.detail)
    #expect(progressDetails.contains("Scryfall Oracle Tags"))
    #expect(progressDetails.contains("Expanding Scryfall Oracle Tags"))
    let recordedURLs = await network.recordedURLs()
    #expect(recordedURLs.contains(EngineFixtures.oracleTagsDownloadURL))
    // `currentSources` resolves both Scryfall manifests. The build may refresh the default-card
    // manifest, but Oracle Tags must use the exact timestamped URI captured in source identity.
    #expect(recordedURLs.filter { $0 == BulkDataClient.bulkDataURL }.count == 3)

    let database = try SQLiteDatabase(
      storage: .readOnlyFile(result.directory.appendingPathComponent("catalog.sqlite"))
    )
    let expectedSemanticTables = [
      "semantic_card_tags",
      "semantic_tag_aliases",
      "semantic_tag_edges",
      "semantic_tag_stats",
      "semantic_tags",
    ]
    let statement = try database.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'semantic_%' ORDER BY name"
    )
    var semanticTables: [String] = []
    while try statement.step() {
      if let name = statement.string(at: 0) {
        semanticTables.append(name)
      }
    }
    #expect(semanticTables == expectedSemanticTables)
    let expectedCounts = [
      "semantic_card_tags": 1,
      "semantic_tag_aliases": 1,
      "semantic_tag_edges": 0,
      "semantic_tag_stats": 1,
      "semantic_tags": 1,
    ]
    for table in expectedSemanticTables {
      let count = try database.prepare("SELECT COUNT(*) FROM \(table)")
      _ = try count.step()
      #expect(count.int(at: 0) == expectedCounts[table])
    }

    let semanticDatabase = try CardDatabase(
      userDatabaseURL: root.appendingPathComponent("semantic-user.sqlite"),
      catalogURL: result.directory.appendingPathComponent("catalog.sqlite")
    )
    let snapshot = try semanticDatabase.semanticCatalogSnapshot()
    #expect(snapshot.tags.first?.slug == "draw-engine")
    #expect(snapshot.tags.first?.source == "scryfall-oracle-tags@2026-06-14T21:00:00.000+00:00")
    #expect(snapshot.cardTags.first?.cardKey == SemanticCardKey(rawValue: "o:oracle-engine-forest"))
    #expect(snapshot.cardTags.first?.annotation == "fixture")
  }

  @Test
  func buildRecoversFromStaleOracleTagsDownloadAndExpansionFiles() async throws {
    let (engine, root, _) = try makeEngine()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try await engine.build(force: true)

    let sourceDirectory = try #require(
      FileManager.default.contentsOfDirectory(
        at: root.appendingPathComponent("cache", isDirectory: true),
        includingPropertiesForKeys: [.isDirectoryKey]
      ).first
    )
    let finalURL = sourceDirectory.appendingPathComponent("scryfall-oracle-tags.jsonl")
    let downloadURL = sourceDirectory.appendingPathComponent("scryfall-oracle-tags.download")
    let expandingURL = sourceDirectory.appendingPathComponent("scryfall-oracle-tags.expanding")
    try FileManager.default.removeItem(at: finalURL)
    try Data("partial download".utf8).write(to: downloadURL)
    try Data("partial expansion".utf8).write(to: expandingURL)

    _ = try await engine.build(force: true)

    var tags: [ScryfallOracleTagDTO] = []
    try await ScryfallOracleTagStreamScanner.scan(url: finalURL) { tags.append($0) }
    #expect(tags.map(\.slug) == ["draw-engine"])
    #expect(!FileManager.default.fileExists(atPath: downloadURL.path))
    #expect(!FileManager.default.fileExists(atPath: expandingURL.path))
  }

  @Test
  func buildRemovesStaleOracleTagsStagingFilesBesideValidCacheWithoutRedownloading() async throws {
    let (engine, root, network) = try makeEngine()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try await engine.build(force: true)

    let sourceDirectory = try #require(
      FileManager.default.contentsOfDirectory(
        at: root.appendingPathComponent("cache", isDirectory: true),
        includingPropertiesForKeys: [.isDirectoryKey]
      ).first
    )
    let finalURL = sourceDirectory.appendingPathComponent("scryfall-oracle-tags.jsonl")
    let downloadURL = sourceDirectory.appendingPathComponent("scryfall-oracle-tags.download")
    let expandingURL = sourceDirectory.appendingPathComponent("scryfall-oracle-tags.expanding")
    try Data("stale download".utf8).write(to: downloadURL)
    try Data("stale expansion".utf8).write(to: expandingURL)
    let downloadCountBefore = await network.recordedURLs()
      .filter { $0 == EngineFixtures.oracleTagsDownloadURL }.count

    _ = try await engine.build(force: true)

    var tags: [ScryfallOracleTagDTO] = []
    try await ScryfallOracleTagStreamScanner.scan(url: finalURL) { tags.append($0) }
    #expect(tags.map(\.slug) == ["draw-engine"])
    #expect(!FileManager.default.fileExists(atPath: downloadURL.path))
    #expect(!FileManager.default.fileExists(atPath: expandingURL.path))
    let downloadCountAfter = await network.recordedURLs()
      .filter { $0 == EngineFixtures.oracleTagsDownloadURL }.count
    #expect(downloadCountAfter == downloadCountBefore)
  }
}

private actor EngineProgressRecorder {
  private var progress: [EngineRunProgress] = []

  func record(_ value: EngineRunProgress) {
    progress.append(value)
  }

  func values() -> [EngineRunProgress] {
    progress
  }
}
