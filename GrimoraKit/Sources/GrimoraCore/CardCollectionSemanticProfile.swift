import Crypto
import Foundation

/// Version 1 measures semantic presence, never copies or card quality. Mainboard is active;
/// commander is active only for the Commander ruleset. Supplemental zones require opt-in.
/// Unsupported stored zones are excluded rather than normalized into active deck cards.
public struct CardCollectionSemanticPolicy: Equatable, Sendable {
  public let includesSideboard: Bool
  public let includesMaybeboard: Bool
  public let explanationLimit: Int

  public init(
    includesSideboard: Bool = false, includesMaybeboard: Bool = false, explanationLimit: Int = 6
  ) {
    self.includesSideboard = includesSideboard
    self.includesMaybeboard = includesMaybeboard
    self.explanationLimit = max(1, explanationLimit)
  }

  func includes(_ zone: CardCollectionZone, ruleset: CardCollectionRuleset) -> Bool {
    switch zone {
    case .mainboard: true
    case .commander: ruleset == .commander && ruleset.allowedZones.contains(.commander)
    case .sideboard: includesSideboard
    case .maybeboard: includesMaybeboard
    }
  }
}

public struct CardCollectionSemanticEntryEvidence: Equatable, Sendable {
  public var entryID: String
  public var printingID: String
  public var zone: CardCollectionZone
  public var quantity: Int
}

/// Exact assertion and canonical hierarchy path supporting a feature. Path begins at the
/// direct assertion and ends at the measured concept; a one-element path is direct.
public struct SemanticConceptAssertion: Hashable, Sendable {
  public var tagPath: [String]
  public var weightMillis: Int
  public var source: String
  public var annotation: String?

  static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.tagPath != rhs.tagPath { return lhs.tagPath.lexicographicallyPrecedes(rhs.tagPath) }
    if lhs.weightMillis != rhs.weightMillis { return lhs.weightMillis > rhs.weightMillis }
    if lhs.source != rhs.source { return lhs.source < rhs.source }
    if (lhs.annotation == nil) != (rhs.annotation == nil) { return lhs.annotation == nil }
    return (lhs.annotation ?? "") < (rhs.annotation ?? "")
  }
}

public struct CardCollectionSemanticSupport: Equatable, Sendable {
  public var cardKey: SemanticCardKey
  public var effectiveWeight: Double
  public var sources: [String]
  public var assertions: [SemanticConceptAssertion]
}

public struct CardCollectionSemanticConcept: Equatable, Sendable {
  public var tagID: String
  public var slug: String
  public var label: String
  public var supportCardCount: Int { supports.count }
  public var coverage: Double
  public var inverseFrequency: Double
  /// Sum of each unique card's hierarchy-adjusted membership × catalog IDF / eligible cards.
  /// No invented concept-kind multiplier is applied.
  public var importance: Double
  public var supports: [CardCollectionSemanticSupport]
  public var sources: [String]
}

public enum CardCollectionSemanticLinkReason: String, Equatable, Sendable {
  case missingSemanticData
  case noSharedEnabledConcepts
  case belowListMedian
}

public struct CardCollectionSemanticConnectivityEvidence: Equatable, Sendable {
  public var cardKey: SemanticCardKey
  public var reason: CardCollectionSemanticLinkReason
  public var linkCount: Int
  public var weightedDegree: Double
  public var listMedianWeightedDegree: Double
  public var missingSemanticDataAffectedMeasurement: Bool
}

public struct CardCollectionSemanticNode: Equatable, Sendable {
  public var cardKey: SemanticCardKey
  public var printingID: String
  public var name: String
  public var quantity: Int
  public var entries: [CardCollectionSemanticEntryEvidence]
  public var hasSemanticData: Bool
  public var linkCount: Int
  public var weightedDegree: Double
}

public struct CardCollectionSemanticEdge: Equatable, Sendable {
  public var first: SemanticCardKey
  public var second: SemanticCardKey
  /// IDF-weighted cosine similarity, using every shared enabled feature.
  public var weight: Double
  public var sharedConceptCount: Int
  public var sharedConcepts: [SemanticRelatedCardConcept]
  /// Support for the displayed concepts, aligned with sharedConcepts.
  public var supportingCards: [[CardCollectionSemanticSupport]]
}

/// A read-only snapshot. Quantities and invalid configurations remain evidence; they do not
/// multiply concept presence or graph edges. Missing printings are included in coverage's
/// denominator once per printing, because their Oracle identity is unknown.
public struct CardCollectionSemanticProfile: Equatable, Sendable {
  public var listID: String
  public var contentFingerprint: String
  public var catalogGeneration: UInt64
  public var policy: CardCollectionSemanticPolicy
  public var nodes: [CardCollectionSemanticNode]
  public var commanderCardKeys: [SemanticCardKey]
  public var excludedEntries: [CardCollectionSemanticEntryEvidence]
  public var missingCardEntries: [CardCollectionSemanticEntryEvidence]
  public var validationWarnings: [CardCollectionRulesetWarning]
  public var dominantConcepts: [CardCollectionSemanticConcept]
  public var edges: [CardCollectionSemanticEdge]
  public var coveredCardCount: Int
  public var eligibleCardCount: Int
  public var coverage: Double {
    eligibleCardCount == 0 ? 0 : Double(coveredCardCount) / Double(eligibleCardCount)
  }
  public var listMedianWeightedDegree: Double
  public var fewLinkEvidence: [CardCollectionSemanticConnectivityEvidence]
  public var fewLinkCards: [SemanticCardKey] { fewLinkEvidence.map(\.cardKey) }
  /// All positive-degree cards tied for the measured maximum; empty when every card is isolated.
  public var highlyConnectedCards: [SemanticCardKey]
}

public enum CardCollectionSemanticProfileLookup: Equatable, Sendable {
  case unavailable
  case available(CardCollectionSemanticProfile)
}

public enum CardCollectionSemanticProfileError: Error {
  case duplicateEntryID(String)
}

public enum CardCollectionSemanticProfiler {
  /// A deterministic fingerprint of semantic input, including evidence IDs, printing choices,
  /// all quantities/zones, explicit commander assignments, ruleset and versioned profile policy.
  /// Presentation order, dates, category labels and list name do not affect the snapshot.
  public static func fingerprint(
    for list: CardCollectionRecord, entries: [CardCollectionEntryRecord],
    policy: CardCollectionSemanticPolicy = .init()
  ) throws -> String {
    var rows = [
      [
        "semantic-profile-v1", list.id, list.ruleset.rawValue, String(policy.includesSideboard),
        String(policy.includesMaybeboard), String(max(1, policy.explanationLimit)),
      ]
    ]
    let matching = entries.filter { $0.listID == list.id }.map { entry in
      var normalized = entry
      normalized.quantity = max(1, entry.quantity)
      return normalized
    }.sorted(by: entryPrecedes)
    for entry in matching {
      try Task.checkCancellation()
      rows.append([entry.id, entry.cardID, entry.zone.rawValue, String(max(1, entry.quantity))])
    }
    let data = try JSONEncoder().encode(rows)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public static func profile(
    for list: CardCollectionRecord, entries: [CardCollectionEntryRecord],
    snapshot: SemanticCatalogSnapshot, catalogGeneration: UInt64 = 0,
    policy: CardCollectionSemanticPolicy = .init()
  ) throws -> CardCollectionSemanticProfile {
    try profile(
      for: list, entries: entries, snapshot: snapshot, catalogGeneration: catalogGeneration,
      policy: policy, beforeEdges: nil)
  }

  static func profile(
    for list: CardCollectionRecord, entries: [CardCollectionEntryRecord],
    snapshot: SemanticCatalogSnapshot, catalogGeneration: UInt64,
    policy: CardCollectionSemanticPolicy,
    beforeEdges: (@Sendable () -> Void)?
  ) throws -> CardCollectionSemanticProfile {
    try Task.checkCancellation()
    let matching = entries.filter { $0.listID == list.id }.map { entry in
      var normalized = entry
      normalized.quantity = max(1, entry.quantity)
      return normalized
    }.sorted(by: entryPrecedes)
    var seen: Set<String> = []
    var groups: [SemanticCardKey: [CardCollectionEntryRecord]] = [:]
    var missing: [CardCollectionSemanticEntryEvidence] = []
    var excluded: [CardCollectionSemanticEntryEvidence] = []
    var commanders: Set<SemanticCardKey> = []
    for entry in matching {
      try Task.checkCancellation()
      guard seen.insert(entry.id).inserted else {
        throw CardCollectionSemanticProfileError.duplicateEntryID(entry.id)
      }
      guard policy.includes(entry.zone, ruleset: list.ruleset) else {
        excluded.append(evidence(entry))
        continue
      }
      guard let card = entry.card, card.id == entry.cardID else {
        missing.append(evidence(entry))
        continue
      }
      let key = SemanticCardKey(oracleID: card.oracleID, printingID: card.id)
      groups[key, default: []].append(entry)
      if entry.zone == .commander { commanders.insert(key) }
    }
    let keys = groups.keys.sorted { $0.rawValue < $1.rawValue }
    let eligibleCount = keys.count + Set(missing.map(\.printingID)).count
    let scorer = try SemanticRelatedCardScorer(snapshot: snapshot)
    let features = try scorer.featureVectors(for: Set(keys))
    let enabledTags = snapshot.tags.filter(\.similarityEnabled).sorted { $0.id < $1.id }
    var idf: [String: Double] = [:]
    for stats in snapshot.stats.sorted(by: { $0.tagID < $1.tagID }) {
      idf[stats.tagID] = Double(stats.inverseFrequencyMillis) / 1000
    }
    var magnitudes: [SemanticCardKey: Double] = [:]
    var supportsByKey: [SemanticCardKey: [String: CardCollectionSemanticSupport]] = [:]
    for key in keys {
      try Task.checkCancellation()
      magnitudes[key] = scorer.magnitude(of: features[key] ?? [:])
      for tagID in (features[key] ?? [:]).keys.sorted() {
        try Task.checkCancellation()
        supportsByKey[key, default: [:]][tagID] = support(
          for: key, tagID: tagID, features: features)
      }
    }
    var concepts: [CardCollectionSemanticConcept] = []
    for tag in enabledTags {
      try Task.checkCancellation()
      let supports = keys.compactMap { supportsByKey[$0]?[tag.id] }
      guard !supports.isEmpty else { continue }
      let specificity = idf[tag.id, default: 1]
      let contribution = supports.reduce(0.0) { $0 + $1.effectiveWeight * specificity }
      concepts.append(
        .init(
          tagID: tag.id, slug: tag.slug, label: tag.label,
          coverage: Double(supports.count) / Double(eligibleCount), inverseFrequency: specificity,
          importance: contribution / Double(eligibleCount), supports: supports,
          sources: Set(supports.flatMap(\.sources)).sorted()))
    }
    concepts.sort {
      if $0.importance != $1.importance { return $0.importance > $1.importance }
      if $0.slug != $1.slug { return $0.slug < $1.slug }
      return $0.tagID < $1.tagID
    }
    var nodes: [CardCollectionSemanticNode] = []
    for key in keys {
      try Task.checkCancellation()
      let group = groups[key, default: []]
      let card = group.compactMap(\.card).sorted { $0.id < $1.id }.first
      nodes.append(
        .init(
          cardKey: key, printingID: card?.id ?? "", name: card?.name ?? "",
          quantity: group.reduce(0) { $0 + max(1, $1.quantity) }, entries: group.map(evidence),
          hasSemanticData: !(features[key] ?? [:]).isEmpty, linkCount: 0, weightedDegree: 0))
    }
    beforeEdges?()
    try Task.checkCancellation()
    var edges: [CardCollectionSemanticEdge] = []
    for first in nodes.indices {
      for second in nodes.indices where second > first {
        try Task.checkCancellation()
        let shared = try scorer.sharedConcepts(
          between: nodes[first].cardKey, and: nodes[second].cardKey, features: features)
        guard !shared.isEmpty else { continue }
        let numerator = shared.reduce(0.0) { $0 + $1.contribution }
        let denominator =
          (magnitudes[nodes[first].cardKey] ?? 0) * (magnitudes[nodes[second].cardKey] ?? 0)
        guard denominator > 0 else { continue }
        let weight = numerator / denominator
        let displayed = Array(shared.prefix(max(1, policy.explanationLimit)))
        edges.append(
          .init(
            first: nodes[first].cardKey, second: nodes[second].cardKey, weight: weight,
            sharedConceptCount: shared.count, sharedConcepts: displayed,
            supportingCards: displayed.map { concept in
              [nodes[first].cardKey, nodes[second].cardKey].compactMap {
                supportsByKey[$0]?[concept.tagID]
              }
            }))
        nodes[first].linkCount += 1
        nodes[second].linkCount += 1
        nodes[first].weightedDegree += weight
        nodes[second].weightedDegree += weight
      }
    }
    let degrees = nodes.map(\.weightedDegree).sorted()
    let median: Double
    if degrees.isEmpty {
      median = 0
    } else if degrees.count.isMultiple(of: 2) {
      median = (degrees[degrees.count / 2 - 1] + degrees[degrees.count / 2]) / 2
    } else {
      median = degrees[degrees.count / 2]
    }
    let coverageIncomplete = !missing.isEmpty || nodes.contains { !$0.hasSemanticData }
    let few = nodes.filter { $0.weightedDegree < median }.map { node in
      CardCollectionSemanticConnectivityEvidence(
        cardKey: node.cardKey,
        reason: !node.hasSemanticData
          ? .missingSemanticData
          : (node.linkCount == 0 ? .noSharedEnabledConcepts : .belowListMedian),
        linkCount: node.linkCount, weightedDegree: node.weightedDegree,
        listMedianWeightedDegree: median, missingSemanticDataAffectedMeasurement: coverageIncomplete
      )
    }
    let maximum = degrees.last ?? 0
    let warnings = CardCollectionRulesetValidator.warnings(for: list, entries: matching).sorted {
      if $0.id != $1.id { return $0.id < $1.id }
      return $0.message < $1.message
    }
    try Task.checkCancellation()
    return .init(
      listID: list.id,
      contentFingerprint: try fingerprint(for: list, entries: entries, policy: policy),
      catalogGeneration: catalogGeneration, policy: policy, nodes: nodes,
      commanderCardKeys: commanders.sorted { $0.rawValue < $1.rawValue }, excludedEntries: excluded,
      missingCardEntries: missing, validationWarnings: warnings, dominantConcepts: concepts,
      edges: edges, coveredCardCount: nodes.filter(\.hasSemanticData).count,
      eligibleCardCount: eligibleCount, listMedianWeightedDegree: median, fewLinkEvidence: few,
      highlyConnectedCards: maximum > 0
        ? nodes.filter { $0.weightedDegree == maximum }.map(\.cardKey) : [])
  }

  private static func entryPrecedes(
    _ lhs: CardCollectionEntryRecord, _ rhs: CardCollectionEntryRecord
  ) -> Bool {
    if lhs.id != rhs.id { return lhs.id < rhs.id }
    if lhs.cardID != rhs.cardID { return lhs.cardID < rhs.cardID }
    if lhs.zone != rhs.zone { return lhs.zone.rawValue < rhs.zone.rawValue }
    return lhs.quantity < rhs.quantity
  }

  private static func evidence(_ entry: CardCollectionEntryRecord)
    -> CardCollectionSemanticEntryEvidence
  {
    .init(
      entryID: entry.id, printingID: entry.cardID, zone: entry.zone,
      quantity: max(1, entry.quantity))
  }

  private static func support(
    for key: SemanticCardKey, tagID: String,
    features: [SemanticCardKey: [String: SemanticRelatedCardScorer.Feature]]
  ) -> CardCollectionSemanticSupport? {
    guard let feature = features[key]?[tagID], feature.weight > 0 else { return nil }
    return .init(
      cardKey: key, effectiveWeight: feature.weight, sources: feature.sources.sorted(),
      assertions: feature.assertions.sorted(by: SemanticConceptAssertion.precedes))
  }
}
