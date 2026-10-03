import Foundation
import GrimoraCore
import Testing

struct SemanticRelatedCardPerformanceTests {
  @Test
  func reportsOptInRelatedCardLookupMeasurements() async throws {
    guard ProcessInfo.processInfo.environment["GRIMORA_RELATED_CARD_BENCHMARK"] != nil else {
      return
    }

    let cardCount = 30_000
    let relatedCardCount = 500
    let tagCount = 4_557
    let membershipsPerCard = 8
    let database = try CardDatabase(storage: .inMemory)
    let cards = (0..<cardCount).map { index in
      CardRecord(
        id: "printing-\(index)",
        oracleID: "oracle-\(index)",
        name: String(format: "Card %05d", index),
        setCode: "tst",
        setName: "Test Set",
        setType: "expansion",
        collectorNumber: String(index + 1),
        collectorNumberNumber: index + 1,
        rarity: "common",
        colorSortKey: 6,
        layout: "normal",
        typeLine: "Artifact",
        oracleText: "Benchmark card."
      )
    }
    try database.replaceAllCards(cards)

    let tags = (0..<tagCount).map { index in
      SemanticTagRecord(
        id: "tag-\(index)",
        namespace: "oracle",
        slug: "tag-\(index)",
        label: "Tag \(index)",
        description: nil,
        similarityEnabled: true,
        source: "synthetic-related-card-benchmark"
      )
    }
    var memberships: [SemanticCardTagRecord] = []
    memberships.reserveCapacity(cardCount * membershipsPerCard)
    for index in 0..<cardCount {
      let tagIDs: [Int]
      if index < relatedCardCount {
        tagIDs = [0, 100, 101, 102, 103, 104, 105, 106]
      } else {
        let start = 200 + ((index * membershipsPerCard) % (tagCount - 208))
        tagIDs = (0..<membershipsPerCard).map { start + $0 }
      }
      let cardKey = SemanticCardKey(oracleID: "oracle-\(index)", printingID: "printing-\(index)")
      memberships.append(contentsOf: tagIDs.map { tagID in
        SemanticCardTagRecord(
          cardKey: cardKey,
          tagID: "tag-\(tagID)",
          weightMillis: 1_000 + (tagID % 7),
          annotation: nil,
          source: "synthetic-related-card-benchmark"
        )
      })
    }
    let stats = (0..<tagCount).map { index in
      SemanticTagStatsRecord(
        tagID: "tag-\(index)",
        directCardCount: 1,
        effectiveCardCount: cardCount,
        inverseFrequencyMillis: 1_000 + (index % 500)
      )
    }
    try database.replaceSemanticCatalog(
      with: SemanticCatalogSnapshot(
        tags: tags,
        aliases: [],
        edges: [],
        cardTags: memberships,
        stats: stats
      )
    )

    let clock = ContinuousClock()
    let start = clock.now
    let lookup = try await database.semanticRelatedCards(
      for: cards[0],
      filters: SemanticRelatedCardFilters(limit: 6)
    )
    let elapsed = start.duration(to: clock.now)
    let milliseconds = Double(elapsed.components.seconds) * 1_000
      + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    guard case .available(let related) = lookup else {
      Issue.record("Expected related-card lookup to be available")
      return
    }

    #expect(related.count == 6)
    #expect(related.allSatisfy { $0.card.oracleID != cards[0].oracleID })
    print("\nRELATED_CARD_BENCHMARK_BEGIN")
    print("cards=\(cardCount)")
    print("memberships=\(memberships.count)")
    print("candidate_pool=\(relatedCardCount - 1)")
    print(String(format: "lookup_ms=%.3f", milliseconds))
    print("results=\(related.count)")
    print("RELATED_CARD_BENCHMARK_END\n")
  }
}
