import Foundation
import GrimoraCore

extension GrimoraAppModel {
  func runFirstSearchPage(generation: UInt64) {
    guard generation == searchGeneration else {
      return
    }

    guard hasLibrary else {
      resetSearchStateForMissingLibrary()
      return
    }

    let request = searchRequest(offset: 0)
    let cacheKey = SearchResultCacheKey(request: request)
    currentSearchCacheKey = cacheKey
    let shouldUseResultCache = shouldCacheFirstSearchPage(for: request)
    let searchHistoryRecord = searchHistoryRecord(for: request)

    searchHistoryRecordTask?.cancel()
    if shouldUseResultCache, let cachedResponse = searchResultCache.response(for: cacheKey) {
      isLoadingMoreCards = false
      isSearchingCards = false
      searchTask = nil
      publishSearchResult(
        .success(cachedResponse),
        generation: generation,
        offset: 0,
        historyRecord: searchHistoryRecord
      )
      return
    }

    isLoadingMoreCards = false
    isSearchingCards = true
    let database = database
    searchTask = Task { [
      weak self,
      database,
      request,
      generation,
      cacheKey,
      shouldUseResultCache,
      searchHistoryRecord
    ] in
      let result = await Task.detached(priority: .userInitiated) {
        do {
          return SearchLoadResult.success(try database.search(request))
        } catch {
          return SearchLoadResult.failure
        }
      }.value

      guard !Task.isCancelled else {
        return
      }

      self?.publishSearchResult(
        result,
        generation: generation,
        offset: 0,
        cacheKey: shouldUseResultCache ? cacheKey : nil,
        historyRecord: searchHistoryRecord
      )
    }
  }

  func loadSearchPage(offset: Int, generation: UInt64) {
    guard generation == searchGeneration,
      hasLibrary,
      let currentSearchCacheKey
    else {
      return
    }

    let request = searchRequest(offset: offset)
    let pageCacheKey = SearchPageCacheKey(
      searchKey: currentSearchCacheKey,
      offset: request.offset,
      limit: request.limit
    )
    if let cachedResponse = searchPageCache.response(for: pageCacheKey) {
      publishSearchResult(
        .success(cachedResponse),
        generation: generation,
        offset: request.offset
      )
      return
    }

    isLoadingMoreCards = true
    let database = database
    searchTask = Task { [weak self, database, request, generation, pageCacheKey] in
      let result = await Task.detached(priority: .userInitiated) {
        do {
          return SearchLoadResult.success(try database.search(request))
        } catch {
          return SearchLoadResult.failure
        }
      }.value

      guard !Task.isCancelled else {
        return
      }

      self?.publishSearchResult(
        result,
        generation: generation,
        offset: request.offset,
        pageCacheKey: pageCacheKey
      )
    }
  }

  func searchRequest(offset: Int) -> CardSearchRequest {
    let resolvedSearch = resolvedSearchConfiguration()
    return CardSearchRequest(
      text: resolvedSearch.text,
      sortMode: resolvedSearch.sortMode,
      sortDirection: resolvedSearch.sortDirection,
      printingDisplayMode: printingDisplayMode,
      offset: offset,
      limit: searchPerformance.pageSize
    )
  }

  func resetSearchStateForMissingLibrary() {
    searchTask?.cancel()
    searchDebounceTask?.cancel()
    nextPagePrefetchTask?.cancel()
    searchHistoryRecordTask?.cancel()
    searchResultCache.removeAll()
    searchPageCache.removeAll()
    currentSearchCacheKey = nil
    searchVisibleImageWindowTracker.reset()
    resetSearchVisibleImageRequests()
    unsupportedSearchMessage = nil
    cards = []
    searchResultTotal = 0
    selectedCard = nil
    canLoadMoreCards = false
    isLoadingMoreCards = false
    isSearchingCards = false
  }

  func shouldCacheFirstSearchPage(for request: CardSearchRequest) -> Bool {
    guard request.offset == 0 else {
      return false
    }

    return !GrimoraSearchHistoryStore.normalizedQuery(request.text).isEmpty
  }

  func searchHistoryRecord(for request: CardSearchRequest) -> SearchHistoryRecord? {
    guard !isDefaultSearchActive else {
      return nil
    }

    let query = GrimoraSearchHistoryStore.normalizedQuery(submittedSearchText)
    guard !query.isEmpty else {
      return nil
    }
    return .scryfall(query)
  }

  func resolvedSearchConfiguration() -> GrimoraResolvedSearchConfiguration {
    if isDefaultSearchActive {
      return GrimoraResolvedSearchConfiguration(
        text: effectiveSearchText(defaultSearchConfiguration.normalizedText),
        sortMode: sortMode,
        sortDirection: sortDirection
      )
    }

    return GrimoraResolvedSearchConfiguration(
      text: effectiveSearchText(submittedSearchText),
      sortMode: sortMode,
      sortDirection: sortDirection
    )
  }

  func setCurrentSort(
    sortMode: SortMode,
    sortDirection: SearchSortDirection
  ) {
    guard self.sortMode != sortMode || self.sortDirection != sortDirection else {
      return
    }

    isUpdatingCurrentSort = true
    self.sortMode = sortMode
    self.sortDirection = sortDirection
    isUpdatingCurrentSort = false
  }

}
