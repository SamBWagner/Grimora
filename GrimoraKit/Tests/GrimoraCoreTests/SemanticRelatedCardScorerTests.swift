import Foundation
import GrimoraCore
import Testing

struct SemanticRelatedCardScorerTests {
  @Test
  func diamondHierarchyPreservesSourcesFromEveryInheritedRoute() throws {
    let first = SemanticCardKey(oracleID: "first", printingID: "first")
    let second = SemanticCardKey(oracleID: "second", printingID: "second")
    let snapshot = SemanticCatalogSnapshot(
      tags: ["draw", "left", "right", "root"].map {
        .init(
          id: $0, namespace: "oracle", slug: $0, label: $0, description: nil,
          similarityEnabled: true, source: $0)
      },
      aliases: [],
      edges: [
        .init(parentTagID: "left", childTagID: "draw"),
        .init(parentTagID: "right", childTagID: "draw"),
        .init(parentTagID: "root", childTagID: "left"),
        .init(parentTagID: "root", childTagID: "right"),
      ],
      cardTags: [first, second].map {
        .init(cardKey: $0, tagID: "draw", weightMillis: 1000, annotation: nil, source: "fixture")
      },
      stats: []
    )
    let matches = try SemanticRelatedCardScorer(snapshot: snapshot).rankedCandidates(
      for: first, among: [.init(cardKey: second, printingID: "second", name: "Second")])
    let root = try #require(matches.first?.sharedConcepts.first { $0.tagID == "root" })
    #expect(root.sources == ["draw", "fixture", "left", "right", "root"])
  }

  @Test
  func formatColorIdentityAndLimitFiltersApplyBeforeRanking() throws {
    let sourceKey = SemanticCardKey(oracleID: "source", printingID: "source-print")
    let legalKey = SemanticCardKey(oracleID: "legal", printingID: "legal-print")
    let bannedKey = SemanticCardKey(oracleID: "banned", printingID: "banned-print")
    let offColorKey = SemanticCardKey(oracleID: "off-color", printingID: "off-color-print")
    let lowerKey = SemanticCardKey(oracleID: "lower", printingID: "lower-print")
    let snapshot = SemanticCatalogSnapshot(
      tags: [
        SemanticTagRecord(
          id: "draw",
          namespace: "oracle",
          slug: "draw-engine",
          label: "Draw Engine",
          description: nil,
          similarityEnabled: true,
          source: "semantic-fixture"
        )
      ],
      aliases: [],
      edges: [],
      cardTags: [
        membership(cardKey: sourceKey, weightMillis: 1_000),
        membership(cardKey: legalKey, weightMillis: 1_000),
        membership(cardKey: bannedKey, weightMillis: 1_000),
        membership(cardKey: offColorKey, weightMillis: 1_000),
        membership(cardKey: lowerKey, weightMillis: 500),
      ],
      stats: [
        SemanticTagStatsRecord(
          tagID: "draw",
          directCardCount: 5,
          effectiveCardCount: 5,
          inverseFrequencyMillis: 1_000
        )
      ]
    )
    let candidates = [
      SemanticRelatedCardCandidate(
        cardKey: bannedKey,
        printingID: "banned-print",
        name: "Banned Card",
        colorIdentity: ["W"],
        legalities: ["commander": "banned"]
      ),
      SemanticRelatedCardCandidate(
        cardKey: legalKey,
        printingID: "legal-print",
        name: "Legal Match",
        colorIdentity: ["W"],
        legalities: ["commander": "legal"]
      ),
      SemanticRelatedCardCandidate(
        cardKey: offColorKey,
        printingID: "off-color-print",
        name: "Off Color Match",
        colorIdentity: ["W", "U"],
        legalities: ["commander": "legal"]
      ),
      SemanticRelatedCardCandidate(
        cardKey: lowerKey,
        printingID: "lower-print",
        name: "Lower Match",
        colorIdentity: ["W"],
        legalities: ["commander": "legal"]
      ),
    ]

    let ranked = try SemanticRelatedCardScorer(snapshot: snapshot).rankedCandidates(
      for: sourceKey,
      among: candidates,
      filters: SemanticRelatedCardFilters(
        format: " Commander ",
        maximumColorIdentity: ["w"],
        limit: 1
      )
    )

    #expect(ranked.map(\.name) == ["Legal Match"])
  }

  @Test
  func formatFilterNormalizesCandidateLegalityKeysAndStatuses() throws {
    let sourceKey = SemanticCardKey(oracleID: "source", printingID: "source-print")
    let candidateKey = SemanticCardKey(oracleID: "candidate", printingID: "candidate-print")
    let snapshot = SemanticCatalogSnapshot(
      tags: [
        SemanticTagRecord(
          id: "draw",
          namespace: "oracle",
          slug: "draw-engine",
          label: "Draw Engine",
          description: nil,
          similarityEnabled: true,
          source: "semantic-fixture"
        )
      ],
      aliases: [],
      edges: [],
      cardTags: [
        membership(cardKey: sourceKey, weightMillis: 1_000),
        membership(cardKey: candidateKey, weightMillis: 1_000),
      ],
      stats: [
        SemanticTagStatsRecord(
          tagID: "draw",
          directCardCount: 2,
          effectiveCardCount: 2,
          inverseFrequencyMillis: 1_000
        )
      ]
    )

    let ranked = try SemanticRelatedCardScorer(snapshot: snapshot).rankedCandidates(
      for: sourceKey,
      among: [
        SemanticRelatedCardCandidate(
          cardKey: candidateKey,
          printingID: "candidate-print",
          name: "Candidate",
          legalities: [" Commander ": " Legal "]
        )
      ],
      filters: SemanticRelatedCardFilters(format: "commander")
    )

    #expect(ranked.map(\.name) == ["Candidate"])
  }

  @Test
  func mathematicallyTiedCandidatesUseStableNameTieBreaking() throws {
    let sourceKey = SemanticCardKey(oracleID: "source", printingID: "source-print")
    let firstKey = SemanticCardKey(oracleID: "first", printingID: "first-print")
    let secondKey = SemanticCardKey(oracleID: "second", printingID: "second-print")
    let tagCount = 512
    let tags = (0..<tagCount).map { index in
      SemanticTagRecord(
        id: "tag-\(index)",
        namespace: "oracle",
        slug: "tag-\(index)",
        label: "Tag \(index)",
        description: nil,
        similarityEnabled: true,
        source: "semantic-fixture"
      )
    }
    let stats = (0..<tagCount).map { index in
      SemanticTagStatsRecord(
        tagID: "tag-\(index)",
        directCardCount: 3,
        effectiveCardCount: 3,
        inverseFrequencyMillis: 1_000 + index
      )
    }
    func memberships(
      cardKey: SemanticCardKey,
      indices: some Sequence<Int>
    ) -> [SemanticCardTagRecord] {
      indices.map { index in
        SemanticCardTagRecord(
          cardKey: cardKey,
          tagID: "tag-\(index)",
          weightMillis: 1_000 + (index % 7),
          annotation: nil,
          source: "semantic-fixture"
        )
      }
    }
    let snapshot = SemanticCatalogSnapshot(
      tags: tags,
      aliases: [],
      edges: [],
      cardTags: memberships(cardKey: sourceKey, indices: 0..<tagCount)
        + memberships(cardKey: firstKey, indices: 0..<tagCount)
        + memberships(cardKey: secondKey, indices: (0..<tagCount).reversed()),
      stats: stats
    )

    let ranked = try SemanticRelatedCardScorer(snapshot: snapshot).rankedCandidates(
      for: sourceKey,
      among: [
        SemanticRelatedCardCandidate(
          cardKey: secondKey,
          printingID: "second-print",
          name: "B"
        ),
        SemanticRelatedCardCandidate(
          cardKey: firstKey,
          printingID: "first-print",
          name: "A"
        ),
      ]
    )

    #expect(ranked.map(\.name) == ["A", "B"])
    #expect(try #require(ranked.first).score == ranked.last?.score)
  }

  @Test
  func cancellationStopsAnInFlightLargeRankingPromptly() async throws {
    let sourceKey = SemanticCardKey(oracleID: "source", printingID: "source-print")
    let tagCount = 512
    let candidateCount = 30_000
    let tags = (0..<tagCount).map { index in
      SemanticTagRecord(
        id: "tag-\(index)",
        namespace: "oracle",
        slug: "tag-\(index)",
        label: "Tag \(index)",
        description: nil,
        similarityEnabled: true,
        source: "semantic-fixture"
      )
    }
    let stats = (0..<tagCount).map { index in
      SemanticTagStatsRecord(
        tagID: "tag-\(index)",
        directCardCount: candidateCount + 1,
        effectiveCardCount: candidateCount + 1,
        inverseFrequencyMillis: 1_000 + index
      )
    }
    var memberships = (0..<tagCount).map { index in
      SemanticCardTagRecord(
        cardKey: sourceKey,
        tagID: "tag-\(index)",
        weightMillis: 1_000,
        annotation: nil,
        source: "semantic-fixture"
      )
    }
    var candidates: [SemanticRelatedCardCandidate] = []
    candidates.reserveCapacity(candidateCount)
    memberships.reserveCapacity(tagCount + candidateCount * 8)
    for index in 0..<candidateCount {
      let cardKey = SemanticCardKey(
        oracleID: "candidate-\(index)",
        printingID: "candidate-print-\(index)"
      )
      candidates.append(
        SemanticRelatedCardCandidate(
          cardKey: cardKey,
          printingID: "candidate-print-\(index)",
          name: "Candidate \(index)"
        )
      )
      memberships.append(
        contentsOf: (0..<8).map { offset in
          let tagIndex = (index * 8 + offset) % tagCount
          return SemanticCardTagRecord(
            cardKey: cardKey,
            tagID: "tag-\(tagIndex)",
            weightMillis: 1_000,
            annotation: nil,
            source: "semantic-fixture"
          )
        })
    }
    let snapshot = SemanticCatalogSnapshot(
      tags: tags,
      aliases: [],
      edges: [],
      cardTags: memberships,
      stats: stats
    )
    let started = RelatedCardRankingStartSignal()
    let rankingTask = Task.detached {
      started.markStarted()
      let scorer = try SemanticRelatedCardScorer(snapshot: snapshot)
      let ranked = try scorer.rankedCandidates(
        for: sourceKey,
        among: candidates,
        filters: SemanticRelatedCardFilters(limit: 12)
      )
      try Task.checkCancellation()
      return ranked
    }
    #expect(started.waitUntilStarted())
    try await Task.sleep(nanoseconds: 10_000_000)

    let clock = ContinuousClock()
    let cancellationStart = clock.now
    rankingTask.cancel()
    let result = await rankingTask.result
    let cancellationDuration = cancellationStart.duration(to: clock.now)

    if case .failure(let error) = result {
      #expect(error is CancellationError)
    } else {
      Issue.record("Expected in-flight ranking to throw CancellationError")
    }
    #expect(cancellationDuration < .milliseconds(20))
  }
}

private final class RelatedCardRankingStartSignal: @unchecked Sendable {
  private let semaphore = DispatchSemaphore(value: 0)

  func markStarted() {
    semaphore.signal()
  }

  func waitUntilStarted() -> Bool {
    semaphore.wait(timeout: .now() + 1) == .success
  }
}

private func membership(
  cardKey: SemanticCardKey,
  weightMillis: Int
) -> SemanticCardTagRecord {
  SemanticCardTagRecord(
    cardKey: cardKey,
    tagID: "draw",
    weightMillis: weightMillis,
    annotation: nil,
    source: "semantic-fixture"
  )
}
