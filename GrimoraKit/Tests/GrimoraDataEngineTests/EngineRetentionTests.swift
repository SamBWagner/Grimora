import CryptoKit
import Foundation
import GrimoraCore
import GrimoraEngineKit
import Testing

/// Retention keeps the engine's ~600 MB build directories and ~900 MB source caches from growing
/// without bound. These tests drive the sweep against a temp state directory seeded with fake build
/// directories, so they assert the policy — how many survive, and which — without running a build.
struct EngineRetentionTests {
  private struct Harness {
    var engine: GrimoraDataEngine
    var root: URL
    var builds: URL
    var caches: URL
    var stateFile: URL
  }

  private func makeHarness(
    buildRetention: Int,
    sourceCacheRetention: Int = 1
  ) throws -> Harness {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EngineRetentionTests-\(UUID().uuidString)", isDirectory: true)
    let environment = [
      "GRIMORA_ENGINE_STATE_DIR": root.appendingPathComponent("state").path,
      "GRIMORA_ENGINE_CACHE_DIR": root.appendingPathComponent("cache").path,
      "GRIMORA_ENGINE_LOG_DIR": root.appendingPathComponent("logs").path,
      "GRIMORA_ENGINE_BUILD_RETENTION": String(buildRetention),
      "GRIMORA_ENGINE_SOURCE_CACHE_RETENTION": String(sourceCacheRetention),
    ]
    let engine = try GrimoraDataEngine(
      environment: environment,
      network: StubNetworkClient(responses: [:])
    )
    return Harness(
      engine: engine,
      root: root,
      builds: engine.configuration.buildsDirectory,
      caches: engine.configuration.cacheDirectory,
      stateFile: engine.configuration.stateFile
    )
  }

  /// Writes a directory holding `bytes` of payload, back-dated so the sweep's newest-first sort is
  /// deterministic rather than dependent on how fast the test ran.
  @discardableResult
  private func makeDirectory(
    _ name: String,
    in parent: URL,
    ageInDays: Int,
    bytes: Int = 4096
  ) throws -> URL {
    let url = parent.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data(repeating: 0x41, count: bytes)
      .write(to: url.appendingPathComponent("catalog.sqlite"))
    let date = Date(timeIntervalSinceNow: -Double(ageInDays) * 86_400)
    try FileManager.default.setAttributes(
      [.creationDate: date, .modificationDate: date],
      ofItemAtPath: url.path
    )
    return url
  }

  private func writeState(
    _ harness: Harness,
    pinnedBuild: String?,
    sources: CatalogSourceVersions? = nil
  ) throws {
    var state = EngineState()
    state.lastPublishedVersion = pinnedBuild
    state.lastBuiltManifestPath = pinnedBuild.map {
      harness.builds.appendingPathComponent($0).appendingPathComponent("manifest.json").path
    }
    state.lastSuccessfulSources = sources
    try state.save(to: harness.stateFile)
  }

  private func names(in directory: URL) throws -> Set<String> {
    Set(
      try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ).map(\.lastPathComponent)
    )
  }

  @Test
  func keepsExactlyTheRetentionCountNewestFirst() async throws {
    let harness = try makeHarness(buildRetention: 3)
    defer { try? FileManager.default.removeItem(at: harness.root) }

    for day in 0..<6 {
      try makeDirectory("v1-day\(day)", in: harness.builds, ageInDays: day)
    }
    try writeState(harness, pinnedBuild: "v1-day0")

    let summary = try harness.engine.pruneArtifacts()

    #expect(try names(in: harness.builds) == ["v1-day0", "v1-day1", "v1-day2"])
    #expect(summary.keptBuilds == ["v1-day0", "v1-day1", "v1-day2"])
    #expect(Set(summary.prunedBuilds) == ["v1-day3", "v1-day4", "v1-day5"])
    #expect(summary.freedBytes > 0)
  }

  @Test
  func neverPrunesThePinnedVersionEvenWhenItIsTheOldest() async throws {
    let harness = try makeHarness(buildRetention: 2)
    defer { try? FileManager.default.removeItem(at: harness.root) }

    for day in 0..<5 {
      try makeDirectory("v1-day\(day)", in: harness.builds, ageInDays: day)
    }
    // The published/delta-base build is the oldest on disk — retention must still spare it.
    try writeState(harness, pinnedBuild: "v1-day4")

    let summary = try harness.engine.pruneArtifacts()

    #expect(try names(in: harness.builds) == ["v1-day0", "v1-day4"])
    #expect(summary.prunedBuilds.contains("v1-day4") == false)
    #expect(Set(summary.prunedBuilds) == ["v1-day1", "v1-day2", "v1-day3"])
  }

  @Test
  func pinnedVersionSurvivesARetentionCountOfOne() async throws {
    let harness = try makeHarness(buildRetention: 1)
    defer { try? FileManager.default.removeItem(at: harness.root) }

    try makeDirectory("v1-new", in: harness.builds, ageInDays: 0)
    try makeDirectory("v1-pinned", in: harness.builds, ageInDays: 9)
    try writeState(harness, pinnedBuild: "v1-pinned")

    _ = try harness.engine.pruneArtifacts()

    // The single slot goes to the pinned build; nothing else is retained.
    #expect(try names(in: harness.builds) == ["v1-pinned"])
  }

  @Test
  func isANoOpWhenUnderTheLimit() async throws {
    let harness = try makeHarness(buildRetention: 3, sourceCacheRetention: 2)
    defer { try? FileManager.default.removeItem(at: harness.root) }

    try makeDirectory("v1-new", in: harness.builds, ageInDays: 0)
    try makeDirectory("v1-old", in: harness.builds, ageInDays: 1)
    try makeDirectory("sources-abc", in: harness.caches, ageInDays: 0)
    try writeState(harness, pinnedBuild: "v1-new")

    let summary = try harness.engine.pruneArtifacts()

    #expect(summary.isEmpty)
    #expect(summary.freedBytes == 0)
    #expect(try names(in: harness.builds) == ["v1-new", "v1-old"])
    #expect(try names(in: harness.caches) == ["sources-abc"])
  }

  @Test
  func dryRunReportsWithoutDeleting() async throws {
    let harness = try makeHarness(buildRetention: 1)
    defer { try? FileManager.default.removeItem(at: harness.root) }

    for day in 0..<4 {
      try makeDirectory("v1-day\(day)", in: harness.builds, ageInDays: day, bytes: 8192)
    }
    try writeState(harness, pinnedBuild: "v1-day0")

    let summary = try harness.engine.pruneArtifacts(dryRun: true)

    #expect(summary.wasDryRun)
    #expect(Set(summary.prunedBuilds) == ["v1-day1", "v1-day2", "v1-day3"])
    #expect(summary.freedBytes > 0)
    #expect(try names(in: harness.builds).count == 4)
  }

  @Test
  func keepsTheSourceCacheTheLastSuccessfulBuildUsed() async throws {
    let harness = try makeHarness(buildRetention: 3, sourceCacheRetention: 1)
    defer { try? FileManager.default.removeItem(at: harness.root) }

    let sources = CatalogSourceVersions(
      scryfallUpdatedAt: "2026-08-09T21:07:33.171+00:00",
      mtgjsonDate: "2026-08-09",
      mtgjsonVersion: "5.3.0+20260809"
    )
    // The cache directory name is derived the same way the engine derives it when downloading.
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let digest = SHA256.hash(data: try encoder.encode(sources))
      .map { String(format: "%02x", $0) }.joined()
    let pinnedCache = "sources-\(digest.prefix(20))"

    try makeDirectory(pinnedCache, in: harness.caches, ageInDays: 5)
    try makeDirectory("sources-newer", in: harness.caches, ageInDays: 0)
    try makeDirectory("sources-oldest", in: harness.caches, ageInDays: 9)
    try writeState(harness, pinnedBuild: nil, sources: sources)

    let summary = try harness.engine.pruneArtifacts()

    #expect(try names(in: harness.caches) == [pinnedCache])
    #expect(Set(summary.prunedSourceCaches) == ["sources-newer", "sources-oldest"])
  }

  @Test
  func ignoresLooseFilesAndInterruptedBuildScratchDirectories() async throws {
    let harness = try makeHarness(buildRetention: 1)
    defer { try? FileManager.default.removeItem(at: harness.root) }

    try makeDirectory("v1-new", in: harness.builds, ageInDays: 0)
    try makeDirectory("v1-old", in: harness.builds, ageInDays: 1)
    // `cleanupInterruptedBuilds()` owns these, and a stray file is not a build.
    try makeDirectory(".building-abc", in: harness.builds, ageInDays: 2)
    try Data("scratch".utf8).write(to: harness.builds.appendingPathComponent("notes.txt"))
    try writeState(harness, pinnedBuild: "v1-new")

    let summary = try harness.engine.pruneArtifacts()

    #expect(summary.prunedBuilds == ["v1-old"])
    #expect(FileManager.default.fileExists(atPath: harness.builds.appendingPathComponent(".building-abc").path))
    #expect(FileManager.default.fileExists(atPath: harness.builds.appendingPathComponent("notes.txt").path))
  }
}
