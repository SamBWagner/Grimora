import Foundation
import GrimoraCore

public struct EngineConfiguration: Sendable {
  public let stateDirectory: URL
  public let cacheDirectory: URL
  public let logDirectory: URL
  public let buildsDirectory: URL
  public let stateFile: URL
  public let lockFile: URL
  public let runHistoryFile: URL
  public let currentRunFile: URL
  public let publicCatalogBaseURL: URL
  /// How many build directories to keep on disk. Only the newest is actually required (it is the
  /// delta base for the next build); the rest are insurance, and each one costs ~600 MB.
  public let buildRetentionCount: Int
  /// How many `sources-<hash>` download caches to keep. Every real build mints a fresh ~900 MB
  /// cache — the hash covers the upstream version triple, which changes daily — so old ones are
  /// never reused.
  public let sourceCacheRetentionCount: Int

  public init(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws {
    let home = fileManager.homeDirectoryForCurrentUser
    stateDirectory = environment["GRIMORA_ENGINE_STATE_DIR"].map(URL.init(fileURLWithPath:))
      ?? home.appendingPathComponent("Library/Application Support/GrimoraDataEngine", isDirectory: true)
    cacheDirectory = environment["GRIMORA_ENGINE_CACHE_DIR"].map(URL.init(fileURLWithPath:))
      ?? home.appendingPathComponent("Library/Caches/GrimoraDataEngine", isDirectory: true)
    logDirectory = environment["GRIMORA_ENGINE_LOG_DIR"].map(URL.init(fileURLWithPath:))
      ?? home.appendingPathComponent("Library/Logs/GrimoraDataEngine", isDirectory: true)
    buildsDirectory = stateDirectory.appendingPathComponent("Builds", isDirectory: true)
    stateFile = stateDirectory.appendingPathComponent("state.json")
    lockFile = stateDirectory.appendingPathComponent("engine.lock")
    runHistoryFile = stateDirectory.appendingPathComponent("runs.json")
    currentRunFile = stateDirectory.appendingPathComponent("current-run.json")
    publicCatalogBaseURL = URL(
      string: environment["GRIMORA_CATALOG_PUBLIC_BASE_URL"]
        ?? "https://grimora-data-api.fly.dev/v1/catalog"
    )!
    buildRetentionCount = environment["GRIMORA_ENGINE_BUILD_RETENTION"]
      .flatMap(Int.init).map { max(1, $0) } ?? 3
    sourceCacheRetentionCount = environment["GRIMORA_ENGINE_SOURCE_CACHE_RETENTION"]
      .flatMap(Int.init).map { max(0, $0) } ?? 1

    for directory in [stateDirectory, cacheDirectory, logDirectory, buildsDirectory] {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }
}

public struct EngineState: Codable, Equatable, Sendable {
  public var lastSuccessfulSources: CatalogSourceVersions?
  public var lastBuiltManifestPath: String?
  public var lastPublishedVersion: String?
  public var lastRunAt: Date?
  public var lastError: String?

  public init(
    lastSuccessfulSources: CatalogSourceVersions? = nil,
    lastBuiltManifestPath: String? = nil,
    lastPublishedVersion: String? = nil,
    lastRunAt: Date? = nil,
    lastError: String? = nil
  ) {
    self.lastSuccessfulSources = lastSuccessfulSources
    self.lastBuiltManifestPath = lastBuiltManifestPath
    self.lastPublishedVersion = lastPublishedVersion
    self.lastRunAt = lastRunAt
    self.lastError = lastError
  }

  public static func load(from url: URL) -> EngineState {
    guard let data = try? Data(contentsOf: url),
      let state = try? Self.decoder.decode(EngineState.self, from: data)
    else {
      return EngineState()
    }
    return state
  }

  public func save(to url: URL) throws {
    let data = try Self.encoder.encode(self)
    try data.write(to: url, options: .atomic)
  }

  private static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  private static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
