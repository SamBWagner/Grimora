import Foundation
import Testing
@testable import GrimoraCore

/// Opt-in end-to-end test against the LIVE deployed catalog API, using the exact client code the
/// shipping iOS app runs (`BulkDataClient` + real `URLSessionNetworkClient` + `CatalogDeltaApplier`).
/// Proves a new app build will interoperate with the newly deployed API before an App Store push.
///
/// Enable with `GRIMORA_PROD_API_TEST=1`. Optionally set `GRIMORA_DELTA_BASE_DIR` to a local
/// `Builds/<version>` matching the chain's delta base to also exercise the published delta. Downloads
/// real artifacts (~126 MB full + ~48 MB delta), so it never runs in CI.
struct ProdApiIntegrationTests {
  private static let apiURL = URL(string: "https://grimora-data-api.fly.dev/v1/catalog")!

  @Test
  func shippingClientInteroperatesWithDeployedAPI() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["GRIMORA_PROD_API_TEST"] == "1" else { return }

    let network = URLSessionNetworkClient()
    let client = BulkDataClient(network: network, catalogAPIURL: Self.apiURL)
    let work = FileManager.default.temporaryDirectory
      .appendingPathComponent("ProdApi-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }

    // 1. current.json parses in the shipping client as a Grimora catalog manifest with digests.
    let bulk = try await client.fetchDefaultCardsManifest()
    #expect(bulk.type == BulkDataManifest.grimoraCatalogType)
    let manifest = try #require(bulk.catalog, "current.json must carry a catalog payload")
    #expect(manifest.contentDigests != nil, "new API should publish content digests")
    print("[prod] current version:", manifest.version, "| digests:", manifest.contentDigests != nil)

    // 2. chain.json parses and points at the current version.
    let chain = try await client.fetchCatalogChain()
    #expect(chain.current == manifest.version)
    print("[prod] chain entries:", chain.entries.count)

    // 3. THE CRITICAL PATH: a full download + install over the real redirect→Tigris path. This is
    //    what every first install / upgrade-from-old-app hits.
    let fullGz = work.appendingPathComponent("catalog.sqlite.gz")
    try await client.downloadDefaultCards(manifest: bulk, to: fullGz, purpose: .bulkDownload)
    #expect(try FileSHA256.hash(url: fullGz) == manifest.artifact.sha256, "compressed SHA must match")
    let fullSQLite = work.appendingPathComponent("catalog.sqlite")
    try GzipArchive.decompressFile(at: fullGz, to: fullSQLite)
    #expect(try FileSHA256.hash(url: fullSQLite) == manifest.artifact.uncompressedSHA256)
    let counts = try CardDatabase.validateCatalog(at: fullSQLite, expectedManifest: manifest)
    #expect(counts == manifest.counts)
    // Attach it as the app would and confirm it's queryable.
    let db = try CardDatabase(
      userDatabaseURL: work.appendingPathComponent("user.sqlite"),
      catalogURL: fullSQLite
    )
    #expect(try db.cardCount() == manifest.counts.cards)
    print("[prod] full download + install OK:", counts.cards, "cards")

    // 4. If the local delta base is available, download the published delta over HTTP and apply it,
    //    proving the deployed delta artifact is consumable by the shipping applier.
    guard let baseDir = env["GRIMORA_DELTA_BASE_DIR"].map(URL.init(fileURLWithPath:)),
      let delta = chain.entries.last?.deltaFromPrevious
    else {
      print("[prod] (skipping delta apply — no GRIMORA_DELTA_BASE_DIR or no delta in chain)")
      return
    }
    let baseCatalog = baseDir.appendingPathComponent("catalog.sqlite")
    guard FileManager.default.fileExists(atPath: baseCatalog.path),
      baseDir.lastPathComponent.contains(delta.baseVersion)
    else {
      print("[prod] (skipping delta apply — base dir doesn't match delta base \(delta.baseVersion))")
      return
    }

    let deltaGz = work.appendingPathComponent("delta.sqlite.gz")
    try await client.downloadCatalogDelta(from: delta.url, to: deltaGz, purpose: .bulkDownload)
    #expect(try FileSHA256.hash(url: deltaGz) == delta.sha256, "delta SHA must match the chain")
    let deltaSQLite = work.appendingPathComponent("delta.sqlite")
    try GzipArchive.decompressFile(at: deltaGz, to: deltaSQLite)

    let working = work.appendingPathComponent("working.sqlite")
    try FileManager.default.copyItem(at: baseCatalog, to: working)
    try CatalogDeltaApplier().apply(deltaURL: deltaSQLite, toWorkingCatalog: working)
    let applied = try CatalogContentDigest.compute(SQLiteDatabase(storage: .readOnlyFile(working)))
    #expect(applied == manifest.contentDigests, "delta-applied base must reproduce target digests")
    print("[prod] published delta downloaded + applied → reproduces target: PASS")
  }
}
