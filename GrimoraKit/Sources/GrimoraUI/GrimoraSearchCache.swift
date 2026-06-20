import Foundation
import GrimoraCore

struct SearchVisibleImageWindowTracker {
  static let defaultStride = 12

  var stride: Int
  private var lastRequest: SearchVisibleImageWindowRequest?

  init(stride: Int = Self.defaultStride) {
    self.stride = max(1, stride)
  }

  func windowStart(for index: Int) -> Int {
    let clampedIndex = max(0, index)
    return (clampedIndex / stride) * stride
  }

  mutating func shouldRefresh(
    windowStart: Int,
    cardIDs: [CardRecord.ID],
    quality: CardImageQuality,
    force: Bool = false
  ) -> Bool {
    guard !cardIDs.isEmpty else {
      lastRequest = nil
      return false
    }

    let request = SearchVisibleImageWindowRequest(
      windowStart: max(0, windowStart),
      cardIDs: cardIDs,
      quality: quality
    )
    guard force || request != lastRequest else {
      return false
    }

    lastRequest = request
    return true
  }

  mutating func reset() {
    lastRequest = nil
  }
}

struct SearchVisibleImageWindowRequest: Equatable {
  var windowStart: Int
  var cardIDs: [CardRecord.ID]
  var quality: CardImageQuality
}

struct SearchResultCacheKey: Equatable, Sendable {
  var text: String
  var sortMode: SortMode
  var sortDirection: SearchSortDirection
  var printingDisplayMode: PrintingDisplayMode

  init(request: CardSearchRequest) {
    text = GrimoraSearchHistoryStore.normalizedQuery(request.text)
    sortMode = request.sortMode
    sortDirection = request.sortDirection
    printingDisplayMode = request.printingDisplayMode
  }
}

struct SearchResultCache {
  var capacity: Int
  private var entries: [SearchResultCacheEntry] = []

  init(capacity: Int) {
    self.capacity = capacity
  }

  mutating func response(for key: SearchResultCacheKey) -> CardSearchResponse? {
    guard let index = entries.firstIndex(where: { $0.key == key }) else {
      return nil
    }

    let entry = entries.remove(at: index)
    entries.insert(entry, at: 0)
    return entry.response
  }

  mutating func store(_ response: CardSearchResponse, for key: SearchResultCacheKey) {
    guard case .results = response else {
      return
    }

    entries.removeAll { $0.key == key }
    entries.insert(SearchResultCacheEntry(key: key, response: response), at: 0)
    if entries.count > capacity {
      entries.removeLast(entries.count - capacity)
    }
  }

  mutating func removeAll() {
    entries.removeAll()
  }

  mutating func patchImageUpdate(_ updatedCard: CardRecord) {
    for entryIndex in entries.indices {
      guard case .results(var cards, let totalCount) = entries[entryIndex].response,
        let cardIndex = cards.firstIndex(where: { $0.id == updatedCard.id })
      else {
        continue
      }

      guard cards[cardIndex] != updatedCard else {
        continue
      }
      cards[cardIndex] = updatedCard
      entries[entryIndex].response = .results(cards, totalCount: totalCount)
    }
  }
}

struct SearchResultCacheEntry {
  var key: SearchResultCacheKey
  var response: CardSearchResponse
}

struct SearchPageCacheKey: Equatable, Sendable {
  var searchKey: SearchResultCacheKey
  var offset: Int
  var limit: Int
}

struct SearchPageCache {
  var capacity: Int
  private var entries: [SearchPageCacheEntry] = []

  init(capacity: Int) {
    self.capacity = capacity
  }

  func contains(_ key: SearchPageCacheKey) -> Bool {
    entries.contains { $0.key == key }
  }

  mutating func response(for key: SearchPageCacheKey) -> CardSearchResponse? {
    guard let index = entries.firstIndex(where: { $0.key == key }) else {
      return nil
    }

    let entry = entries.remove(at: index)
    entries.insert(entry, at: 0)
    return entry.response
  }

  mutating func store(_ response: CardSearchResponse, for key: SearchPageCacheKey) {
    guard capacity > 0, case .results = response else {
      return
    }

    entries.removeAll { $0.key == key }
    entries.insert(SearchPageCacheEntry(key: key, response: response), at: 0)
    if entries.count > capacity {
      entries.removeLast(entries.count - capacity)
    }
  }

  mutating func removeAll() {
    entries.removeAll()
  }

  mutating func patchImageUpdate(_ updatedCard: CardRecord) {
    for entryIndex in entries.indices {
      guard case .results(var cards, let totalCount) = entries[entryIndex].response,
        let cardIndex = cards.firstIndex(where: { $0.id == updatedCard.id })
      else {
        continue
      }

      guard cards[cardIndex] != updatedCard else {
        continue
      }
      cards[cardIndex] = updatedCard
      entries[entryIndex].response = .results(cards, totalCount: totalCount)
    }
  }
}

struct SearchPageCacheEntry {
  var key: SearchPageCacheKey
  var response: CardSearchResponse
}

enum SearchLoadResult: Sendable {
  case success(CardSearchResponse)
  case failure
}

enum SearchListCreationResult: Sendable {
  case success(listID: CardListRecord.ID, cardCount: Int)
  case empty
  case unsupported
  case emptyName
  case failure
}

enum PlainTextSearchSubmissionResult: Sendable {
  case success(PlainTextSearchTranspilation)
  case unsupported(SearchQueryUnsupportedReason)
  case failure(String)
}

enum SearchHistoryRecord: Sendable {
  case scryfall(String)
  case plainText(String)

  var query: String {
    switch self {
    case .scryfall(let query), .plainText(let query):
      query
    }
  }
}

enum PrintingsLoadResult: Sendable {
  case success([CardRecord])
  case failure
}

struct GrimoraResolvedSearchConfiguration: Sendable {
  var text: String
  var sortMode: SortMode
  var sortDirection: SearchSortDirection
}
