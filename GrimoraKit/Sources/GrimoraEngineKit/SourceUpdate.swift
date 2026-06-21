import Foundation
import GrimoraCore

/// The result of comparing the current upstream source versions against the last successful build,
/// broken down per data source so callers can see exactly what changed.
public struct CatalogUpdateCheck: Sendable, Equatable {
  /// The versions currently published by the upstream sources.
  public var current: CatalogSourceVersions
  /// The source versions baked into the last successful build, if any.
  public var lastBuilt: CatalogSourceVersions?

  public init(current: CatalogSourceVersions, lastBuilt: CatalogSourceVersions?) {
    self.current = current
    self.lastBuilt = lastBuilt
  }

  /// True when there is no prior build to compare against (everything is effectively new).
  public var hasPriorBuild: Bool { lastBuilt != nil }

  /// Scryfall card data changed since the last build (or there is no prior build).
  public var scryfallChanged: Bool {
    guard let lastBuilt else { return true }
    return lastBuilt.scryfallUpdatedAt != current.scryfallUpdatedAt
  }

  /// MTGJSON pricing data changed since the last build (or there is no prior build).
  public var mtgjsonChanged: Bool {
    guard let lastBuilt else { return true }
    return lastBuilt.mtgjsonDate != current.mtgjsonDate
      || lastBuilt.mtgjsonVersion != current.mtgjsonVersion
  }

  public var updateAvailable: Bool { scryfallChanged || mtgjsonChanged }
}
