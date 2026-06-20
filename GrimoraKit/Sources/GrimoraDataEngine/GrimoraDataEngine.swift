import CryptoKit
import Foundation
import GrimoraCore
import GrimoraDataPipeline

enum EngineError: Error, CustomStringConvertible {
  case invalidCommand
  case missingArtifact(URL)
  case missingManifest(URL)
  case missingConfiguration(String)
  case missingTigrisCredentials

  var description: String {
    switch self {
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

struct GrimoraDataEngine {
  private let configuration: EngineConfiguration
  private let fileManager: FileManager
  private let environment: [String: String]
  private let network: NetworkClient

  init(
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

  func execute(arguments: [String]) async throws {
    guard let command = arguments.first else {
      throw EngineError.invalidCommand
    }
    let lock = try ProcessLock(url: configuration.lockFile)
    defer { withExtendedLifetime(lock) {} }
    try cleanupInterruptedBuilds()

    switch command {
    case "check":
      let sources = try await currentSources()
      let state = EngineState.load(from: configuration.stateFile)
      print(state.lastSuccessfulSources == sources ? "unchanged" : "update available")
      print(try jsonString(sources))
    case "build":
      let result = try await build(force: arguments.contains("--force"))
      print(result.manifestURL.path)
    case "publish":
      guard arguments.count == 2 else {
        throw EngineError.invalidCommand
      }
      try await publish(URL(fileURLWithPath: arguments[1]))
    case "run":
      try await run(force: arguments.contains("--force"))
    case "status":
      print(try jsonString(EngineState.load(from: configuration.stateFile)))
    default:
      throw EngineError.invalidCommand
    }
  }

  private func run(force: Bool) async throws {
    let sources = try await currentSources()
    let state = EngineState.load(from: configuration.stateFile)
    guard force || state.lastSuccessfulSources != sources else {
      print("sources unchanged")
      return
    }
    let result = try await build(sources: sources, force: force)
    try await publish(result.artifactURL)
  }

  private func build(force: Bool) async throws -> LocalBuildResult {
    let sources = try await currentSources()
    return try await build(sources: sources, force: force)
  }

  private func build(
    sources: CatalogSourceVersions,
    force: Bool
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
      let inputs = try await downloadInputs(sources: sources)
      let databaseURL = workingDirectory.appendingPathComponent("catalog.sqlite")
      let pipelineResult = try await CatalogPipeline().build(
        inputs: inputs,
        databaseURL: databaseURL,
        temporaryDirectory: workingDirectory.appendingPathComponent("Temporary", isDirectory: true)
      ) { progress in
        print("[\(progress.stage.rawValue)] \(progress.completed)")
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

  private func publish(_ argument: URL) async throws {
    let result = try LocalBuildResult.load(argument: argument)
    let publisher = TigrisPublisher(
      configuration: try TigrisConfiguration(environment: environment)
    )
    try await publisher.publish(
      manifest: result.manifest,
      artifactURL: result.artifactURL,
      manifestURL: result.manifestURL
    )
    var state = EngineState.load(from: configuration.stateFile)
    state.lastPublishedVersion = result.manifest.version
    state.lastRunAt = Date()
    state.lastError = nil
    try state.save(to: configuration.stateFile)
    print("published \(result.manifest.version)")
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

  private func downloadInputs(sources: CatalogSourceVersions) async throws -> CatalogBuildInputs {
    let sourceDirectory = configuration.cacheDirectory
      .appendingPathComponent(try sourceCacheVersion(sources: sources), isDirectory: true)
    try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

    let scryfallManifest = try await BulkDataClient(network: network).fetchDefaultCardsManifest()
    let scryfallURL = sourceDirectory.appendingPathComponent("scryfall-default-cards.json")
    let identifiersURL = sourceDirectory.appendingPathComponent("mtgjson-identifiers.json.gz")
    let pricesURL = sourceDirectory.appendingPathComponent("mtgjson-prices.json.gz")
    if !fileManager.fileExists(atPath: scryfallURL.path) {
      try await BulkDataClient(network: network)
        .downloadDefaultCards(manifest: scryfallManifest, to: scryfallURL)
    }
    let mtgjsonClient = MTGJSONPriceHistoryClient(network: network)
    if !fileManager.fileExists(atPath: identifiersURL.path) {
      try await mtgjsonClient.downloadAllPrintings(to: identifiersURL)
    }
    if !fileManager.fileExists(atPath: pricesURL.path) {
      try await mtgjsonClient.downloadAllPrices(to: pricesURL)
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

  private func jsonString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}

enum CatalogVersioning {
  static func contentVersion(
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

private struct LocalBuildResult {
  var directory: URL
  var artifactURL: URL
  var manifestURL: URL
  var manifest: CatalogManifest

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
