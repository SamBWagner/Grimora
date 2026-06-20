import Foundation
import GrimoraCore

struct EngineConfiguration: Sendable {
  let stateDirectory: URL
  let cacheDirectory: URL
  let logDirectory: URL
  let buildsDirectory: URL
  let stateFile: URL
  let lockFile: URL
  let publicCatalogBaseURL: URL

  init(
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
    publicCatalogBaseURL = URL(
      string: environment["GRIMORA_CATALOG_PUBLIC_BASE_URL"]
        ?? "https://grimora-data-api.fly.dev/v1/catalog"
    )!

    for directory in [stateDirectory, cacheDirectory, logDirectory, buildsDirectory] {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }
}

struct EngineState: Codable, Equatable, Sendable {
  var lastSuccessfulSources: CatalogSourceVersions?
  var lastBuiltManifestPath: String?
  var lastPublishedVersion: String?
  var lastRunAt: Date?
  var lastError: String?

  static func load(from url: URL) -> EngineState {
    guard let data = try? Data(contentsOf: url),
      let state = try? Self.decoder.decode(EngineState.self, from: data)
    else {
      return EngineState()
    }
    return state
  }

  func save(to url: URL) throws {
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
