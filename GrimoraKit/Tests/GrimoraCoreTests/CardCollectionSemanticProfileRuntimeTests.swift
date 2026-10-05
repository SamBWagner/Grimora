import Darwin
import Foundation
import GrimoraCore
import XCTest

/// Runs unconditionally on the host and in each Xcode simulator profile-test target.
/// The fixture is seeded into the production database; both cold and cached APIs are measured.
@MainActor
final class CardCollectionSemanticProfileRuntimeTests: XCTestCase {
  func testSeededHundredCardCommanderPartialAndHighConnectivityBenchmarks() async throws {
    for highConnectivity in [false, true] {
      let database = try CardDatabase(storage: .inMemory)
      let fixture = fixture(highConnectivity: highConnectivity)
      try database.replaceAllCards(fixture.cards)
      try database.replaceSemanticCatalog(with: fixture.snapshot)
      let memoryBefore = try residentMemoryBytes()
      let start = ContinuousClock.now
      let lookup = try await database.collectionSemanticProfile(
        for: fixture.list, entries: fixture.entries)
      let cold = start.duration(to: .now)
      let memoryAfter = try residentMemoryBytes()
      guard case .available(let profile) = lookup else {
        return XCTFail("Seeded catalog unavailable")
      }
      XCTAssertEqual(profile.nodes.count, 100)
      XCTAssertEqual(profile.nodes.reduce(0) { $0 + $1.quantity }, 100)
      XCTAssertEqual(profile.commanderCardKeys.count, 1)
      XCTAssertEqual(profile.coveredCardCount, highConnectivity ? 100 : 75)
      XCTAssertTrue(profile.validationWarnings.isEmpty)
      XCTAssertEqual(profile.edges.count, highConnectivity ? 4950 : 525)
      let warmStart = ContinuousClock.now
      let warm = try await database.collectionSemanticProfile(
        for: fixture.list, entries: fixture.entries.reversed())
      let warmTime = warmStart.duration(to: .now)
      XCTAssertEqual(warm, lookup)
      print(
        "COLLECTION_PROFILE_BENCHMARK mode=\(highConnectivity ? "high-connectivity" : "partial-75-percent") nodes=100 edges=\(profile.edges.count) cold_ms=\(milliseconds(cold)) warm_ms=\(milliseconds(warmTime)) resident_before_bytes=\(memoryBefore) resident_after_bytes=\(memoryAfter) resident_delta_bytes=\(Int64(memoryAfter) - Int64(memoryBefore))"
      )
    }
  }

  private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
  }

  private func residentMemoryBytes() throws -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { throw BenchmarkError.memoryMeasurementFailed(result) }
    return info.resident_size
  }

  private enum BenchmarkError: Error { case memoryMeasurementFailed(kern_return_t) }

  private func fixture(highConnectivity: Bool) -> (
    list: CardCollectionRecord, cards: [CardRecord], entries: [CardCollectionEntryRecord],
    snapshot: SemanticCatalogSnapshot
  ) {
    let list = CardCollectionRecord(
      id: "seeded-commander", name: "Seeded Commander", ruleset: .commander,
      createdAt: .distantPast, updatedAt: .distantPast)
    let cards = (0..<100).map { index in
      CardRecord(
        id: "printing-\(index)", oracleID: "oracle-\(index)", name: "Seeded card \(index)",
        setCode: "tst", setName: "Seeded Profile", setType: "expansion",
        collectorNumber: String(index), rarity: "common", colorSortKey: 0, layout: "normal",
        typeLine: index == 0 ? "Legendary Creature" : "Creature",
        oracleText: "Seeded runtime fixture.", legalities: ["commander": "legal"])
    }
    let entries = cards.enumerated().map { index, card in
      CardCollectionEntryRecord(
        id: "entry-\(index)", listID: list.id, zone: index == 0 ? .commander : .mainboard,
        cardID: card.id, position: index, createdAt: .distantPast, card: card)
    }
    let tagCount = highConnectivity ? 8 : 5
    let tags = (0..<tagCount).map { index in
      SemanticTagRecord(
        id: "functional-\(index)", namespace: "oracle", slug: "functional-\(index)",
        label: "Functional concept \(index)", description: nil, similarityEnabled: true,
        source: "seeded-profile-fixture")
    }
    let coveredCards = highConnectivity ? cards : Array(cards.prefix(75))
    let memberships = coveredCards.enumerated().flatMap { index, card in
      let indices = highConnectivity ? Array(0..<tagCount) : [index % tagCount]
      return indices.map { tagIndex in
        SemanticCardTagRecord(
          cardKey: .init(oracleID: card.oracleID, printingID: card.id),
          tagID: "functional-\(tagIndex)", weightMillis: 1000,
          annotation: "Seeded deterministic measurement", source: "seeded-profile-fixture")
      }
    }
    let stats = tags.map { tag in
      let count = memberships.filter { $0.tagID == tag.id }.count
      return SemanticTagStatsRecord(
        tagID: tag.id, directCardCount: count, effectiveCardCount: count,
        inverseFrequencyMillis: Int((1000 * (1 + log(101.0 / Double(count + 1)))).rounded()))
    }
    return (
      list, cards, entries,
      .init(tags: tags, aliases: [], edges: [], cardTags: memberships, stats: stats)
    )
  }
}
