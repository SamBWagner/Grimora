import Foundation
import GrimoraCore

enum VisibleImageRequestSource {
  case search
  case list
}

extension GrimoraAppModel {
  func isLoadingVisiblePreview(
    for card: CardRecord,
    quality: CardImageQuality
  ) -> Bool {
    guard !card.hasExistingDisplayImage else {
      return false
    }

    let key = VisibleImageRequestKey(cardID: card.id, quality: quality)
    guard isCurrentVisibleImageRequest(key) else {
      return false
    }

    switch visibleImageRequestStates[key]?.phase {
    case .queued, .inFlight, .retrying:
      return true
    case .failed, .none:
      return false
    }
  }

  func visiblePreviewAccessibilityValue(
    for card: CardRecord,
    quality: CardImageQuality
  ) -> String {
    if card.hasExistingDisplayImage {
      return "Image"
    }

    return isLoadingVisiblePreview(for: card, quality: quality)
      ? "Loading Image"
      : "Text Only"
  }

  func visiblePreviewLoadingEntry(
    for card: CardRecord,
    quality: CardImageQuality
  ) -> VisiblePreviewLoadingEntry {
    visiblePreviewLoadingStore.entry(
      for: VisibleImageRequestKey(cardID: card.id, quality: quality)
    )
  }

  func setSelectedCard(
    _ card: CardRecord?,
    listEntryID: CardListEntryRecord.ID?
  ) {
    isUpdatingSelectedCardSource = true
    selectedCardListEntryID = listEntryID
    selectedCard = card
    isUpdatingSelectedCardSource = false
  }

  public func cacheVisibleImages(
    for card: CardRecord,
    quality: CardImageQuality = .small
  ) async {
    guard shouldEnqueueVisibleImageRequest(for: card, quality: quality) else {
      return
    }

    await imageDownloadCoordinator.enqueue(
      card: card,
      quality: quality,
      lane: .visible,
      generation: visibleImageDownloadGeneration,
      onStart: { [weak self] start in
        self?.handleImageDownloadStart(start)
      },
      onComplete: { [weak self] completion in
        self?.handleImageDownloadCompletion(completion)
      }
    )
  }

  public func cacheVisibleImages(
    around index: Int,
    quality: CardImageQuality = .small,
    forceRefresh: Bool = false
  ) async {
    guard cards.indices.contains(index) else {
      return
    }

    let windowStart = searchVisibleImageWindowTracker.windowStart(for: index)
    let windowCards = visibleImageWindow(startingAt: windowStart)
    guard searchVisibleImageWindowTracker.shouldRefresh(
      windowStart: windowStart,
      cardIDs: windowCards.map(\.id),
      quality: quality,
      force: forceRefresh
    ) else {
      return
    }

    await previewImageWarmer.scheduleVisible(
      paths: windowCards.flatMap { $0.artworkImagePathsForPreload(preferredQuality: quality) }
    )

    let downloadableCards = windowCards.filter {
      shouldEnqueueVisibleImageRequest(for: $0, quality: quality)
    }
    updateVisibleImageWindow(
      keys: visibleImageRequestKeys(for: downloadableCards, quality: quality),
      source: .search
    )
    markVisibleImageRequestsQueued(for: downloadableCards, quality: quality)
    await imageDownloadCoordinator.replaceVisibleWindow(
      cards: downloadableCards,
      quality: quality,
      generation: visibleImageDownloadGeneration,
      onStart: { [weak self] start in
        self?.handleImageDownloadStart(start)
      },
      onComplete: { [weak self] completion in
        self?.handleImageDownloadCompletion(completion)
      }
    )
  }

  public func cacheVisibleListEntryImages(
    around entryID: CardListEntryRecord.ID,
    quality: CardImageQuality = .small,
    forceRefresh: Bool = false
  ) async {
    guard let entryIndex = selectedListEntries.firstIndex(where: { $0.id == entryID }) else {
      return
    }

    let windowStart = listVisibleImageWindowTracker.windowStart(for: entryIndex)
    let windowEntries = visibleListImageWindow(startingAt: windowStart)
    let windowIdentity = windowEntries.map { entry in
      "\(entry.id):\(entry.card?.id ?? entry.cardID)"
    }
    guard listVisibleImageWindowTracker.shouldRefresh(
      windowStart: windowStart,
      cardIDs: windowIdentity,
      quality: quality,
      force: forceRefresh
    ) else {
      return
    }

    let windowCards = windowEntries.compactMap(\.card)
    await previewImageWarmer.scheduleVisible(
      paths: windowCards.flatMap { $0.artworkImagePathsForPreload(preferredQuality: quality) }
    )

    let downloadableCards = windowCards.filter {
      shouldEnqueueVisibleImageRequest(for: $0, quality: quality)
    }
    updateVisibleImageWindow(
      keys: visibleImageRequestKeys(for: downloadableCards, quality: quality),
      source: .list
    )
    markVisibleImageRequestsQueued(for: downloadableCards, quality: quality)
    await imageDownloadCoordinator.replaceVisibleWindow(
      cards: downloadableCards,
      quality: quality,
      generation: visibleImageDownloadGeneration,
      onStart: { [weak self] start in
        self?.handleImageDownloadStart(start)
      },
      onComplete: { [weak self] completion in
        self?.handleImageDownloadCompletion(completion)
      }
    )
  }

  func visibleImageWindow(startingAt startIndex: Int) -> [CardRecord] {
    guard !cards.isEmpty else {
      return []
    }

    let safeStart = min(max(0, startIndex), cards.count - 1)
    let endIndex = min(
      cards.count,
      safeStart + max(1, searchPerformance.imageLookaheadCount) + 1
    )
    return Array(cards[safeStart..<endIndex])
  }

  func visibleListImageWindow(startingAt startIndex: Int) -> [CardListEntryRecord] {
    guard !selectedListEntries.isEmpty else {
      return []
    }

    let safeStart = min(max(0, startIndex), selectedListEntries.count - 1)
    let endIndex = min(
      selectedListEntries.count,
      safeStart + max(1, searchPerformance.imageLookaheadCount) + 1
    )
    return Array(selectedListEntries[safeStart..<endIndex])
  }

  func shouldCacheDisplayImage(
    for card: CardRecord,
    quality: CardImageQuality
  ) -> Bool {
    !card.hasCachedArtworkPresentationImages(for: quality)
      || card.hasUnavailableCachedArtworkPresentationImageFile(for: quality)
  }

  func shouldEnqueueVisibleImageRequest(
    for card: CardRecord,
    quality: CardImageQuality
  ) -> Bool {
    let sources = CardArtworkPresentationResolver.imageSources(for: card)
    guard !sources.isEmpty else {
      return false
    }

    return sources.contains { source in
      !source.hasCachedImage(for: quality)
        || (!source.cachedImagePaths(for: quality).isEmpty
          && hasRemoteDisplayCandidate(for: quality, in: source))
    }
  }

  public func cacheDetailImages(for card: CardRecord) async {
    if shouldCacheDisplayImage(for: card, quality: .small) {
      await imageDownloadCoordinator.enqueue(
        card: card,
        quality: .small,
        lane: .detail,
        onStart: { _ in },
        onComplete: { [weak self] completion in
          self?.handleImageDownloadCompletion(completion)
        }
      )
    }

    await imageDownloadCoordinator.enqueue(
      card: card,
      quality: .large,
      lane: .detail,
      onStart: { _ in },
      onComplete: { [weak self] completion in
        self?.handleImageDownloadCompletion(completion)
      }
    )
  }

  public func cachePrintingThumbnailImage(for card: CardRecord) async {
    if shouldCacheDisplayImage(for: card, quality: .small) {
      await imageDownloadCoordinator.enqueue(
        card: card,
        quality: .small,
        lane: .visible,
        generation: visibleImageDownloadGeneration,
        onStart: { [weak self] start in
          self?.handleImageDownloadStart(start)
        },
        onComplete: { [weak self] completion in
          self?.handleImageDownloadCompletion(completion)
        }
      )
    }
  }

  public func cachePrintingPreviewImages(for card: CardRecord) async {
    if shouldCacheDisplayImage(for: card, quality: .small) {
      await imageDownloadCoordinator.enqueue(
        card: card,
        quality: .small,
        lane: .detail,
        onStart: { _ in },
        onComplete: { [weak self] completion in
          self?.handleImageDownloadCompletion(completion)
        }
      )
    }

    if shouldCacheDisplayImage(for: card, quality: .large) {
      await imageDownloadCoordinator.enqueue(
        card: card,
        quality: .large,
        lane: .detail,
        onStart: { _ in },
        onComplete: { [weak self] completion in
          self?.handleImageDownloadCompletion(completion)
        }
      )
    }
  }

  public func cachePrintingPreviewImages(for cards: [CardRecord]) async {
    var cachedCardIDs: Set<CardRecord.ID> = []
    for card in cards where cachedCardIDs.insert(card.id).inserted {
      await cachePrintingPreviewImages(for: card)
    }
  }

  private func handleImageDownloadStart(_ start: CardImageDownloadStart) {
    guard start.lane == .visible else {
      return
    }

    let key = VisibleImageRequestKey(cardID: start.card.id, quality: start.quality)
    guard isActiveVisibleImageRequest(key) else {
      return
    }

    guard let state = visibleImageRequestStates[key], state.phase == .queued else {
      return
    }
    setVisibleImageRequestState(
      VisibleImageRequestState(
      phase: .inFlight,
      attempt: state.attempt
      ),
      for: key
    )
  }

  private func handleImageDownloadCompletion(_ completion: CardImageDownloadCompletion) {
    if let updatedCard = completion.updatedCard {
      patchImageUpdate(updatedCard)
    }

    guard completion.lane == .visible else {
      return
    }

    let key = VisibleImageRequestKey(cardID: completion.card.id, quality: completion.quality)
    guard isActiveVisibleImageRequest(key) else {
      clearVisibleImageRequest(key)
      return
    }

    let latestCard = cardForVisibleImageRequest(key) ?? completion.updatedCard ?? completion.card
    guard shouldCacheDisplayImage(for: latestCard, quality: completion.quality) else {
      clearVisibleImageRequest(key)
      return
    }

    handleVisibleImageDownloadFailure(for: latestCard, key: key)
  }

  private func handleVisibleImageDownloadFailure(
    for card: CardRecord,
    key: VisibleImageRequestKey
  ) {
    let currentAttempt = visibleImageRequestStates[key]?.attempt ?? 1
    guard currentAttempt < imageDownloadConfiguration.visibleRetryAttemptCount else {
      visibleImageRetryTasks[key]?.cancel()
      visibleImageRetryTasks[key] = nil
      setVisibleImageRequestState(
        VisibleImageRequestState(
        phase: .failed,
        attempt: currentAttempt
        ),
        for: key
      )
      return
    }

    let nextAttempt = currentAttempt + 1
    setVisibleImageRequestState(
      VisibleImageRequestState(
      phase: .retrying,
      attempt: nextAttempt
      ),
      for: key
    )
    scheduleVisibleImageRetry(for: card, key: key, attempt: nextAttempt)
  }

  private func scheduleVisibleImageRetry(
    for card: CardRecord,
    key: VisibleImageRequestKey,
    attempt: Int
  ) {
    visibleImageRetryTasks[key]?.cancel()
    let delayNanoseconds = visibleRetryDelayNanoseconds(beforeAttempt: attempt)
    visibleImageRetryTasks[key] = Task { [weak self] in
      if delayNanoseconds > 0 {
        do {
          try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
          return
        }
      }

      guard !Task.isCancelled else {
        return
      }

      await self?.retryVisibleImageDownload(
        fallbackCard: card,
        key: key,
        attempt: attempt
      )
    }
  }

  private func retryVisibleImageDownload(
    fallbackCard: CardRecord,
    key: VisibleImageRequestKey,
    attempt: Int
  ) async {
    visibleImageRetryTasks[key] = nil
    guard isActiveVisibleImageRequest(key) else {
      clearVisibleImageRequest(key)
      return
    }

    let card = cardForVisibleImageRequest(key) ?? fallbackCard
    guard shouldCacheDisplayImage(for: card, quality: key.quality) else {
      clearVisibleImageRequest(key)
      return
    }

    setVisibleImageRequestState(
      VisibleImageRequestState(
      phase: .queued,
      attempt: attempt
      ),
      for: key
    )
    await imageDownloadCoordinator.enqueue(
      card: card,
      quality: key.quality,
      lane: .visible,
      generation: visibleImageDownloadGeneration,
      onStart: { [weak self] start in
        self?.handleImageDownloadStart(start)
      },
      onComplete: { [weak self] completion in
        self?.handleImageDownloadCompletion(completion)
      }
    )
  }

  private func visibleImageRequestKeys(
    for cards: [CardRecord],
    quality: CardImageQuality
  ) -> Set<VisibleImageRequestKey> {
    Set(cards.map { VisibleImageRequestKey(cardID: $0.id, quality: quality) })
  }

  private func markVisibleImageRequestsQueued(
    for cards: [CardRecord],
    quality: CardImageQuality
  ) {
    for card in cards {
      let key = VisibleImageRequestKey(cardID: card.id, quality: quality)
      switch visibleImageRequestStates[key]?.phase {
      case .inFlight, .queued:
        continue
      case .retrying, .failed, .none:
        visibleImageRetryTasks[key]?.cancel()
        visibleImageRetryTasks[key] = nil
        setVisibleImageRequestState(
          VisibleImageRequestState(
          phase: .queued,
          attempt: 1
          ),
          for: key
        )
      }
    }
  }

  private func updateVisibleImageWindow(
    keys: Set<VisibleImageRequestKey>,
    source: VisibleImageRequestSource
  ) {
    if visibleImageRequestSource != source {
      visibleImageDownloadGeneration += 1
      visibleImageRequestSource = source
      searchVisibleImageRequestWindows = []
      listVisibleImageRequestWindows = []
    }

    switch source {
    case .search:
      searchVisibleImageRequestKeys = keys
      listVisibleImageRequestKeys = []
      searchVisibleImageRequestWindows = retainedVisibleImageWindows(
        adding: keys,
        to: searchVisibleImageRequestWindows
      )
      listVisibleImageRequestWindows = []
    case .list:
      searchVisibleImageRequestKeys = []
      listVisibleImageRequestKeys = keys
      listVisibleImageRequestWindows = retainedVisibleImageWindows(
        adding: keys,
        to: listVisibleImageRequestWindows
      )
      searchVisibleImageRequestWindows = []
    }

    visiblePreviewLoadingStore.updateCurrentKeys(
      searchVisibleImageRequestKeys.union(listVisibleImageRequestKeys)
    )

    let activeKeys = retainedVisibleImageRequestKeys
    for key in Array(visibleImageRequestStates.keys) where !activeKeys.contains(key) {
      clearVisibleImageRequest(key)
    }
    for key in Array(visibleImageRetryTasks.keys) where !activeKeys.contains(key) {
      clearVisibleImageRequest(key)
    }
  }

  private func isActiveVisibleImageRequest(_ key: VisibleImageRequestKey) -> Bool {
    retainedVisibleImageRequestKeys.contains(key)
  }

  private func isCurrentVisibleImageRequest(_ key: VisibleImageRequestKey) -> Bool {
    searchVisibleImageRequestKeys.contains(key)
      || listVisibleImageRequestKeys.contains(key)
  }

  func resetSearchVisibleImageRequests() {
    visibleImageDownloadGeneration += 1
    let keys = searchVisibleImageRequestWindows.flatMap { $0 }
    searchVisibleImageRequestKeys = []
    searchVisibleImageRequestWindows = []
    if visibleImageRequestSource == .search {
      visibleImageRequestSource = nil
    }
    visiblePreviewLoadingStore.updateCurrentKeys(listVisibleImageRequestKeys)
    for key in keys {
      clearVisibleImageRequest(key)
    }
  }

  func resetListVisibleImageRequests() {
    visibleImageDownloadGeneration += 1
    let keys = listVisibleImageRequestWindows.flatMap { $0 }
    listVisibleImageRequestKeys = []
    listVisibleImageRequestWindows = []
    if visibleImageRequestSource == .list {
      visibleImageRequestSource = nil
    }
    visiblePreviewLoadingStore.updateCurrentKeys(searchVisibleImageRequestKeys)
    for key in keys {
      clearVisibleImageRequest(key)
    }
  }

  func resetAllVisibleImageRequests() {
    visibleImageDownloadGeneration += 1
    searchVisibleImageRequestKeys = []
    listVisibleImageRequestKeys = []
    searchVisibleImageRequestWindows = []
    listVisibleImageRequestWindows = []
    visibleImageRequestSource = nil
    visiblePreviewLoadingStore.removeAll()
    for key in Array(visibleImageRequestStates.keys) {
      clearVisibleImageRequest(key)
    }
    for key in Array(visibleImageRetryTasks.keys) {
      clearVisibleImageRequest(key)
    }
  }

  private func clearVisibleImageRequest(_ key: VisibleImageRequestKey) {
    visibleImageRetryTasks[key]?.cancel()
    visibleImageRetryTasks[key] = nil
    setVisibleImageRequestState(nil, for: key)
  }

  private func setVisibleImageRequestState(
    _ state: VisibleImageRequestState?,
    for key: VisibleImageRequestKey
  ) {
    visibleImageRequestStates[key] = state
    visiblePreviewLoadingStore.setState(state, for: key)
  }

  private var retainedVisibleImageRequestKeys: Set<VisibleImageRequestKey> {
    Set(searchVisibleImageRequestWindows.flatMap { $0 })
      .union(listVisibleImageRequestWindows.flatMap { $0 })
  }

  private func retainedVisibleImageWindows(
    adding keys: Set<VisibleImageRequestKey>,
    to windows: [Set<VisibleImageRequestKey>]
  ) -> [Set<VisibleImageRequestKey>] {
    guard !keys.isEmpty else {
      return windows
    }

    var updated = windows.filter { $0 != keys }
    updated.insert(keys, at: 0)
    let retainedCount = imageDownloadConfiguration.visibleRetainedWindowCount
    if updated.count > retainedCount {
      updated.removeLast(updated.count - retainedCount)
    }
    return updated
  }

  private func cardForVisibleImageRequest(_ key: VisibleImageRequestKey) -> CardRecord? {
    cards.first { $0.id == key.cardID }
      ?? selectedListEntries.compactMap(\.card).first { $0.id == key.cardID }
  }

  private func hasRemoteDisplayCandidate(
    for quality: CardImageQuality,
    in source: CardArtworkImageSource
  ) -> Bool {
    fallbackQualities(for: quality).contains { source.hasRemoteImage(for: $0) }
  }

  private func fallbackQualities(for quality: CardImageQuality) -> [CardImageQuality] {
    switch quality {
    case .small:
      [.small, .normal]
    case .normal:
      [.normal, .small]
    case .large:
      [.large, .normal, .small]
    case .artCrop:
      [.artCrop, .normal, .small]
    }
  }

  private func visibleRetryDelayNanoseconds(beforeAttempt attempt: Int) -> UInt64 {
    let delays = imageDownloadConfiguration.visibleRetryDelayNanoseconds
    guard !delays.isEmpty else {
      return 0
    }

    let delayIndex = max(0, attempt - 2)
    guard delayIndex < delays.count else {
      return delays[delays.count - 1]
    }

    return delays[delayIndex]
  }

  public func loadPrintings(for card: CardRecord) async {
    guard selectedCard?.id == card.id else {
      return
    }

    if !selectedCardPrintings.contains(where: { $0.id == card.id }) {
      selectedCardPrintings = [card]
    }
    let database = database
    let result = await Task.detached(priority: .userInitiated) {
      do {
        return PrintingsLoadResult.success(try database.printings(for: card))
      } catch {
        return PrintingsLoadResult.failure
      }
    }.value

    guard selectedCard?.id == card.id else {
      return
    }

    switch result {
    case .success(let printings):
      selectedCardPrintings = printings.isEmpty ? [card] : printings
    case .failure:
      selectedCardPrintings = [card]
    }
  }

  public func loadValueGuide(for card: CardRecord) async {
    guard selectedCard?.id == card.id else {
      return
    }

    let database = database
    let result = await Task.detached(priority: .userInitiated) {
      do {
        return try database.valueGuide(forCardID: card.id)
      } catch {
        return CardValueGuide(cardID: card.id)
      }
    }.value

    guard selectedCard?.id == card.id else {
      return
    }
    selectedCardValueGuide = result
  }

  public func loadValueExchangeRateIfNeeded(for currency: CardValueDisplayCurrency) async {
    guard currency != .usd else {
      valueExchangeRate = nil
      return
    }

    if valueExchangeRate?.quoteCurrency == currency {
      return
    }

    do {
      valueExchangeRate = try await currencyExchangeRateClient.latestRate(from: .usd, to: currency)
    } catch {
      valueExchangeRate = nil
    }
  }
}
