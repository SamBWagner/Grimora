import Foundation
import GrimoraCore

actor CardImageDownloadCoordinator {
  enum Lane: Sendable {
    case visible
    case detail
  }

  typealias StartHandler = @MainActor @Sendable (CardImageDownloadStart) -> Void
  typealias CompletionHandler = @MainActor @Sendable (CardImageDownloadCompletion) -> Void

  private struct RequestKey: Hashable {
    var cardID: String
    var quality: CardImageQuality
  }

  private struct WorkItem {
    var key: RequestKey
    var card: CardRecord
    var quality: CardImageQuality
    var lane: Lane
    var generation: Int
    var onStart: StartHandler
    var onComplete: CompletionHandler
  }

  private let imageCache: CardImageCache
  private let visibleLimit: Int
  private let detailLimit: Int
  private let visibleAttemptTimeoutNanoseconds: UInt64
  private let visiblePendingLimit: Int
  private var visibleQueue: [WorkItem] = []
  private var detailQueue: [WorkItem] = []
  private var queuedKeys: Set<RequestKey> = []
  private var inFlightKeys: Set<RequestKey> = []
  private var activeVisibleCount = 0
  private var activeDetailCount = 0
  private var drainContinuations: [CheckedContinuation<Void, Never>] = []

  init(
    imageCache: CardImageCache,
    visibleLimit: Int,
    detailLimit: Int,
    visibleAttemptTimeoutNanoseconds: UInt64,
    visiblePendingLimit: Int
  ) {
    self.imageCache = imageCache
    self.visibleLimit = max(1, visibleLimit)
    self.detailLimit = max(1, detailLimit)
    self.visibleAttemptTimeoutNanoseconds = visibleAttemptTimeoutNanoseconds
    self.visiblePendingLimit = max(1, visiblePendingLimit)
  }

  func enqueue(
    card: CardRecord,
    quality: CardImageQuality,
    lane: Lane,
    generation: Int = 0,
    onStart: @escaping StartHandler,
    onComplete: @escaping CompletionHandler
  ) {
    let key = RequestKey(cardID: card.id, quality: quality)
    guard !queuedKeys.contains(key), !inFlightKeys.contains(key) else {
      return
    }

    queuedKeys.insert(key)
    let item = WorkItem(
      key: key,
      card: card,
      quality: quality,
      lane: lane,
      generation: generation,
      onStart: onStart,
      onComplete: onComplete
    )
    switch lane {
    case .visible:
      visibleQueue.append(item)
    case .detail:
      detailQueue.append(item)
    }

    startAvailableWork()
  }

  func replaceVisibleWindow(
    cards: [CardRecord],
    quality: CardImageQuality,
    generation: Int,
    onStart: @escaping StartHandler,
    onComplete: @escaping CompletionHandler
  ) {
    let requestedItems = cards.map { card in
      WorkItem(
        key: RequestKey(cardID: card.id, quality: quality),
        card: card,
        quality: quality,
        lane: .visible,
        generation: generation,
        onStart: onStart,
        onComplete: onComplete
      )
    }
    let requestedKeys = Set(requestedItems.map(\.key))

    detailQueue.removeAll { requestedKeys.contains($0.key) }
    visibleQueue.removeAll { $0.generation != generation }
    let existingVisibleItems = Dictionary(
      uniqueKeysWithValues: visibleQueue.map { ($0.key, $0) }
    )
    let prioritizedItems: [WorkItem] = requestedItems.compactMap { item in
      guard !inFlightKeys.contains(item.key) else {
        return nil
      }

      return existingVisibleItems[item.key] ?? item
    }
    let retainedItems = visibleQueue.filter { !requestedKeys.contains($0.key) }
    visibleQueue = prioritizedItems + retainedItems
    if visibleQueue.count > visiblePendingLimit {
      visibleQueue.removeLast(visibleQueue.count - visiblePendingLimit)
    }
    queuedKeys = Set(detailQueue.map(\.key)).union(visibleQueue.map(\.key))

    startAvailableWork()
  }

  func drain() async {
    guard !isIdle else {
      return
    }

    await withCheckedContinuation { continuation in
      drainContinuations.append(continuation)
    }
  }

  private var isIdle: Bool {
    visibleQueue.isEmpty
      && detailQueue.isEmpty
      && activeVisibleCount == 0
      && activeDetailCount == 0
  }

  private func startAvailableWork() {
    while activeDetailCount < detailLimit, !detailQueue.isEmpty {
      start(detailQueue.removeFirst())
    }

    while activeVisibleCount < visibleLimit, !visibleQueue.isEmpty {
      start(visibleQueue.removeFirst())
    }
  }

  private func start(_ item: WorkItem) {
    queuedKeys.remove(item.key)
    inFlightKeys.insert(item.key)

    switch item.lane {
    case .visible:
      activeVisibleCount += 1
    case .detail:
      activeDetailCount += 1
    }

    let priority: TaskPriority = item.lane == .detail ? .userInitiated : .utility
    let timeoutNanoseconds =
      item.lane == .visible ? visibleAttemptTimeoutNanoseconds : 0
    Task { @MainActor in
      item.onStart(
        CardImageDownloadStart(
          card: item.card,
          quality: item.quality,
          lane: item.lane
        ))
    }
    Task.detached(priority: priority) { [imageCache] in
      let updatedCard = await Self.cacheDisplayedImageRecord(
        imageCache: imageCache,
        card: item.card,
        quality: item.quality,
        timeoutNanoseconds: timeoutNanoseconds
      )

      await self.complete(item, updatedCard: updatedCard)
    }
  }

  private func complete(_ item: WorkItem, updatedCard: CardRecord?) async {
    inFlightKeys.remove(item.key)
    switch item.lane {
    case .visible:
      activeVisibleCount -= 1
    case .detail:
      activeDetailCount -= 1
    }

    await item.onComplete(
      CardImageDownloadCompletion(
        card: item.card,
        quality: item.quality,
        lane: item.lane,
        updatedCard: updatedCard
      ))

    startAvailableWork()
    resumeDrainContinuationsIfNeeded()
  }

  private static func cacheDisplayedImageRecord(
    imageCache: CardImageCache,
    card: CardRecord,
    quality: CardImageQuality,
    timeoutNanoseconds: UInt64
  ) async -> CardRecord? {
    do {
      guard timeoutNanoseconds > 0 else {
        return try await imageCache.cacheDisplayedImageRecord(for: card, quality: quality)
      }

      return try await withThrowingTaskGroup(of: CardRecord?.self) { group in
        group.addTask {
          try await imageCache.cacheDisplayedImageRecord(for: card, quality: quality)
        }
        group.addTask {
          try await Task.sleep(nanoseconds: timeoutNanoseconds)
          throw CancellationError()
        }

        let result = try await group.next() ?? nil
        group.cancelAll()
        return result
      }
    } catch {
      return nil
    }
  }

  private func resumeDrainContinuationsIfNeeded() {
    guard isIdle else {
      return
    }

    let continuations = drainContinuations
    drainContinuations.removeAll()
    continuations.forEach { $0.resume() }
  }
}

struct CardImageDownloadStart: Sendable {
  var card: CardRecord
  var quality: CardImageQuality
  var lane: CardImageDownloadCoordinator.Lane
}

struct CardImageDownloadCompletion: Sendable {
  var card: CardRecord
  var quality: CardImageQuality
  var lane: CardImageDownloadCoordinator.Lane
  var updatedCard: CardRecord?
}
