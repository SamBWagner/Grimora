import Foundation
import GrimoraCore

extension GrimoraAppModel {
  func refreshLibraryState() {
    do {
      libraryState = try database.isLibraryReady() ? .ready : .missing
    } catch {
      libraryState = .missing
    }
  }

  func publishSearchResult(
    _ result: SearchLoadResult,
    generation: UInt64,
    offset: Int,
    cacheKey: SearchResultCacheKey? = nil,
    pageCacheKey: SearchPageCacheKey? = nil,
    historyRecord: SearchHistoryRecord? = nil
  ) {
    guard generation == searchGeneration else {
      return
    }

    isLoadingMoreCards = false
    isSearchingCards = false
    switch result {
    case .success(.results(let cards, let totalCount)):
      unsupportedSearchMessage = nil
      searchResultTotal = totalCount
      if let pageCacheKey {
        searchPageCache.store(CardSearchResponse.results(cards, totalCount: totalCount), for: pageCacheKey)
      }
      if let cacheKey {
        searchResultCache.store(CardSearchResponse.results(cards, totalCount: totalCount), for: cacheKey)
      }

      if offset == 0 {
        searchVisibleImageWindowTracker.reset()
        resetSearchVisibleImageRequests()
        self.cards = cards
      } else if offset == self.cards.count {
        self.cards.append(contentsOf: cards)
      } else if offset < self.cards.count {
        let replacementEnd = min(self.cards.count, offset + cards.count)
        self.cards.replaceSubrange(offset..<replacementEnd, with: cards.prefix(replacementEnd - offset))
      }

      canLoadMoreCards = self.cards.count < totalCount
      if let selectedCard, !self.cards.contains(where: { $0.id == selectedCard.id }) {
        self.selectedCard = self.cards.first
      }
      if let historyRecord {
        scheduleSearchHistoryRecord(historyRecord, generation: generation)
      }
      prefetchNextSearchPageIfNeeded(generation: generation)
    case .success(.unsupported(let reason)):
      guard offset == 0 else {
        return
      }
      unsupportedSearchMessage = reason.message
      searchVisibleImageWindowTracker.reset()
      resetSearchVisibleImageRequests()
      cards = []
      searchResultTotal = 0
      selectedCard = nil
      canLoadMoreCards = false
    case .failure:
      unsupportedSearchMessage = nil
      if offset == 0 {
        searchVisibleImageWindowTracker.reset()
        resetSearchVisibleImageRequests()
        cards = []
        searchResultTotal = 0
        canLoadMoreCards = false
      }
      statusMessage = "Search failed."
    }
  }

  func prefetchNextSearchPageIfNeeded(generation: UInt64) {
    guard searchPerformance.prefetchesNextPage,
      generation == searchGeneration,
      canLoadMoreCards,
      !cards.isEmpty,
      let currentSearchCacheKey
    else {
      return
    }

    let request = searchRequest(offset: cards.count)
    let pageCacheKey = SearchPageCacheKey(
      searchKey: currentSearchCacheKey,
      offset: request.offset,
      limit: request.limit
    )
    guard !searchPageCache.contains(pageCacheKey) else {
      return
    }

    nextPagePrefetchTask?.cancel()
    let database = database
    nextPagePrefetchTask = Task { [weak self, database, request, generation, pageCacheKey] in
      let result = await Task.detached(priority: .utility) {
        do {
          return SearchLoadResult.success(try database.search(request))
        } catch {
          return SearchLoadResult.failure
        }
      }.value

      guard !Task.isCancelled else {
        return
      }

      self?.storePrefetchedSearchPage(result, generation: generation, pageCacheKey: pageCacheKey)
    }
  }

  func storePrefetchedSearchPage(
    _ result: SearchLoadResult,
    generation: UInt64,
    pageCacheKey: SearchPageCacheKey
  ) {
    guard generation == searchGeneration,
      case .success(let response) = result
    else {
      return
    }

    searchPageCache.store(response, for: pageCacheKey)
  }

  func scheduleSearchHistoryRecord(_ record: SearchHistoryRecord, generation: UInt64) {
    let normalizedQuery = GrimoraSearchHistoryStore.normalizedQuery(record.query)
    guard !normalizedQuery.isEmpty else {
      return
    }

    searchHistoryRecordTask?.cancel()
    searchHistoryRecordTask = Task { [weak self, generation, record] in
      try? await Task.sleep(nanoseconds: GrimoraAppModel.searchHistorySettleDelayNanoseconds)
      guard !Task.isCancelled else {
        return
      }

      self?.recordSearchHistory(record, generation: generation)
    }
  }

  func recordSearchHistory(_ record: SearchHistoryRecord, generation: UInt64) {
    guard generation == searchGeneration, !isDefaultSearchActive else {
      return
    }

    let query = record.query
    guard GrimoraSearchHistoryStore.normalizedQuery(submittedSearchText) == query,
      ScryfallSyntaxValidator.validate(query).isValidScryfall
    else {
      return
    }

    let updatedHistory = searchHistoryStore.historyByRecording(query, in: searchHistory)
    guard updatedHistory != searchHistory else {
      return
    }

    searchHistory = updatedHistory
    searchHistoryStore.save(updatedHistory)
    scheduleSearchHistoryPreviewWarm()
    durableCloudSyncPreferencesChanged()
  }

  func scheduleSearchHistoryPreviewWarm() {
    searchHistoryImageWarmTask?.cancel()
    guard hasLibrary,
      imageDownloadConfiguration.historyWarmQueryLimit > 0,
      imageDownloadConfiguration.historyWarmResultLimit > 0
    else {
      Task { await previewImageWarmer.cancelHistory() }
      return
    }

    let queries = Array(searchHistory.prefix(imageDownloadConfiguration.historyWarmQueryLimit))
    guard !queries.isEmpty else {
      Task { await previewImageWarmer.cancelHistory() }
      return
    }

    let database = database
    let sortMode = sortMode
    let sortDirection = sortDirection
    let printingDisplayMode = printingDisplayMode
    let resultLimit = imageDownloadConfiguration.historyWarmResultLimit
    let warmer = previewImageWarmer
    searchHistoryImageWarmTask = Task {
      let paths = await Task.detached(priority: .utility) {
        var seenPaths: Set<String> = []
        var paths: [String] = []
        for query in queries {
          guard !Task.isCancelled else {
            return paths
          }

          let request = CardSearchRequest(
            text: query,
            sortMode: sortMode,
            sortDirection: sortDirection,
            printingDisplayMode: printingDisplayMode,
            offset: 0,
            limit: resultLimit
          )
          guard case .results(let cards, _) = try? database.search(request) else {
            continue
          }

          for path in cards.flatMap({ $0.artworkImagePathsForPreload(preferredQuality: .normal) }) {
            let filePath = LocalCardImageLoader.fileSystemPath(from: path)
            guard seenPaths.insert(filePath).inserted else {
              continue
            }
            paths.append(path)
          }
        }
        return paths
      }.value

      guard !Task.isCancelled else {
        return
      }

      await warmer.scheduleHistory(paths: paths)
    }
  }

  func shouldLoadMoreCards(afterAppearingCardAt index: Int) -> Bool {
    guard cards.indices.contains(index) else {
      return false
    }

    return index >= cards.count - searchPerformance.loadMoreThreshold
  }

  func patchImageUpdate(_ updatedCard: CardRecord) {
    if let index = cards.firstIndex(where: { $0.id == updatedCard.id }) {
      if cards[index] != updatedCard {
        cards[index] = updatedCard
      }
    }

    if let index = selectedCardPrintings.firstIndex(where: { $0.id == updatedCard.id }) {
      if selectedCardPrintings[index] != updatedCard {
        selectedCardPrintings[index] = updatedCard
      }
    }

    for index in selectedCollectionEntries.indices where selectedCollectionEntries[index].cardID == updatedCard.id {
      if selectedCollectionEntries[index].card != updatedCard {
        selectedCollectionEntries[index].card = updatedCard
      }
    }

    // The detail grid renders from the cached sections (built off-main), which hold their own
    // copies of the entries. Patch those too — otherwise a just-downloaded image is written into
    // `selectedCollectionEntries` but never reaches the on-screen tile, which reads the section.
    for sectionIndex in selectedCollectionSections.indices {
      for entryIndex in selectedCollectionSections[sectionIndex].entries.indices
      where selectedCollectionSections[sectionIndex].entries[entryIndex].cardID == updatedCard.id {
        if selectedCollectionSections[sectionIndex].entries[entryIndex].card != updatedCard {
          selectedCollectionSections[sectionIndex].entries[entryIndex].card = updatedCard
        }
      }
    }

    for index in cardCollectionOverviewItems.indices where cardCollectionOverviewItems[index].topCard?.id == updatedCard.id {
      if cardCollectionOverviewItems[index].topCard != updatedCard {
        cardCollectionOverviewItems[index].topCard = updatedCard
        cardCollectionOverviewItems[index].topEntry?.card = updatedCard
      }
    }

    searchResultCache.patchImageUpdate(updatedCard)
    searchPageCache.patchImageUpdate(updatedCard)

    if selectedCard?.id == updatedCard.id, selectedCard != Optional(updatedCard) {
      setSelectedCard(updatedCard, listEntryID: selectedCardCollectionEntryID)
    }
  }

  public func drainImageDownloadsForTesting() async {
    await imageDownloadCoordinator.drain()
  }

  public func drainPreviewImageWarmerForTesting() async {
    await searchHistoryImageWarmTask?.value
    await previewImageWarmer.drainForTesting()
  }

  public func drainSearchForTesting() async {
    await searchDebounceTask?.value
    await searchTask?.value
    await nextPagePrefetchTask?.value
  }

  /// Waits for the in-flight asynchronous selected-list load (started by
  /// `selectCardCollection`) to publish, so tests can assert the loaded
  /// `selectedCollection*` state deterministically.
  public func drainSelectedListLoadForTesting() async {
    await listLoadTask?.value
  }

  public func drainSearchHistoryForTesting() async {
    await searchHistoryRecordTask?.value
  }
}
