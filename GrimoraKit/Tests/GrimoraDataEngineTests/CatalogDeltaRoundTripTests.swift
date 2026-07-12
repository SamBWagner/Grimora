import Foundation
import GrimoraCore
import GrimoraEngineKit
import Testing

/// Proves the core of the incremental-update feature: a delta generated from catalog A → B, applied
/// on top of a copy of A, reproduces B's *logical content* exactly (same content digests, counts,
/// and `quick_check`), even though the files differ byte-for-byte. Exercises every patch section —
/// price-only update, non-price upsert, new card, deleted card, and a one-day series append.
struct CatalogDeltaRoundTripTests {
  @Test
  func deltaFromAtoBReproducesBExactly() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DeltaRoundTrip-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let buildA = try await buildCatalog(fixture: .versionA, root: root, tag: "a")
    let buildB = try await buildCatalog(fixture: .versionB, root: root, tag: "b")

    // Sanity: the two builds differ and have the expected shape.
    #expect(buildA.manifest.counts.cards == 3) // forest, relic, ghost
    #expect(buildB.manifest.counts.cards == 3) // forest, relic, isle (ghost removed)
    #expect(buildA.manifest.version != buildB.manifest.version)

    let baseCatalog = buildA.directory.appendingPathComponent("catalog.sqlite")
    let targetCatalog = buildB.directory.appendingPathComponent("catalog.sqlite")

    // Generate the delta and assert it used the compact/narrow encodings we expect.
    let deltaURL = root.appendingPathComponent("delta-a-to-b.sqlite")
    let stats = try CatalogDeltaBuilder().buildDelta(
      baseCatalogURL: baseCatalog,
      targetCatalogURL: targetCatalog,
      baseVersion: buildA.manifest.version,
      targetVersion: buildB.manifest.version,
      into: deltaURL
    )
    #expect(stats.cardsPriceUpdated == 1) // forest price 0.50 -> 0.55, nothing else changed
    #expect(stats.cardsUpserted == 2) // relic (oracle changed) + isle (new)
    #expect(stats.cardsDeleted == 1) // ghost
    #expect(stats.seriesSlid == 1) // forest's 91-day window slid one day
    #expect(stats.seriesReplaced == 0) // ...as a slide, not a full replace

    // Apply the delta onto a copy of A.
    let working = root.appendingPathComponent("working.sqlite")
    try FileManager.default.copyItem(at: baseCatalog, to: working)
    try CatalogDeltaApplier().apply(deltaURL: deltaURL, toWorkingCatalog: working)

    // The patched catalog is logically identical to a fresh build of B.
    let expected = try digests(of: targetCatalog)
    let actual = try digests(of: working)
    #expect(actual == expected)

    // ...and structurally valid, with matching counts and consistent FTS.
    let counts = try CardDatabase.validateCatalog(at: working)
    #expect(counts == buildB.manifest.counts)
    try assertConsistent(working)

    // Spot-check user-visible data: forest's current value matches B, ghost is gone, isle exists.
    let db = try CardDatabase(
      userDatabaseURL: root.appendingPathComponent("reader-user.sqlite"),
      catalogURL: working
    )
    #expect(try db.card(id: "engine-ghost") == nil)
    #expect(try db.card(id: "engine-isle")?.name == "Engine Isle")
    #expect(try db.card(id: "engine-relic")?.oracleText == "{T}: Add {C} or {W}.")
    #expect(try db.valueGuide(forCardID: "engine-forest").entries.first?.currentPrice == 0.55)
  }

  /// End-to-end check of the engine's build hook: a second build (sharing state with the first) must
  /// emit a `delta.json` + gzipped delta from the prior build that reproduces this build when applied.
  @Test
  func engineBuildHookStagesWorkingDeltaFromPreviousBuild() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EngineDeltaHook-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    // Both builds share one engine state/builds dir so the second sees the first as its base.
    let engineRoot = root.appendingPathComponent("engine", isDirectory: true)
    let buildA = try await build(fixture: .versionA, engineRoot: engineRoot)
    let buildB = try await build(fixture: .versionB, engineRoot: engineRoot)

    #expect(buildB.manifest.contentDigests != nil)

    let deltaJSON = buildB.directory.appendingPathComponent("delta.json")
    #expect(FileManager.default.fileExists(atPath: deltaJSON.path))
    let sidecar = try JSONDecoder().decode(
      CatalogDeltaSidecar.self,
      from: Data(contentsOf: deltaJSON)
    )
    #expect(sidecar.baseVersion == buildA.manifest.version)
    let deltaGz = buildB.directory.appendingPathComponent(sidecar.fileName)
    #expect(FileManager.default.fileExists(atPath: deltaGz.path))
    #expect(try FileSHA256.hash(url: deltaGz) == sidecar.sha256)

    // Applying the engine-generated delta to a copy of A reproduces B exactly.
    let deltaSQLite = root.appendingPathComponent("engine-delta.sqlite")
    try GzipArchive.decompressFile(at: deltaGz, to: deltaSQLite)
    let working = root.appendingPathComponent("working.sqlite")
    try FileManager.default.copyItem(
      at: buildA.directory.appendingPathComponent("catalog.sqlite"),
      to: working
    )
    try CatalogDeltaApplier().apply(deltaURL: deltaSQLite, toWorkingCatalog: working)

    let expected = try digests(of: buildB.directory.appendingPathComponent("catalog.sqlite"))
    #expect(try digests(of: working) == expected)
  }

  /// Full client staging path: with build A installed and B advertised via `current.json` + a chain
  /// carrying the A→B delta, `stageLatestCatalog` patches locally (downloading only the delta, never
  /// the full artifact) and stages a catalog logically identical to a fresh build of B.
  @Test
  func clientStagesIncrementallyFromChain() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ClientStaging-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let buildA = try await buildCatalog(fixture: .versionA, root: root, tag: "a")
    let buildB = try await buildCatalog(fixture: .versionB, root: root, tag: "b")
    let catalogA = buildA.directory.appendingPathComponent("catalog.sqlite")
    let catalogB = buildB.directory.appendingPathComponent("catalog.sqlite")

    // Build + gzip the A→B delta the server would publish.
    let deltaSQLite = root.appendingPathComponent("delta.sqlite")
    _ = try CatalogDeltaBuilder().buildDelta(
      baseCatalogURL: catalogA,
      targetCatalogURL: catalogB,
      baseVersion: buildA.manifest.version,
      targetVersion: buildB.manifest.version,
      into: deltaSQLite
    )
    let deltaGz = root.appendingPathComponent("delta.sqlite.gz")
    try GzipArchive.compressFile(at: deltaSQLite, to: deltaGz)

    // Lay down an active managed install of A (catalog + persisted manifest with digests).
    let supportDir = root.appendingPathComponent("Support", isDirectory: true)
    let activeDir = supportDir.appendingPathComponent("Database-v2", isDirectory: true)
    try FileManager.default.createDirectory(at: activeDir, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: catalogA, to: activeDir.appendingPathComponent("Catalog.sqlite"))
    try CatalogManifest.encoder(prettyPrinted: true).encode(buildA.manifest)
      .write(to: activeDir.appendingPathComponent("manifest.json"))

    // Stub the catalog API: current.json = B, chain = [A, B] with the A→B delta.
    let apiURL = URL(string: "https://example.test/v1/catalog")!
    let deltaURL = apiURL.appendingPathComponent(buildB.manifest.version)
      .appendingPathComponent("delta").appendingPathComponent(buildA.manifest.version)
    let chain = CatalogChain(
      current: buildB.manifest.version,
      entries: [
        CatalogChainEntry(
          version: buildA.manifest.version,
          catalogSchemaVersion: buildA.manifest.catalogSchemaVersion,
          contentDigests: buildA.manifest.contentDigests!,
          deltaFromPrevious: nil
        ),
        CatalogChainEntry(
          version: buildB.manifest.version,
          catalogSchemaVersion: buildB.manifest.catalogSchemaVersion,
          contentDigests: buildB.manifest.contentDigests!,
          deltaFromPrevious: CatalogDeltaDescriptor(
            baseVersion: buildA.manifest.version,
            url: deltaURL,
            sha256: try FileSHA256.hash(url: deltaGz),
            bytes: Int64((try Data(contentsOf: deltaGz)).count),
            formatVersion: CatalogDelta.currentFormatVersion
          )
        ),
      ]
    )
    let network = StubNetworkClient(responses: [
      apiURL: try CatalogManifest.encoder().encode(buildB.manifest),
      apiURL.appendingPathComponent("chain"): try CatalogChain.encoder().encode(chain),
      deltaURL: try Data(contentsOf: deltaGz),
    ])
    let service = ManagedCatalogMigrationService(
      supportDirectory: supportDir,
      bulkDataClient: BulkDataClient(network: network, catalogAPIURL: apiURL),
      availableCapacity: { _ in .max }
    )

    let staged = try await service.stageLatestCatalog(manual: true)
    #expect(staged.version == buildB.manifest.version)

    // Only the delta was fetched — never the full artifact.
    let requested = await network.recordedURLs()
    #expect(requested.contains(deltaURL))
    #expect(!requested.contains(buildB.manifest.artifact.downloadURL))

    // The staged catalog is logically identical to a fresh build of B.
    let readyCatalog = supportDir.appendingPathComponent(".CatalogMigrationReady")
      .appendingPathComponent("Catalog.sqlite")
    #expect(try digests(of: readyCatalog) == digests(of: catalogB))
  }

  /// Multi-step Phase 2 path: with build A installed and the chain advertising A→B→C, the client walks
  /// both deltas (downloading each, never the full artifact) and stages a catalog identical to C.
  @Test
  func clientWalksMultipleDeltasWhenSeveralBuildsBehind() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MultiStep-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let buildA = try await buildCatalog(fixture: .versionA, root: root, tag: "a")
    let buildB = try await buildCatalog(fixture: .versionB, root: root, tag: "b")
    let buildC = try await buildCatalog(fixture: .versionC, root: root, tag: "c")

    let apiURL = URL(string: "https://example.test/v1/catalog")!
    let gzAB = try makeDeltaGz(from: buildA, to: buildB, in: root, name: "ab")
    let gzBC = try makeDeltaGz(from: buildB, to: buildC, in: root, name: "bc")
    let descAB = try descriptor(base: buildA, target: buildB, apiURL: apiURL, gz: gzAB)
    let descBC = try descriptor(base: buildB, target: buildC, apiURL: apiURL, gz: gzBC)

    let supportDir = root.appendingPathComponent("Support", isDirectory: true)
    try installActiveCatalog(buildA, supportDirectory: supportDir)

    let chain = CatalogChain(
      current: buildC.manifest.version,
      entries: [
        chainEntry(for: buildA, deltaFromPrevious: nil),
        chainEntry(for: buildB, deltaFromPrevious: descAB),
        chainEntry(for: buildC, deltaFromPrevious: descBC),
      ]
    )
    let network = StubNetworkClient(responses: [
      apiURL: try CatalogManifest.encoder().encode(buildC.manifest),
      apiURL.appendingPathComponent("chain"): try CatalogChain.encoder().encode(chain),
      descAB.url: try Data(contentsOf: gzAB),
      descBC.url: try Data(contentsOf: gzBC),
    ])
    let service = ManagedCatalogMigrationService(
      supportDirectory: supportDir,
      bulkDataClient: BulkDataClient(network: network, catalogAPIURL: apiURL),
      availableCapacity: { _ in .max }
    )

    let staged = try await service.stageLatestCatalog(manual: true)
    #expect(staged.version == buildC.manifest.version)

    let requested = await network.recordedURLs()
    #expect(requested.contains(descAB.url))
    #expect(requested.contains(descBC.url))
    #expect(!requested.contains(buildC.manifest.artifact.downloadURL))

    let readyCatalog = supportDir.appendingPathComponent(".CatalogMigrationReady")
      .appendingPathComponent("Catalog.sqlite")
    #expect(
      try digests(of: readyCatalog)
        == digests(of: buildC.directory.appendingPathComponent("catalog.sqlite"))
    )
  }

  /// When the deltas would together rival the full compressed artifact, the client abandons the
  /// incremental path and does a plain full download instead.
  @Test
  func clientFallsBackToFullWhenDeltaPathIsTooLarge() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("OversizedPath-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let buildA = try await buildCatalog(fixture: .versionA, root: root, tag: "a")
    let buildB = try await buildCatalog(fixture: .versionB, root: root, tag: "b")

    let apiURL = URL(string: "https://example.test/v1/catalog")!
    let gzAB = try makeDeltaGz(from: buildA, to: buildB, in: root, name: "ab")
    // Inflate the advertised delta size past B's full artifact so the summed-bytes guard trips.
    let descAB = try descriptor(
      base: buildA,
      target: buildB,
      apiURL: apiURL,
      gz: gzAB,
      bytesOverride: buildB.manifest.artifact.compressedBytes + 1
    )

    let supportDir = root.appendingPathComponent("Support", isDirectory: true)
    try installActiveCatalog(buildA, supportDirectory: supportDir)

    let chain = CatalogChain(
      current: buildB.manifest.version,
      entries: [
        chainEntry(for: buildA, deltaFromPrevious: nil),
        chainEntry(for: buildB, deltaFromPrevious: descAB),
      ]
    )
    let network = StubNetworkClient(responses: [
      apiURL: try CatalogManifest.encoder().encode(buildB.manifest),
      apiURL.appendingPathComponent("chain"): try CatalogChain.encoder().encode(chain),
      buildB.manifest.artifact.downloadURL: try Data(contentsOf: buildB.artifactURL),
    ])
    let service = ManagedCatalogMigrationService(
      supportDirectory: supportDir,
      bulkDataClient: BulkDataClient(network: network, catalogAPIURL: apiURL),
      availableCapacity: { _ in .max }
    )

    let staged = try await service.stageLatestCatalog(manual: true)
    #expect(staged.version == buildB.manifest.version)

    // The full artifact was downloaded; the (oversized) delta was not.
    let requested = await network.recordedURLs()
    #expect(requested.contains(buildB.manifest.artifact.downloadURL))
    #expect(!requested.contains(descAB.url))
  }

  // MARK: - Helpers

  private func build(fixture: DeltaTestFixture, engineRoot: URL) async throws -> LocalBuildResult {
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": engineRoot.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": engineRoot.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": engineRoot.appendingPathComponent("logs").path,
      "GRIMORA_CATALOG_PUBLIC_BASE_URL": "https://example.test/v1/catalog",
    ]
    let network = StubNetworkClient(responses: try fixture.responses())
    let engine = try GrimoraDataEngine(environment: environment, network: network)
    return try await engine.build(force: true)
  }

  private func makeDeltaGz(
    from base: LocalBuildResult,
    to target: LocalBuildResult,
    in directory: URL,
    name: String
  ) throws -> URL {
    let deltaSQLite = directory.appendingPathComponent("\(name).sqlite")
    _ = try CatalogDeltaBuilder().buildDelta(
      baseCatalogURL: base.directory.appendingPathComponent("catalog.sqlite"),
      targetCatalogURL: target.directory.appendingPathComponent("catalog.sqlite"),
      baseVersion: base.manifest.version,
      targetVersion: target.manifest.version,
      into: deltaSQLite
    )
    let gz = directory.appendingPathComponent("\(name).sqlite.gz")
    try GzipArchive.compressFile(at: deltaSQLite, to: gz)
    return gz
  }

  private func descriptor(
    base: LocalBuildResult,
    target: LocalBuildResult,
    apiURL: URL,
    gz: URL,
    bytesOverride: Int64? = nil
  ) throws -> CatalogDeltaDescriptor {
    CatalogDeltaDescriptor(
      baseVersion: base.manifest.version,
      url: apiURL.appendingPathComponent(target.manifest.version)
        .appendingPathComponent("delta").appendingPathComponent(base.manifest.version),
      sha256: try FileSHA256.hash(url: gz),
      bytes: try bytesOverride ?? Int64(Data(contentsOf: gz).count),
      formatVersion: CatalogDelta.currentFormatVersion
    )
  }

  private func chainEntry(
    for build: LocalBuildResult,
    deltaFromPrevious: CatalogDeltaDescriptor?
  ) -> CatalogChainEntry {
    CatalogChainEntry(
      version: build.manifest.version,
      catalogSchemaVersion: build.manifest.catalogSchemaVersion,
      contentDigests: build.manifest.contentDigests!,
      deltaFromPrevious: deltaFromPrevious
    )
  }

  private func installActiveCatalog(_ build: LocalBuildResult, supportDirectory: URL) throws {
    let activeDir = supportDirectory.appendingPathComponent("Database-v2", isDirectory: true)
    try FileManager.default.createDirectory(at: activeDir, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
      at: build.directory.appendingPathComponent("catalog.sqlite"),
      to: activeDir.appendingPathComponent("Catalog.sqlite")
    )
    try CatalogManifest.encoder(prettyPrinted: true).encode(build.manifest)
      .write(to: activeDir.appendingPathComponent("manifest.json"))
  }

  private func digests(of catalogURL: URL) throws -> CatalogContentDigests {
    let database = try SQLiteDatabase(storage: .readOnlyFile(catalogURL))
    return try CatalogContentDigest.compute(database)
  }

  private func assertConsistent(_ catalogURL: URL) throws {
    let database = try SQLiteDatabase(storage: .readOnlyFile(catalogURL))
    #expect(try database.quickCheck() == "ok")
    func count(_ table: String) throws -> Int {
      let statement = try database.prepare("SELECT COUNT(*) FROM \(table)")
      _ = try statement.step()
      return statement.int(at: 0) ?? 0
    }
    let cards = try count("cards")
    #expect(try count("cards_fts") == cards)
    #expect(try count("cards_name_fts") == cards)
  }

  private func buildCatalog(
    fixture: DeltaTestFixture,
    root: URL,
    tag: String
  ) async throws -> LocalBuildResult {
    let engineRoot = root.appendingPathComponent("engine-\(tag)", isDirectory: true)
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": engineRoot.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": engineRoot.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": engineRoot.appendingPathComponent("logs").path,
      "GRIMORA_CATALOG_PUBLIC_BASE_URL": "https://example.test/v1/catalog",
    ]
    let network = StubNetworkClient(responses: try fixture.responses())
    let engine = try GrimoraDataEngine(environment: environment, network: network)
    return try await engine.build(force: true)
  }
}

/// Related catalog snapshots. `versionB` differs from `versionA` by a price-only change (forest), a
/// non-price change (relic oracle text), a new card (isle), a deletion (ghost), and one appended
/// price day. `versionC` slides once more off `versionB` (forest price + one more price day), so
/// A→B→C exercises multi-step chain walking.
private enum DeltaTestFixture {
  case versionA
  case versionB
  case versionC

  var scryfallUpdatedAt: String {
    switch self {
    case .versionA: "2026-06-14T09:00:00.000+00:00"
    case .versionB: "2026-06-15T09:00:00.000+00:00"
    case .versionC: "2026-06-16T09:00:00.000+00:00"
    }
  }

  var mtgjsonDate: String {
    switch self {
    case .versionA: "2026-06-14"
    case .versionB: "2026-06-15"
    case .versionC: "2026-06-16"
    }
  }

  func responses() throws -> [URL: Data] {
    [
      BulkDataClient.bulkDataURL: bulkManifestJSON(),
      EngineFixtures.scryfallDownloadURL: defaultCardsJSON(),
      MTGJSONPriceHistoryClient.metaURL: metaJSON(),
      MTGJSONPriceHistoryClient.allPrintingsURL: try EngineFixtures.gzip(printingsJSON()),
      MTGJSONPriceHistoryClient.allPricesURL: try EngineFixtures.gzip(pricesJSON()),
    ]
  }

  private func bulkManifestJSON() -> Data {
    Data("""
      {
        "object": "list", "has_more": false,
        "data": [{
          "object": "bulk_data", "id": "bulk-default", "type": "default_cards",
          "updated_at": "\(scryfallUpdatedAt)",
          "uri": "https://api.scryfall.com/bulk-data/bulk-default",
          "name": "Default Cards", "description": "fixture", "size": 123,
          "download_uri": "\(EngineFixtures.scryfallDownloadURL.absoluteString)",
          "content_type": "application/json", "content_encoding": "gzip"
        }]
      }
      """.utf8)
  }

  private func defaultCardsJSON() -> Data {
    let forestPrice: String
    switch self {
    case .versionA: forestPrice = "0.50"
    case .versionB: forestPrice = "0.55"
    case .versionC: forestPrice = "0.60"
    }
    let relicOracle = self == .versionA ? "{T}: Add {C}." : "{T}: Add {C} or {W}."
    var cards = [
      """
      {"object":"card","id":"engine-forest","oracle_id":"oracle-engine-forest","name":"Engine Forest",
       "lang":"en","released_at":"2024-01-01","layout":"normal","cmc":1,"type_line":"Creature — Treefolk",
       "oracle_text":"Reach","power":"1","toughness":"2","colors":["G"],"color_identity":["G"],
       "keywords":["Reach"],"produced_mana":["G"],"legalities":{"commander":"legal"},"games":["paper"],
       "finishes":["nonfoil"],"foil":false,"nonfoil":true,"digital":false,"set":"eng",
       "set_name":"Engine Fixture Set","set_type":"expansion","collector_number":"1","rarity":"common",
       "prices":{"usd":"\(forestPrice)"},
       "image_uris":{"normal":"https://cards.scryfall.io/normal/front/e/f/engine-forest.jpg"}}
      """,
      """
      {"object":"card","id":"engine-relic","oracle_id":"oracle-engine-relic","name":"Engine Relic",
       "lang":"en","released_at":"2024-02-01","layout":"normal","cmc":2,"type_line":"Artifact",
       "oracle_text":"\(relicOracle)","colors":[],"color_identity":[],"games":["paper"],"digital":false,
       "set":"eng","set_name":"Engine Fixture Set","set_type":"expansion","collector_number":"2","rarity":"rare"}
      """,
    ]
    switch self {
    case .versionA:
      cards.append(
        """
        {"object":"card","id":"engine-ghost","oracle_id":"oracle-engine-ghost","name":"Engine Ghost",
         "lang":"en","released_at":"2024-03-01","layout":"normal","cmc":3,"type_line":"Creature — Spirit",
         "oracle_text":"Flying","power":"2","toughness":"2","colors":["W"],"color_identity":["W"],
         "games":["paper"],"digital":false,"set":"eng","set_name":"Engine Fixture Set",
         "set_type":"expansion","collector_number":"3","rarity":"uncommon"}
        """)
    case .versionB, .versionC:
      cards.append(
        """
        {"object":"card","id":"engine-isle","oracle_id":"oracle-engine-isle","name":"Engine Isle",
         "lang":"en","released_at":"2024-04-01","layout":"normal","cmc":0,"type_line":"Land",
         "oracle_text":"{T}: Add {U}.","colors":[],"color_identity":["U"],"games":["paper"],"digital":false,
         "set":"eng","set_name":"Engine Fixture Set","set_type":"expansion","collector_number":"4","rarity":"common"}
        """)
    }
    return Data("[\(cards.joined(separator: ","))]".utf8)
  }

  private func metaJSON() -> Data {
    Data("""
      {"meta": {"date": "\(mtgjsonDate)", "version": "5.3.0"}}
      """.utf8)
  }

  private func printingsJSON() -> Data {
    Data("""
      {"data": {"ENG": {"cards": [
        {"uuid": "uuid-engine-forest", "identifiers": {"scryfallId": "engine-forest"}}
      ]}}}
      """.utf8)
  }

  private func pricesJSON() -> Data {
    let days: String
    switch self {
    case .versionA:
      days = #""2026-06-13": 0.48, "2026-06-14": 0.50"#
    case .versionB:
      days = #""2026-06-13": 0.48, "2026-06-14": 0.50, "2026-06-15": 0.55"#
    case .versionC:
      days = #""2026-06-13": 0.48, "2026-06-14": 0.50, "2026-06-15": 0.55, "2026-06-16": 0.60"#
    }
    return Data("""
      {"data": {"uuid-engine-forest": {"paper": {"tcgplayer": {"retail": {"normal": {\(days)}}}}}}}
      """.utf8)
  }
}
