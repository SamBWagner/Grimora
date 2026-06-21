import CryptoKit
import Foundation
import GrimoraCore
import GrimoraDataPipeline

public enum EngineError: Error, CustomStringConvertible {
  case invalidCommand
  case missingArtifact(URL)
  case missingManifest(URL)
  case missingConfiguration(String)
  case missingTigrisCredentials
  case noLocalBuild

  public var description: String {
    switch self {
    case .noLocalBuild:
      "no local build is available to publish — run a build first"
    case .invalidCommand:
      """
      usage:
        grimora-data-engine check
        grimora-data-engine build [--force]
        grimora-data-engine publish <artifact>
        grimora-data-engine run [--force]
        grimora-data-engine status
      """
    case .missingArtifact(let url):
      "catalog artifact does not exist at \(url.path)"
    case .missingManifest(let url):
      "catalog manifest does not exist at \(url.path)"
    case .missingConfiguration(let name):
      "missing required configuration \(name)"
    case .missingTigrisCredentials:
      "Tigris credentials are missing from the environment and macOS Keychain"
    }
  }
}

/// Callback invoked as a run advances. Receives coarse phase plus pipeline stage detail.
public typealias EngineProgressHandler = @Sendable (EngineRunProgress) async -> Void

/// Orchestrates the catalog build/publish pipeline and records every run to disk so that any
/// observer (the CLI's launchd agent or the SwiftUI dashboard) sees the same history and live
/// progress in the shared engine state directory.
public struct GrimoraDataEngine {
  public let configuration: EngineConfiguration
  private let fileManager: FileManager
  private let environment: [String: String]
  private let network: NetworkClient

  public init(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    network: NetworkClient = URLSessionNetworkClient(
      userAgent: "GrimoraDataEngine/1.0"
    )
  ) throws {
    configuration = try EngineConfiguration(fileManager: fileManager, environment: environment)
    self.fileManager = fileManager
    self.environment = environment
    self.network = network
  }

  // MARK: - Read-only observation

  /// The last persisted single-run state (backwards-compatible `state.json`).
  public func loadState() -> EngineState {
    EngineState.load(from: configuration.stateFile)
  }

  /// All recorded runs, newest first.
  public func loadRunHistory() -> [EngineRunRecord] {
    RunHistoryStore(fileURL: configuration.runHistoryFile).all()
  }

  /// The currently in-flight run, if `current-run.json` is present. May be stale if a process
  /// crashed; cross-check with ``isRunning()``.
  public func currentRun() -> CurrentRunStatus? {
    CurrentRunStatusStore(fileURL: configuration.currentRunFile).read()
  }

  /// Whether another process currently holds the engine lock (i.e. a build is actually running).
  public func isRunning() -> Bool {
    do {
      let lock = try ProcessLock(url: configuration.lockFile)
      withExtendedLifetime(lock) {}
      return false
    } catch ProcessLockError.alreadyRunning {
      return true
    } catch {
      return false
    }
  }

  // MARK: - Commands

  /// Fetches the latest source versions and reports, per data source, whether they differ from the
  /// last successful build.
  public func checkForUpdate() async throws -> CatalogUpdateCheck {
    let sources = try await currentSources()
    let state = EngineState.load(from: configuration.stateFile)
    return CatalogUpdateCheck(current: sources, lastBuilt: state.lastSuccessfulSources)
  }

  /// Build + publish if sources changed (or `force`). Returns the recorded outcome.
  @discardableResult
  public func run(
    force: Bool,
    trigger: EngineRunTrigger = .cli,
    progress: EngineProgressHandler? = nil
  ) async throws -> EngineRunRecord.Outcome {
    let info = try await recordRun(operation: .run, trigger: trigger, userProgress: progress) { report in
      await report(EngineRunProgress(phase: .checking))
      let sources = try await currentSources()
      let state = EngineState.load(from: configuration.stateFile)
      guard force || state.lastSuccessfulSources != sources else {
        return RunResultInfo(
          outcome: .skippedUnchanged,
          publishedVersion: state.lastPublishedVersion,
          sourceVersions: sources,
          counts: nil
        )
      }
      let result = try await performBuild(sources: sources, force: force, report: report)
      try await performPublish(result: result, report: report)
      return RunResultInfo(
        outcome: .succeeded,
        publishedVersion: result.manifest.version,
        sourceVersions: sources,
        counts: result.manifest.counts
      )
    }
    return info.outcome
  }

  /// Build the catalog locally (no publish). Returns the local artifacts.
  @discardableResult
  public func build(
    force: Bool,
    trigger: EngineRunTrigger = .cli,
    progress: EngineProgressHandler? = nil
  ) async throws -> LocalBuildResult {
    var built: LocalBuildResult?
    _ = try await recordRun(operation: .build, trigger: trigger, userProgress: progress) { report in
      await report(EngineRunProgress(phase: .checking))
      let sources = try await currentSources()
      let result = try await performBuild(sources: sources, force: force, report: report)
      built = result
      return RunResultInfo(
        outcome: .succeeded,
        publishedVersion: nil,
        sourceVersions: sources,
        counts: result.manifest.counts
      )
    }
    return built!
  }

  /// The most recent successful local build still present on disk, if any. Useful for inspecting
  /// the catalog (e.g. `catalog.sqlite` in the build directory) before publishing.
  public func lastLocalBuild() -> LocalBuildResult? {
    let state = EngineState.load(from: configuration.stateFile)
    guard let manifestPath = state.lastBuiltManifestPath else { return nil }
    let directory = URL(fileURLWithPath: manifestPath).deletingLastPathComponent()
    return try? LocalBuildResult.load(directory: directory)
  }

  /// Publishes the most recent local build. Throws `EngineError.noLocalBuild` if none exists.
  public func publishLastBuild(
    trigger: EngineRunTrigger = .cli,
    progress: EngineProgressHandler? = nil
  ) async throws {
    guard let build = lastLocalBuild() else {
      throw EngineError.noLocalBuild
    }
    try await publish(build.directory, trigger: trigger, progress: progress)
  }

  /// Publish a previously built artifact (or its containing directory).
  public func publish(
    _ argument: URL,
    trigger: EngineRunTrigger = .cli,
    progress: EngineProgressHandler? = nil
  ) async throws {
    let result = try LocalBuildResult.load(argument: argument)
    _ = try await recordRun(operation: .publish, trigger: trigger, userProgress: progress) { report in
      try await performPublish(result: result, report: report)
      return RunResultInfo(
        outcome: .succeeded,
        publishedVersion: result.manifest.version,
        sourceVersions: result.manifest.sources,
        counts: result.manifest.counts
      )
    }
  }

  // MARK: - Recording

  private struct RunResultInfo {
    var outcome: EngineRunRecord.Outcome
    var publishedVersion: String?
    var sourceVersions: CatalogSourceVersions?
    var counts: CatalogCounts?
  }

  /// Acquires the process lock, writes live progress to `current-run.json`, and appends a record to
  /// `runs.json` on completion (success or failure) so every execution path stays observable.
  private func recordRun(
    operation: EngineRunRecord.Operation,
    trigger: EngineRunTrigger,
    userProgress: EngineProgressHandler?,
    body: (_ report: @escaping EngineProgressHandler) async throws -> RunResultInfo
  ) async throws -> RunResultInfo {
    let lock = try ProcessLock(url: configuration.lockFile)
    defer { withExtendedLifetime(lock) {} }
    try cleanupInterruptedBuilds()

    let runID = UUID()
    let startedAt = Date()
    let history = RunHistoryStore(fileURL: configuration.runHistoryFile)
    let current = CurrentRunStatusStore(fileURL: configuration.currentRunFile)

    let report: EngineProgressHandler = { progress in
      current.write(
        CurrentRunStatus(
          runID: runID,
          trigger: trigger,
          operation: operation,
          startedAt: startedAt,
          progress: progress,
          updatedAt: Date()
        )
      )
      await userProgress?(progress)
    }

    do {
      let info = try await body(report)
      history.append(
        EngineRunRecord(
          id: runID,
          trigger: trigger,
          operation: operation,
          startedAt: startedAt,
          finishedAt: Date(),
          outcome: info.outcome,
          publishedVersion: info.publishedVersion,
          sourceVersions: info.sourceVersions,
          counts: info.counts,
          error: nil
        )
      )
      current.clear()
      return info
    } catch {
      history.append(
        EngineRunRecord(
          id: runID,
          trigger: trigger,
          operation: operation,
          startedAt: startedAt,
          finishedAt: Date(),
          outcome: .failed,
          publishedVersion: nil,
          sourceVersions: nil,
          counts: nil,
          error: String(describing: error)
        )
      )
      current.clear()
      throw error
    }
  }

  // MARK: - Core pipeline

  private func performBuild(
    sources: CatalogSourceVersions,
    force: Bool,
    report: @escaping EngineProgressHandler
  ) async throws -> LocalBuildResult {
    let state = EngineState.load(from: configuration.stateFile)
    if !force,
      state.lastSuccessfulSources == sources,
      let manifestPath = state.lastBuiltManifestPath
    {
      let existingDirectory = URL(fileURLWithPath: manifestPath).deletingLastPathComponent()
      if let result = try? LocalBuildResult.load(directory: existingDirectory) {
        return result
      }
    }

    let workingDirectory = configuration.buildsDirectory
      .appendingPathComponent(".building-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    do {
      await report(EngineRunProgress(phase: .downloading))
      let inputs = try await downloadInputs(sources: sources, report: report)
      let databaseURL = workingDirectory.appendingPathComponent("catalog.sqlite")
      let pipelineResult = try await CatalogPipeline().build(
        inputs: inputs,
        databaseURL: databaseURL,
        temporaryDirectory: workingDirectory.appendingPathComponent("Temporary", isDirectory: true)
      ) { progress in
        await report(
          EngineRunProgress(
            phase: .building,
            stage: progress.stage.rawValue,
            completed: progress.completed,
            total: progress.total
          )
        )
      }
      let artifactURL = workingDirectory.appendingPathComponent("catalog.sqlite.gz")
      try GzipArchive.compressFile(at: databaseURL, to: artifactURL)
      let compressedSHA256 = try sha256(artifactURL)
      let version = try CatalogVersioning.contentVersion(
        sources: sources,
        enrichments: pipelineResult.enrichments,
        artifactSHA256: compressedSHA256
      )
      let artifact = CatalogArtifact(
        downloadURL: configuration.publicCatalogBaseURL.appendingPathComponent(version),
        compressedBytes: try fileSize(artifactURL),
        uncompressedBytes: try fileSize(databaseURL),
        sha256: compressedSHA256,
        uncompressedSHA256: try sha256(databaseURL)
      )
      let manifest = CatalogManifest(
        version: version,
        generatedAt: Date(),
        sources: sources,
        enrichments: pipelineResult.enrichments,
        artifact: artifact,
        counts: pipelineResult.counts
      )
      let manifestURL = workingDirectory.appendingPathComponent("manifest.json")
      try CatalogManifest.encoder(prettyPrinted: true).encode(manifest)
        .write(to: manifestURL, options: .atomic)
      _ = try CardDatabase.validateCatalog(at: databaseURL, expectedManifest: manifest)

      let finalDirectory = configuration.buildsDirectory.appendingPathComponent(
        version,
        isDirectory: true
      )
      if fileManager.fileExists(atPath: finalDirectory.path) {
        try fileManager.removeItem(at: finalDirectory)
      }
      try fileManager.moveItem(at: workingDirectory, to: finalDirectory)
      let finalManifest = finalDirectory.appendingPathComponent("manifest.json")
      var state = EngineState.load(from: configuration.stateFile)
      state.lastSuccessfulSources = sources
      state.lastBuiltManifestPath = finalManifest.path
      state.lastRunAt = Date()
      state.lastError = nil
      try state.save(to: configuration.stateFile)
      return try LocalBuildResult.load(directory: finalDirectory)
    } catch {
      var state = EngineState.load(from: configuration.stateFile)
      state.lastRunAt = Date()
      state.lastError = String(describing: error)
      try? state.save(to: configuration.stateFile)
      throw error
    }
  }

  private func performPublish(
    result: LocalBuildResult,
    report: @escaping EngineProgressHandler
  ) async throws {
    await report(EngineRunProgress(phase: .publishing))
    let publisher = TigrisPublisher(
      configuration: try TigrisConfiguration(environment: environment)
    )
    try await publisher.publish(
      manifest: result.manifest,
      artifactURL: result.artifactURL,
      manifestURL: result.manifestURL,
      progress: { fraction, label in
        await report(
          EngineRunProgress(
            phase: .publishing,
            detail: label,
            completed: Int((fraction * 1000).rounded()),
            total: 1000
          )
        )
      }
    )
    var state = EngineState.load(from: configuration.stateFile)
    state.lastPublishedVersion = result.manifest.version
    state.lastRunAt = Date()
    state.lastError = nil
    try state.save(to: configuration.stateFile)
  }

  private func currentSources() async throws -> CatalogSourceVersions {
    let scryfall = try await BulkDataClient(network: network).fetchDefaultCardsManifest()
    let mtgjson = try await MTGJSONPriceHistoryClient(network: network).fetchMeta()
    return CatalogSourceVersions(
      scryfallUpdatedAt: scryfall.updatedAt,
      mtgjsonDate: mtgjson.date,
      mtgjsonVersion: mtgjson.version
    )
  }

  private func downloadInputs(
    sources: CatalogSourceVersions,
    report: @escaping EngineProgressHandler
  ) async throws -> CatalogBuildInputs {
    let sourceDirectory = configuration.cacheDirectory
      .appendingPathComponent(try sourceCacheVersion(sources: sources), isDirectory: true)
    try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

    func downloadReporter(_ label: String) -> @Sendable (NetworkDownloadProgress) async -> Void {
      { progress in
        await report(
          EngineRunProgress(
            phase: .downloading,
            detail: label,
            completed: Int(clamping: progress.completedBytes),
            total: progress.totalBytes.map { Int(clamping: $0) }
          )
        )
      }
    }

    let scryfallManifest = try await BulkDataClient(network: network).fetchDefaultCardsManifest()
    let scryfallURL = sourceDirectory.appendingPathComponent("scryfall-default-cards.json")
    let identifiersURL = sourceDirectory.appendingPathComponent("mtgjson-identifiers.json.gz")
    let pricesURL = sourceDirectory.appendingPathComponent("mtgjson-prices.json.gz")
    if !fileManager.fileExists(atPath: scryfallURL.path) {
      try await BulkDataClient(network: network)
        .downloadDefaultCards(
          manifest: scryfallManifest,
          to: scryfallURL,
          progress: downloadReporter("Scryfall card data")
        )
    }
    let mtgjsonClient = MTGJSONPriceHistoryClient(network: network)
    if !fileManager.fileExists(atPath: identifiersURL.path) {
      try await mtgjsonClient.downloadAllPrintings(
        to: identifiersURL,
        progress: downloadReporter("MTGJSON card identifiers")
      )
    }
    if !fileManager.fileExists(atPath: pricesURL.path) {
      try await mtgjsonClient.downloadAllPrices(
        to: pricesURL,
        progress: downloadReporter("MTGJSON pricing data")
      )
    }
    return CatalogBuildInputs(
      scryfallJSONURL: scryfallURL,
      mtgjsonIdentifiersGzipURL: identifiersURL,
      mtgjsonPricesGzipURL: pricesURL,
      sources: sources
    )
  }

  private func cleanupInterruptedBuilds() throws {
    for url in try fileManager.contentsOfDirectory(
      at: configuration.buildsDirectory,
      includingPropertiesForKeys: nil
    ) where url.lastPathComponent.hasPrefix(".building-") {
      try fileManager.removeItem(at: url)
    }
  }

  private func sourceCacheVersion(sources: CatalogSourceVersions) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(sources)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return "sources-\(digest.prefix(20))"
  }

  private func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
      if data.isEmpty {
        break
      }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func fileSize(_ url: URL) throws -> Int64 {
    let value = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
    return value?.int64Value ?? 0
  }
}

public enum CatalogVersioning {
  public static func contentVersion(
    sources: CatalogSourceVersions,
    enrichments: [CatalogEnrichmentVersion],
    artifactSHA256: String,
    pipelineVersion: Int = CatalogPipeline.currentVersion
  ) throws -> String {
    let identity = CatalogBuildIdentity(
      catalogSchemaVersion: CatalogManifest.currentSchemaVersion,
      pipelineVersion: pipelineVersion,
      sources: sources,
      enrichments: enrichments,
      artifactSHA256: artifactSHA256
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(identity)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return "v\(CatalogManifest.currentSchemaVersion)-\(digest.prefix(20))"
  }
}

private struct CatalogBuildIdentity: Encodable {
  var catalogSchemaVersion: Int
  var pipelineVersion: Int
  var sources: CatalogSourceVersions
  var enrichments: [CatalogEnrichmentVersion]
  var artifactSHA256: String
}

public struct LocalBuildResult: Sendable {
  public var directory: URL
  public var artifactURL: URL
  public var manifestURL: URL
  public var manifest: CatalogManifest

  static func load(argument: URL) throws -> LocalBuildResult {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: argument.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      return try load(directory: argument)
    }
    guard FileManager.default.fileExists(atPath: argument.path) else {
      throw EngineError.missingArtifact(argument)
    }
    return try load(directory: argument.deletingLastPathComponent())
  }

  static func load(directory: URL) throws -> LocalBuildResult {
    let artifactURL = directory.appendingPathComponent("catalog.sqlite.gz")
    let manifestURL = directory.appendingPathComponent("manifest.json")
    guard FileManager.default.fileExists(atPath: artifactURL.path) else {
      throw EngineError.missingArtifact(artifactURL)
    }
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      throw EngineError.missingManifest(manifestURL)
    }
    let manifest = try CatalogManifest.decoder()
      .decode(CatalogManifest.self, from: Data(contentsOf: manifestURL))
    return LocalBuildResult(
      directory: directory,
      artifactURL: artifactURL,
      manifestURL: manifestURL,
      manifest: manifest
    )
  }
}
