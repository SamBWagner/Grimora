import Foundation
import Testing

@testable import GrimoraCore

struct CardCollectionSemanticProfileTests {
  @Test func emptyAndOneCardProfilesAreHonest() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let card = makeCard("a")
    try database.replaceAllCards([card])
    try database.replaceSemanticCatalog(with: semantics([card]))
    let empty = try await database.collectionSemanticProfile(for: list(), entries: [])
    guard case .available(let profile) = empty else {
      Issue.record("Expected available empty profile")
      return
    }
    #expect(profile.nodes.isEmpty)
    #expect(profile.coverage == 0)
    #expect(profile.edges.isEmpty)
    let result = try await database.collectionSemanticProfile(for: list(), entries: [entry(card)])
    guard case .available(let single) = result else {
      Issue.record("Expected single profile")
      return
    }
    #expect(single.nodes.count == 1)
    #expect(single.coveredCardCount == 1)
    #expect(single.coverage == 1)
    #expect(single.edges.isEmpty)
    #expect(single.nodes[0].weightedDegree == 0)
    #expect(single.fewLinkCards.isEmpty)
  }

  @Test func printingsCollapseQuantitiesAndZonesRemainExplicit() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let a = makeCard("a", oracleID: "shared")
    let b = makeCard("b", oracleID: "shared")
    let c = makeCard("c")
    try database.replaceAllCards([a, b, c])
    try database.replaceSemanticCatalog(with: semantics([a, c]))
    let entries = [
      entry(a, zone: .commander), entry(b, quantity: 3), entry(c, zone: .maybeboard, quantity: 8),
      entry(c, zone: .sideboard, id: "side"),
    ]
    let profile = try await available(database, list: list(.commander), entries: entries)
    #expect(profile.nodes.count == 1)
    #expect(profile.nodes[0].quantity == 4)
    #expect(profile.nodes[0].entries.map(\.entryID) == ["a", "b"])
    #expect(profile.commanderCardKeys == [.init(oracleID: "shared", printingID: "a")])
    #expect(profile.excludedEntries.count == 2)
    #expect(profile.validationWarnings.contains { $0.id.hasPrefix("commander-singleton") })
    #expect(profile.dominantConcepts[0].supportCardCount == 1)
    let collection = try await available(database, list: list(), entries: entries)
    #expect(collection.commanderCardKeys.isEmpty)
    #expect(collection.nodes[0].quantity == 3)
    #expect(collection.excludedEntries.count == 3)
  }

  @Test func blankOracleIdentityFallsBackToPrinting() async throws {
    let database = try CardDatabase(storage: .inMemory)
    var cards = [makeCard("nil"), makeCard("empty"), makeCard("blank")]
    cards[0].oracleID = nil
    cards[1].oracleID = ""
    cards[2].oracleID = " \t\n "
    try database.replaceAllCards(cards)
    try database.replaceSemanticCatalog(with: semantics(cards))
    let profile = try await available(database, list: list(), entries: cards.map { entry($0) })
    #expect(profile.nodes.map { $0.cardKey.rawValue } == ["p:blank", "p:empty", "p:nil"])
    #expect(profile.coveredCardCount == 3)
    #expect(profile.edges.count == 3)
  }

  @Test func partialCoverageIncludesMissingRecordsAndDisabledMetadata() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let cards = [makeCard("a"), makeCard("b"), makeCard("c")]
    try database.replaceAllCards(cards)
    var snapshot = semantics([cards[0]])
    snapshot.tags.append(
      .init(
        id: "metadata", namespace: "oracle", slug: "metadata", label: "Metadata", description: nil,
        similarityEnabled: false, source: "fixture"))
    snapshot.cardTags.append(
      .init(
        cardKey: .init(oracleID: "b", printingID: "b"), tagID: "metadata", weightMillis: 1000,
        annotation: nil, source: "fixture"))
    try database.replaceSemanticCatalog(with: snapshot)
    let profile = try await available(
      database, list: list(), entries: cards.map { entry($0) } + [entry(makeCard("missing"))])
    #expect(profile.nodes.count == 3)
    #expect(profile.missingCardEntries.map(\.printingID) == ["missing"])
    #expect(profile.coveredCardCount == 1)
    #expect(profile.coverage == 0.25)
    #expect(profile.nodes.filter { !$0.hasSemanticData }.count == 2)
    #expect(profile.dominantConcepts.map(\.tagID) == ["draw"])
    #expect(profile.edges.isEmpty)
    let legacy = try CardDatabase(storage: .inMemory)
    #expect(try await legacy.collectionSemanticProfile(for: list(), entries: []) == .unavailable)
  }

  @Test func conceptsEdgesAndRelativeFewLinksRetainExactEvidence() throws {
    let cards = (0..<5).map { makeCard("card-\($0)") }
    var snapshot = semantics(Array(cards.prefix(4)))
    snapshot.tags.append(
      .init(
        id: "broad", namespace: "oracle", slug: "broad", label: "Broad", description: nil,
        similarityEnabled: true, source: "parent-source"))
    snapshot.edges = [.init(parentTagID: "broad", childTagID: "draw")]
    snapshot.stats[0].inverseFrequencyMillis = 3000
    snapshot.stats.append(
      .init(tagID: "broad", directCardCount: 0, effectiveCardCount: 4, inverseFrequencyMillis: 1000)
    )
    let profile = try CardCollectionSemanticProfiler.profile(
      for: list(), entries: cards.map { entry($0) }, snapshot: snapshot)
    let draw = try #require(profile.dominantConcepts.first)
    #expect(draw.tagID == "draw")
    #expect(draw.supportCardCount == 4)
    #expect(draw.coverage == 0.8)
    #expect(abs(draw.importance - 2.4) < 0.000001)
    #expect(draw.supports.map { $0.cardKey.rawValue } == (0..<4).map { "o:card-\($0)" })
    #expect(profile.dominantConcepts[1].importance == 0.4)
    #expect(profile.dominantConcepts[1].supports[0].assertions[0].tagPath == ["draw", "broad"])
    #expect(profile.dominantConcepts[1].supports[0].sources == ["fixture", "parent-source"])
    #expect(profile.edges.count == 6)
    #expect(profile.edges[0].sharedConcepts.map(\.tagID) == ["draw", "broad"])
    #expect(profile.edges[0].sharedConcepts[0].contribution == 9)
    #expect(profile.nodes[0].linkCount == 3)
    #expect(profile.nodes[0].weightedDegree > 2.99)
    #expect(profile.fewLinkCards.map(\.rawValue) == ["o:card-4"])
    #expect(profile.fewLinkEvidence[0].reason == .missingSemanticData)
    #expect(profile.fewLinkEvidence[0].missingSemanticDataAffectedMeasurement)
    #expect(profile.highlyConnectedCards.count == 4)
  }

  @Test func independentRunsReversedOrderDuplicateAssertionsAndCyclesAreStable() throws {
    let cards = (0..<60).map { makeCard("card-\($0)") }
    let entries = cards.map { entry($0, quantity: 4) }
    var snapshot = semantics(cards)
    snapshot.tags.append(
      .init(
        id: "parent", namespace: "oracle", slug: "parent", label: "Parent", description: nil,
        similarityEnabled: true, source: "é-source"))
    snapshot.edges = [
      .init(parentTagID: "parent", childTagID: "draw"),
      .init(parentTagID: "draw", childTagID: "parent"),
    ]
    let expected = try CardCollectionSemanticProfiler.profile(
      for: list(), entries: entries, snapshot: snapshot)
    #expect(expected.nodes.count == 60)
    #expect(expected.edges.count == 1770)
    #expect(expected.nodes.allSatisfy { $0.quantity == 4 && $0.linkCount == 59 })
    snapshot.cardTags += snapshot.cardTags
    snapshot.cardTags.reverse()
    snapshot.tags.reverse()
    snapshot.edges.reverse()
    snapshot.stats.reverse()
    for _ in 0..<3 {
      let actual = try CardCollectionSemanticProfiler.profile(
        for: list(), entries: entries.reversed(), snapshot: snapshot)
      #expect(actual == expected)
    }
  }

  @Test func isolatedZeroWeightAndSingleCardCasesHaveNoRelativeJudgment() throws {
    let cards = (0..<4).map { makeCard("card-\($0)") }
    var snapshot = semantics(cards)
    snapshot.cardTags = cards.enumerated().map { index, card in
      .init(
        cardKey: .init(oracleID: card.oracleID, printingID: card.id), tagID: "tag-\(index)",
        weightMillis: index == 3 ? 0 : 1000, annotation: nil, source: "fixture")
    }
    snapshot.tags = (0..<4).map {
      .init(
        id: "tag-\($0)", namespace: "oracle", slug: "tag-\($0)", label: "Tag", description: nil,
        similarityEnabled: true, source: "fixture")
    }
    snapshot.stats = []
    let profile = try CardCollectionSemanticProfiler.profile(
      for: list(), entries: cards.map { entry($0) }, snapshot: snapshot)
    #expect(profile.edges.isEmpty)
    #expect(profile.coveredCardCount == 3)
    #expect(profile.fewLinkCards.isEmpty)
    #expect(profile.highlyConnectedCards.isEmpty)
    #expect(profile.listMedianWeightedDegree == 0)
  }

  @Test func fingerprintCacheAndSemanticGenerationInvalidation() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let cards = [makeCard("a"), makeCard("b")]
    let entries = cards.map { entry($0) }
    try database.replaceAllCards(cards)
    try database.replaceSemanticCatalog(with: semantics(cards))
    let first = try await available(database, list: list(), entries: entries)
    #expect(database.withDatabaseLock { database.collectionSemanticProfileCache.count } == 1)
    let hit = try await available(database, list: list(), entries: entries.reversed())
    #expect(first == hit)
    var changed = entries
    changed[0].quantity = 2
    let quantity = try await available(database, list: list(), entries: changed)
    #expect(quantity.contentFingerprint != first.contentFingerprint)
    #expect(quantity.nodes[0].quantity == 2)
    changed[0].zone = .maybeboard
    let zone = try await available(database, list: list(), entries: changed)
    #expect(zone.contentFingerprint != quantity.contentFingerprint)
    #expect(zone.nodes.count == 1)
    let supplemental = try await available(
      database, list: list(), entries: changed, policy: .init(includesMaybeboard: true))
    #expect(supplemental.nodes.count == 2)
    #expect(supplemental.contentFingerprint != zone.contentFingerprint)
    let commander = try await available(
      database, list: list(.commander), entries: [entry(cards[0], zone: .commander), entries[1]])
    #expect(commander.commanderCardKeys.count == 1)
    #expect(commander.contentFingerprint != first.contentFingerprint)
    try database.replaceSemanticCatalog(with: semantics([cards[0]]))
    #expect(database.withDatabaseLock { database.collectionSemanticProfileCache.isEmpty })
    let replacement = try await available(database, list: list(), entries: entries)
    #expect(replacement.edges.isEmpty)
    #expect(replacement.catalogGeneration != first.catalogGeneration)
    try database.resetForStreamingCatalogBuild()
    let reset = try await available(database, list: list(), entries: entries)
    #expect(reset.nodes.isEmpty)
    #expect(reset.missingCardEntries.count == 2)
    try database.appendCatalogCards(cards)
    let appended = try await available(database, list: list(), entries: entries)
    #expect(appended.nodes.count == 2)
    #expect(appended.catalogGeneration != reset.catalogGeneration)
  }

  @Test func generationChangeRetriesExtractionAndDoesNotHoldLockForAggregation() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let cards = [makeCard("a"), makeCard("b")]
    try database.replaceAllCards(cards)
    try database.replaceSemanticCatalog(with: semantics(cards))
    let extracted = ProfileGate()
    let resume = ProfileGate()
    let attempts = ProfileAttempts()
    let task = Task {
      try await database.collectionSemanticProfile(
        for: list(), entries: cards.map { entry($0) }, policy: .init(),
        afterInput: {
          if await attempts.record() == 1 {
            await extracted.open()
            await resume.wait()
          }
        })
    }
    await extracted.wait()
    try database.replaceSemanticCatalog(with: semantics([cards[1]]))
    await resume.open()
    let lookup = try await task.value
    guard case .available(let profile) = lookup else {
      Issue.record("Expected retried profile")
      return
    }
    #expect(profile.coveredCardCount == 1)
    #expect(profile.edges.isEmpty)
    #expect(await attempts.count == 2)
  }

  @Test func cancellationWaitingForLockDoesNotQueueExtraction() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let blocker = ProfileBlocker()
    let holder = Task.detached { database.withDatabaseLock { blocker.pause() } }
    #expect(blocker.waitUntilPaused())
    let task = Task { try await database.collectionSemanticProfile(for: list(), entries: []) }
    try await Task.sleep(for: .milliseconds(20))
    let start = ContinuousClock.now
    task.cancel()
    let result = await task.result
    blocker.resume()
    await holder.value
    guard case .failure(let error) = result else {
      Issue.record("Canceled lock waiter returned a profile")
      return
    }
    #expect(error is CancellationError)
    #expect(start.duration(to: .now) < .milliseconds(150))
  }

  @Test func cancellationStopsInFlightAggregationOutsideDatabaseLock() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let cards = (0..<100).map { makeCard("card-\($0)") }
    try database.replaceAllCards(cards)
    try database.replaceSemanticCatalog(with: semantics(cards))
    let blocker = ProfileBlocker()
    let task = Task {
      try await database.collectionSemanticProfile(
        for: list(.commander), entries: cards.map { entry($0) }, policy: .init(), afterInput: nil,
        beforeEdges: { blocker.pause() })
    }
    #expect(blocker.waitUntilPaused())
    // Extraction and feature/concept aggregation have already finished. Another thread can
    // mutate the database while the aggregation task is paused, proving no global lock is held.
    try database.replaceAllCards(cards)
    task.cancel()
    blocker.resume()
    guard case .failure(let error) = await task.result else {
      Issue.record("Canceled aggregation completed")
      return
    }
    #expect(error is CancellationError)
  }

  @Test func hierarchyUsesOneCanonicalStrongestPathPerAssertion() throws {
    let card = makeCard("a")
    var snapshot = semantics([card])
    snapshot.tags += ["left", "right", "root"].map {
      .init(
        id: $0, namespace: "oracle", slug: $0, label: $0, description: nil, similarityEnabled: true,
        source: $0)
    }
    snapshot.edges = [
      .init(parentTagID: "left", childTagID: "draw"),
      .init(parentTagID: "right", childTagID: "draw"),
      .init(parentTagID: "root", childTagID: "left"),
      .init(parentTagID: "root", childTagID: "right"),
    ]
    let profile = try CardCollectionSemanticProfiler.profile(
      for: list(), entries: [entry(card)], snapshot: snapshot)
    let root = try #require(profile.dominantConcepts.first { $0.tagID == "root" })
    #expect(root.supports[0].effectiveWeight == 0.25)
    #expect(root.supports[0].sources == ["fixture", "left", "right", "root"])
    #expect(root.supports[0].assertions.map(\.tagPath) == [["draw", "left", "root"]])
  }

  @Test func sixtyCardConstructedCopiesDoNotMultiplyPresence() throws {
    let cards = (0..<15).map { makeCard("card-\($0)") }
    let profile = try CardCollectionSemanticProfiler.profile(
      for: list(), entries: cards.map { entry($0, quantity: 4) }, snapshot: semantics(cards))
    #expect(profile.nodes.reduce(0) { $0 + $1.quantity } == 60)
    #expect(profile.nodes.count == 15)
    #expect(profile.dominantConcepts[0].supportCardCount == 15)
    #expect(profile.edges.count == 105)
  }

  @Test func attachedCatalogShadowingReplacementAndRaceDoNotReuseStaleProfiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "profile-attached-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cards = [makeCard("a"), makeCard("b")]
    func catalog(_ filename: String, tagged: [CardRecord]) throws -> URL {
      let url = directory.appendingPathComponent(filename)
      let writer = try CardDatabase(storage: .file(url))
      try writer.replaceAllCards(cards)
      try writer.replaceSemanticCatalog(with: semantics(tagged))
      try writer.prepareForCatalogDistribution()
      return url
    }
    let current = try catalog("Catalog.sqlite", tagged: cards)
    let replacement = try catalog("Replacement.sqlite", tagged: [cards[1]])
    let database = try CardDatabase(
      userDatabaseURL: directory.appendingPathComponent("User.sqlite"), catalogURL: current)
    // Deliberately recreate stale main tables. Explicit catalog-schema reads must win.
    try database.withDatabaseLock {
      try database.database.execute(
        "CREATE TABLE main.semantic_tags (id TEXT); CREATE TABLE main.semantic_card_tags (card_key TEXT); CREATE TABLE main.semantic_tag_stats (tag_id TEXT); CREATE TABLE main.semantic_tag_edges (parent_tag_id TEXT)"
      )
    }
    let entries = cards.map { entry($0) }
    let original = try await available(database, list: list(), entries: entries)
    #expect(original.edges.count == 1)
    let counts = try CardDatabase.validateCatalog(at: replacement)
    let manifest = CatalogManifest(
      version: "profile-replacement", generatedAt: .distantPast,
      sources: .init(
        scryfallUpdatedAt: "fixture", mtgjsonDate: "fixture", mtgjsonVersion: "fixture"),
      artifact: .init(
        downloadURL: URL(string: "https://example.test/profile")!, compressedBytes: 0,
        uncompressedBytes: 0, sha256: "", uncompressedSHA256: ""), counts: counts)
    let extracted = ProfileGate()
    let resume = ProfileGate()
    let attempts = ProfileAttempts()
    var changed = entries
    changed[0].quantity = 2  // Force a cold extraction.
    let raceEntries = changed
    let task = Task {
      try await database.collectionSemanticProfile(
        for: list(), entries: raceEntries, policy: .init(),
        afterInput: {
          if await attempts.record() == 1 {
            await extracted.open()
            await resume.wait()
          }
        })
    }
    await extracted.wait()
    try database.installCatalog(from: replacement, expectedManifest: manifest)
    await resume.open()
    guard case .available(let retried) = try await task.value else {
      Issue.record("Expected replacement profile")
      return
    }
    #expect(await attempts.count == 2)
    #expect(retried.coveredCardCount == 1)
    #expect(retried.edges.isEmpty)
    let refreshed = try await available(database, list: list(), entries: entries)
    #expect(refreshed.edges.isEmpty)
    #expect(refreshed.catalogGeneration != original.catalogGeneration)
    #expect(refreshed.nodes[0].printingID == "a")
  }

  @Test func fewLinksDistinguishesPresentDataFromMissingDataWithoutQualityLabels() throws {
    let cards = (0..<5).map { makeCard("card-\($0)") }
    var snapshot = semantics(cards)
    snapshot.cardTags[4].weightMillis = 100
    snapshot.tags.append(
      .init(
        id: "specific", namespace: "oracle", slug: "specific", label: "Specific", description: nil,
        similarityEnabled: true, source: "fixture"))
    snapshot.cardTags.append(
      .init(
        cardKey: .init(oracleID: cards[4].oracleID, printingID: cards[4].id), tagID: "specific",
        weightMillis: 1000, annotation: nil, source: "fixture"))
    snapshot.stats.append(
      .init(
        tagID: "specific", directCardCount: 1, effectiveCardCount: 1, inverseFrequencyMillis: 3000))
    let profile = try CardCollectionSemanticProfiler.profile(
      for: list(), entries: cards.map { entry($0) }, snapshot: snapshot)
    #expect(profile.coverage == 1)
    #expect(profile.fewLinkEvidence.count == 1)
    #expect(profile.fewLinkEvidence[0].reason == .belowListMedian)
    #expect(profile.fewLinkEvidence[0].linkCount == 4)
    #expect(!profile.fewLinkEvidence[0].missingSemanticDataAffectedMeasurement)
    snapshot.cardTags.removeAll { $0.cardKey.oracleID == cards[4].oracleID && $0.tagID == "draw" }
    let isolated = try CardCollectionSemanticProfiler.profile(
      for: list(), entries: cards.map { entry($0) }, snapshot: snapshot)
    #expect(isolated.fewLinkEvidence[0].reason == .noSharedEnabledConcepts)
    #expect(!isolated.fewLinkEvidence[0].missingSemanticDataAffectedMeasurement)
  }

  private func available(
    _ database: CardDatabase, list: CardCollectionRecord, entries: [CardCollectionEntryRecord],
    policy: CardCollectionSemanticPolicy = .init()
  ) async throws -> CardCollectionSemanticProfile {
    let result = try await database.collectionSemanticProfile(
      for: list, entries: entries, policy: policy)
    guard case .available(let profile) = result else { throw ProfileTestError.unavailable }
    return profile
  }
  private enum ProfileTestError: Error { case unavailable }

  private func list(_ ruleset: CardCollectionRuleset = .none) -> CardCollectionRecord {
    .init(
      id: "list", name: "Fixture", ruleset: ruleset, createdAt: .distantPast,
      updatedAt: .distantPast)
  }
  private func makeCard(_ id: String, oracleID: String? = nil) -> CardRecord {
    .init(
      id: id, oracleID: oracleID ?? id, name: id, setCode: "tst", setName: "Test",
      setType: "expansion", collectorNumber: id, rarity: "common", manaCost: "{W}", colorSortKey: 0,
      layout: "normal", typeLine: "Creature", oracleText: "Fixture.")
  }
  private func entry(
    _ card: CardRecord, zone: CardCollectionZone = .mainboard, quantity: Int = 1, id: String? = nil
  ) -> CardCollectionEntryRecord {
    .init(
      id: id ?? card.id, listID: "list", zone: zone, cardID: card.id, position: 0,
      quantity: quantity, createdAt: .distantPast, card: card)
  }
  private func semantics(_ cards: [CardRecord]) -> SemanticCatalogSnapshot {
    .init(
      tags: [
        .init(
          id: "draw", namespace: "oracle", slug: "draw", label: "Draw", description: nil,
          similarityEnabled: true, source: "fixture")
      ], aliases: [], edges: [],
      cardTags: cards.map {
        .init(
          cardKey: .init(oracleID: $0.oracleID, printingID: $0.id), tagID: "draw",
          weightMillis: 1000, annotation: nil, source: "fixture")
      },
      stats: [
        .init(
          tagID: "draw", directCardCount: cards.count, effectiveCardCount: cards.count,
          inverseFrequencyMillis: 1000)
      ])
  }
}

private actor ProfileGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func open() {
    isOpen = true
    let pending = waiters
    waiters = []
    for waiter in pending { waiter.resume() }
  }
}
private actor ProfileAttempts {
  var count = 0
  func record() -> Int {
    count += 1
    return count
  }
}

private final class ProfileBlocker: @unchecked Sendable {
  private let condition = NSCondition()
  private var paused = false
  private var released = false
  func pause() {
    condition.lock()
    defer { condition.unlock() }
    paused = true
    condition.broadcast()
    while !released { condition.wait() }
  }
  func waitUntilPaused() -> Bool {
    condition.lock()
    defer { condition.unlock() }
    let deadline = Date().addingTimeInterval(5)
    while !paused { if !condition.wait(until: deadline) { return false } }
    return true
  }
  func resume() {
    condition.lock()
    released = true
    condition.broadcast()
    condition.unlock()
  }
}
