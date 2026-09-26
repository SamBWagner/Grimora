import Foundation
import GrimoraCore

public enum ScryfallOracleTagsSemanticEnrichmentError: Error, Equatable, Sendable {
  case missingSourceIdentity
  case emptySource
  case invalidTagObject(String)
  case duplicateTagID(String)
  case orphanHierarchyEdge(parent: String, child: String)
  case cyclicHierarchy
}

public struct ScryfallOracleTagsSemanticEnrichmentStage: CatalogEnrichmentStage {
  public static let identifier = "scryfall-oracle-tags"
  public static let version = 2

  public let oracleTagsJSONLURL: URL
  public let sourceUpdatedAt: String

  public var identifier: String { Self.identifier }
  public var version: Int { Self.version }

  public init(
    oracleTagsJSONLURL: URL,
    sourceUpdatedAt: String
  ) {
    self.oracleTagsJSONLURL = oracleTagsJSONLURL
    self.sourceUpdatedAt = sourceUpdatedAt
  }

  public func enrich(database: CardDatabase) async throws {
    guard !sourceUpdatedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ScryfallOracleTagsSemanticEnrichmentError.missingSourceIdentity
    }
    if try oracleTagsJSONLURL.resourceValues(forKeys: [.fileSizeKey]).fileSize == 0 {
      throw ScryfallOracleTagsSemanticEnrichmentError.emptySource
    }

    var accumulator = OracleTagsSemanticAccumulator(
      source: "scryfall-oracle-tags@\(sourceUpdatedAt)"
    )
    try await ScryfallOracleTagStreamScanner.scan(url: oracleTagsJSONLURL) { tag in
      try accumulator.consume(tag)
    }
    let validCardKeys = try database.semanticCardIdentityKeys()
    try database.replaceSemanticCatalog(
      with: accumulator.snapshot(validCardKeys: validCardKeys)
    )
  }
}

private struct OracleTagsSemanticAccumulator {
  private struct TagDraft {
    var id: String
    var namespace: String
    var slug: String
    var label: String
    var description: String?
  }

  private struct Edge: Hashable {
    var parent: String
    var child: String
  }

  private struct AliasIdentity: Hashable {
    var tagID: String
    var aliasKey: String
  }

  private struct MembershipIdentity: Hashable {
    var cardKey: SemanticCardKey
    var tagID: String
  }

  private var tagsByID: [String: TagDraft] = [:]
  private var aliasesByIdentity: [AliasIdentity: SemanticTagAliasRecord] = [:]
  private var edges: Set<Edge> = []
  private var membershipsByIdentity: [MembershipIdentity: SemanticCardTagRecord] = [:]
  private let source: String

  init(source: String) {
    self.source = source
  }

  mutating func consume(_ dto: ScryfallOracleTagDTO) throws {
    guard dto.object == "tag" else {
      throw ScryfallOracleTagsSemanticEnrichmentError.invalidTagObject(dto.object)
    }
    let id = dto.id.semanticTrimmed
    guard tagsByID[id] == nil else {
      throw ScryfallOracleTagsSemanticEnrichmentError.duplicateTagID(id)
    }
    tagsByID[id] = TagDraft(
      id: id,
      namespace: dto.type.semanticTrimmed,
      slug: dto.slug.semanticTrimmed,
      label: dto.label.semanticTrimmed,
      description: dto.description?.semanticTrimmed.nilIfEmpty
    )

    for alias in dto.aliases {
      let display = alias.semanticTrimmed
      let key = SemanticTagAliasRecord.normalizedKey(for: display)
      let identity = AliasIdentity(tagID: id, aliasKey: key)
      let candidate = SemanticTagAliasRecord(
        tagID: id,
        alias: display,
        aliasKey: key
      )
      if let existing = aliasesByIdentity[identity] {
        aliasesByIdentity[identity] = existing.alias <= candidate.alias ? existing : candidate
      } else {
        aliasesByIdentity[identity] = candidate
      }
    }

    for parentID in dto.parentIDs {
      edges.insert(Edge(parent: parentID.semanticTrimmed, child: id))
    }
    for childID in dto.childIDs {
      edges.insert(Edge(parent: id, child: childID.semanticTrimmed))
    }

    for tagging in dto.taggings {
      let cardKey = SemanticCardKey(rawValue: "o:\(tagging.oracleID.semanticTrimmed)")
      let identity = MembershipIdentity(cardKey: cardKey, tagID: id)
      let candidate = SemanticCardTagRecord(
        cardKey: cardKey,
        tagID: id,
        weightMillis: Self.weightMillis(tagging.weight),
        annotation: tagging.annotation?.semanticTrimmed.nilIfEmpty,
        source: source
      )
      if let existing = membershipsByIdentity[identity] {
        membershipsByIdentity[identity] = Self.preferredMembership(existing, candidate)
      } else {
        membershipsByIdentity[identity] = candidate
      }
    }
  }

  func snapshot(validCardKeys: Set<SemanticCardKey>) throws -> SemanticCatalogSnapshot {
    guard !tagsByID.isEmpty else {
      throw ScryfallOracleTagsSemanticEnrichmentError.emptySource
    }
    let tagIDs = Set(tagsByID.keys)
    var childrenByParent: [String: Set<String>] = [:]
    for edge in edges {
      guard tagIDs.contains(edge.parent), tagIDs.contains(edge.child) else {
        throw ScryfallOracleTagsSemanticEnrichmentError.orphanHierarchyEdge(
          parent: edge.parent,
          child: edge.child
        )
      }
      childrenByParent[edge.parent, default: []].insert(edge.child)
    }
    try validateAcyclic(tagIDs: tagIDs, childrenByParent: childrenByParent)

    let memberships = membershipsByIdentity.values.filter {
      validCardKeys.contains($0.cardKey)
    }
    let disabledTagIDs = similarityDisabledTagIDs(childrenByParent: childrenByParent)
    let directCardsByTag = Dictionary(grouping: memberships, by: \.tagID)
      .mapValues { Set($0.map(\.cardKey)) }
    let allCards = Set(memberships.map(\.cardKey))
    var effectiveMemo: [String: Set<SemanticCardKey>] = [:]

    func effectiveCards(for tagID: String) -> Set<SemanticCardKey> {
      if let cached = effectiveMemo[tagID] {
        return cached
      }
      var result = directCardsByTag[tagID, default: []]
      for childID in childrenByParent[tagID, default: []] {
        result.formUnion(effectiveCards(for: childID))
      }
      effectiveMemo[tagID] = result
      return result
    }

    let tags = tagsByID.values.map { tag in
      SemanticTagRecord(
        id: tag.id,
        namespace: tag.namespace,
        slug: tag.slug,
        label: tag.label,
        description: tag.description,
        similarityEnabled: !disabledTagIDs.contains(tag.id),
        source: source
      )
    }.sorted { $0.id < $1.id }

    let statistics = tags.map { tag in
      let directCount = directCardsByTag[tag.id, default: []].count
      let effectiveCount = effectiveCards(for: tag.id).count
      let idfMillis: Int
      if tag.similarityEnabled {
        let numerator = Double(allCards.count + 1)
        let denominator = Double(effectiveCount + 1)
        idfMillis = max(0, Int(((log(numerator / denominator) + 1) * 1_000).rounded()))
      } else {
        idfMillis = 0
      }
      return SemanticTagStatsRecord(
        tagID: tag.id,
        directCardCount: directCount,
        effectiveCardCount: effectiveCount,
        inverseFrequencyMillis: idfMillis
      )
    }

    return SemanticCatalogSnapshot(
      tags: tags,
      aliases: aliasesByIdentity.values.sorted {
        ($0.tagID, $0.aliasKey) < ($1.tagID, $1.aliasKey)
      },
      edges: edges.map {
        SemanticTagEdgeRecord(parentTagID: $0.parent, childTagID: $0.child)
      }.sorted {
        ($0.parentTagID, $0.childTagID) < ($1.parentTagID, $1.childTagID)
      },
      cardTags: memberships.sorted {
        ($0.cardKey.rawValue, $0.tagID, $0.source)
          < ($1.cardKey.rawValue, $1.tagID, $1.source)
      },
      stats: statistics
    )
  }

  private func similarityDisabledTagIDs(
    childrenByParent: [String: Set<String>]
  ) -> Set<String> {
    let roots = Set(tagsByID.values.filter {
      ["card-names", "cycle"].contains($0.slug)
    }.map(\.id))
    var disabled: Set<String> = []
    var pending = Array(roots)
    while let next = pending.popLast() {
      guard disabled.insert(next).inserted else { continue }
      pending.append(contentsOf: childrenByParent[next, default: []])
    }
    return disabled
  }

  private func validateAcyclic(
    tagIDs: Set<String>,
    childrenByParent: [String: Set<String>]
  ) throws {
    var visiting: Set<String> = []
    var visited: Set<String> = []

    func visit(_ tagID: String) throws {
      if visited.contains(tagID) { return }
      guard visiting.insert(tagID).inserted else {
        throw ScryfallOracleTagsSemanticEnrichmentError.cyclicHierarchy
      }
      for childID in childrenByParent[tagID, default: []] {
        try visit(childID)
      }
      visiting.remove(tagID)
      visited.insert(tagID)
    }

    for tagID in tagIDs {
      try visit(tagID)
    }
  }

  private static func preferredMembership(
    _ lhs: SemanticCardTagRecord,
    _ rhs: SemanticCardTagRecord
  ) -> SemanticCardTagRecord {
    if lhs.weightMillis != rhs.weightMillis {
      return lhs.weightMillis > rhs.weightMillis ? lhs : rhs
    }
    return (lhs.annotation ?? "") <= (rhs.annotation ?? "") ? lhs : rhs
  }

  private static func weightMillis(_ weight: ScryfallOracleTaggingWeight) -> Int {
    switch weight {
    case .weak: 500
    case .median: 1_000
    case .strong: 1_500
    case .veryStrong: 2_000
    }
  }
}

private extension String {
  var semanticTrimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
