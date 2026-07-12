import Foundation

/// Namespace for delta-format constants shared by the engine (generation) and the client (apply).
public enum CatalogDelta {
  /// Bumped only when the patch-database schema changes in a way an older client can't apply. A
  /// client that encounters a `formatVersion` it doesn't recognize falls back to a full download.
  public static let currentFormatVersion = 1
}

/// Locates a single build-to-build delta artifact (`catalogs/<target>/delta-from-<base>.sqlite.gz`).
public struct CatalogDeltaDescriptor: Codable, Equatable, Sendable {
  /// The version this delta patches *from*. Applying it to a catalog at `baseVersion` yields the
  /// catalog for the enclosing ``CatalogChainEntry/version``.
  public var baseVersion: String
  /// Download URL for the gzipped patch database (an API URL that 302-redirects to storage).
  public var url: URL
  /// SHA-256 of the gzipped patch artifact, verified before it is decompressed.
  public var sha256: String
  /// Compressed size in bytes, used for the client's capacity precheck.
  public var bytes: Int64
  /// Patch-database schema version; see ``CatalogDelta/currentFormatVersion``.
  public var formatVersion: Int

  public init(
    baseVersion: String,
    url: URL,
    sha256: String,
    bytes: Int64,
    formatVersion: Int
  ) {
    self.baseVersion = baseVersion
    self.url = url
    self.sha256 = sha256
    self.bytes = bytes
    self.formatVersion = formatVersion
  }
}

/// One build in the retained chain. Carries the content digests a client verifies its patched
/// catalog against, plus (when available) the delta that reaches this build from its predecessor.
public struct CatalogChainEntry: Codable, Equatable, Sendable {
  public var version: String
  public var catalogSchemaVersion: Int
  public var contentDigests: CatalogContentDigests
  /// The delta from the previous entry in the chain. `nil` for the oldest retained entry, or when
  /// no consecutive delta could be produced (e.g. the previous build was pruned) — in which case a
  /// client sitting on an earlier version must fall back to a full download.
  public var deltaFromPrevious: CatalogDeltaDescriptor?

  public init(
    version: String,
    catalogSchemaVersion: Int,
    contentDigests: CatalogContentDigests,
    deltaFromPrevious: CatalogDeltaDescriptor?
  ) {
    self.version = version
    self.catalogSchemaVersion = catalogSchemaVersion
    self.contentDigests = contentDigests
    self.deltaFromPrevious = deltaFromPrevious
  }
}

/// The ordered chain of recent builds, published as a single mutable `chain.json` alongside
/// `current.json`. A client finds its installed version in `entries` and walks forward, applying
/// each `deltaFromPrevious`; if its version isn't present (too old / expired base), it full-downloads.
public struct CatalogChain: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  /// The newest version — the download target. Equals `entries.last?.version`.
  public var current: String
  /// Retained window, ordered oldest → newest.
  public var entries: [CatalogChainEntry]

  public init(
    schemaVersion: Int = CatalogChain.currentSchemaVersion,
    current: String,
    entries: [CatalogChainEntry]
  ) {
    self.schemaVersion = schemaVersion
    self.current = current
    self.entries = entries
  }

  public static func decoder() -> JSONDecoder {
    JSONDecoder()
  }

  public static func encoder(prettyPrinted: Bool = false) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    return encoder
  }

  /// The consecutive deltas a client on `installedVersion` must apply, in order, to reach
  /// ``current``. Returns `nil` when there is no complete, single-schema delta path — the caller
  /// must then fall back to a full download. An empty array means already up to date.
  public func deltaPath(from installedVersion: String) -> [CatalogDeltaDescriptor]? {
    guard let installedIndex = entries.firstIndex(where: { $0.version == installedVersion }) else {
      return nil
    }
    let installedSchema = entries[installedIndex].catalogSchemaVersion
    var path: [CatalogDeltaDescriptor] = []
    var index = installedIndex + 1
    while index < entries.count {
      let entry = entries[index]
      guard entry.catalogSchemaVersion == installedSchema,
        let delta = entry.deltaFromPrevious,
        delta.baseVersion == entries[index - 1].version,
        delta.formatVersion == CatalogDelta.currentFormatVersion
      else {
        return nil
      }
      path.append(delta)
      index += 1
    }
    return path
  }
}
