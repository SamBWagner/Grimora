import Foundation

public struct SemanticRelatedCardCandidate: Equatable, Sendable {
  public var cardKey: SemanticCardKey
  public var printingID: String
  public var name: String
  public var colorIdentity: Set<String>
  public var legalities: [String: String]

  public init(
    cardKey: SemanticCardKey,
    printingID: String,
    name: String,
    colorIdentity: Set<String> = [],
    legalities: [String: String] = [:]
  ) {
    self.cardKey = cardKey
    self.printingID = printingID
    self.name = name
    self.colorIdentity = colorIdentity
    self.legalities = legalities
  }
}

public struct SemanticRelatedCardFilters: Equatable, Sendable {
  public var format: String?
  public var maximumColorIdentity: Set<String>?
  public var limit: Int

  public init(
    format: String? = nil,
    maximumColorIdentity: Set<String>? = nil,
    limit: Int = 12
  ) {
    self.format = format
    self.maximumColorIdentity = maximumColorIdentity
    self.limit = limit
  }

  func includes(_ candidate: SemanticRelatedCardCandidate) -> Bool {
    if let format = format?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased(),
      !format.isEmpty
    {
      let status = candidate.legalities.first { key, _ in
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == format
      }?.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if status != "legal" {
        return false
      }
    }

    if let maximumColorIdentity {
      let allowed = Set(maximumColorIdentity.map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      })
      let candidateColors = Set(candidate.colorIdentity.map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      })
      if !candidateColors.isSubset(of: allowed) {
        return false
      }
    }

    return true
  }
}

public struct SemanticRelatedCardConcept: Identifiable, Equatable, Sendable {
  public var tagID: String
  public var slug: String
  public var label: String
  public var contribution: Double
  public var sources: [String]

  public var id: String {
    tagID
  }

  public init(
    tagID: String,
    slug: String,
    label: String,
    contribution: Double,
    sources: [String]
  ) {
    self.tagID = tagID
    self.slug = slug
    self.label = label
    self.contribution = contribution
    self.sources = sources
  }
}

public struct SemanticRelatedCardMatch: Identifiable, Equatable, Sendable {
  public var candidate: SemanticRelatedCardCandidate
  public var score: Double
  public var sharedConcepts: [SemanticRelatedCardConcept]

  public var id: SemanticCardKey {
    candidate.cardKey
  }

  public var cardKey: SemanticCardKey {
    candidate.cardKey
  }

  public var printingID: String {
    candidate.printingID
  }

  public var name: String {
    candidate.name
  }

  public init(
    candidate: SemanticRelatedCardCandidate,
    score: Double,
    sharedConcepts: [SemanticRelatedCardConcept]
  ) {
    self.candidate = candidate
    self.score = score
    self.sharedConcepts = sharedConcepts
  }
}

public struct SemanticRelatedCard: Identifiable, Equatable, Sendable {
  public var card: CardRecord
  public var score: Double
  public var sharedConcepts: [SemanticRelatedCardConcept]

  public var id: SemanticCardKey {
    SemanticCardKey(oracleID: card.oracleID, printingID: card.id)
  }

  public init(
    card: CardRecord,
    score: Double,
    sharedConcepts: [SemanticRelatedCardConcept]
  ) {
    self.card = card
    self.score = score
    self.sharedConcepts = sharedConcepts
  }
}

public enum SemanticRelatedCardsLookup: Equatable, Sendable {
  case unavailable
  case available([SemanticRelatedCard])
}

public struct SemanticRelatedCardScorer: Sendable {
  private struct Feature: Sendable {
    var weight: Double
    var sources: Set<String>
  }

  private let tagsByID: [String: SemanticTagRecord]
  private let parentsByChild: [String: [String]]
  private let membershipsByCardKey: [SemanticCardKey: [SemanticCardTagRecord]]
  private let inverseFrequencyByTagID: [String: Double]

  public init(snapshot: SemanticCatalogSnapshot) throws {
    var tags: [String: SemanticTagRecord] = [:]
    tags.reserveCapacity(snapshot.tags.count)
    for (index, tag) in snapshot.tags.enumerated() {
      try Self.checkCancellation(at: index)
      if tag.similarityEnabled {
        tags[tag.id] = tag
      }
    }

    var parents: [String: [String]] = [:]
    parents.reserveCapacity(snapshot.edges.count)
    for (index, edge) in snapshot.edges.enumerated() {
      try Self.checkCancellation(at: index)
      parents[edge.childTagID, default: []].append(edge.parentTagID)
    }
    for (index, childTagID) in parents.keys.sorted().enumerated() {
      try Self.checkCancellation(at: index)
      parents[childTagID]?.sort()
    }

    var memberships: [SemanticCardKey: [SemanticCardTagRecord]] = [:]
    memberships.reserveCapacity(snapshot.cardTags.count)
    for (index, membership) in snapshot.cardTags.enumerated() {
      try Self.checkCancellation(at: index)
      memberships[membership.cardKey, default: []].append(membership)
    }

    var inverseFrequency: [String: Double] = [:]
    inverseFrequency.reserveCapacity(snapshot.stats.count)
    for (index, stats) in snapshot.stats.enumerated() {
      try Self.checkCancellation(at: index)
      inverseFrequency[stats.tagID] = Double(stats.inverseFrequencyMillis) / 1_000
    }
    try Task.checkCancellation()

    tagsByID = tags
    parentsByChild = parents
    membershipsByCardKey = memberships
    inverseFrequencyByTagID = inverseFrequency
  }

  public func rankedCandidates(
    for sourceCardKey: SemanticCardKey,
    among candidates: [SemanticRelatedCardCandidate],
    filters: SemanticRelatedCardFilters = SemanticRelatedCardFilters()
  ) throws -> [SemanticRelatedCardMatch] {
    try Task.checkCancellation()
    guard filters.limit > 0 else {
      return []
    }

    var collapsedCandidates: [SemanticCardKey: SemanticRelatedCardCandidate] = [:]
    for (cardKey, printings) in Dictionary(grouping: candidates, by: \.cardKey) {
      try Task.checkCancellation()
      if let preferred = printings.sorted(by: Self.candidatePrecedes).first {
        collapsedCandidates[cardKey] = preferred
      }
    }
    let relevantCardKeys = Set(collapsedCandidates.keys).union([sourceCardKey])
    let featuresByCardKey = try featureVectors(for: relevantCardKeys)
    guard let sourceFeatures = featuresByCardKey[sourceCardKey], !sourceFeatures.isEmpty else {
      return []
    }
    let sourceMagnitude = magnitude(of: sourceFeatures)
    guard sourceMagnitude > 0 else {
      return []
    }

    var matches: [SemanticRelatedCardMatch] = []
    matches.reserveCapacity(collapsedCandidates.count)
    for cardKey in collapsedCandidates.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
      try Task.checkCancellation()
      guard let candidate = collapsedCandidates[cardKey] else {
        continue
      }
      guard cardKey != sourceCardKey,
        filters.includes(candidate),
        let candidateFeatures = featuresByCardKey[cardKey],
        !candidateFeatures.isEmpty
      else {
        continue
      }

      let candidateMagnitude = magnitude(of: candidateFeatures)
      guard candidateMagnitude > 0 else {
        continue
      }

      let sharedTagIDs = Set(sourceFeatures.keys).intersection(candidateFeatures.keys).sorted()
      var concepts: [SemanticRelatedCardConcept] = []
      concepts.reserveCapacity(sharedTagIDs.count)
      for tagID in sharedTagIDs {
        try Task.checkCancellation()
        guard let tag = tagsByID[tagID] else {
          continue
        }
        let contribution = weightedContribution(
          source: sourceFeatures[tagID]?.weight ?? 0,
          candidate: candidateFeatures[tagID]?.weight ?? 0,
          tagID: tagID
        )
        guard contribution > 0 else {
          continue
        }
        let sources = (sourceFeatures[tagID]?.sources ?? [])
          .union(candidateFeatures[tagID]?.sources ?? [])
          .union([tag.source])
          .sorted()
        concepts.append(
          SemanticRelatedCardConcept(
            tagID: tagID,
            slug: tag.slug,
            label: tag.label,
            contribution: contribution,
            sources: sources
          )
        )
      }
      concepts.sort {
        if $0.contribution != $1.contribution {
          return $0.contribution > $1.contribution
        }
        if $0.slug != $1.slug {
          return $0.slug < $1.slug
        }
        return $0.tagID < $1.tagID
      }
      let numerator = concepts.reduce(0.0) { $0 + $1.contribution }
      guard numerator > 0 else {
        continue
      }

      matches.append(
        SemanticRelatedCardMatch(
          candidate: candidate,
          score: numerator / (sourceMagnitude * candidateMagnitude),
          sharedConcepts: concepts
        )
      )
    }
    try Task.checkCancellation()
    return matches.sorted {
      if $0.score != $1.score {
        return $0.score > $1.score
      }
      if $0.name != $1.name {
        return $0.name < $1.name
      }
      return $0.cardKey.rawValue < $1.cardKey.rawValue
    }.prefix(filters.limit).map { $0 }
  }

  private func featureVectors(
    for cardKeys: Set<SemanticCardKey>
  ) throws -> [SemanticCardKey: [String: Feature]] {
    var features = Dictionary(uniqueKeysWithValues: cardKeys.map { ($0, [String: Feature]()) })
    for cardKey in cardKeys.sorted(by: { $0.rawValue < $1.rawValue }) {
      try Task.checkCancellation()
      for membership in membershipsByCardKey[cardKey, default: []] {
        try Task.checkCancellation()
        try addFeature(
          tagID: membership.tagID,
          weight: Double(membership.weightMillis) / 1_000,
          sources: [membership.source],
          depth: 0,
          to: cardKey,
          features: &features,
          visited: []
        )
      }
    }
    return features
  }

  private func addFeature(
    tagID: String,
    weight: Double,
    sources: Set<String>,
    depth: Int,
    to cardKey: SemanticCardKey,
    features: inout [SemanticCardKey: [String: Feature]],
    visited: Set<String>
  ) throws {
    try Task.checkCancellation()
    guard let tag = tagsByID[tagID], !visited.contains(tagID) else {
      return
    }

    var nextVisited = visited
    nextVisited.insert(tagID)
    let effectiveWeight = weight * pow(0.5, Double(depth))
    let featureSources = sources.union([tag.source])
    if let existing = features[cardKey]?[tagID] {
      features[cardKey]?[tagID] = Feature(
        weight: max(existing.weight, effectiveWeight),
        sources: existing.sources.union(featureSources)
      )
    } else {
      features[cardKey]?[tagID] = Feature(
        weight: effectiveWeight,
        sources: featureSources
      )
    }

    for parentTagID in parentsByChild[tagID, default: []] {
      try addFeature(
        tagID: parentTagID,
        weight: weight,
        sources: featureSources,
        depth: depth + 1,
        to: cardKey,
        features: &features,
        visited: nextVisited
      )
    }
  }

  private func magnitude(of features: [String: Feature]) -> Double {
    sqrt(features.keys.sorted().reduce(0.0) { total, tagID in
      let weighted = (features[tagID]?.weight ?? 0) * inverseFrequency(for: tagID)
      return total + weighted * weighted
    })
  }

  private func weightedContribution(
    source: Double,
    candidate: Double,
    tagID: String
  ) -> Double {
    let inverseFrequency = inverseFrequency(for: tagID)
    return source * candidate * inverseFrequency * inverseFrequency
  }

  private func inverseFrequency(for tagID: String) -> Double {
    inverseFrequencyByTagID[tagID, default: 1]
  }

  private static func candidatePrecedes(
    _ lhs: SemanticRelatedCardCandidate,
    _ rhs: SemanticRelatedCardCandidate
  ) -> Bool {
    if lhs.name != rhs.name {
      return lhs.name < rhs.name
    }
    return lhs.printingID < rhs.printingID
  }

  private static func checkCancellation(at index: Int) throws {
    if index.isMultiple(of: 256) {
      try Task.checkCancellation()
    }
  }

}
