import Foundation
import GrimoraCore
import GrimoraEngineKit
import Testing

/// Opt-in validation against real, machine-local engine builds. Point `GRIMORA_DELTA_BASE_DIR` and
/// `GRIMORA_DELTA_TARGET_DIR` at two `Builds/<version>` directories (each with `catalog.sqlite` +
/// `manifest.json`). It diffs the two real ~464 MB catalogs, applies the delta on top of the base,
/// and asserts the patched catalog equals the target by content digest — while reporting the real
/// compressed delta size vs. the full artifact. Skips (no-op) when the env vars aren't set, so it
/// never runs in CI.
struct RealDeltaValidationTests {
  @Test
  func realBuildDeltaAppliesAndShrinksDownload() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let baseDir = environment["GRIMORA_DELTA_BASE_DIR"].map(URL.init(fileURLWithPath:)),
      let targetDir = environment["GRIMORA_DELTA_TARGET_DIR"].map(URL.init(fileURLWithPath:))
    else {
      return
    }

    let baseCatalog = baseDir.appendingPathComponent("catalog.sqlite")
    let targetCatalog = targetDir.appendingPathComponent("catalog.sqlite")
    let baseManifest = try CatalogManifest.decoder().decode(
      CatalogManifest.self, from: Data(contentsOf: baseDir.appendingPathComponent("manifest.json")))
    let targetManifest = try CatalogManifest.decoder().decode(
      CatalogManifest.self, from: Data(contentsOf: targetDir.appendingPathComponent("manifest.json")))

    let work = FileManager.default.temporaryDirectory
      .appendingPathComponent("RealDelta-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }

    // 1. Generate the delta between the two real builds and compress it for transport.
    let deltaSQLite = work.appendingPathComponent("delta.sqlite")
    let stats = try CatalogDeltaBuilder().buildDelta(
      baseCatalogURL: baseCatalog,
      targetCatalogURL: targetCatalog,
      baseVersion: baseManifest.version,
      targetVersion: targetManifest.version,
      into: deltaSQLite
    )
    let deltaGz = work.appendingPathComponent("delta.sqlite.gz")
    try GzipArchive.compressFile(at: deltaSQLite, to: deltaGz)
    let deltaGzBytes =
      (try FileManager.default.attributesOfItem(atPath: deltaGz.path)[.size] as? NSNumber)?
      .int64Value ?? 0

    // 2. Apply on top of a copy of the base and verify it reproduces the target exactly.
    let working = work.appendingPathComponent("working.sqlite")
    try FileManager.default.copyItem(at: baseCatalog, to: working)
    try CatalogDeltaApplier().apply(deltaURL: deltaSQLite, toWorkingCatalog: working)

    let targetDigests = try CatalogContentDigest.compute(
      SQLiteDatabase(storage: .readOnlyFile(targetCatalog)))
    let workingDigests = try CatalogContentDigest.compute(
      SQLiteDatabase(storage: .readOnlyFile(working)))
    #expect(workingDigests == targetDigests)
    let counts = try CardDatabase.validateCatalog(at: working, expectedManifest: targetManifest)
    #expect(counts == targetManifest.counts)

    // 3. Report the real numbers.
    let fullBytes = targetManifest.artifact.compressedBytes
    let ratio = Double(fullBytes) / Double(max(deltaGzBytes, 1))
    func mb(_ bytes: Int64) -> String {
      ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    print(
      """

      ── Real delta validation ──────────────────────────────────────
      base    \(baseManifest.version)  (mtgjson \(baseManifest.sources.mtgjsonDate))
      target  \(targetManifest.version)  (mtgjson \(targetManifest.sources.mtgjsonDate))
      stats   priceUpd=\(stats.cardsPriceUpdated) upsert=\(stats.cardsUpserted) del=\(stats.cardsDeleted) \
      faces=\(stats.cardFacesReplacedCards) slide=\(stats.seriesSlid) replace=\(stats.seriesReplaced) \
      seriesDel=\(stats.seriesDeleted) map+=\(stats.mappingsUpserted) map-=\(stats.mappingsDeleted) meta=\(stats.metadataSet)
      delta   \(mb(deltaGzBytes))   vs full   \(mb(fullBytes))   →  \(String(format: "%.1f", ratio))× smaller
      digests match (cards, card_faces, series, summaries, mappings): PASS
      ───────────────────────────────────────────────────────────────

      """)
  }
}
