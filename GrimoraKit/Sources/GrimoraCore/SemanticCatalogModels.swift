import Foundation

public struct SemanticCardKey: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(oracleID: String?, printingID: String) {
    if let oracleID, !oracleID.isEmpty {
      rawValue = "o:\(oracleID)"
    } else {
      rawValue = "p:\(printingID)"
    }
  }

  public var oracleID: String? {
    guard rawValue.hasPrefix("o:") else { return nil }
    return String(rawValue.dropFirst(2))
  }

  public var printingID: String? {
    guard rawValue.hasPrefix("p:") else { return nil }
    return String(rawValue.dropFirst(2))
  }
}

public struct SemanticTagRecord: Identifiable, Codable, Equatable, Sendable {
  public var id: String
  public var namespace: String
  public var slug: String
  public var label: String
  public var description: String?
  public var similarityEnabled: Bool
  public var source: String

  public init(
    id: String,
    namespace: String,
    slug: String,
    label: String,
    description: String?,
    similarityEnabled: Bool,
    source: String
  ) {
    self.id = id
    self.namespace = namespace
    self.slug = slug
    self.label = label
    self.description = description
    self.similarityEnabled = similarityEnabled
    self.source = source
  }
}

public struct SemanticTagAliasRecord: Codable, Equatable, Sendable {
  public var tagID: String
  public var alias: String
  public var aliasKey: String

  public init(tagID: String, alias: String, aliasKey: String) {
    self.tagID = tagID
    self.alias = alias
    self.aliasKey = aliasKey
  }

  public static func normalizedKey(for alias: String) -> String {
    let locale = Locale(identifier: "en_US_POSIX")
    return alias
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: locale
      )
      .lowercased(with: locale)
  }
}

public struct SemanticTagEdgeRecord: Codable, Equatable, Sendable {
  public var parentTagID: String
  public var childTagID: String

  public init(parentTagID: String, childTagID: String) {
    self.parentTagID = parentTagID
    self.childTagID = childTagID
  }
}

public struct SemanticCardTagRecord: Codable, Equatable, Sendable {
  public var cardKey: SemanticCardKey
  public var tagID: String
  public var weightMillis: Int
  public var annotation: String?
  public var source: String

  public init(
    cardKey: SemanticCardKey,
    tagID: String,
    weightMillis: Int,
    annotation: String?,
    source: String
  ) {
    self.cardKey = cardKey
    self.tagID = tagID
    self.weightMillis = weightMillis
    self.annotation = annotation
    self.source = source
  }
}

public struct SemanticTagStatsRecord: Codable, Equatable, Sendable {
  public var tagID: String
  public var directCardCount: Int
  public var effectiveCardCount: Int
  public var inverseFrequencyMillis: Int

  public init(
    tagID: String,
    directCardCount: Int,
    effectiveCardCount: Int,
    inverseFrequencyMillis: Int
  ) {
    self.tagID = tagID
    self.directCardCount = directCardCount
    self.effectiveCardCount = effectiveCardCount
    self.inverseFrequencyMillis = inverseFrequencyMillis
  }
}

public struct SemanticCatalogSnapshot: Codable, Equatable, Sendable {
  public var tags: [SemanticTagRecord]
  public var aliases: [SemanticTagAliasRecord]
  public var edges: [SemanticTagEdgeRecord]
  public var cardTags: [SemanticCardTagRecord]
  public var stats: [SemanticTagStatsRecord]

  public init(
    tags: [SemanticTagRecord],
    aliases: [SemanticTagAliasRecord],
    edges: [SemanticTagEdgeRecord],
    cardTags: [SemanticCardTagRecord],
    stats: [SemanticTagStatsRecord]
  ) {
    self.tags = tags
    self.aliases = aliases
    self.edges = edges
    self.cardTags = cardTags
    self.stats = stats
  }

  public static let empty = SemanticCatalogSnapshot(
    tags: [],
    aliases: [],
    edges: [],
    cardTags: [],
    stats: []
  )
}
