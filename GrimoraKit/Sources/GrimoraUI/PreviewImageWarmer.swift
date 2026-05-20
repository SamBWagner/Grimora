import Foundation

actor PreviewImageWarmer {
  private let loader: LocalCardImageLoader
  private let historyWarmDelayNanoseconds: UInt64
  private var visibleTask: Task<Void, Never>?
  private var historyTask: Task<Void, Never>?
  private var pendingHistoryPaths: [String] = []
  private var visibleWarmID = 0
  private var historyWarmID = 0
  private var drainContinuations: [CheckedContinuation<Void, Never>] = []

  init(
    loader: LocalCardImageLoader = .shared,
    historyWarmDelayNanoseconds: UInt64
  ) {
    self.loader = loader
    self.historyWarmDelayNanoseconds = historyWarmDelayNanoseconds
  }

  func scheduleVisible(paths: [String]) {
    historyTask?.cancel()
    let paths = uniqueExistingPaths(paths)
    guard !paths.isEmpty else {
      visibleTask?.cancel()
      visibleTask = nil
      reschedulePendingHistoryAfterIdle()
      return
    }

    visibleTask?.cancel()
    visibleWarmID += 1
    let warmID = visibleWarmID
    visibleTask = Task(priority: .utility) { [weak self, loader] in
      await loader.preload(paths: paths)
      await self?.completeVisibleWarm(id: warmID)
    }

    reschedulePendingHistoryAfterIdle()
  }

  func scheduleHistory(paths: [String]) {
    pendingHistoryPaths = uniqueExistingPaths(paths)
    reschedulePendingHistoryAfterIdle()
  }

  func cancelHistory() {
    pendingHistoryPaths = []
    historyTask?.cancel()
    historyTask = nil
    resumeDrainContinuationsIfNeeded()
  }

  func drainForTesting() async {
    while !isIdle {
      await withCheckedContinuation { continuation in
        drainContinuations.append(continuation)
      }
    }
  }

  private var isIdle: Bool {
    (visibleTask == nil || visibleTask?.isCancelled == true)
      && (historyTask == nil || historyTask?.isCancelled == true)
      && pendingHistoryPaths.isEmpty
  }

  private func reschedulePendingHistoryAfterIdle() {
    historyTask?.cancel()
    historyWarmID += 1
    let warmID = historyWarmID
    guard !pendingHistoryPaths.isEmpty else {
      historyTask = nil
      resumeDrainContinuationsIfNeeded()
      return
    }

    let paths = pendingHistoryPaths
    let delay = historyWarmDelayNanoseconds
    historyTask = Task(priority: .background) { [weak self, loader] in
      if delay > 0 {
        do {
          try await Task.sleep(nanoseconds: delay)
        } catch {
          return
        }
      }

      guard !Task.isCancelled else {
        return
      }

      await loader.preload(paths: paths)
      await self?.completeHistoryWarm(paths: paths, id: warmID)
    }
  }

  private func completeVisibleWarm(id: Int) {
    guard visibleWarmID == id else {
      return
    }

    visibleTask = nil
    resumeDrainContinuationsIfNeeded()
  }

  private func completeHistoryWarm(paths: [String], id: Int) {
    guard historyWarmID == id else {
      return
    }

    if pendingHistoryPaths == paths {
      pendingHistoryPaths = []
    }
    historyTask = nil
    resumeDrainContinuationsIfNeeded()
  }

  private func uniqueExistingPaths(_ paths: [String]) -> [String] {
    var seen: Set<String> = []
    return paths.compactMap { path in
      let filePath = LocalCardImageLoader.fileSystemPath(from: path)
      guard seen.insert(filePath).inserted else {
        return nil
      }
      let size = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size]) as? NSNumber
      guard (size?.intValue ?? 0) > 0 else {
        return nil
      }
      return path
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
