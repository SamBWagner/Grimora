import Foundation

extension CardDatabase {
  /// Loads one catalog generation under the cancellable database lock, then expands and
  /// aggregates outside it. Hydrated caller cards are never trusted across catalog installs.
  public func collectionSemanticProfile(
    for list: CardCollectionRecord,
    entries: [CardCollectionEntryRecord],
    policy: CardCollectionSemanticPolicy = .init()
  ) async throws -> CardCollectionSemanticProfileLookup {
    try await collectionSemanticProfile(
      for: list, entries: entries, policy: policy, afterInput: nil)
  }

  func collectionSemanticProfile(
    for list: CardCollectionRecord,
    entries: [CardCollectionEntryRecord],
    policy: CardCollectionSemanticPolicy,
    afterInput: (@Sendable () async -> Void)?,
    beforeEdges: (@Sendable () -> Void)? = nil
  ) async throws -> CardCollectionSemanticProfileLookup {
    let fingerprint = try CardCollectionSemanticProfiler.fingerprint(
      for: list, entries: entries, policy: policy)
    while true {
      try Task.checkCancellation()
      let query = try await withCancellableDatabaseLock {
        if let cached = collectionSemanticProfileCache[fingerprint] {
          return CollectionSemanticQuery.cached(cached)
        }
        guard try functionalOracleTagsAvailableUnlocked() else {
          return CollectionSemanticQuery.unavailable
        }
        var hydrated = entries.filter { $0.listID == list.id }
        let ids = Set(hydrated.map(\.cardID)).sorted()
        var cards: [String: CardRecord] = [:]
        // Each non-suspending hydration batch is bounded; check cancellation between batches.
        for start in stride(from: 0, to: ids.count, by: 256) {
          try Task.checkCancellation()
          let chunk = Array(ids[start..<min(start + 256, ids.count)])
          cards.merge(try cardsByID(forIDs: chunk)) { _, new in new }
        }
        var keys: Set<SemanticCardKey> = []
        for index in hydrated.indices {
          try Task.checkCancellation()
          hydrated[index].card = cards[hydrated[index].cardID]
          if policy.includes(hydrated[index].zone, ruleset: list.ruleset),
            let card = hydrated[index].card
          {
            keys.insert(SemanticCardKey(oracleID: card.oracleID, printingID: card.id))
          }
        }
        return CollectionSemanticQuery.input(
          .init(
            entries: hydrated,
            snapshot: .init(
              tags: try semanticTagsUnlocked(), aliases: [], edges: try semanticEdgesUnlocked(),
              cardTags: try semanticCardTagsUnlocked(cardKeys: keys),
              stats: try semanticStatsUnlocked()), generation: catalogContentGeneration))
      }
      switch query {
      case .unavailable: return .unavailable
      case .cached(let profile):
        try Task.checkCancellation()
        return .available(profile)
      case .input(let input):
        await afterInput?()
        try Task.checkCancellation()
        let profile = try CardCollectionSemanticProfiler.profile(
          for: list, entries: input.entries, snapshot: input.snapshot,
          catalogGeneration: input.generation, policy: policy, beforeEdges: beforeEdges)
        let current = try await withCancellableDatabaseLock {
          guard catalogContentGeneration == input.generation else { return false }
          // Bounded instance-local cache. Every catalog mutation clears it under this lock.
          if collectionSemanticProfileCache.count >= 8 {
            collectionSemanticProfileCache.removeAll(keepingCapacity: true)
          }
          collectionSemanticProfileCache[fingerprint] = profile
          return true
        }
        try Task.checkCancellation()
        if current { return .available(profile) }
      }
    }
  }
}

private struct CollectionSemanticInput {
  var entries: [CardCollectionEntryRecord]
  var snapshot: SemanticCatalogSnapshot
  var generation: UInt64
}

private enum CollectionSemanticQuery {
  case unavailable
  case cached(CardCollectionSemanticProfile)
  case input(CollectionSemanticInput)
}
