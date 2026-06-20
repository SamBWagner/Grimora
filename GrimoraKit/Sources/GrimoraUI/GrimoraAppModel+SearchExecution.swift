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
    plainTextSearchTask?.cancel()
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
    isTranslatingSearch = false
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

    if searchInputMode == .plainText {
      let prompt = GrimoraSearchHistoryStore.normalizedQuery(submittedSearchText)
      guard !prompt.isEmpty, generatedSearchQuery != nil else {
        return nil
      }
      return .plainText(prompt)
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
        text: defaultSearchConfiguration.searchText(
          includingAlwaysIncluded: defaultSearchConfiguration.normalizedText
        ),
        sortMode: sortMode,
        sortDirection: sortDirection
      )
    }

    if searchInputMode == .plainText {
      return GrimoraResolvedSearchConfiguration(
        text: defaultSearchConfiguration.searchText(includingAlwaysIncluded: generatedSearchQuery ?? ""),
        sortMode: sortMode,
        sortDirection: sortDirection
      )
    }

    return GrimoraResolvedSearchConfiguration(
      text: defaultSearchConfiguration.searchText(includingAlwaysIncluded: submittedSearchText),
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

  func handleSearchTextChange(oldValue: String) {
    guard searchText != oldValue else {
      return
    }

    if searchInputMode == .plainText {
      plainTextSearchTask?.cancel()
      isTranslatingSearch = false
      plainTextSearchStatusMessage = nil
      plainTextSearchErrorMessage = nil
      return
    }

    generatedSearchQuery = nil
    plainTextSearchStatusMessage = nil
    plainTextSearchErrorMessage = nil
  }

  func handleSearchInputModeChange(from oldValue: SearchInputMode) {
    guard !isUpdatingSearchInputMode, searchInputMode != oldValue else {
      return
    }

    plainTextSearchTask?.cancel()
    isTranslatingSearch = false
    generatedSearchQuery = nil
    plainTextSearchStatusMessage = nil
    plainTextSearchErrorMessage = nil

    if searchInputMode == .plainText, !plainTextSearchTranspiler.availability.isAvailable {
      let unavailableMessage =
        plainTextSearchTranspiler.availability.message ?? "Plain-text search is unavailable."
      isUpdatingSearchInputMode = true
      searchInputMode = oldValue
      isUpdatingSearchInputMode = false
      plainTextSearchErrorMessage = unavailableMessage
      return
    }

    if searchInputMode == .scryfall
      || GrimoraSearchHistoryStore.normalizedQuery(searchText).isEmpty
    {
      reloadSearch()
    } else {
      cancelSearchWorkForPendingPlainTextPrompt()
    }
  }

  var hasPendingPlainTextPrompt: Bool {
    searchInputMode == .plainText
      && hasUnsubmittedSearchText
  }

  func cancelSearchWorkForPendingPlainTextPrompt() {
    searchGeneration += 1
    searchDebounceTask?.cancel()
    searchTask?.cancel()
    nextPagePrefetchTask?.cancel()
    searchHistoryRecordTask?.cancel()
    currentSearchCacheKey = nil
    canLoadMoreCards = false
    isLoadingMoreCards = false
    isSearchingCards = false
  }

  func publishPlainTextSearchTranslation(
    _ result: PlainTextSearchSubmissionResult,
    prompt: String,
    generation: UInt64
  ) {
    guard generation == searchGeneration,
      searchInputMode == .plainText,
      GrimoraSearchHistoryStore.normalizedQuery(searchText) == prompt,
      GrimoraSearchHistoryStore.normalizedQuery(submittedSearchText) == prompt
    else {
      return
    }

    isTranslatingSearch = false
    switch result {
    case .success(let transpilation):
      let query = GrimoraSearchHistoryStore.normalizedQuery(transpilation.query)
      generatedSearchQuery = query
      plainTextSearchStatusMessage = transpilation.note
      plainTextSearchErrorMessage = nil
      runFirstSearchPage(generation: generation)
    case .unsupported(let reason):
      generatedSearchQuery = nil
      plainTextSearchStatusMessage = nil
      plainTextSearchErrorMessage = reason.message
      unsupportedSearchMessage = reason.message
      canLoadMoreCards = false
    case .failure(let message):
      generatedSearchQuery = nil
      plainTextSearchStatusMessage = nil
      plainTextSearchErrorMessage = message
    }
  }

  static func validatedPlainTextSearch(
    prompt: String,
    transpiler: any PlainTextSearchTranspiling
  ) async -> PlainTextSearchSubmissionResult {
    do {
      let first = try await transpiler.transpile(prompt)
      switch validatedTranspilation(first, prompt: prompt) {
      case .success(let transpilation):
        return .success(transpilation)
      case .failure(let reason):
        if let repaired = locallyRepairedTranspilation(first, prompt: prompt, reason: reason) {
          switch validatedTranspilation(repaired, prompt: prompt) {
          case .success(let transpilation):
            return .success(transpilation)
          case .failure:
            break
          }
        }

        do {
          let repaired = try await transpiler.repair(
            prompt: prompt,
            rejectedQuery: first.query,
            reason: reason
          )
          switch validatedTranspilation(repaired, prompt: prompt) {
          case .success(let transpilation):
            return .success(transpilation)
          case .failure(let repairedReason):
            return .unsupported(repairedReason)
          }
        } catch {
          return .unsupported(reason)
        }
      }
    } catch let error as PlainTextSearchTranspilerError {
      return .failure(error.message)
    } catch {
      return .failure("Plain-text search failed.")
    }
  }

  static func validatedTranspilation(
    _ transpilation: PlainTextSearchTranspilation,
    prompt: String
  ) -> Result<PlainTextSearchTranspilation, SearchQueryUnsupportedReason> {
    let query = canonicalizedPlainTextSearchQuery(
      GrimoraSearchHistoryStore.normalizedQuery(transpilation.query),
      prompt: prompt
    )
    guard !query.isEmpty else {
      return .failure(
        SearchQueryUnsupportedReason(
          query: "",
          token: prompt,
          detail: "Plain-text search could not produce a Scryfall query."
        )
      )
    }

    if let reason = SearchQuery.explicitSyntaxUnsupportedReason(for: query) {
      return .failure(reason)
    }
    return .success(PlainTextSearchTranspilation(query: query, note: transpilation.note))
  }

  static func canonicalizedPlainTextSearchQuery(_ query: String, prompt: String) -> String {
    guard promptDescribesCreatureTokenCreation(prompt) else {
      return query
    }

    let normalizedQuery = normalizedPlainTextRepairText(query)
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
    if ["o:creature token", "oracle:creature token"].contains(normalizedQuery) {
      return "o:\"creature token\""
    }

    return query
  }

  static func locallyRepairedTranspilation(
    _ transpilation: PlainTextSearchTranspilation,
    prompt: String,
    reason: SearchQueryUnsupportedReason
  ) -> PlainTextSearchTranspilation? {
    let token = normalizedPlainTextRepairText(reason.token)
    guard ["c:token", "color:token"].contains(token),
      promptDescribesCreatureTokenCreation(prompt)
    else {
      return nil
    }

    return PlainTextSearchTranspilation(query: "o:\"creature token\"", note: transpilation.note)
  }

  static func promptDescribesCreatureTokenCreation(_ prompt: String) -> Bool {
    let normalizedPrompt = normalizedPlainTextRepairText(prompt)
    guard normalizedPrompt.contains("token"),
      normalizedPrompt.contains("creature")
    else {
      return false
    }

    return [
      "create",
      "creates",
      "creating",
      "make",
      "makes",
      "making",
      "produce",
      "produces",
      "generates",
      "generate",
    ].contains { normalizedPrompt.contains($0) }
  }

  static func normalizedPlainTextRepairText(_ text: String) -> String {
    text
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
  }
}
