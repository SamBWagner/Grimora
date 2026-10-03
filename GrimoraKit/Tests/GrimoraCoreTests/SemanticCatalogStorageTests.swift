@testable import GrimoraCore
import Foundation
import Testing

struct SemanticCatalogStorageTests {
  @Test
  func replacementPersistsAllSemanticRecordsAndSupportsBothTraversalDirections() throws {
    let database = try CardDatabase(storage: .inMemory)
    let snapshot = semanticSnapshot()

    try database.replaceSemanticCatalog(with: snapshot)

    #expect(try database.semanticCatalogSnapshot() == snapshot)
    #expect(
      try database.semanticTagIDs(for: SemanticCardKey(oracleID: "oracle-card", printingID: "print-a"))
        == ["tag-card-draw"]
    )
    #expect(
      try database.semanticCardKeys(tagID: "tag-card-draw")
        == [SemanticCardKey(oracleID: "oracle-card", printingID: "print-b")]
    )
    #expect(try semanticIndexNames(database: database).isSuperset(of: [
      "idx_semantic_card_tags_card_tag",
      "idx_semantic_card_tags_tag_card",
      "idx_semantic_tag_aliases_key",
      "idx_semantic_tag_edges_child_parent",
    ]))
  }

  @Test
  func malformedReplacementRollsBackToThePreviousSemanticCatalog() throws {
    let database = try CardDatabase(storage: .inMemory)
    let original = semanticSnapshot()
    try database.replaceSemanticCatalog(with: original)

    var malformed = original
    malformed.edges.append(
      SemanticTagEdgeRecord(parentTagID: "missing-parent", childTagID: "tag-card-draw")
    )

    #expect(throws: (any Error).self) {
      try database.replaceSemanticCatalog(with: malformed)
    }
    #expect(try database.semanticCatalogSnapshot() == original)
  }

  @Test
  func invalidSemanticRecordsAreRejectedWithoutReplacingThePreviousCatalog() throws {
    let original = semanticSnapshot()

    var blankTag = original
    blankTag.tags[0].id = " "

    var emptyCardIdentity = original
    emptyCardIdentity.cardTags[0].cardKey = SemanticCardKey(rawValue: "o:")

    var mismatchedAliasKey = original
    mismatchedAliasKey.aliases[0].aliasKey = "not-the-normalized-alias"

    var duplicateMembership = original
    duplicateMembership.cardTags.append(original.cardTags[0])

    var invalidStats = original
    invalidStats.stats[0].effectiveCardCount = -1

    for invalid in [
      blankTag,
      emptyCardIdentity,
      mismatchedAliasKey,
      duplicateMembership,
      invalidStats,
    ] {
      try expectRejectedSemanticReplacement(invalid, preserving: original)
    }
  }

  @Test
  func cyclicHierarchyIsRejectedWithoutReplacingThePreviousCatalog() throws {
    let original = semanticSnapshot()
    var cyclic = original
    cyclic.edges.append(
      SemanticTagEdgeRecord(
        parentTagID: "tag-card-draw",
        childTagID: "tag-card-advantage"
      )
    )

    try expectRejectedSemanticReplacement(cyclic, preserving: original)
  }

  @Test
  func cardToTagTraversalDeduplicatesMembershipsFromMultipleSources() throws {
    let database = try CardDatabase(storage: .inMemory)
    var snapshot = semanticSnapshot()
    var secondSource = snapshot.cardTags[0]
    secondSource.source = "curated-overrides"
    snapshot.cardTags.append(secondSource)

    try database.replaceSemanticCatalog(with: snapshot)

    #expect(
      try database.semanticTagIDs(for: snapshot.cardTags[0].cardKey)
        == ["tag-card-draw"]
    )
  }

  @Test
  func functionalTagLookupIsUnavailableWithoutGameplayEnabledOracleTags() throws {
    let database = try CardDatabase(storage: .inMemory)
    let cardKey = SemanticCardKey(oracleID: "oracle-card", printingID: "print-a")

    #expect(try database.semanticFunctionalTags(for: cardKey) == .unavailable)

    try database.replaceSemanticCatalog(
      with: SemanticCatalogSnapshot(
        tags: [
          SemanticTagRecord(
            id: "tag-metadata",
            namespace: "metadata",
            slug: "alliteration",
            label: "Alliteration",
            description: nil,
            similarityEnabled: true,
            source: "metadata-fixture"
          )
        ],
        aliases: [],
        edges: [],
        cardTags: [],
        stats: []
      )
    )

    #expect(try database.semanticFunctionalTags(for: cardKey) == .unavailable)
  }

  @Test
  func functionalTagLookupReturnsAvailableEmptyForAnUntaggedCardInAnOracleCatalog() throws {
    let database = try CardDatabase(storage: .inMemory)
    var snapshot = semanticSnapshot()
    snapshot.cardTags = []
    snapshot.stats = []
    try database.replaceSemanticCatalog(with: snapshot)

    #expect(
      try database.semanticFunctionalTags(
        for: SemanticCardKey(oracleID: "untagged-card", printingID: "print-z")
      ) == .available([])
    )
  }

  @Test
  func relatedCardsCollapsePrintingsExcludeTheSourceAndReturnExplanations() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let source = relatedCard(id: "source-print", oracleID: "source", name: "Source")
    let preferredCandidate = relatedCard(
      id: "candidate-base",
      oracleID: "candidate",
      name: "Candidate",
      language: "en",
      isBasePrinting: true
    )
    let alternateCandidate = relatedCard(
      id: "candidate-alt",
      oracleID: "candidate",
      name: "Candidate",
      language: "ja",
      isBasePrinting: false
    )
    let unrelated = relatedCard(id: "unrelated", oracleID: "unrelated", name: "Unrelated")
    try database.replaceAllCards([source, preferredCandidate, alternateCandidate, unrelated])
    try database.replaceSemanticCatalog(
      with: SemanticCatalogSnapshot(
        tags: [
          SemanticTagRecord(
            id: "draw",
            namespace: "oracle",
            slug: "draw-engine",
            label: "Draw Engine",
            description: nil,
            similarityEnabled: true,
            source: "tag-source"
          )
        ],
        aliases: [],
        edges: [],
        cardTags: [
          SemanticCardTagRecord(
            cardKey: SemanticCardKey(oracleID: "source", printingID: source.id),
            tagID: "draw",
            weightMillis: 1_000,
            annotation: nil,
            source: "source-membership"
          ),
          SemanticCardTagRecord(
            cardKey: SemanticCardKey(oracleID: "candidate", printingID: preferredCandidate.id),
            tagID: "draw",
            weightMillis: 1_000,
            annotation: nil,
            source: "candidate-membership"
          ),
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
    )

    let lookup = try await database.semanticRelatedCards(for: source)
    guard case .available(let related) = lookup else {
      Issue.record("Expected semantic related cards to be available")
      return
    }

    #expect(related.map(\.card.id) == ["candidate-base"])
    #expect(related[0].sharedConcepts.map(\.slug) == ["draw-engine"])
    #expect(related[0].sharedConcepts[0].sources == [
      "candidate-membership",
      "source-membership",
      "tag-source",
    ])
  }

  @Test
  func relatedCardsIncludeCandidatesThatShareOnlyAnInheritedConcept() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let source = relatedCard(id: "source-print", oracleID: "source", name: "Source")
    let candidate = relatedCard(id: "candidate-print", oracleID: "candidate", name: "Candidate")
    try database.replaceAllCards([source, candidate])
    try database.replaceSemanticCatalog(
      with: SemanticCatalogSnapshot(
        tags: [
          SemanticTagRecord(
            id: "draw",
            namespace: "oracle",
            slug: "draw",
            label: "Draw",
            description: nil,
            similarityEnabled: true,
            source: "tag-source"
          ),
          SemanticTagRecord(
            id: "enchantment-draw",
            namespace: "oracle",
            slug: "enchantment-draw",
            label: "Enchantment Draw",
            description: nil,
            similarityEnabled: true,
            source: "tag-source"
          ),
          SemanticTagRecord(
            id: "creature-draw",
            namespace: "oracle",
            slug: "creature-draw",
            label: "Creature Draw",
            description: nil,
            similarityEnabled: true,
            source: "tag-source"
          ),
        ],
        aliases: [],
        edges: [
          SemanticTagEdgeRecord(parentTagID: "draw", childTagID: "enchantment-draw"),
          SemanticTagEdgeRecord(parentTagID: "draw", childTagID: "creature-draw"),
        ],
        cardTags: [
          SemanticCardTagRecord(
            cardKey: SemanticCardKey(oracleID: source.oracleID, printingID: source.id),
            tagID: "enchantment-draw",
            weightMillis: 1_000,
            annotation: nil,
            source: "source-membership"
          ),
          SemanticCardTagRecord(
            cardKey: SemanticCardKey(oracleID: candidate.oracleID, printingID: candidate.id),
            tagID: "creature-draw",
            weightMillis: 1_000,
            annotation: nil,
            source: "candidate-membership"
          ),
        ],
        stats: [
          SemanticTagStatsRecord(
            tagID: "draw",
            directCardCount: 0,
            effectiveCardCount: 2,
            inverseFrequencyMillis: 1_000
          ),
          SemanticTagStatsRecord(
            tagID: "enchantment-draw",
            directCardCount: 1,
            effectiveCardCount: 1,
            inverseFrequencyMillis: 1_500
          ),
          SemanticTagStatsRecord(
            tagID: "creature-draw",
            directCardCount: 1,
            effectiveCardCount: 1,
            inverseFrequencyMillis: 1_500
          ),
        ]
      )
    )

    let lookup = try await database.semanticRelatedCards(for: source)
    guard case .available(let related) = lookup else {
      Issue.record("Expected semantic related cards to be available")
      return
    }

    #expect(related.map(\.card.id) == [candidate.id])
    #expect(related[0].sharedConcepts.map(\.slug) == ["draw"])
  }

  @Test
  func relatedCardLookupStopsBeforeDatabaseWorkWhenItsTaskIsAlreadyCancelled() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let source = relatedCard(id: "source-print", oracleID: "source", name: "Source")
    let candidate = relatedCard(id: "candidate-print", oracleID: "candidate", name: "Candidate")
    try database.replaceAllCards([source, candidate])
    try database.replaceSemanticCatalog(
      with: SemanticCatalogSnapshot(
        tags: [
          SemanticTagRecord(
            id: "draw",
            namespace: "oracle",
            slug: "draw-engine",
            label: "Draw Engine",
            description: nil,
            similarityEnabled: true,
            source: "tag-source"
          )
        ],
        aliases: [],
        edges: [],
        cardTags: [
          SemanticCardTagRecord(
            cardKey: SemanticCardKey(oracleID: source.oracleID, printingID: source.id),
            tagID: "draw",
            weightMillis: 1_000,
            annotation: nil,
            source: "source-membership"
          ),
          SemanticCardTagRecord(
            cardKey: SemanticCardKey(oracleID: candidate.oracleID, printingID: candidate.id),
            tagID: "draw",
            weightMillis: 1_000,
            annotation: nil,
            source: "candidate-membership"
          ),
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
    )

    let gate = RelatedCardLookupGate()
    let task = Task {
      await gate.wait()
      return try await database.semanticRelatedCards(for: source)
    }
    task.cancel()
    await gate.open()

    do {
      _ = try await task.value
      Issue.record("Expected the cancelled related-card lookup to throw CancellationError")
    } catch is CancellationError {
      // Expected.
    } catch {
      Issue.record("Expected CancellationError, got \(error)")
    }
  }

  @Test
  func relatedCardLookupCancellationDoesNotWaitForHeldDatabaseLock() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let source = relatedCard(id: "source-print", oracleID: "source", name: "Source")
    let candidate = relatedCard(id: "candidate-print", oracleID: "candidate", name: "Candidate")
    try database.replaceAllCards([source, candidate])
    try database.replaceSemanticCatalog(
      with: relatedCardSnapshot(source: source, candidate: candidate)
    )

    let blocker = RelatedCardDatabaseLockBlocker()
    let holder = Task.detached {
      blocker.hold(database)
    }
    #expect(blocker.waitUntilHeld())
    let delayedRelease = Task.detached {
      try? await Task.sleep(nanoseconds: 300_000_000)
      blocker.release()
    }
    let lookupTask = Task {
      try await database.semanticRelatedCards(for: source)
    }
    try await Task.sleep(nanoseconds: 20_000_000)

    let clock = ContinuousClock()
    let cancellationStart = clock.now
    lookupTask.cancel()
    let result = await lookupTask.result
    let cancellationDuration = cancellationStart.duration(to: clock.now)

    if case .failure(let error) = result {
      #expect(error is CancellationError)
    } else {
      Issue.record("Expected the blocked related-card lookup to be cancelled")
    }
    #expect(cancellationDuration < .milliseconds(150))
    _ = await delayedRelease.result
    _ = await holder.result
  }

  @Test
  func relatedCardLookupRetriesWhenCatalogChangesBeforeHydration() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let source = relatedCard(id: "source-print", oracleID: "source", name: "Source")
    let firstCandidate = relatedCard(
      id: "candidate-a-print",
      oracleID: "candidate-a",
      name: "Candidate A"
    )
    let replacementCandidate = relatedCard(
      id: "candidate-b-print",
      oracleID: "candidate-b",
      name: "Candidate B"
    )
    try database.replaceAllCards([source, firstCandidate])
    try database.replaceSemanticCatalog(
      with: relatedCardSnapshot(source: source, candidate: firstCandidate)
    )

    let inputBuilt = RelatedCardLookupGate()
    let continueLookup = RelatedCardLookupGate()
    let lookupTask = Task {
      try await database.semanticRelatedCards(
        for: source,
        afterInput: {
          await inputBuilt.open()
          await continueLookup.wait()
        }
      )
    }
    await inputBuilt.wait()
    try database.withDatabaseLock {
      try database.replaceAllCards([source, replacementCandidate])
      try database.replaceSemanticCatalog(
        with: relatedCardSnapshot(source: source, candidate: replacementCandidate)
      )
    }
    await continueLookup.open()

    let lookup = try await lookupTask.value
    guard case .available(let related) = lookup else {
      Issue.record("Expected related-card lookup to remain available after retry")
      return
    }
    #expect(related.map(\.card.id) == [replacementCandidate.id])
  }

  @Test
  func relatedCardLookupRetriesWhenStreamingResetChangesCatalog() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let source = relatedCard(id: "source-print", oracleID: "source", name: "Source")
    let candidate = relatedCard(id: "candidate-print", oracleID: "candidate", name: "Candidate")
    try database.replaceAllCards([source, candidate])
    try database.replaceSemanticCatalog(
      with: relatedCardSnapshot(source: source, candidate: candidate)
    )

    let inputBuilt = RelatedCardLookupGate()
    let continueLookup = RelatedCardLookupGate()
    let attempts = RelatedCardLookupAttemptCounter()
    let lookupTask = Task {
      try await database.semanticRelatedCards(
        for: source,
        afterInput: {
          let attempt = await attempts.record()
          if attempt == 1 {
            await inputBuilt.open()
            await continueLookup.wait()
          }
        }
      )
    }
    await inputBuilt.wait()
    try database.resetForStreamingCatalogBuild()
    await continueLookup.open()

    let lookup = try await lookupTask.value
    guard case .available(let related) = lookup else {
      Issue.record("Expected related-card lookup to remain available after streaming reset")
      return
    }
    #expect(related.isEmpty)
    #expect(await attempts.value() == 2)
  }

  @Test
  func relatedCardLookupRetriesWhenStreamingAppendChangesPreferredPrinting() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let source = relatedCard(id: "source-print", oracleID: "source", name: "Source")
    let alternateCandidate = relatedCard(
      id: "candidate-alt",
      oracleID: "candidate",
      name: "Candidate",
      language: "ja",
      isBasePrinting: false
    )
    let preferredCandidate = relatedCard(
      id: "candidate-base",
      oracleID: "candidate",
      name: "Candidate",
      language: "en",
      isBasePrinting: true
    )
    try database.replaceAllCards([source, alternateCandidate])
    try database.replaceSemanticCatalog(
      with: relatedCardSnapshot(source: source, candidate: alternateCandidate)
    )

    let inputBuilt = RelatedCardLookupGate()
    let continueLookup = RelatedCardLookupGate()
    let attempts = RelatedCardLookupAttemptCounter()
    let lookupTask = Task {
      try await database.semanticRelatedCards(
        for: source,
        afterInput: {
          let attempt = await attempts.record()
          if attempt == 1 {
            await inputBuilt.open()
            await continueLookup.wait()
          }
        }
      )
    }
    await inputBuilt.wait()
    try database.appendCatalogCards([preferredCandidate])
    await continueLookup.open()

    let lookup = try await lookupTask.value
    guard case .available(let related) = lookup else {
      Issue.record("Expected related-card lookup to remain available after streaming append")
      return
    }
    #expect(related.map(\.card.id) == [preferredCandidate.id])
    #expect(await attempts.value() == 2)
  }

  @Test
  func semanticReadsSupportCaseVariantTableNames() throws {
    let database = try CardDatabase(storage: .inMemory)
    let snapshot = semanticSnapshot()
    try database.replaceSemanticCatalog(with: snapshot)
    try renameSemanticTablesToUppercase(database.database)

    #expect(try database.semanticCatalogSnapshot() == snapshot)
    #expect(
      try database.semanticTagIDs(for: snapshot.cardTags[0].cardKey)
        == ["tag-card-draw"]
    )
    #expect(
      try database.semanticCardKeys(tagID: "tag-card-draw")
        == [snapshot.cardTags[0].cardKey]
    )
  }

  @Test
  func attachedCatalogReadsSemanticTablesInsteadOfEmptyMainShadowCopies() throws {
    let directory = semanticTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let catalogURL = directory.appendingPathComponent("Catalog.sqlite")
    let snapshot = semanticSnapshot()

    var catalog: CardDatabase? = try CardDatabase(storage: .file(catalogURL))
    try catalog?.replaceAllCards([Fixtures.records()[0]])
    try catalog?.replaceSemanticCatalog(with: snapshot)
    try catalog?.prepareForCatalogDistribution()
    catalog = nil

    let attached = try CardDatabase(
      userDatabaseURL: directory.appendingPathComponent("User.sqlite"),
      catalogURL: catalogURL
    )

    #expect(try attached.semanticCatalogSnapshot() == snapshot)
  }

  @Test
  func attachedCatalogRanksAndHydratesRelatedCards() async throws {
    let directory = semanticTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let catalogURL = directory.appendingPathComponent("Catalog.sqlite")
    let source = relatedCard(id: "source-print", oracleID: "source", name: "Source")
    let candidate = relatedCard(id: "candidate-print", oracleID: "candidate", name: "Candidate")

    var catalog: CardDatabase? = try CardDatabase(storage: .file(catalogURL))
    try catalog?.replaceAllCards([source, candidate])
    try catalog?.replaceSemanticCatalog(
      with: SemanticCatalogSnapshot(
        tags: [
          SemanticTagRecord(
            id: "draw",
            namespace: "oracle",
            slug: "draw-engine",
            label: "Draw Engine",
            description: nil,
            similarityEnabled: true,
            source: "tag-source"
          )
        ],
        aliases: [],
        edges: [],
        cardTags: [
          SemanticCardTagRecord(
            cardKey: SemanticCardKey(oracleID: source.oracleID, printingID: source.id),
            tagID: "draw",
            weightMillis: 1_000,
            annotation: nil,
            source: "source-membership"
          ),
          SemanticCardTagRecord(
            cardKey: SemanticCardKey(oracleID: candidate.oracleID, printingID: candidate.id),
            tagID: "draw",
            weightMillis: 1_000,
            annotation: nil,
            source: "candidate-membership"
          ),
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
    )
    try catalog?.prepareForCatalogDistribution()
    catalog = nil

    let attached = try CardDatabase(
      userDatabaseURL: directory.appendingPathComponent("User.sqlite"),
      catalogURL: catalogURL
    )
    let lookup = try await attached.semanticRelatedCards(for: source)
    guard case .available(let related) = lookup else {
      Issue.record("Expected attached semantic related cards to be available")
      return
    }

    #expect(related.map(\.card.id) == [candidate.id])
    #expect(related[0].sharedConcepts.map(\.slug) == ["draw-engine"])
  }

  @Test
  func legacyCatalogWithoutSemanticTablesOpensWithAnEmptySemanticSnapshot() throws {
    let directory = semanticTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let catalogURL = directory.appendingPathComponent("LegacyCatalog.sqlite")

    var catalog: CardDatabase? = try CardDatabase(storage: .file(catalogURL))
    try catalog?.replaceAllCards([Fixtures.records()[0]])
    try catalog?.prepareForCatalogDistribution()
    catalog = nil

    var rawCatalog: SQLiteDatabase? = try SQLiteDatabase(storage: .file(catalogURL))
    try rawCatalog?.execute(
      """
      DROP TABLE semantic_tag_stats;
      DROP TABLE semantic_card_tags;
      DROP TABLE semantic_tag_edges;
      DROP TABLE semantic_tag_aliases;
      DROP TABLE semantic_tags;
      """
    )
    rawCatalog = nil

    let attached = try CardDatabase(
      userDatabaseURL: directory.appendingPathComponent("User.sqlite"),
      catalogURL: catalogURL
    )

    #expect(try attached.cardCount() == 1)
    #expect(try attached.semanticCatalogSnapshot() == .empty)
    #expect(
      try attached.semanticTagIDs(for: SemanticCardKey(oracleID: "legacy", printingID: "legacy"))
        == []
    )
    #expect(try attached.semanticCardKeys(tagID: "missing") == [])
  }
}

private func relatedCard(
  id: String,
  oracleID: String,
  name: String,
  language: String = "en",
  isBasePrinting: Bool = true
) -> CardRecord {
  CardRecord(
    id: id,
    oracleID: oracleID,
    name: name,
    language: language,
    setCode: "tst",
    setName: "Test Set",
    setType: "expansion",
    collectorNumber: "1",
    rarity: "rare",
    colorSortKey: 6,
    colorIdentity: ["W"],
    layout: "normal",
    typeLine: "Enchantment",
    oracleText: "Test text.",
    legalities: ["commander": "legal"],
    isBasePrinting: isBasePrinting
  )
}

private func relatedCardSnapshot(
  source: CardRecord,
  candidate: CardRecord
) -> SemanticCatalogSnapshot {
  SemanticCatalogSnapshot(
    tags: [
      SemanticTagRecord(
        id: "draw",
        namespace: "oracle",
        slug: "draw-engine",
        label: "Draw Engine",
        description: nil,
        similarityEnabled: true,
        source: "tag-source"
      )
    ],
    aliases: [],
    edges: [],
    cardTags: [
      SemanticCardTagRecord(
        cardKey: SemanticCardKey(oracleID: source.oracleID, printingID: source.id),
        tagID: "draw",
        weightMillis: 1_000,
        annotation: nil,
        source: "source-membership"
      ),
      SemanticCardTagRecord(
        cardKey: SemanticCardKey(oracleID: candidate.oracleID, printingID: candidate.id),
        tagID: "draw",
        weightMillis: 1_000,
        annotation: nil,
        source: "candidate-membership"
      ),
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
}

private actor RelatedCardLookupGate {
  private var isOpen = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else {
      return
    }
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let waiting = continuations
    continuations.removeAll()
    waiting.forEach { $0.resume() }
  }
}

private actor RelatedCardLookupAttemptCounter {
  private var count = 0

  func record() -> Int {
    count += 1
    return count
  }

  func value() -> Int {
    count
  }
}

private final class RelatedCardDatabaseLockBlocker: @unchecked Sendable {
  private let acquired = DispatchSemaphore(value: 0)
  private let released = DispatchSemaphore(value: 0)

  func hold(_ database: CardDatabase) {
    database.withDatabaseLock {
      acquired.signal()
      released.wait()
    }
  }

  func waitUntilHeld() -> Bool {
    acquired.wait(timeout: .now() + 1) == .success
  }

  func release() {
    released.signal()
  }
}

private func semanticSnapshot() -> SemanticCatalogSnapshot {
  SemanticCatalogSnapshot(
    tags: [
      SemanticTagRecord(
        id: "tag-card-advantage",
        namespace: "oracle",
        slug: "card-advantage",
        label: "Card Advantage",
        description: nil,
        similarityEnabled: true,
        source: "scryfall-oracle-tags"
      ),
      SemanticTagRecord(
        id: "tag-card-draw",
        namespace: "oracle",
        slug: "card-draw",
        label: "Card Draw",
        description: "Moves cards from a library into a hand.",
        similarityEnabled: true,
        source: "scryfall-oracle-tags"
      ),
    ],
    aliases: [
      SemanticTagAliasRecord(
        tagID: "tag-card-draw",
        alias: "Draw cards",
        aliasKey: SemanticTagAliasRecord.normalizedKey(for: "Draw cards")
      ),
    ],
    edges: [
      SemanticTagEdgeRecord(parentTagID: "tag-card-advantage", childTagID: "tag-card-draw"),
    ],
    cardTags: [
      SemanticCardTagRecord(
        cardKey: SemanticCardKey(oracleID: "oracle-card", printingID: "print-a"),
        tagID: "tag-card-draw",
        weightMillis: 1_500,
        annotation: "repeatable",
        source: "scryfall-oracle-tags"
      ),
    ],
    stats: [
      SemanticTagStatsRecord(
        tagID: "tag-card-advantage",
        directCardCount: 0,
        effectiveCardCount: 1,
        inverseFrequencyMillis: 700
      ),
      SemanticTagStatsRecord(
        tagID: "tag-card-draw",
        directCardCount: 1,
        effectiveCardCount: 1,
        inverseFrequencyMillis: 900
      ),
    ]
  )
}

private func semanticIndexNames(database: CardDatabase) throws -> Set<String> {
  let statement = try database.database.prepare(
    "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_semantic_%'"
  )
  var result: Set<String> = []
  while try statement.step() {
    if let name = statement.string(at: 0) {
      result.insert(name)
    }
  }
  return result
}

private func renameSemanticTablesToUppercase(_ database: SQLiteDatabase) throws {
  for table in [
    "semantic_tags",
    "semantic_tag_aliases",
    "semantic_tag_edges",
    "semantic_card_tags",
    "semantic_tag_stats",
  ] {
    try database.execute("ALTER TABLE \(table) RENAME TO \(table)_case_variant")
    try database.execute("ALTER TABLE \(table)_case_variant RENAME TO \(table.uppercased())")
  }
}

private func expectRejectedSemanticReplacement(
  _ invalid: SemanticCatalogSnapshot,
  preserving original: SemanticCatalogSnapshot
) throws {
  let database = try CardDatabase(storage: .inMemory)
  try database.replaceSemanticCatalog(with: original)

  #expect(throws: (any Error).self) {
    try database.replaceSemanticCatalog(with: invalid)
  }
  #expect(try database.semanticCatalogSnapshot() == original)
}

private func semanticTemporaryDirectory() -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("SemanticCatalogStorageTests-\(UUID().uuidString)", isDirectory: true)
  try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
