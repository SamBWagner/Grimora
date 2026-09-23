import Foundation
import Testing

struct SemanticRelationshipBenchmarkTests {
  @Test
  func trueEnchantressAnaloguesOutrankBroadDrawEngines() throws {
    let fixture = try SemanticBenchmarkFixture.load()
    let scorer = SemanticBenchmarkScorer(fixture: fixture)

    let ranked = try scorer.rankedCandidates(
      forPrintingID: "0babfe00-9bad-48fc-b3b1-df8280242fd2"
    )
    let positions = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($0.element.name, $0.offset) })
    let broadDrawPosition = try #require(positions["Beast Whisperer"])

    for name in ["Satyr Enchanter", "Enchantress's Presence", "Mesa Enchantress"] {
      #expect(try #require(positions[name]) < broadDrawPosition)
    }
  }

  @Test
  func metadataBranchesMakeNoSimilarityContribution() throws {
    let fixture = try SemanticBenchmarkFixture.load()
    let scorer = SemanticBenchmarkScorer(fixture: fixture)

    let featureSlugs = try scorer.featureSlugs(
      forPrintingID: "0babfe00-9bad-48fc-b3b1-df8280242fd2"
    )

    #expect(featureSlugs.contains("enchantment-engine"))
    #expect(!featureSlugs.contains("alliteration"))
    #expect(!featureSlugs.contains("card-names"))
    #expect(!featureSlugs.contains("cycle-mh2-r-two-color-new"))
    #expect(!featureSlugs.contains("cycle"))

    var noisyFixture = fixture
    let lightningBoltOracleID = "4457ed35-7c10-48c8-9776-456485fdf070"
    for index in noisyFixture.tags.indices where [
      "alliteration",
      "cycle-mh2-r-two-color-new",
    ].contains(noisyFixture.tags[index].slug) {
      noisyFixture.tags[index].taggings.append(
        SemanticFixtureTagging(
          oracleID: lightningBoltOracleID,
          weight: .median,
          annotation: "Benchmark-only shared metadata noise"
        )
      )
    }
    let noisyRanked = try SemanticBenchmarkScorer(fixture: noisyFixture).rankedCandidates(
      forPrintingID: "0babfe00-9bad-48fc-b3b1-df8280242fd2"
    )
    #expect(!noisyRanked.contains { $0.oracleID == lightningBoltOracleID })
  }

  @Test
  func fixturePreservesTheSourceContractAndBenchmarkRoles() throws {
    let fixture = try SemanticBenchmarkFixture.load()
    let enchantmentEngine = try #require(fixture.tags.first { $0.slug == "enchantment-engine" })

    #expect(fixture.cardsSource == fixture.tagsSource)
    #expect(fixture.source.provider == "Scryfall")
    #expect(fixture.source.capturedAt == "2026-09-23")
    #expect(fixture.source.oracleTagsUpdatedAt == "2026-09-22T21:00:31.331+00:00")
    #expect(fixture.source.oracleTagsDownloadURI.lastPathComponent == "oracle-tags-20260922210031.jsonl.gz")
    #expect(enchantmentEngine.id == "729b31fd-d563-4985-b40b-f1b0941d9156")
    #expect(enchantmentEngine.label == "enchantment engine")
    #expect(enchantmentEngine.description != nil)
    #expect(enchantmentEngine.aliases == ["enchantress"])
    #expect(enchantmentEngine.parentIDs.count == 2)
    #expect(enchantmentEngine.taggings.allSatisfy { $0.weight == .median })
    #expect(enchantmentEngine.taggings.contains {
      $0.oracleID == "0fc64fd6-f057-4056-9dca-47accb7ff036"
    })

    let roles = Set(fixture.cards.map(\.benchmarkRole))
    #expect(roles.isSuperset(of: [
      "query",
      "query-reprint",
      "true-enchantress-analogue",
      "near-enchantress-analogue",
      "broad-cast-trigger-draw-engine",
      "lifegain-only",
      "unrelated",
    ]))
  }

  @Test
  func reprintsCollapseToOneOracleIdentity() throws {
    let fixture = try SemanticBenchmarkFixture.load()
    let scorer = SemanticBenchmarkScorer(fixture: fixture)
    let sythisOracleID = "0fc64fd6-f057-4056-9dca-47accb7ff036"
    let satyrOracleID = "aa321138-b1a7-4b8e-a2ca-b9ce65704e92"

    #expect(fixture.cards.filter { $0.oracleID == sythisOracleID }.count == 2)
    #expect(fixture.cards.filter { $0.oracleID == satyrOracleID }.count == 2)

    let ranked = try scorer.rankedCandidates(
      forPrintingID: "0babfe00-9bad-48fc-b3b1-df8280242fd2"
    )
    #expect(ranked.allSatisfy { $0.oracleID != sythisOracleID })
    #expect(Set(ranked.map(\.oracleID)).count == ranked.count)
    #expect(ranked.filter { $0.oracleID == satyrOracleID }.count == 1)
  }

  @Test
  func resultsExposeTheirStrongestSharedFunctionalConcepts() throws {
    let fixture = try SemanticBenchmarkFixture.load()
    let scorer = SemanticBenchmarkScorer(fixture: fixture)

    let ranked = try scorer.rankedCandidates(
      forPrintingID: "0babfe00-9bad-48fc-b3b1-df8280242fd2"
    )
    let satyr = try #require(ranked.first { $0.name == "Satyr Enchanter" })
    let strongest = Array(satyr.sharedConcepts.prefix(4))

    #expect(strongest == [
      "cast-trigger-you",
      "enchantment-engine",
      "draw-engine",
      "repeatable-pure-draw",
    ])
    #expect(!satyr.sharedConcepts.contains("alliteration"))
    #expect(!satyr.sharedConcepts.contains("cycle"))
  }
}

private struct SemanticBenchmarkFixture {
  var source: SemanticFixtureSource
  var cardsSource: SemanticFixtureSource
  var tagsSource: SemanticFixtureSource
  var cards: [SemanticFixtureCard]
  var tags: [SemanticFixtureTag]
  var similarityDisabledRootSlugs: Set<String>

  static func load() throws -> SemanticBenchmarkFixture {
    let cardsDocument: SemanticCardsDocument = try decodeResource("SemanticCards")
    let tagsDocument: SemanticTagsDocument = try decodeResource("SemanticTags")
    guard cardsDocument.source == tagsDocument.source else {
      throw SemanticBenchmarkFixtureError.inconsistentSourceMetadata
    }
    return SemanticBenchmarkFixture(
      source: tagsDocument.source,
      cardsSource: cardsDocument.source,
      tagsSource: tagsDocument.source,
      cards: cardsDocument.cards,
      tags: tagsDocument.tags,
      similarityDisabledRootSlugs: Set(tagsDocument.similarityDisabledRootSlugs)
    )
  }

  private static func decodeResource<Value: Decodable>(_ name: String) throws -> Value {
    guard let url = Bundle.module.url(
      forResource: name,
      withExtension: "json",
      subdirectory: "Fixtures"
    ) else {
      throw SemanticBenchmarkFixtureError.missingResource(name)
    }
    return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
  }
}

private struct SemanticCardsDocument: Decodable {
  var source: SemanticFixtureSource
  var cards: [SemanticFixtureCard]
}

private struct SemanticTagsDocument: Decodable {
  var source: SemanticFixtureSource
  var similarityDisabledRootSlugs: [String]
  var tags: [SemanticFixtureTag]
}

private struct SemanticFixtureSource: Decodable, Equatable {
  var provider: String
  var capturedAt: String
  var oracleTagsUpdatedAt: String
  var oracleTagsDownloadURI: URL
}

private struct SemanticFixtureCard: Decodable {
  var printingID: String
  var oracleID: String
  var name: String
  var benchmarkRole: String
}

private struct SemanticFixtureTag: Decodable {
  var id: String
  var slug: String
  var label: String
  var description: String?
  var aliases: [String]
  var parentIDs: [String]
  var taggings: [SemanticFixtureTagging]
}

private struct SemanticFixtureTagging: Decodable {
  var oracleID: String
  var weight: SemanticFixtureTagWeight
  var annotation: String?
}

private enum SemanticFixtureTagWeight: String, Decodable {
  case weak
  case median
  case strong
  case veryStrong = "very_strong"
}

private struct SemanticBenchmarkResult {
  var oracleID: String
  var name: String
  var score: Double
  var sharedConcepts: [String]
}

private struct SemanticBenchmarkScorer {
  var fixture: SemanticBenchmarkFixture

  func rankedCandidates(forPrintingID printingID: String) throws -> [SemanticBenchmarkResult] {
    guard let queryCard = fixture.cards.first(where: { $0.printingID == printingID }) else {
      throw SemanticBenchmarkFixtureError.missingPrinting(printingID)
    }

    let cardsByOracleID = Dictionary(grouping: fixture.cards, by: \.oracleID)
    let featuresByOracleID = featureVectors(oracleIDs: Set(cardsByOracleID.keys))
    guard let queryFeatures = featuresByOracleID[queryCard.oracleID] else {
      return []
    }

    let documentFrequency = fixture.tags.reduce(into: [String: Int]()) { counts, tag in
      counts[tag.id] = featuresByOracleID.values.count { $0[tag.id] != nil }
    }
    let documentCount = Double(cardsByOracleID.count)
    let inverseFrequency = documentFrequency.mapValues { frequency in
      log((documentCount + 1) / (Double(frequency) + 1)) + 1
    }

    return cardsByOracleID.compactMap { oracleID, cards in
      guard oracleID != queryCard.oracleID, let candidateFeatures = featuresByOracleID[oracleID] else {
        return nil
      }

      let sharedTagIDs = Set(queryFeatures.keys).intersection(candidateFeatures.keys)
      let numerator = sharedTagIDs.reduce(0.0) { total, tagID in
        let idf = inverseFrequency[tagID, default: 1]
        return total + queryFeatures[tagID, default: 0] * candidateFeatures[tagID, default: 0] * idf * idf
      }
      let queryMagnitude = sqrt(queryFeatures.reduce(0.0) { total, feature in
        let idf = inverseFrequency[feature.key, default: 1]
        return total + feature.value * feature.value * idf * idf
      })
      let candidateMagnitude = sqrt(candidateFeatures.reduce(0.0) { total, feature in
        let idf = inverseFrequency[feature.key, default: 1]
        return total + feature.value * feature.value * idf * idf
      })
      guard numerator > 0, queryMagnitude > 0, candidateMagnitude > 0 else {
        return nil
      }

      let tagByID = Dictionary(uniqueKeysWithValues: fixture.tags.map { ($0.id, $0) })
      let sharedConcepts = sharedTagIDs.sorted { lhs, rhs in
        let lhsContribution = queryFeatures[lhs, default: 0]
          * candidateFeatures[lhs, default: 0]
          * pow(inverseFrequency[lhs, default: 1], 2)
        let rhsContribution = queryFeatures[rhs, default: 0]
          * candidateFeatures[rhs, default: 0]
          * pow(inverseFrequency[rhs, default: 1], 2)
        if lhsContribution != rhsContribution {
          return lhsContribution > rhsContribution
        }
        return (tagByID[lhs]?.slug ?? lhs) < (tagByID[rhs]?.slug ?? rhs)
      }.compactMap { tagByID[$0]?.slug }

      return SemanticBenchmarkResult(
        oracleID: oracleID,
        name: cards[0].name,
        score: numerator / (queryMagnitude * candidateMagnitude),
        sharedConcepts: sharedConcepts
      )
    }.sorted {
      if $0.score != $1.score {
        return $0.score > $1.score
      }
      if $0.name != $1.name {
        return $0.name < $1.name
      }
      return $0.oracleID < $1.oracleID
    }
  }

  func featureSlugs(forPrintingID printingID: String) throws -> Set<String> {
    guard let card = fixture.cards.first(where: { $0.printingID == printingID }) else {
      throw SemanticBenchmarkFixtureError.missingPrinting(printingID)
    }
    let tagByID = Dictionary(uniqueKeysWithValues: fixture.tags.map { ($0.id, $0) })
    let features = featureVectors(oracleIDs: [card.oracleID])[card.oracleID, default: [:]]
    return Set(features.keys.compactMap { tagByID[$0]?.slug })
  }

  private func featureVectors(oracleIDs: Set<String>) -> [String: [String: Double]] {
    let tagByID = Dictionary(uniqueKeysWithValues: fixture.tags.map { ($0.id, $0) })
    let disabledTagIDs = disabledTagIDs(tagByID: tagByID)
    var features = Dictionary(uniqueKeysWithValues: oracleIDs.map { ($0, [String: Double]()) })

    for tag in fixture.tags where !disabledTagIDs.contains(tag.id) {
      for tagging in tag.taggings where oracleIDs.contains(tagging.oracleID) {
        addFeature(
          tagID: tag.id,
          weight: weight(for: tagging.weight),
          depth: 0,
          to: tagging.oracleID,
          features: &features,
          tagByID: tagByID,
          disabledTagIDs: disabledTagIDs,
          visited: []
        )
      }
    }
    return features
  }

  private func addFeature(
    tagID: String,
    weight: Double,
    depth: Int,
    to oracleID: String,
    features: inout [String: [String: Double]],
    tagByID: [String: SemanticFixtureTag],
    disabledTagIDs: Set<String>,
    visited: Set<String>
  ) {
    guard !disabledTagIDs.contains(tagID), !visited.contains(tagID), let tag = tagByID[tagID] else {
      return
    }
    var nextVisited = visited
    nextVisited.insert(tagID)
    let effectiveWeight = weight * pow(0.5, Double(depth))
    features[oracleID, default: [:]][tagID] = max(
      features[oracleID, default: [:]][tagID, default: 0],
      effectiveWeight
    )
    for parentID in tag.parentIDs {
      addFeature(
        tagID: parentID,
        weight: weight,
        depth: depth + 1,
        to: oracleID,
        features: &features,
        tagByID: tagByID,
        disabledTagIDs: disabledTagIDs,
        visited: nextVisited
      )
    }
  }

  private func disabledTagIDs(tagByID: [String: SemanticFixtureTag]) -> Set<String> {
    var memo: [String: Bool] = [:]

    func isDisabled(_ tagID: String, visiting: Set<String>) -> Bool {
      if let cached = memo[tagID] {
        return cached
      }
      guard let tag = tagByID[tagID], !visiting.contains(tagID) else {
        return false
      }
      if fixture.similarityDisabledRootSlugs.contains(tag.slug) {
        memo[tagID] = true
        return true
      }
      var nextVisiting = visiting
      nextVisiting.insert(tagID)
      let disabled = tag.parentIDs.contains { isDisabled($0, visiting: nextVisiting) }
      memo[tagID] = disabled
      return disabled
    }

    return Set(tagByID.keys.filter { isDisabled($0, visiting: []) })
  }

  private func weight(for value: SemanticFixtureTagWeight) -> Double {
    switch value {
    case .weak: 0.5
    case .median: 1
    case .strong: 1.5
    case .veryStrong: 2
    }
  }
}

private enum SemanticBenchmarkFixtureError: Error {
  case missingResource(String)
  case missingPrinting(String)
  case inconsistentSourceMetadata
}
