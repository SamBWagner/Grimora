import Combine
import XCTest

@testable import GrimoraCore
@testable import GrimoraUI

private func modelTestImageData() -> Data {
  Data([0xff, 0xd8, 0xff, 0xd9])
}

private func modelTestPNGImageData() -> Data {
  Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
}

private actor ModelTestNetworkClient: NetworkClient {
  var dataResponses: [URL: Data]
  private var recordedRequests: [(url: URL, purpose: NetworkPurpose)] = []

  init(dataResponses: [URL: Data]) {
    self.dataResponses = dataResponses
  }

  func data(from url: URL, purpose: NetworkPurpose) async throws -> Data {
    recordedRequests.append((url, purpose))
    return dataResponses[url] ?? Data()
  }

  func download(
    from url: URL,
    to destination: URL,
    purpose: NetworkPurpose,
    progress: (@Sendable (NetworkDownloadProgress) async -> Void)? = nil
  ) async throws {
    recordedRequests.append((url, purpose))
    let data = dataResponses[url] ?? Data()
    await progress?(NetworkDownloadProgress(completedBytes: 0, totalBytes: Int64(data.count)))
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: destination, options: .atomic)
    await progress?(NetworkDownloadProgress(completedBytes: Int64(data.count), totalBytes: Int64(data.count)))
  }

  func requests() -> [(url: URL, purpose: NetworkPurpose)] {
    recordedRequests
  }
}

private actor SuspendedModelNetworkClient: NetworkClient {
  var dataResponses: [URL: Data]
  let suspendedURL: URL
  private var recordedRequests: [(url: URL, purpose: NetworkPurpose)] = []
  private var releaseImmediately = false
  private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
  private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  init(dataResponses: [URL: Data], suspendedURL: URL) {
    self.dataResponses = dataResponses
    self.suspendedURL = suspendedURL
  }

  func data(from url: URL, purpose: NetworkPurpose) async throws -> Data {
    recordedRequests.append((url, purpose))
    resumeRequestWaiters()
    if url == suspendedURL {
      await waitForRelease()
    }
    return dataResponses[url] ?? Data()
  }

  func download(
    from url: URL,
    to destination: URL,
    purpose: NetworkPurpose,
    progress: (@Sendable (NetworkDownloadProgress) async -> Void)? = nil
  ) async throws {
    recordedRequests.append((url, purpose))
    resumeRequestWaiters()
    if url == suspendedURL {
      await waitForRelease()
    }
    let data = dataResponses[url] ?? Data()
    await progress?(NetworkDownloadProgress(completedBytes: 0, totalBytes: Int64(data.count)))
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: destination, options: .atomic)
    await progress?(NetworkDownloadProgress(completedBytes: Int64(data.count), totalBytes: Int64(data.count)))
  }

  func waitForRequestCount(_ count: Int) async {
    if recordedRequests.count >= count {
      return
    }

    await withCheckedContinuation { continuation in
      requestWaiters.append((count, continuation))
    }
  }

  func release() {
    releaseImmediately = true
    let continuations = releaseContinuations
    releaseContinuations.removeAll()
    for continuation in continuations {
      continuation.resume()
    }
  }

  func requests() -> [(url: URL, purpose: NetworkPurpose)] {
    recordedRequests
  }

  private func waitForRelease() async {
    if releaseImmediately {
      return
    }

    await withCheckedContinuation { continuation in
      releaseContinuations.append(continuation)
    }
  }

  private func resumeRequestWaiters() {
    let ready = requestWaiters.filter { recordedRequests.count >= $0.0 }
    requestWaiters.removeAll { recordedRequests.count >= $0.0 }
    for waiter in ready {
      waiter.1.resume()
    }
  }
}

private struct ModelTestImageResolver: ImageResolving {
  var rootDirectory: URL
  var failedURLs: Set<URL> = []

  func localPaths(for remoteURLs: ImageURLPair, cardID: String, faceIndex: Int?) -> LocalImagePair {
    let store = ImageStore(rootDirectory: rootDirectory)
    return LocalImagePair(
      smallPath: remoteURLs.small.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.small.rawValue
        ).path
      },
      normalPath: remoteURLs.normal.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.normal.rawValue
        ).path
      },
      largePath: remoteURLs.large.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.large.rawValue
        ).path
      },
      artCropPath: remoteURLs.artCrop.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.artCrop.rawValue
        ).path
      }
    )
  }

  func resolve(
    _ remoteURLs: ImageURLPair,
    cardID: String,
    faceIndex: Int?,
    qualities: Set<CardImageQuality>
  ) async -> ImageResolution {
    let store = ImageStore(rootDirectory: rootDirectory)
    var paths = LocalImagePair()
    var failures: [URL] = []

    for quality in CardImageQuality.allCases where qualities.contains(quality) {
      let remoteURL: URL?
      switch quality {
      case .small:
        remoteURL = remoteURLs.small
      case .normal:
        remoteURL = remoteURLs.normal
      case .large:
        remoteURL = remoteURLs.large
      case .artCrop:
        remoteURL = remoteURLs.artCrop
      }

      guard let remoteURL else {
        continue
      }

      let localURL = store.localURL(
        for: remoteURL, cardID: cardID, faceIndex: faceIndex, quality: quality.rawValue)
      if failedURLs.contains(remoteURL) {
        failures.append(remoteURL)
        continue
      }

      try? FileManager.default.createDirectory(
        at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? modelTestImageData().write(to: localURL, options: .atomic)

      switch quality {
      case .small:
        paths.smallPath = localURL.path
      case .normal:
        paths.normalPath = localURL.path
      case .large:
        paths.largePath = localURL.path
      case .artCrop:
        paths.artCropPath = localURL.path
      }
    }

    return ImageResolution(paths: paths, failedURLs: failures)
  }
}

private struct ModelImageResolutionCall: Equatable, Sendable {
  var cardID: String
  var faceIndex: Int?
  var qualities: Set<CardImageQuality>
  var remoteURLs: ImageURLPair
}

private actor RecordingModelImageResolver: ImageResolving {
  nonisolated let rootDirectory: URL
  private var calls: [ModelImageResolutionCall] = []

  init(rootDirectory: URL) {
    self.rootDirectory = rootDirectory
  }

  nonisolated func localPaths(for remoteURLs: ImageURLPair, cardID: String, faceIndex: Int?)
    -> LocalImagePair
  {
    let store = ImageStore(rootDirectory: rootDirectory)
    return LocalImagePair(
      smallPath: remoteURLs.small.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.small.rawValue
        ).path
      },
      normalPath: remoteURLs.normal.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.normal.rawValue
        ).path
      },
      largePath: remoteURLs.large.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.large.rawValue
        ).path
      },
      artCropPath: remoteURLs.artCrop.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.artCrop.rawValue
        ).path
      }
    )
  }

  func resolve(
    _ remoteURLs: ImageURLPair,
    cardID: String,
    faceIndex: Int?,
    qualities: Set<CardImageQuality>
  ) async -> ImageResolution {
    calls.append(
      ModelImageResolutionCall(
        cardID: cardID,
        faceIndex: faceIndex,
        qualities: qualities,
        remoteURLs: remoteURLs
      ))

    let store = ImageStore(rootDirectory: rootDirectory)
    var paths = LocalImagePair()

    for quality in CardImageQuality.allCases where qualities.contains(quality) {
      let remoteURL: URL?
      switch quality {
      case .small:
        remoteURL = remoteURLs.small
      case .normal:
        remoteURL = remoteURLs.normal
      case .large:
        remoteURL = remoteURLs.large
      case .artCrop:
        remoteURL = remoteURLs.artCrop
      }

      guard let remoteURL else {
        continue
      }

      let localURL = store.localURL(
        for: remoteURL, cardID: cardID, faceIndex: faceIndex, quality: quality.rawValue)
      try? FileManager.default.createDirectory(
        at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? modelTestImageData().write(to: localURL, options: .atomic)

      switch quality {
      case .small:
        paths.smallPath = localURL.path
      case .normal:
        paths.normalPath = localURL.path
      case .large:
        paths.largePath = localURL.path
      case .artCrop:
        paths.artCropPath = localURL.path
      }
    }

    return ImageResolution(paths: paths)
  }

  func recordedCalls() -> [ModelImageResolutionCall] {
    calls
  }
}

private actor FlakyModelImageResolver: ImageResolving {
  nonisolated let rootDirectory: URL
  private var remainingFailureCounts: [URL: Int]
  private var calls: [ModelImageResolutionCall] = []
  private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  init(rootDirectory: URL, failureCounts: [URL: Int]) {
    self.rootDirectory = rootDirectory
    self.remainingFailureCounts = failureCounts
  }

  nonisolated func localPaths(for remoteURLs: ImageURLPair, cardID: String, faceIndex: Int?)
    -> LocalImagePair
  {
    let store = ImageStore(rootDirectory: rootDirectory)
    return LocalImagePair(
      smallPath: remoteURLs.small.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.small.rawValue
        ).path
      },
      normalPath: remoteURLs.normal.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.normal.rawValue
        ).path
      },
      largePath: remoteURLs.large.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.large.rawValue
        ).path
      },
      artCropPath: remoteURLs.artCrop.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.artCrop.rawValue
        ).path
      }
    )
  }

  func resolve(
    _ remoteURLs: ImageURLPair,
    cardID: String,
    faceIndex: Int?,
    qualities: Set<CardImageQuality>
  ) async -> ImageResolution {
    calls.append(
      ModelImageResolutionCall(
        cardID: cardID,
        faceIndex: faceIndex,
        qualities: qualities,
        remoteURLs: remoteURLs
      ))
    resumeSatisfiedCallWaiters()

    let store = ImageStore(rootDirectory: rootDirectory)
    var paths = LocalImagePair()
    var failures: [URL] = []

    for quality in CardImageQuality.allCases where qualities.contains(quality) {
      let remoteURL: URL?
      switch quality {
      case .small:
        remoteURL = remoteURLs.small
      case .normal:
        remoteURL = remoteURLs.normal
      case .large:
        remoteURL = remoteURLs.large
      case .artCrop:
        remoteURL = remoteURLs.artCrop
      }

      guard let remoteURL else {
        continue
      }

      if let remainingFailures = remainingFailureCounts[remoteURL], remainingFailures > 0 {
        remainingFailureCounts[remoteURL] = remainingFailures - 1
        failures.append(remoteURL)
        continue
      }

      let localURL = store.localURL(
        for: remoteURL, cardID: cardID, faceIndex: faceIndex, quality: quality.rawValue)
      try? FileManager.default.createDirectory(
        at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? modelTestImageData().write(to: localURL, options: .atomic)

      switch quality {
      case .small:
        paths.smallPath = localURL.path
      case .normal:
        paths.normalPath = localURL.path
      case .large:
        paths.largePath = localURL.path
      case .artCrop:
        paths.artCropPath = localURL.path
      }
    }

    return ImageResolution(paths: paths, failedURLs: failures)
  }

  func waitForCallCount(_ count: Int) async {
    guard calls.count < count else {
      return
    }

    await withCheckedContinuation { continuation in
      callWaiters.append((count, continuation))
    }
  }

  func recordedCalls() -> [ModelImageResolutionCall] {
    calls
  }

  func callCountsByCardID() -> [String: Int] {
    Dictionary(grouping: calls, by: \.cardID).mapValues(\.count)
  }

  private func resumeSatisfiedCallWaiters() {
    let ready = callWaiters.filter { calls.count >= $0.0 }
    callWaiters.removeAll { calls.count >= $0.0 }
    for waiter in ready {
      waiter.1.resume()
    }
  }
}

private actor DelayedModelImageResolver: ImageResolving {
  nonisolated let rootDirectory: URL
  private var startedCount = 0
  private var startedCardIDs: [String] = []
  private var activeCount = 0
  private var maxActiveCount = 0
  private var releaseImmediately = false
  private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
  private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  init(rootDirectory: URL) {
    self.rootDirectory = rootDirectory
  }

  nonisolated func localPaths(for remoteURLs: ImageURLPair, cardID: String, faceIndex: Int?)
    -> LocalImagePair
  {
    let store = ImageStore(rootDirectory: rootDirectory)
    return LocalImagePair(
      smallPath: remoteURLs.small.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.small.rawValue
        ).path
      },
      normalPath: remoteURLs.normal.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.normal.rawValue
        ).path
      },
      largePath: remoteURLs.large.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.large.rawValue
        ).path
      },
      artCropPath: remoteURLs.artCrop.map {
        store.localURL(
          for: $0, cardID: cardID, faceIndex: faceIndex, quality: CardImageQuality.artCrop.rawValue
        ).path
      }
    )
  }

  func resolve(
    _ remoteURLs: ImageURLPair,
    cardID: String,
    faceIndex: Int?,
    qualities: Set<CardImageQuality>
  ) async -> ImageResolution {
    startedCount += 1
    startedCardIDs.append(cardID)
    activeCount += 1
    maxActiveCount = max(maxActiveCount, activeCount)
    resumeSatisfiedStartWaiters()

    if !releaseImmediately {
      await withCheckedContinuation { continuation in
        releaseContinuations.append(continuation)
      }
    }

    activeCount -= 1
    return writeImage(remoteURLs, cardID: cardID, faceIndex: faceIndex, qualities: qualities)
  }

  func waitForStartedCount(_ count: Int) async {
    guard startedCount < count else {
      return
    }

    await withCheckedContinuation { continuation in
      startWaiters.append((count, continuation))
    }
  }

  func releaseAll() {
    releaseImmediately = true
    let continuations = releaseContinuations
    releaseContinuations.removeAll()
    continuations.forEach { $0.resume() }
  }

  func counts() -> (started: Int, active: Int, maxActive: Int) {
    (startedCount, activeCount, maxActiveCount)
  }

  func startedIDs() -> [String] {
    startedCardIDs
  }

  private func resumeSatisfiedStartWaiters() {
    var remaining: [(Int, CheckedContinuation<Void, Never>)] = []
    for (count, continuation) in startWaiters {
      if startedCount >= count {
        continuation.resume()
      } else {
        remaining.append((count, continuation))
      }
    }
    startWaiters = remaining
  }

  private func writeImage(
    _ remoteURLs: ImageURLPair,
    cardID: String,
    faceIndex: Int?,
    qualities: Set<CardImageQuality>
  ) -> ImageResolution {
    let store = ImageStore(rootDirectory: rootDirectory)
    var paths = LocalImagePair()

    for quality in CardImageQuality.allCases where qualities.contains(quality) {
      let remoteURL: URL?
      switch quality {
      case .small:
        remoteURL = remoteURLs.small
      case .normal:
        remoteURL = remoteURLs.normal
      case .large:
        remoteURL = remoteURLs.large
      case .artCrop:
        remoteURL = remoteURLs.artCrop
      }

      guard let remoteURL else {
        continue
      }

      let localURL = store.localURL(
        for: remoteURL, cardID: cardID, faceIndex: faceIndex, quality: quality.rawValue)
      try? FileManager.default.createDirectory(
        at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? modelTestImageData().write(to: localURL, options: .atomic)

      switch quality {
      case .small:
        paths.smallPath = localURL.path
      case .normal:
        paths.normalPath = localURL.path
      case .large:
        paths.largePath = localURL.path
      case .artCrop:
        paths.artCropPath = localURL.path
      }
    }

    return ImageResolution(paths: paths)
  }
}

private final class TestPlainTextSearchTranspiler: PlainTextSearchTranspiling, @unchecked Sendable {
  enum Response: Sendable {
    case success(query: String, note: String? = nil)
    case failure(String)
    case unavailable(String)
  }

  private let response: Response
  private let repairResponse: Response?
  private let delayNanoseconds: UInt64
  private let lock = NSLock()
  private var transpileCallCount = 0
  private var repairCallCount = 0

  var availability: PlainTextSearchTranspilerAvailability {
    switch response {
    case .unavailable(let message):
      .unavailable(message)
    case .success, .failure:
      .available
    }
  }

  init(
    response: Response,
    repairResponse: Response? = nil,
    delayNanoseconds: UInt64 = 0
  ) {
    self.response = response
    self.repairResponse = repairResponse
    self.delayNanoseconds = delayNanoseconds
  }

  func transpile(_ prompt: String) async throws -> PlainTextSearchTranspilation {
    lock.withLock {
      transpileCallCount += 1
    }
    return try await result(for: response)
  }

  func repair(
    prompt: String,
    rejectedQuery: String,
    reason: SearchQueryUnsupportedReason
  ) async throws -> PlainTextSearchTranspilation {
    lock.withLock {
      repairCallCount += 1
    }
    return try await result(for: repairResponse ?? response)
  }

  func counts() -> (transpile: Int, repair: Int) {
    lock.withLock {
      (transpileCallCount, repairCallCount)
    }
  }

  private func result(for response: Response) async throws -> PlainTextSearchTranspilation {
    if delayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    switch response {
    case .success(let query, let note):
      return PlainTextSearchTranspilation(query: query, note: note)
    case .failure(let message):
      throw PlainTextSearchTranspilerError.failed(message)
    case .unavailable(let message):
      throw PlainTextSearchTranspilerError.unavailable(message)
    }
  }
}

@MainActor
final class GrimoraAppModelTests: XCTestCase {
  func testModelLoadsSearchesSortsAndTogglesFilters() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    XCTAssertTrue(model.hasLibrary)
    XCTAssertFalse(model.isSearchingCards)
    XCTAssertFalse(model.cards.contains(where: { $0.name == "Digital Conjurer" }))

    model.searchText = "forest"
    XCTAssertFalse(model.isSearchingCards)
    XCTAssertTrue(model.hasUnsubmittedSearchText)
    await model.submitSearch()
    XCTAssertTrue(model.isSearchingCards)
    XCTAssertFalse(model.isLoadingMoreCards)
    await model.drainSearchForTesting()
    XCTAssertFalse(model.isSearchingCards)
    XCTAssertEqual(model.cards.map(\.name), ["Alpha Forest"])

    model.clearSearch()
    model.sortMode = .artistName
    await model.drainSearchForTesting()
    XCTAssertEqual(model.cards.first?.name, "Beta Mage")

    model.toggleFilter(.realCards)
    await model.drainSearchForTesting()
    XCTAssertTrue(model.cards.contains(where: { $0.name == "Soldier Token" }))
  }

  func testModelWaitsForExplicitScryfallSubmit() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration(
          textDebounceNanoseconds: 1_000_000,
          prefetchesNextPage: false
        )
      ))
    await model.drainSearchForTesting()

    model.searchText = "forest"

    XCTAssertFalse(model.isSearchingCards)
    XCTAssertNotEqual(model.cards.map(\.id), ["forest"])

    await model.drainSearchForTesting()
    XCTAssertEqual(model.cards.map(\.id), ["forest", "beta"])

    await model.submitSearch()
    XCTAssertTrue(model.isSearchingCards)
    await model.drainSearchForTesting()

    XCTAssertEqual(model.cards.map(\.id), ["forest"])
  }

  func testScryfallDraftCancelAndHistoryHydrationWaitForSubmit() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.searchText = "forest"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.submittedSearchText, "forest")
    XCTAssertEqual(model.cards.map(\.id), ["forest"])

    model.searchText = "beta"
    await model.drainSearchForTesting()

    XCTAssertEqual(model.searchText, "beta")
    XCTAssertEqual(model.submittedSearchText, "forest")
    XCTAssertTrue(model.hasUnsubmittedSearchText)
    XCTAssertEqual(model.cards.map(\.id), ["forest"])

    model.cancelSearchEditing()

    XCTAssertEqual(model.searchText, "forest")
    XCTAssertFalse(model.hasUnsubmittedSearchText)
    XCTAssertEqual(model.cards.map(\.id), ["forest"])

    model.searchText = "beta"
    await model.drainSearchForTesting()

    XCTAssertEqual(model.cards.map(\.id), ["forest"])
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.submittedSearchText, "beta")
    XCTAssertEqual(model.cards.map(\.id), ["beta"])
  }

  func testClearingSearchDraftReturnsToDefaultSearch() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.searchText = "forest"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.submittedSearchText, "forest")
    XCTAssertEqual(model.cards.map(\.id), ["forest"])

    model.searchText = "beta"
    model.setSearchDraft("")
    await model.drainSearchForTesting()

    XCTAssertEqual(model.searchText, "")
    XCTAssertEqual(model.submittedSearchText, "")
    XCTAssertFalse(model.hasUnsubmittedSearchText)
    XCTAssertEqual(model.cards.map(\.id), ["forest", "beta"])
  }

  func testFiltersReloadUsingSubmittedQueryWhileDraftDiffers() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.searchText = "t:creature"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.cards.map(\.id), ["forest", "beta"])

    model.searchText = "beta"
    model.toggleFilter(.realCards)
    await model.drainSearchForTesting()

    XCTAssertEqual(model.searchText, "beta")
    XCTAssertEqual(model.submittedSearchText, "t:creature")
    XCTAssertTrue(model.hasUnsubmittedSearchText)
    XCTAssertTrue(model.cards.contains { $0.id == "forest" })
    XCTAssertTrue(model.cards.contains { $0.id == "beta" })
    XCTAssertTrue(model.cards.contains { $0.id == "token" })
  }

  func testModelLoadsMoreSearchResultsNearEnd() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(pagedRecords(count: 510))
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    XCTAssertEqual(model.cards.count, 250)
    XCTAssertEqual(model.searchResultTotal, 510)
    XCTAssertTrue(model.canLoadMoreCards)
    XCTAssertFalse(model.isLoadingMoreCards)
    XCTAssertFalse(model.isSearchingCards)

    let earlyCard = try XCTUnwrap(model.cards.first)
    model.loadMoreCardsIfNeeded(afterAppearing: earlyCard)
    await model.drainSearchForTesting()
    XCTAssertEqual(model.cards.count, 250)

    let firstPageLastCard = try XCTUnwrap(model.cards.last)
    model.loadMoreCardsIfNeeded(afterAppearing: firstPageLastCard)
    XCTAssertTrue(model.isLoadingMoreCards)
    XCTAssertFalse(model.isSearchingCards)
    await model.drainSearchForTesting()

    XCTAssertEqual(model.cards.count, 500)
    XCTAssertEqual(model.searchResultTotal, 510)
    XCTAssertTrue(model.canLoadMoreCards)
    XCTAssertFalse(model.isLoadingMoreCards)
    XCTAssertFalse(model.isSearchingCards)

    let secondPageLastCard = try XCTUnwrap(model.cards.last)
    model.loadMoreCardsIfNeeded(afterAppearing: secondPageLastCard)
    await model.drainSearchForTesting()

    XCTAssertEqual(model.cards.count, 510)
    XCTAssertEqual(model.searchResultTotal, 510)
    XCTAssertFalse(model.canLoadMoreCards)
    XCTAssertFalse(model.isLoadingMoreCards)
    XCTAssertFalse(model.isSearchingCards)
  }

  func testModelUsesPrefetchedNextSearchPageWhenLoadingMore() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(pagedRecords(count: 510))
    try markLibraryReady(database)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration(
          textDebounceNanoseconds: 0,
          prefetchesNextPage: true
        )
      ))
    await model.drainSearchForTesting()

    XCTAssertEqual(model.cards.count, 250)
    XCTAssertTrue(model.canLoadMoreCards)

    let firstPageLastCard = try XCTUnwrap(model.cards.last)
    model.loadMoreCardsIfNeeded(afterAppearing: firstPageLastCard)

    XCTAssertFalse(model.isLoadingMoreCards)
    XCTAssertEqual(model.cards.count, 500)
    XCTAssertEqual(model.searchResultTotal, 510)
    XCTAssertTrue(model.canLoadMoreCards)
  }

  func testModelCreatesListFromFullCurrentSearchBeyondLoadedPage() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(pagedRecords(count: 510))
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    XCTAssertEqual(model.cards.count, 250)
    XCTAssertEqual(model.searchResultTotal, 510)

    let createdList = await model.createCardListFromCurrentSearch(named: "Paged Picks")
    let list = try XCTUnwrap(createdList)

    XCTAssertEqual(list.name, "Paged Picks")
    XCTAssertEqual(model.sidebarSelection, .list(list.id))
    XCTAssertEqual(model.selectedList?.id, list.id)
    XCTAssertEqual(model.selectedList?.entryCount, 510)
    XCTAssertEqual(model.selectedListEntries.count, 510)
    XCTAssertEqual(model.selectedListEntries.first?.cardID, "paged-1000")
    XCTAssertEqual(model.selectedListEntries.last?.cardID, "paged-1509")
    XCTAssertEqual(model.statusMessage, "Created Paged Picks with 510 cards.")
  }

  func testModelBulkAddsSelectedCardIDsToExistingList() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "Deck Box", selectAfterCreate: true))

    model.addCards(["forest", "beta"], toListID: list.id)

    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["forest", "beta"])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [1, 1])
    XCTAssertEqual(model.selectedList?.entryCount, 2)
    XCTAssertEqual(model.statusMessage, "Added 2 cards to Deck Box.")
  }

  func testModelAddsCardsToAutoCreatedFavouritesIdempotently() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let currentList = try XCTUnwrap(model.createCardList(named: "Current", selectAfterCreate: true))
    let forest = try XCTUnwrap(model.cards.first { $0.id == "forest" })

    model.addCardToFavourites(forest)
    model.addCardToFavourites(forest)
    model.addCardsToFavourites(["forest", "beta", "forest"], primaryCard: forest)

    let favourites = try XCTUnwrap(model.cardLists.first { $0.name == "Favourites" })
    XCTAssertEqual(model.selectedListID, currentList.id)
    XCTAssertEqual(model.sidebarSelection, .list(currentList.id))
    XCTAssertEqual(favourites.entryCount, 2)

    let entries = try database.cardListEntries(forListID: favourites.id)
    XCTAssertEqual(entries.map(\.cardID), ["forest", "beta"])
    XCTAssertEqual(entries.map(\.quantity), [1, 1])
    XCTAssertEqual(model.statusMessage, "Added 1 card to Favourites.")
  }

  func testModelReusesFavoritesAliasForFavourites() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let aliasList = try XCTUnwrap(model.createCardList(named: "Favorites"))
    XCTAssertEqual(aliasList.name, "Favourites")

    model.addCardsToFavourites(["forest", "beta"])

    XCTAssertEqual(model.cardLists.map(\.name), ["Favourites"])
    XCTAssertEqual(model.cardLists.first?.entryCount, 2)
    let entries = try database.cardListEntries(forListID: aliasList.id)
    XCTAssertEqual(entries.map(\.cardID), ["forest", "beta"])
    XCTAssertEqual(entries.map(\.quantity), [1, 1])
  }

  func testModelProtectsSystemFavouritesList() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let favourites = try XCTUnwrap(model.favouritesList)
    XCTAssertEqual(model.cardLists.map(\.name), ["Favourites"])
    XCTAssertTrue(model.isProtectedFavouritesList(favourites))
    XCTAssertTrue(model.pinnedCardLists.isEmpty)
    XCTAssertTrue(model.unpinnedCardLists.isEmpty)

    model.renameCardList(id: favourites.id, to: "Deck Box")
    model.setCardListPinned(id: favourites.id, isPinned: true)
    model.moveCardList(id: favourites.id, toPosition: 3, isPinned: true)
    model.deleteCardList(id: favourites.id)

    let protectedList = try XCTUnwrap(model.favouritesList)
    XCTAssertEqual(protectedList.id, favourites.id)
    XCTAssertEqual(protectedList.name, "Favourites")
    XCTAssertFalse(protectedList.isPinned)
    XCTAssertEqual(model.cardLists.map(\.name), ["Favourites"])
  }

  func testListOverviewUsesVisibleTopCardOrderingAndHandlesMissingImages() async throws {
    let database = try CardDatabase(storage: .inMemory)
    var records = uiRecords()
    records[0].normalImagePath = "/tmp/forest-normal.jpg"
    records[0].artCropImagePath = "/tmp/forest-art-crop.jpg"
    records[1].normalImagePath = "/tmp/beta-normal.jpg"
    try database.replaceAllCards(records)
    try markLibraryReady(database)
    let list = try database.createCardList(named: "Drafts")
    let category = try database.createCardListCategory(inList: list.id, named: "Main")
    try database.appendCard("forest", toList: list.id, categoryID: category.id)
    try database.appendCard("beta", toList: list.id, categoryID: category.id)

    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let favouritesItem = try XCTUnwrap(model.cardListOverviewItems.first)
    XCTAssertEqual(favouritesItem.list.name, "Favourites")
    XCTAssertNil(favouritesItem.topEntry)
    XCTAssertNil(favouritesItem.topCard?.listOverviewImagePath)

    let initialItem = try XCTUnwrap(model.cardListOverviewItems.first { $0.list.id == list.id })
    XCTAssertEqual(initialItem.topEntry?.cardID, "forest")
    XCTAssertEqual(initialItem.topCard?.id, "forest")
    XCTAssertEqual(initialItem.topCard?.listOverviewImagePath, "/tmp/forest-art-crop.jpg")

    model.setCardListDisplaySort(id: list.id, mode: .name, direction: .descending)

    let sortedItem = try XCTUnwrap(model.cardListOverviewItems.first { $0.list.id == list.id })
    XCTAssertEqual(sortedItem.topEntry?.cardID, "beta")
    XCTAssertEqual(sortedItem.topCard?.id, "beta")
    XCTAssertEqual(sortedItem.topCard?.listOverviewImagePath, "/tmp/beta-normal.jpg")
  }

  func testModelCreatesListFromSelectedCardIDsAndConsolidatesDuplicates() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(
      model.createCardList(
        named: "Selected Picks",
        addingCardIDs: ["forest", "beta", "forest"],
        selectAfterCreate: true
      )
    )

    XCTAssertEqual(model.sidebarSelection, .list(list.id))
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["forest", "beta"])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [2, 1])
    XCTAssertEqual(model.selectedList?.entryCount, 3)
    XCTAssertEqual(model.statusMessage, "Created Selected Picks with 3 cards.")
  }

  func testModelCreatesSearchListUsingAllPrintingsInCurrentOrder() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([
      CardRecord(
        id: "forest-old",
        oracleID: "forest-oracle",
        name: "Alpha Forest",
        releasedAt: "2020-01-01",
        setCode: "abc",
        setName: "Alpha Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 0,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Forest sample.",
        isRealCard: true
      ),
      CardRecord(
        id: "forest-new",
        oracleID: "forest-oracle",
        name: "Alpha Forest",
        releasedAt: "2021-01-01",
        setCode: "xyz",
        setName: "Second Set",
        setType: "expansion",
        collectorNumber: "2",
        collectorNumberNumber: 2,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 0,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Forest sample.",
        isRealCard: true
      ),
    ])
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.printingDisplayMode = .all
    model.searchText = "forest"
    model.sortMode = .releaseDate
    model.sortDirection = .ascending
    await model.submitSearch()
    await model.drainSearchForTesting()
    let currentResultOrder = model.cards.map(\.id)

    let createdList = await model.createCardListFromCurrentSearch(named: "All Forests")
    let list = try XCTUnwrap(createdList)

    XCTAssertEqual(model.sidebarSelection, .list(list.id))
    XCTAssertEqual(model.selectedList?.id, list.id)
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), currentResultOrder)
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [1, 1])
  }

  func testModelDoesNotCreateSearchListForEmptyOrUnsupportedSearch() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.searchText = "no-card-has-this-name"
    await model.submitSearch()
    await model.drainSearchForTesting()
    let emptyList = await model.createCardListFromCurrentSearch(named: "Nothing")
    XCTAssertNil(emptyList)
    XCTAssertEqual(model.cardLists.map(\.name), ["Favourites"])
    XCTAssertEqual(model.statusMessage, "No search results to add.")

    model.searchText = "cube:vintage"
    await model.submitSearch()
    await model.drainSearchForTesting()
    let unsupportedList = await model.createCardListFromCurrentSearch(named: "Unsupported")
    XCTAssertNil(unsupportedList)
    XCTAssertEqual(model.cardLists.map(\.name), ["Favourites"])
    XCTAssertEqual(model.statusMessage, "No search results to add.")
  }

  func testModelShowsUnsupportedSearchState() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.searchText = "cube:vintage"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertTrue(model.cards.isEmpty)
    XCTAssertEqual(model.searchResultTotal, 0)
    XCTAssertEqual(
      model.unsupportedSearchMessage,
      "“cube:vintage” is Scryfall syntax that Grimora does not support offline yet.")
  }

  func testSearchPublishesLatestRequestOnly() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.searchText = "forest"
    await model.submitSearch()
    model.searchText = "beta"
    await model.submitSearch()
    await model.drainSearchForTesting()
    try await Task.sleep(nanoseconds: 50_000_000)

    XCTAssertEqual(model.cards.map(\.name), ["Beta Mage"])
  }

  func testPlainTextSearchWaitsForSubmitAndRunsGeneratedQuery() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let transpiler = TestPlainTextSearchTranspiler(
      response: .success(query: "name:forest", note: "Looking for Forest.")
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, plainTextSearchTranspiler: transpiler))
    await model.drainSearchForTesting()
    let initialResultIDs = model.cards.map(\.id)

    model.setSearchInputMode(.plainText)
    model.searchText = "show me forests"
    await model.drainSearchForTesting()

    XCTAssertEqual(transpiler.counts().transpile, 0)
    XCTAssertEqual(model.cards.map(\.id), initialResultIDs)
    XCTAssertNil(model.generatedSearchQuery)

    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(transpiler.counts().transpile, 1)
    XCTAssertEqual(model.searchText, "show me forests")
    XCTAssertEqual(model.generatedSearchQuery, "name:forest")
    XCTAssertEqual(model.cards.map(\.id), ["forest"])
  }

  func testPlainTextSearchUnavailableDoesNotEnterMode() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        plainTextSearchTranspiler: TestPlainTextSearchTranspiler(
          response: .unavailable("Apple Intelligence is off.")
        )
      ))
    await model.drainSearchForTesting()

    model.setSearchInputMode(.plainText)

    XCTAssertEqual(model.searchInputMode, .scryfall)
    XCTAssertEqual(model.plainTextSearchErrorMessage, "Apple Intelligence is off.")
  }

  func testPlainTextSearchRepairsUnsupportedGeneratedQuery() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let transpiler = TestPlainTextSearchTranspiler(
      response: .success(query: "cube:vintage"),
      repairResponse: .success(query: "name:forest")
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, plainTextSearchTranspiler: transpiler))
    await model.drainSearchForTesting()

    model.setSearchInputMode(.plainText)
    model.searchText = "cards for vintage cube forests"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(transpiler.counts().repair, 1)
    XCTAssertEqual(model.generatedSearchQuery, "name:forest")
    XCTAssertNil(model.unsupportedSearchMessage)
    XCTAssertEqual(model.cards.map(\.id), ["forest"])
  }

  func testPlainTextSearchAcceptsBareGeneratedScryfallNameTerms() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let transpiler = TestPlainTextSearchTranspiler(
      response: .success(query: "red goblin blue draw"),
      repairResponse: .failure("Bare Scryfall name searches should not require repair.")
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, plainTextSearchTranspiler: transpiler))
    await model.drainSearchForTesting()

    model.setSearchInputMode(.plainText)
    model.searchText = "goblins, red, also blue, maybe ones that have something that draws?"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(transpiler.counts().repair, 0)
    XCTAssertEqual(model.generatedSearchQuery, "red goblin blue draw")
    XCTAssertNil(model.unsupportedSearchMessage)
  }

  func testPlainTextSearchLocallyRepairsCreatureTokenColorMistake() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let transpiler = TestPlainTextSearchTranspiler(
      response: .success(query: "c:token"),
      repairResponse: .failure("The model repair should not be needed.")
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, plainTextSearchTranspiler: transpiler))
    await model.drainSearchForTesting()

    model.setSearchInputMode(.plainText)
    model.searchText = "creates tokens that are creatures"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(transpiler.counts().transpile, 1)
    XCTAssertEqual(transpiler.counts().repair, 0)
    XCTAssertEqual(model.generatedSearchQuery, "o:\"creature token\"")
    XCTAssertNil(model.unsupportedSearchMessage)
    XCTAssertNil(model.plainTextSearchErrorMessage)
  }

  func testPlainTextSearchCanonicalizesUnquotedCreatureTokenOraclePhrase() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let transpiler = TestPlainTextSearchTranspiler(
      response: .success(query: "o:creature token"),
      repairResponse: .failure("The model repair should not be needed.")
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, plainTextSearchTranspiler: transpiler))
    await model.drainSearchForTesting()

    model.setSearchInputMode(.plainText)
    model.searchText = "creates tokens that are creatures"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(transpiler.counts().transpile, 1)
    XCTAssertEqual(transpiler.counts().repair, 0)
    XCTAssertEqual(model.generatedSearchQuery, "o:\"creature token\"")
    XCTAssertNil(model.unsupportedSearchMessage)
    XCTAssertNil(model.plainTextSearchErrorMessage)
  }

  func testPlainTextSearchShowsUnsupportedWhenRepairStillFails() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        plainTextSearchTranspiler: TestPlainTextSearchTranspiler(
          response: .success(query: "cube:vintage"),
          repairResponse: .success(query: "atag:dragon")
        )
      ))
    await model.drainSearchForTesting()

    model.setSearchInputMode(.plainText)
    model.searchText = "cards tagged as dragons"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertNil(model.generatedSearchQuery)
    XCTAssertEqual(
      model.unsupportedSearchMessage,
      "“atag:dragon” is Scryfall syntax that Grimora does not support offline yet.")
    XCTAssertEqual(model.plainTextSearchErrorMessage, model.unsupportedSearchMessage)
  }

  func testPlainTextSearchRecordsSeparateHistoryAfterSuccessfulSearch() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let scryfallHistoryStore = isolatedSearchHistoryStore()
    let plainTextHistoryStore = GrimoraSearchHistoryStore(
      userDefaults: isolatedUserDefaults(),
      key: GrimoraSearchPreferences.plainTextSearchHistoryKey
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        searchHistoryStore: scryfallHistoryStore,
        plainTextSearchHistoryStore: plainTextHistoryStore,
        plainTextSearchTranspiler: TestPlainTextSearchTranspiler(response: .success(query: "name:forest"))
      ))
    await model.drainSearchForTesting()

    model.setSearchInputMode(.plainText)
    model.searchText = "show me forests"
    await model.submitSearch()
    await model.drainSearchForTesting()
    await model.drainSearchHistoryForTesting()

    XCTAssertEqual(model.searchHistory, [])
    XCTAssertEqual(scryfallHistoryStore.load(), [])
    XCTAssertEqual(model.plainTextSearchHistory, ["show me forests"])
    XCTAssertEqual(plainTextHistoryStore.load(), ["show me forests"])
  }

  func testPlainTextSearchClearRemovesPromptAndGeneratedQuery() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        plainTextSearchTranspiler: TestPlainTextSearchTranspiler(response: .success(query: "name:forest"))
      ))
    await model.drainSearchForTesting()

    model.setSearchInputMode(.plainText)
    model.searchText = "show me forests"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.generatedSearchQuery, "name:forest")

    model.clearSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.searchText, "")
    XCTAssertNil(model.generatedSearchQuery)
    XCTAssertNil(model.plainTextSearchErrorMessage)
  }

  func testPlainTextSearchIgnoresStaleTranslationAfterPromptChanges() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let transpiler = TestPlainTextSearchTranspiler(
      response: .success(query: "name:forest"),
      delayNanoseconds: 50_000_000
    )
    let model = GrimoraAppModel(
      environment: environment(database: database, plainTextSearchTranspiler: transpiler))
    await model.drainSearchForTesting()
    let initialResultIDs = model.cards.map(\.id)

    model.setSearchInputMode(.plainText)
    model.searchText = "show me forests"
    let submitTask = Task {
      await model.submitSearch()
    }
    try await Task.sleep(nanoseconds: 5_000_000)
    model.searchText = "show me beta"
    await submitTask.value
    await model.drainSearchForTesting()

    XCTAssertNil(model.generatedSearchQuery)
    XCTAssertFalse(model.isTranslatingSearch)
    XCTAssertEqual(model.cards.map(\.id), initialResultIDs)
  }

  func testSearchHistoryStorePersistsTrimsDedupesAndCapsRecentQueries() {
    let userDefaults = isolatedUserDefaults()
    let store = GrimoraSearchHistoryStore(userDefaults: userDefaults)

    var history: [String] = []
    for query in [" Forest ", "Beta", "forest", "  ", "Gamma", "Beta"] {
      history = store.historyByRecording(query, in: history)
    }

    XCTAssertEqual(history, ["Beta", "Gamma", "forest", "Forest"])

    for index in 0..<12 {
      history = store.historyByRecording("query-\(index)", in: history)
    }
    history = store.historyByRecording(" query-5 ", in: history)
    store.save(history)

    let reloadedStore = GrimoraSearchHistoryStore(userDefaults: userDefaults)
    XCTAssertEqual(
      reloadedStore.load(),
      ["query-5", "query-11", "query-10", "query-9", "query-8", "query-7", "query-6", "query-4", "query-3", "query-2"]
    )

    reloadedStore.clear()
    XCTAssertEqual(reloadedStore.load(), [])
  }

  func testDefaultSearchConfigurationLoadsFromUserDefaults() {
    let userDefaults = isolatedUserDefaults()
    userDefaults.set(" mage ", forKey: GrimoraSearchPreferences.defaultSearchTextKey)
    userDefaults.set(SortMode.artistName.rawValue, forKey: GrimoraSearchPreferences.defaultSearchSortModeKey)
    userDefaults.set(
      SearchSortDirection.descending.rawValue,
      forKey: GrimoraSearchPreferences.defaultSearchSortDirectionKey
    )

    let configuration = GrimoraSearchPreferences.configuration(userDefaults: userDefaults)

    XCTAssertEqual(configuration.text, " mage ")
    XCTAssertEqual(configuration.sortMode, .artistName)
    XCTAssertEqual(configuration.sortDirection, .descending)
  }

  func testModelRecordsOnlySuccessfulSettledUserSearchesInHistory() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let historyStore = isolatedSearchHistoryStore()
    let model = GrimoraAppModel(
      environment: environment(database: database, searchHistoryStore: historyStore))
    await model.drainSearchForTesting()

    model.searchText = " forest "
    await model.submitSearch()
    await model.drainSearchForTesting()
    await model.drainSearchHistoryForTesting()

    XCTAssertEqual(model.searchHistory, ["forest"])
    XCTAssertEqual(historyStore.load(), ["forest"])

    model.searchText = "cube:vintage"
    await model.submitSearch()
    await model.drainSearchForTesting()
    await model.drainSearchHistoryForTesting()

    XCTAssertEqual(model.searchHistory, ["forest"])

    model.clearSearch()
    model.applySearchPreferences(
      GrimoraDefaultSearchConfiguration(
        text: "mage",
        sortMode: .releaseDate,
        sortDirection: .ascending
      ))
    await model.drainSearchForTesting()
    await model.drainSearchHistoryForTesting()

    XCTAssertTrue(model.isDefaultSearchActive)
    XCTAssertEqual(model.searchHistory, ["forest"])
  }

  func testModelClearsSearchHistoryAndCancelsPendingHistoryRecord() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let historyStore = isolatedSearchHistoryStore()
    historyStore.save(["alpha"])
    let model = GrimoraAppModel(
      environment: environment(database: database, searchHistoryStore: historyStore))
    await model.drainSearchForTesting()

    XCTAssertEqual(model.searchHistory, ["alpha"])

    model.searchText = "forest"
    await model.submitSearch()
    await model.drainSearchForTesting()
    model.clearSearchHistory()
    await model.drainSearchHistoryForTesting()

    XCTAssertEqual(model.searchHistory, [])
    XCTAssertEqual(historyStore.load(), [])
  }

  func testSearchHistoryPreviewWarmerDecodesRecentCachedLocalPathsWithoutResolver() async throws {
    LocalCardImageLoader.shared.clearForTesting()
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: imageDirectory,
      withIntermediateDirectories: true
    )
    let alphaImage = imageDirectory.appendingPathComponent("alpha.png")
    let betaImage = imageDirectory.appendingPathComponent("beta.png")
    try modelTestPNGImageData().write(to: alphaImage, options: .atomic)
    try modelTestPNGImageData().write(to: betaImage, options: .atomic)
    try database.replaceAllCards([
      CardRecord(
        id: "alpha",
        oracleID: "alpha",
        name: "Alpha Card",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        normalImagePath: alphaImage.path
      ),
      CardRecord(
        id: "beta",
        oracleID: "beta",
        name: "Beta Card",
        releasedAt: "2024-01-02",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "2",
        collectorNumberNumber: 2,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        normalImagePath: betaImage.path
      )
    ])
    try markLibraryReady(database)
    let historyStore = isolatedSearchHistoryStore()
    historyStore.save(["alpha", "beta"])
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          historyWarmQueryLimit: 1,
          historyWarmResultLimit: 1,
          historyWarmDelayNanoseconds: 0
        ),
        searchHistoryStore: historyStore
      ))

    await model.drainSearchForTesting()
    await model.drainPreviewImageWarmerForTesting()

    XCTAssertNotNil(LocalCardImageLoader.shared.cachedImage(atPath: alphaImage.path))
    XCTAssertNil(LocalCardImageLoader.shared.cachedImage(atPath: betaImage.path))
    let calls = await resolver.recordedCalls()
    XCTAssertTrue(calls.isEmpty)
  }

  func testSearchHistoryPreviewWarmerSkipsMissingLocalPaths() async throws {
    LocalCardImageLoader.shared.clearForTesting()
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let missingImage = imageDirectory.appendingPathComponent("missing.png")
    try database.replaceAllCards([
      CardRecord(
        id: "missing",
        oracleID: "missing",
        name: "Missing Local Image",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        normalImagePath: missingImage.path,
        normalImageURL: "https://example.test/missing-normal.jpg"
      )
    ])
    try markLibraryReady(database)
    let historyStore = isolatedSearchHistoryStore()
    historyStore.save(["missing"])
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          historyWarmQueryLimit: 5,
          historyWarmResultLimit: 96,
          historyWarmDelayNanoseconds: 0
        ),
        searchHistoryStore: historyStore
      ))

    await model.drainSearchForTesting()
    await model.drainPreviewImageWarmerForTesting()

    XCTAssertNil(LocalCardImageLoader.shared.cachedImage(atPath: missingImage.path))
    let calls = await resolver.recordedCalls()
    XCTAssertTrue(calls.isEmpty)
  }

  func testRepeatedFirstPageSearchUsesCacheUntilSearchContextChanges() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.searchText = "forest"
    await model.submitSearch()
    XCTAssertTrue(model.isSearchingCards)
    await model.drainSearchForTesting()
    XCTAssertFalse(model.isSearchingCards)
    XCTAssertEqual(model.cards.map(\.id), ["forest"])

    try database.replaceAllCards([
      CardRecord(
        id: "replacement-forest",
        name: "Replacement Forest",
        releasedAt: "2025-01-01",
        setCode: "rpl",
        setName: "Replacement Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 0,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Forest replacement.",
        isRealCard: true
      )
    ])

    model.searchText = "forest"
    await model.submitSearch()
    XCTAssertFalse(model.isSearchingCards)
    await model.drainSearchForTesting()
    XCTAssertFalse(model.isSearchingCards)
    XCTAssertEqual(model.cards.map(\.id), ["forest"])

    model.toggleFilter(.realCards)
    await model.drainSearchForTesting()
    XCTAssertEqual(model.cards.map(\.id), ["replacement-forest"])
  }

  func testImportClearsCachedSearchResults() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try database.saveMetadataValue(
      "2026-04-01T09:09:59.477+00:00", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
    try database.saveMetadataValue(
      CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
    try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)
    let downloadURL = URL(string: "https://example.test/default.json")!
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let network = ModelTestNetworkClient(dataResponses: [
      BulkDataClient.bulkDataURL: manifestListJSON(downloadURL: downloadURL),
      downloadURL: setupCardsJSON(),
    ])
    let importer = LibraryImporter(
      database: database,
      imageResolver: ModelTestImageResolver(rootDirectory: imageDirectory)
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        importer: importer
      ))
    await model.drainSearchForTesting()

    model.searchText = "forest"
    await model.submitSearch()
    await model.drainSearchForTesting()
    XCTAssertEqual(model.cards.map(\.id), ["forest"])

    await model.checkForUpdates()
    await model.importAvailableUpdate()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.cards.map(\.id), ["setup-forest"])
    XCTAssertEqual(model.libraryActivity?.operation, .importCardDatabase)
    XCTAssertEqual(model.libraryActivity?.state, .succeeded)
    XCTAssertEqual(model.libraryActivity?.message, "Imported 1 cards. Images load as you browse.")
  }

  func testManualUpdateCheckDoesNotExposeImportWhenLibraryIsCurrent() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let downloadURL = URL(string: "https://example.test/default.json")!
    let network = ModelTestNetworkClient(dataResponses: [
      BulkDataClient.bulkDataURL: manifestListJSON(downloadURL: downloadURL)
    ])
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network
      ))
    await model.drainSearchForTesting()

    await model.checkForUpdates()

    XCTAssertNil(model.updateManifest)
    XCTAssertEqual(model.statusMessage, "Library is current.")
  }

  func testRefreshCardDatabasePreservesUserLists() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let list = try database.createCardList(named: "Favorites")
    let category = try database.createCardListCategory(inList: list.id, named: "Ramp")
    try database.appendCard("forest", toList: list.id, categoryID: category.id, quantity: 3)
    let downloadURL = URL(string: "https://example.test/default.json")!
    let network = ModelTestNetworkClient(dataResponses: [
      BulkDataClient.bulkDataURL: manifestListJSON(downloadURL: downloadURL),
      downloadURL: setupCardsJSON(),
    ])
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let importer = LibraryImporter(
      database: database,
      imageResolver: ModelTestImageResolver(rootDirectory: imageDirectory)
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        importer: importer,
        imageStore: ImageStore(rootDirectory: imageDirectory)
      ))
    await model.drainSearchForTesting()

    await model.refreshCardDatabase()
    await model.drainSearchForTesting()

    XCTAssertEqual(try database.cardCount(), 1)
    XCTAssertEqual(model.cards.map(\.id), ["setup-forest"])
    XCTAssertEqual(try database.cardLists().map(\.name), ["Favourites"])
    XCTAssertEqual(try database.cardListCategories(forListID: list.id).map(\.name), ["Ramp"])
    let entries = try database.cardListEntries(forListID: list.id)
    XCTAssertEqual(entries.map(\.cardID), ["forest"])
    XCTAssertEqual(entries.map(\.quantity), [3])
    XCTAssertNil(entries.first?.card)
    XCTAssertEqual(model.libraryActivity?.operation, .refreshCardDatabase)
    XCTAssertEqual(model.libraryActivity?.state, .succeeded)
    XCTAssertEqual(model.libraryActivity?.message, "Refreshed 1 cards. Images load as you browse.")
  }

  func testRefreshCardValuesShowsDataLoadActivityWhileRunning() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let network = SuspendedModelNetworkClient(
      dataResponses: valueHistoryNetworkResponses(cardID: "forest"),
      suspendedURL: MTGJSONPriceHistoryClient.metaURL
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        priceHistoryEnabled: true
      ))
    await model.drainSearchForTesting()

    let refreshTask = Task {
      await model.refreshCardValues()
    }
    await network.waitForRequestCount(1)

    XCTAssertEqual(model.statusMessage, "Checking MTGJSON value history...")
    XCTAssertEqual(model.libraryActivity?.operation, .refreshCardValues)
    XCTAssertEqual(model.libraryActivity?.title, "Refreshing Card Values")
    XCTAssertEqual(model.libraryActivity?.message, "Checking MTGJSON value history...")
    XCTAssertEqual(model.libraryActivity?.state, .running)

    await network.release()
    await refreshTask.value

    XCTAssertEqual(model.libraryActivity?.state, .succeeded)
    XCTAssertEqual(model.libraryActivity?.message, "Indexed 1 value points.")
  }

  func testPriceHistoryProgressUpdatesStatusAndDataLoadActivity() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let model = GrimoraAppModel(environment: environment(database: database))
    let activityID = model.beginLibraryActivity(
      operation: .refreshCardValues,
      title: "Refreshing Card Values",
      message: "Checking MTGJSON value history..."
    )

    model.handlePriceHistoryProgress(
      .downloadingPriceHistoryDataProgress(
        file: .cardIdentifiers,
        completedBytes: 25,
        totalBytes: 100
      )
    )

    var identifierStep = try activityStep("download-price-identifiers", in: model)
    XCTAssertEqual(identifierStep.state, .running)
    XCTAssertEqual(identifierStep.progress ?? -1, 0.25, accuracy: 0.001)
    XCTAssertEqual(model.libraryActivity?.id, activityID)

    model.handlePriceHistoryProgress(
      .downloadingPriceHistoryDataProgress(
        file: .prices,
        completedBytes: 60,
        totalBytes: 120
      )
    )

    identifierStep = try activityStep("download-price-identifiers", in: model)
    let pricesStep = try activityStep("download-prices", in: model)
    XCTAssertEqual(identifierStep.state, .succeeded)
    XCTAssertEqual(pricesStep.state, .running)
    XCTAssertEqual(pricesStep.progress ?? -1, 0.5, accuracy: 0.001)

    model.handlePriceHistoryProgress(.buildingPriceIDMap)

    let indexStep = try activityStep("index-price-history", in: model)
    XCTAssertEqual(model.statusMessage, "Mapping cards to current prices...")
    XCTAssertEqual(model.libraryActivity?.id, activityID)
    XCTAssertEqual(model.libraryActivity?.message, "Mapping cards to current prices...")
    XCTAssertEqual(model.libraryActivity?.state, .running)
    XCTAssertEqual(indexStep.state, .running)
    XCTAssertNil(indexStep.progress)
    XCTAssertEqual(indexStep.detail, "Mapping cards")

    model.handlePriceHistoryProgress(.importingPriceHistory)

    let importingStep = try activityStep("index-price-history", in: model)
    XCTAssertEqual(model.statusMessage, "Importing current TCGplayer prices...")
    XCTAssertEqual(model.libraryActivity?.id, activityID)
    XCTAssertEqual(model.libraryActivity?.message, "Importing current TCGplayer prices...")
    XCTAssertEqual(model.libraryActivity?.state, .running)
    XCTAssertEqual(importingStep.state, .running)
    XCTAssertNil(importingStep.progress)
    XCTAssertEqual(importingStep.detail, "Importing prices")
  }

  func testImportProgressUpdatesDataLoadActivitySteps() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let model = GrimoraAppModel(environment: environment(database: database))
    _ = model.beginLibraryActivity(
      operation: .setupLibrary,
      title: "Setting Up Library",
      message: "Checking Scryfall card database..."
    )
    let manifest = BulkDataManifest(
      id: "bulk-id",
      type: "default_cards",
      updatedAt: "2026-04-25T09:09:59.477+00:00",
      name: "Default Cards",
      size: 100,
      downloadURI: URL(string: "https://example.test/default.json")!
    )

    model.handleImportProgress(.downloadingBulkData, manifest: manifest)
    model.handleImportProgress(
      .downloadingBulkDataProgress(completedBytes: 25, totalBytes: 100),
      manifest: manifest
    )

    var cardDownloadStep = try activityStep("download-card-data", in: model)
    XCTAssertEqual(cardDownloadStep.state, .running)
    XCTAssertEqual(cardDownloadStep.progress ?? -1, 0.25, accuracy: 0.001)
    XCTAssertTrue(model.statusMessage.hasPrefix("Downloading Default Cards ("))

    model.handleImportProgress(.decodingCardData, manifest: manifest)

    cardDownloadStep = try activityStep("download-card-data", in: model)
    var buildStep = try activityStep("build-card-library", in: model)
    XCTAssertEqual(cardDownloadStep.state, .succeeded)
    XCTAssertEqual(buildStep.state, .running)
    XCTAssertNil(buildStep.progress)
    XCTAssertEqual(buildStep.detail, "Reading card data")

    model.handleImportProgress(.storingSearchIndex(cardCount: 42), manifest: manifest)

    buildStep = try activityStep("build-card-library", in: model)
    XCTAssertEqual(buildStep.state, .running)
    XCTAssertNil(buildStep.progress)
    XCTAssertEqual(buildStep.detail, "Writing 42 cards")
    XCTAssertEqual(model.statusMessage, "Writing offline search index for 42 cards...")

    model.handleImportProgress(.cardDataReady(cardCount: 42), manifest: manifest)

    buildStep = try activityStep("build-card-library", in: model)
    XCTAssertEqual(buildStep.state, .succeeded)
    XCTAssertEqual(buildStep.progress, 1)
  }

  func testRefreshCardValuesImportsPricingOnlyAndPreservesCurrentState() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let list = try database.createCardList(named: "Favorites")
    try database.appendCard("forest", toList: list.id, quantity: 2)
    let network = ModelTestNetworkClient(dataResponses: valueHistoryNetworkResponses(cardID: "forest"))
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        priceHistoryEnabled: true
      ))
    await model.drainSearchForTesting()

    model.searchText = "forest"
    await model.submitSearch()
    await model.drainSearchForTesting()
    let selectedCard = try XCTUnwrap(model.cards.first)
    model.selectCard(selectedCard)

    await model.refreshCardValues()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.statusMessage, "Indexed 1 value points.")
    XCTAssertEqual(model.libraryActivity?.operation, .refreshCardValues)
    XCTAssertEqual(model.libraryActivity?.title, "Refreshing Card Values")
    XCTAssertEqual(model.libraryActivity?.message, "Indexed 1 value points.")
    XCTAssertEqual(model.libraryActivity?.state, .succeeded)
    XCTAssertEqual(model.cards.map(\.id), ["forest"])
    XCTAssertEqual(try database.cardCount(), uiRecords().count)
    XCTAssertEqual(try database.cardLists().map(\.name), ["Favourites"])
    XCTAssertEqual(try database.cardListEntries(forListID: list.id).map(\.cardID), ["forest"])
    XCTAssertEqual(model.selectedCard?.id, "forest")
    XCTAssertEqual(model.selectedCardValueGuide?.entries.first?.currentPrice, 3.25)
    XCTAssertEqual(
      try database.metadataValue(forKey: MetadataKey.defaultCardsUpdatedAt.rawValue),
      "2026-04-25T09:09:59.477+00:00"
    )
    let requests = await network.requests()
    XCTAssertEqual(requests.map(\.url), [
      MTGJSONPriceHistoryClient.metaURL,
      MTGJSONPriceHistoryClient.allPrintingsURL,
      MTGJSONPriceHistoryClient.allPricesTodayURL,
    ])
    XCTAssertEqual(requests.map(\.purpose), [
      .priceHistoryDownload,
      .priceHistoryDownload,
      .priceHistoryDownload,
    ])
    XCTAssertFalse(requests.contains { $0.purpose == .bulkDownload })
  }

  func testBackgroundValueHistoryProgressAndCompletionReloadSelectedGuide() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let network = SuspendedModelNetworkClient(
      dataResponses: valueHistoryNetworkResponses(
        cardID: "forest",
        price: 3.25,
        fullHistoryPrice: 4.00
      ),
      suspendedURL: MTGJSONPriceHistoryClient.allPricesURL
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        priceHistoryEnabled: true
      ))
    await model.drainSearchForTesting()
    let selectedCard = try XCTUnwrap(model.cards.first { $0.id == "forest" })
    model.selectCard(selectedCard)

    await model.refreshCardValues()
    XCTAssertEqual(model.selectedCardValueGuide?.entries.first?.currentPrice, 3.25)

    await network.waitForRequestCount(4)
    XCTAssertEqual(model.valueHistoryBackgroundActivity?.state, .running)
    XCTAssertEqual(model.valueHistoryBackgroundActivity?.title, "90-day history updating")

    await network.release()
    await model.valueHistoryBackgroundTask?.value
    for _ in 0..<50 where model.selectedCardValueGuide?.entries.first?.currentPrice != 4.00 {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertNil(model.valueHistoryBackgroundActivity)
    XCTAssertEqual(model.selectedCardValueGuide?.entries.first?.currentPrice, 4.00)
    XCTAssertEqual(model.selectedCardValueGuide?.entries.first?.history.count, 2)
  }

  func testRefreshCardValuesSkipsWhenValueHistoryIsCurrent() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    try await seedValueHistory(in: database, cardID: "forest", uuid: "uuid-forest")
    let network = ModelTestNetworkClient(dataResponses: [
      MTGJSONPriceHistoryClient.metaURL: modelValueHistoryMetaJSON()
    ])
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        priceHistoryEnabled: true
      ))
    await model.drainSearchForTesting()

    await model.refreshCardValues()

    XCTAssertEqual(model.statusMessage, "Value history is current.")
    XCTAssertEqual(model.libraryActivity?.message, "Value history is current.")
    XCTAssertEqual(model.libraryActivity?.state, .succeeded)
    XCTAssertEqual(try database.valueSummaryCount(), 1)
    let requests = await network.requests()
    XCTAssertEqual(requests.map(\.url), [MTGJSONPriceHistoryClient.metaURL])
    XCTAssertEqual(requests.map(\.purpose), [.priceHistoryDownload])
  }

  func testRefreshCardValuesFailureDoesNotClearSearchOrLists() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let list = try database.createCardList(named: "Favorites")
    try database.appendCard("forest", toList: list.id, quantity: 2)
    let network = ModelTestNetworkClient(dataResponses: [
      MTGJSONPriceHistoryClient.metaURL: Data()
    ])
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        priceHistoryEnabled: true
      ))
    await model.drainSearchForTesting()

    model.searchText = "forest"
    await model.submitSearch()
    await model.drainSearchForTesting()
    await model.refreshCardValues()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.statusMessage, "Value history could not be updated; card search is ready.")
    XCTAssertEqual(model.libraryActivity?.message, "Value history could not be updated; card search is ready.")
    XCTAssertEqual(model.libraryActivity?.state, .failed)
    XCTAssertTrue(model.hasLibrary)
    XCTAssertEqual(model.cards.map(\.id), ["forest"])
    XCTAssertEqual(try database.cardLists().map(\.name), ["Favourites"])
    XCTAssertEqual(try database.cardListEntries(forListID: list.id).map(\.cardID), ["forest"])
    let requests = await network.requests()
    XCTAssertEqual(requests.map(\.purpose), [.priceHistoryDownload])
    XCTAssertFalse(requests.contains { $0.purpose == .bulkDownload })
  }

  func testRefreshCardValuesRequiresLocalLibrary() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let network = ModelTestNetworkClient(dataResponses: valueHistoryNetworkResponses(cardID: "forest"))
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        priceHistoryEnabled: true
      ))

    await model.refreshCardValues()

    XCTAssertEqual(model.statusMessage, "Set up the card database before refreshing values.")
    XCTAssertNil(model.libraryActivity)
    XCTAssertFalse(model.hasLibrary)
    let requests = await network.requests()
    XCTAssertTrue(requests.isEmpty)
  }

  func testLibraryActivityAutoDismissDoesNotClearNewerActivity() async throws {
    let model = GrimoraAppModel(environment: environment(database: try CardDatabase(storage: .inMemory)))
    let oldID = model.beginLibraryActivity(
      operation: .refreshCardValues,
      title: "Refreshing Card Values",
      message: "Working"
    )
    model.finishLibraryActivity(id: oldID, message: "Done", state: .succeeded)
    let newerID = UUID()
    model.libraryActivity = GrimoraLibraryActivity(
      id: newerID,
      title: "Importing Card Database",
      message: "Still working",
      state: .running
    )

    try? await Task.sleep(
      nanoseconds: GrimoraAppModel.libraryActivityCompletionDelayNanoseconds + 150_000_000
    )

    XCTAssertEqual(model.libraryActivity?.id, newerID)
    XCTAssertEqual(model.libraryActivity?.message, "Still working")
  }

  func testLibraryActivitySuccessAutoDismissClearsDataLoad() async throws {
    let model = GrimoraAppModel(environment: environment(database: try CardDatabase(storage: .inMemory)))
    let activityID = model.beginLibraryActivity(
      operation: .refreshCardValues,
      title: "Refreshing Card Values",
      message: "Working"
    )

    model.finishLibraryActivity(id: activityID, message: "Done", state: .succeeded)
    try? await Task.sleep(
      nanoseconds: GrimoraAppModel.libraryActivityCompletionDelayNanoseconds + 150_000_000
    )

    XCTAssertNil(model.libraryActivity)
  }

  func testLibraryActivityFailureStaysVisibleUntilDismissed() async throws {
    let model = GrimoraAppModel(environment: environment(database: try CardDatabase(storage: .inMemory)))
    let activityID = model.beginLibraryActivity(
      operation: .refreshCardValues,
      title: "Refreshing Card Values",
      message: "Working"
    )

    model.finishLibraryActivity(id: activityID, message: "Failed", state: .failed)
    try? await Task.sleep(
      nanoseconds: GrimoraAppModel.libraryActivityCompletionDelayNanoseconds + 150_000_000
    )

    XCTAssertEqual(model.libraryActivity?.id, activityID)
    XCTAssertEqual(model.libraryActivity?.message, "Failed")

    model.dismissLibraryActivity()

    XCTAssertNil(model.libraryActivity)
  }

  func testDeleteCachedImagesClearsImagePathsAndPreservesLists() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let cachedImage = imageDirectory.appendingPathComponent("forest/front/normal.jpg")
    try FileManager.default.createDirectory(
      at: cachedImage.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try modelTestImageData().write(to: cachedImage, options: .atomic)
    var records = uiRecords()
    records[0].normalImagePath = cachedImage.path
    try database.replaceAllCards(records)
    try markLibraryReady(database)
    let list = try database.createCardList(named: "Favorites")
    try database.appendCard("forest", toList: list.id, quantity: 2)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageStore: ImageStore(rootDirectory: imageDirectory)
      ))
    await model.drainSearchForTesting()

    await model.deleteCachedImages()
    await model.drainSearchForTesting()

    XCTAssertFalse(FileManager.default.fileExists(atPath: cachedImage.path))
    XCTAssertEqual(try database.cardCount(), records.count)
    XCTAssertEqual(try database.cardLists().map(\.name), ["Favourites"])
    XCTAssertEqual(try database.cardListEntries(forListID: list.id).map(\.cardID), ["forest"])
    let cards = try cards(in: database, matching: "forest")
    XCTAssertNil(cards.first?.normalImagePath)
    XCTAssertEqual(try database.metadataValue(forKey: MetadataKey.requiredImagesCached.rawValue), "false")
  }

  func testDeleteAndRefreshCardDatabaseDeletesImagesAndPreservesLists() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let list = try database.createCardList(named: "Favorites")
    try database.appendCard("forest", toList: list.id, quantity: 2)
    let downloadURL = URL(string: "https://example.test/default.json")!
    let network = ModelTestNetworkClient(dataResponses: [
      BulkDataClient.bulkDataURL: manifestListJSON(downloadURL: downloadURL),
      downloadURL: setupCardsJSON(),
    ])
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let cachedImage = imageDirectory.appendingPathComponent("forest/front/normal.jpg")
    try FileManager.default.createDirectory(
      at: cachedImage.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try modelTestImageData().write(to: cachedImage, options: .atomic)
    let importer = LibraryImporter(
      database: database,
      imageResolver: ModelTestImageResolver(rootDirectory: imageDirectory)
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        importer: importer,
        imageStore: ImageStore(rootDirectory: imageDirectory)
      ))
    await model.drainSearchForTesting()

    await model.deleteAndRefreshCardDatabase()
    await model.drainSearchForTesting()

    XCTAssertFalse(FileManager.default.fileExists(atPath: cachedImage.path))
    XCTAssertEqual(try database.cardCount(), 1)
    XCTAssertEqual(model.cards.map(\.id), ["setup-forest"])
    XCTAssertEqual(try database.cardLists().map(\.name), ["Favourites"])
    let entries = try database.cardListEntries(forListID: list.id)
    XCTAssertEqual(entries.map(\.cardID), ["forest"])
    XCTAssertEqual(entries.map(\.quantity), [2])
    XCTAssertNil(entries.first?.card)
    let cards = try cards(in: database, matching: "setup")
    XCTAssertNil(cards.first?.smallImagePath)
    XCTAssertNil(cards.first?.normalImagePath)
    XCTAssertNil(cards.first?.largeImagePath)
    XCTAssertEqual(model.libraryActivity?.operation, .deleteAndRefreshDatabase)
    XCTAssertEqual(model.libraryActivity?.title, "Deleting and Refreshing Database")
    XCTAssertEqual(model.libraryActivity?.state, .succeeded)
  }

  func testAutomaticUpdateCheckIsSkippedWhenAnyLocalCardDataExists() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([uiRecords()[0]])
    let downloadURL = URL(string: "https://example.test/default.json")!
    let network = ModelTestNetworkClient(dataResponses: [
      BulkDataClient.bulkDataURL: manifestListJSON(downloadURL: downloadURL)
    ])

    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        autoUpdateChecksEnabled: true
      ))
    try await Task.sleep(nanoseconds: 50_000_000)

    let requests = await network.requests()
    XCTAssertFalse(model.hasLibrary)
    XCTAssertTrue(requests.isEmpty)
  }

  func testAutomaticUpdateCheckRunsWhenNoLocalCardDataExists() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let downloadURL = URL(string: "https://example.test/default.json")!
    let network = ModelTestNetworkClient(dataResponses: [
      BulkDataClient.bulkDataURL: manifestListJSON(downloadURL: downloadURL)
    ])

    _ = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        autoUpdateChecksEnabled: true
      ))
    try await Task.sleep(nanoseconds: 50_000_000)

    let requests = await network.requests()
    XCTAssertEqual(requests.map(\.purpose), [.manifestCheck])
  }

  func testInitialDefaultSearchConfigurationSeedsFirstSearch() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)

    let model = GrimoraAppModel(
      environment: environment(database: database),
      initialDefaultSearchConfiguration: GrimoraDefaultSearchConfiguration(
        text: " t:creature ",
        sortMode: .releaseDate,
        sortDirection: .ascending
      ))
    await model.drainSearchForTesting()

    XCTAssertTrue(model.isDefaultSearchActive)
    XCTAssertEqual(model.activeDefaultSearchText, "t:creature")
    XCTAssertEqual(model.sortMode, .releaseDate)
    XCTAssertEqual(model.sortDirection, .ascending)
    XCTAssertEqual(model.cards.map(\.id), ["beta", "forest"])
  }

  func testAlwaysIncludedSearchTextIsPrependedToDirectAndDefaultSearches() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([
      CardRecord(
        id: "commander-creature",
        name: "Commander Creature",
        releasedAt: "2020-01-01",
        setCode: "abc",
        setName: "Alpha Set",
        setType: "expansion",
        collectorNumber: "1",
        rarity: "rare",
        colorSortKey: 0,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "",
        legalities: ["commander": "legal"],
        isRealCard: true
      ),
      CardRecord(
        id: "modern-creature",
        name: "Modern Creature",
        releasedAt: "2020-01-02",
        setCode: "abc",
        setName: "Alpha Set",
        setType: "expansion",
        collectorNumber: "2",
        rarity: "rare",
        colorSortKey: 0,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "",
        legalities: ["modern": "legal"],
        isRealCard: true
      )
    ])
    try markLibraryReady(database)

    let model = GrimoraAppModel(
      environment: environment(database: database),
      initialDefaultSearchConfiguration: GrimoraDefaultSearchConfiguration(
        text: "",
        alwaysIncludedText: " legal:commander "
      )
    )
    await model.drainSearchForTesting()
    XCTAssertEqual(model.cards.map(\.id), ["commander-creature"])

    model.searchText = "t:creature"
    await model.drainSearchForTesting()
    XCTAssertEqual(model.cards.map(\.id), ["commander-creature"])
  }

  func testAlwaysIncludedSearchTextIsPrependedToPlainTextGeneratedQueries() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([
      CardRecord(
        id: "commander-creature",
        name: "Commander Creature",
        releasedAt: "2020-01-01",
        setCode: "abc",
        setName: "Alpha Set",
        setType: "expansion",
        collectorNumber: "1",
        rarity: "rare",
        colorSortKey: 0,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "",
        legalities: ["commander": "legal"],
        isRealCard: true
      ),
      CardRecord(
        id: "commander-artifact",
        name: "Commander Artifact",
        releasedAt: "2020-01-02",
        setCode: "abc",
        setName: "Alpha Set",
        setType: "expansion",
        collectorNumber: "2",
        rarity: "rare",
        colorSortKey: 6,
        layout: "normal",
        typeLine: "Artifact",
        oracleText: "",
        legalities: ["commander": "legal"],
        isRealCard: true
      )
    ])
    try markLibraryReady(database)

    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        plainTextSearchTranspiler: TestPlainTextSearchTranspiler(response: .success(query: "t:creature"))
      ),
      initialDefaultSearchConfiguration: GrimoraDefaultSearchConfiguration(
        alwaysIncludedText: "legal:commander"
      ),
      initialSearchInputMode: .plainText
    )
    await model.drainSearchForTesting()

    model.searchText = "commander creatures"
    await model.submitSearch()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.generatedSearchQuery, "t:creature")
    XCTAssertEqual(model.cards.map(\.id), ["commander-creature"])
  }

  func testReturningToInitialDefaultSearchUsesCachedFirstPageResults() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(
      environment: environment(database: database),
      initialDefaultSearchConfiguration: GrimoraDefaultSearchConfiguration(
        text: "forest",
        sortMode: .name,
        sortDirection: .ascending
      ))
    await model.drainSearchForTesting()
    XCTAssertEqual(model.cards.map(\.id), ["forest"])

    try database.replaceAllCards([
      CardRecord(
        id: "replacement-forest",
        name: "Replacement Forest",
        releasedAt: "2025-01-01",
        setCode: "rpl",
        setName: "Replacement Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 0,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Forest replacement.",
        isRealCard: true
      )
    ])

    model.searchText = "replacement"
    await model.submitSearch()
    await model.drainSearchForTesting()
    XCTAssertFalse(model.isDefaultSearchActive)
    XCTAssertEqual(model.cards.map(\.id), ["replacement-forest"])

    model.clearSearch()
    XCTAssertFalse(model.isSearchingCards)
    await model.drainSearchForTesting()

    XCTAssertTrue(model.isDefaultSearchActive)
    XCTAssertEqual(model.cards.map(\.id), ["forest"])
  }

  func testDefaultSearchAppliesWhenSearchTextIsEmpty() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.applySearchPreferences(
      GrimoraDefaultSearchConfiguration(
        text: " mage ",
        sortMode: .releaseDate,
        sortDirection: .ascending
      ))
    await model.drainSearchForTesting()

    XCTAssertTrue(model.isDefaultSearchActive)
    XCTAssertEqual(model.activeDefaultSearchText, "mage")
    XCTAssertEqual(model.cards.map(\.id), ["beta"])

    model.searchText = "forest"
    await model.submitSearch()
    await model.drainSearchForTesting()
    XCTAssertFalse(model.isDefaultSearchActive)
    XCTAssertEqual(model.cards.map(\.id), ["forest"])

    model.clearSearch()
    await model.drainSearchForTesting()
    XCTAssertTrue(model.isDefaultSearchActive)
    XCTAssertEqual(model.cards.map(\.id), ["beta"])

    model.searchText = "   "
    await model.drainSearchForTesting()
    XCTAssertTrue(model.isDefaultSearchActive)
    XCTAssertEqual(model.cards.map(\.id), ["beta"])
  }

  func testDefaultSearchSortSeedsCurrentSortAndCanBeAdjustedForCurrentView() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.applySearchPreferences(
      GrimoraDefaultSearchConfiguration(
        text: "t:creature",
        sortMode: .releaseDate,
        sortDirection: .ascending
      ))
    await model.drainSearchForTesting()

    XCTAssertTrue(model.isDefaultSearchActive)
    XCTAssertEqual(model.sortMode, .releaseDate)
    XCTAssertEqual(model.sortDirection, .ascending)
    XCTAssertEqual(model.cards.map(\.id), ["beta", "forest"])

    model.sortDirection = .descending
    await model.drainSearchForTesting()
    XCTAssertEqual(model.cards.map(\.id), ["forest", "beta"])
    XCTAssertEqual(model.defaultSearchConfiguration.sortMode, .releaseDate)
    XCTAssertEqual(model.defaultSearchConfiguration.sortDirection, .ascending)

    model.sortMode = .artistName
    model.sortDirection = .ascending
    await model.drainSearchForTesting()
    XCTAssertTrue(model.isDefaultSearchActive)
    XCTAssertEqual(model.cards.map(\.id), ["beta", "forest"])

    model.searchText = "t:creature"
    await model.submitSearch()
    await model.drainSearchForTesting()
    XCTAssertFalse(model.isDefaultSearchActive)
    XCTAssertEqual(model.cards.map(\.id), ["beta", "forest"])

    model.applySearchPreferences(
      GrimoraDefaultSearchConfiguration(
        text: "t:creature",
        sortMode: .releaseDate,
        sortDirection: .descending
      ))
    await model.drainSearchForTesting()
    XCTAssertEqual(model.sortMode, .artistName)
    XCTAssertEqual(model.sortDirection, .ascending)
    XCTAssertEqual(model.cards.map(\.id), ["beta", "forest"])

    model.clearSearch()
    await model.drainSearchForTesting()
    XCTAssertTrue(model.isDefaultSearchActive)
    XCTAssertEqual(model.cards.map(\.id), ["beta", "forest"])
  }

  func testUnsupportedDefaultSearchShowsUnsupportedState() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.applySearchPreferences(
      GrimoraDefaultSearchConfiguration(
        text: "cube:vintage",
        sortMode: .releaseDate,
        sortDirection: .ascending
      ))
    await model.drainSearchForTesting()

    XCTAssertTrue(model.isDefaultSearchActive)
    XCTAssertTrue(model.cards.isEmpty)
    XCTAssertEqual(model.searchResultTotal, 0)
    XCTAssertEqual(
      model.unsupportedSearchMessage,
      "“cube:vintage” is Scryfall syntax that Grimora does not support offline yet.")
  }

  func testInitialSetupImportsCardDataWithoutImageDownloads() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let downloadURL = URL(string: "https://example.test/default.json")!
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let network = ModelTestNetworkClient(dataResponses: [
      BulkDataClient.bulkDataURL: manifestListJSON(downloadURL: downloadURL),
      downloadURL: setupCardsJSON(),
    ])
    let importer = LibraryImporter(
      database: database,
      imageResolver: ModelTestImageResolver(rootDirectory: imageDirectory)
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        importer: importer
      ))

    XCTAssertEqual(model.libraryState, .missing)
    XCTAssertFalse(model.hasLibrary)

    await model.startInitialSetup()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.libraryState, .ready)
    XCTAssertTrue(model.hasLibrary)
    XCTAssertEqual(model.cards.map(\.name), ["Setup Forest"])
    XCTAssertTrue(try database.isLibraryReady())

    let storedCards = try cards(in: database, matching: "setup")
    XCTAssertNil(storedCards.first?.smallImagePath)
    XCTAssertNil(storedCards.first?.normalImagePath)
    XCTAssertNil(storedCards.first?.largeImagePath)
    XCTAssertEqual(model.statusMessage, "Imported 1 cards. Images load as you browse.")
    XCTAssertEqual(model.libraryActivity?.operation, .setupLibrary)
    XCTAssertEqual(model.libraryActivity?.state, .succeeded)
  }

  func testInitialSetupDoesNotRequireImageDownloads() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let downloadURL = URL(string: "https://example.test/default.json")!
    let failedImageURL = URL(string: "https://example.test/setup-small.jpg")!
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let network = ModelTestNetworkClient(dataResponses: [
      BulkDataClient.bulkDataURL: manifestListJSON(downloadURL: downloadURL),
      downloadURL: setupCardsJSON(),
    ])
    let importer = LibraryImporter(
      database: database,
      imageResolver: ModelTestImageResolver(
        rootDirectory: imageDirectory, failedURLs: [failedImageURL])
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        importer: importer
      ))

    await model.startInitialSetup()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.libraryState, .ready)
    XCTAssertTrue(model.hasLibrary)
    XCTAssertEqual(model.cards.map(\.name), ["Setup Forest"])
    XCTAssertEqual(try database.cardCount(), 1)

    let storedCards = try cards(in: database, matching: "setup")
    XCTAssertNil(storedCards.first?.smallImagePath)
    XCTAssertNil(storedCards.first?.normalImagePath)
    XCTAssertNil(storedCards.first?.largeImagePath)
  }

  func testRequiredSyncedDatabaseUpdateShowsDataLoadActivity() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let downloadURL = URL(string: "https://example.test/synced-default.json")!
    let requiredIdentity = LibraryIdentity(
      defaultCardsUpdatedAt: "2026-05-01T00:00:00.000+00:00",
      defaultCardsDownloadURI: downloadURL,
      defaultCardsName: "Synced Default Cards",
      defaultCardsSize: 123
    )
    let coordinator = CloudSyncCoordinator(
      database: database,
      transport: MemoryCloudSyncTransport(
        state: CloudRemoteState(requiredLibraryIdentity: requiredIdentity)
      )
    )
    let network = ModelTestNetworkClient(dataResponses: [
      downloadURL: setupCardsJSON()
    ])
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        network: network,
        cloudSyncCoordinator: coordinator
      ))

    model.cloudSyncMode = .enabled
    await model.startCloudSync()
    await model.importRequiredCloudDatabaseUpdate()
    await model.drainSearchForTesting()

    XCTAssertEqual(model.libraryActivity?.operation, .updateSyncedDatabase)
    XCTAssertEqual(model.libraryActivity?.title, "Updating Synced Database")
    XCTAssertEqual(model.libraryActivity?.state, .succeeded)
    XCTAssertEqual(model.statusMessage, "iCloud sync is ready.")
    XCTAssertTrue(model.hasLibrary)
    XCTAssertEqual(try database.cardCount(), 1)
  }

  func testAllPrintingsToggleExpandsDuplicateOracleResults() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([
      CardRecord(
        id: "krenko-old",
        oracleID: "krenko",
        name: "Krenko, Mob Boss",
        language: "en",
        releasedAt: "2020-01-01",
        setCode: "old",
        setName: "Old Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 3,
        layout: "normal",
        typeLine: "Legendary Creature",
        oracleText: "Create Goblins.",
        isRealCard: true
      ),
      CardRecord(
        id: "krenko-new",
        oracleID: "krenko",
        name: "Krenko, Mob Boss",
        language: "en",
        releasedAt: "2024-01-01",
        setCode: "new",
        setName: "New Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 3,
        layout: "normal",
        typeLine: "Legendary Creature",
        oracleText: "Create Goblins.",
        isRealCard: true
      ),
    ])
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.searchText = "krenko"
    await model.submitSearch()
    await model.drainSearchForTesting()
    XCTAssertEqual(model.cards.map(\.id), ["krenko-new"])

    model.searchText = "krenko unique:prints"
    await model.submitSearch()
    await model.drainSearchForTesting()
    XCTAssertEqual(Set(model.cards.map(\.id)), Set(["krenko-new", "krenko-old"]))
    XCTAssertEqual(model.printingDisplayMode, .preferred)

    model.searchText = "krenko"
    model.printingDisplayMode = .all
    await model.submitSearch()
    await model.drainSearchForTesting()
    XCTAssertEqual(Set(model.cards.map(\.id)), Set(["krenko-new", "krenko-old"]))
  }

  func testLoadPrintingsPublishesSameOraclePrintings() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let selected = CardRecord(
      id: "shared-new",
      oracleID: "shared-oracle",
      name: "Shared Mage",
      language: "en",
      releasedAt: "2024-01-01",
      setCode: "new",
      setName: "New Set",
      setType: "expansion",
      collectorNumber: "1",
      collectorNumberNumber: 1,
      rarity: "rare",
      rarityRank: 2,
      colorSortKey: 1,
      layout: "normal",
      typeLine: "Creature",
      oracleText: "Draw.",
      isRealCard: true
    )
    try database.replaceAllCards([
      CardRecord(
        id: "shared-old",
        oracleID: "shared-oracle",
        name: "Shared Mage",
        language: "en",
        releasedAt: "2020-01-01",
        setCode: "old",
        setName: "Old Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 1,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Draw.",
        isRealCard: true
      ),
      selected,
      CardRecord(
        id: "other",
        oracleID: "other-oracle",
        name: "Other Mage",
        language: "en",
        releasedAt: "2025-01-01",
        setCode: "oth",
        setName: "Other Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 1,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Draw.",
        isRealCard: true
      )
    ])
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.selectedCard = selected
    await model.loadPrintings(for: selected)

    XCTAssertEqual(model.selectedCardPrintings.map(\.id), ["shared-new", "shared-old"])
    let olderPrinting = try XCTUnwrap(model.selectedCardPrintings.first { $0.id == "shared-old" })

    model.selectedCard = olderPrinting

    XCTAssertEqual(model.selectedCardPrintings.map(\.id), ["shared-new", "shared-old"])
    await model.loadPrintings(for: olderPrinting)
    XCTAssertEqual(model.selectedCardPrintings.map(\.id), ["shared-new", "shared-old"])
  }

  func testPrintingThumbnailAndPreviewImageCachingPatchSelectedPrintings() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let selected = CardRecord(
      id: "shared-new",
      oracleID: "shared-oracle",
      name: "Shared Mage",
      language: "en",
      releasedAt: "2024-01-01",
      setCode: "new",
      setName: "New Set",
      setType: "expansion",
      collectorNumber: "1",
      collectorNumberNumber: 1,
      rarity: "rare",
      rarityRank: 2,
      colorSortKey: 1,
      layout: "normal",
      typeLine: "Creature",
      oracleText: "Draw.",
      isRealCard: true
    )
    try database.replaceAllCards([
      selected,
      CardRecord(
        id: "shared-old",
        oracleID: "shared-oracle",
        name: "Shared Mage",
        language: "en",
        releasedAt: "2020-01-01",
        setCode: "old",
        setName: "Old Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 1,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Draw.",
        isRealCard: true,
        smallImageURL: "https://example.test/shared-old-small.jpg",
        normalImageURL: "https://example.test/shared-old-normal.jpg",
        largeImageURL: "https://example.test/shared-old-large.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = ModelTestImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    model.selectedCard = selected
    await model.loadPrintings(for: selected)
    let olderPrinting = try XCTUnwrap(model.selectedCardPrintings.first { $0.id == "shared-old" })

    await model.cachePrintingThumbnailImage(for: olderPrinting)
    await model.drainImageDownloadsForTesting()

    let thumbnailPrinting = try XCTUnwrap(
      model.selectedCardPrintings.first { $0.id == "shared-old" })
    XCTAssertNotNil(thumbnailPrinting.smallImagePath)
    XCTAssertNil(thumbnailPrinting.normalImagePath)
    XCTAssertNil(thumbnailPrinting.largeImagePath)
    XCTAssertEqual(thumbnailPrinting.displayImagePath, thumbnailPrinting.smallImagePath)

    await model.cachePrintingPreviewImages(for: thumbnailPrinting)
    await model.drainImageDownloadsForTesting()

    let previewPrinting = try XCTUnwrap(
      model.selectedCardPrintings.first { $0.id == "shared-old" })
    XCTAssertNotNil(previewPrinting.largeImagePath)
    XCTAssertEqual(previewPrinting.detailImagePath, previewPrinting.largeImagePath)
  }

  func testBatchPrintingPreviewImageCachingPrewarmsAllAvailablePrintings() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let printings = [
      CardRecord(
        id: "swarm-c21",
        oracleID: "swarm-oracle",
        name: "Swarm Intelligence",
        releasedAt: "2021-04-23",
        setCode: "c21",
        setName: "Commander 2021",
        setType: "commander",
        collectorNumber: "130",
        collectorNumberNumber: 130,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 1,
        layout: "normal",
        typeLine: "Enchantment",
        oracleText: "Copy spells.",
        isRealCard: true,
        smallImageURL: "https://example.test/swarm-c21-small.jpg",
        largeImageURL: "https://example.test/swarm-c21-large.jpg"
      ),
      CardRecord(
        id: "swarm-c20",
        oracleID: "swarm-oracle",
        name: "Swarm Intelligence",
        releasedAt: "2020-04-17",
        setCode: "c20",
        setName: "Commander 2020",
        setType: "commander",
        collectorNumber: "124",
        collectorNumberNumber: 124,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 1,
        layout: "normal",
        typeLine: "Enchantment",
        oracleText: "Copy spells.",
        isRealCard: true,
        smallImageURL: "https://example.test/swarm-c20-small.jpg",
        largeImageURL: "https://example.test/swarm-c20-large.jpg"
      ),
      CardRecord(
        id: "swarm-hou",
        oracleID: "swarm-oracle",
        name: "Swarm Intelligence",
        releasedAt: "2017-07-14",
        setCode: "hou",
        setName: "Hour of Devastation",
        setType: "expansion",
        collectorNumber: "50",
        collectorNumberNumber: 50,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 1,
        layout: "normal",
        typeLine: "Enchantment",
        oracleText: "Copy spells.",
        isRealCard: true,
        smallImageURL: "https://example.test/swarm-hou-small.jpg",
        largeImageURL: "https://example.test/swarm-hou-large.jpg"
      )
    ]
    try database.replaceAllCards(printings)
    try markLibraryReady(database)
    let resolver = ModelTestImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let selected = try XCTUnwrap(model.cards.first { $0.id == "swarm-c21" })
    model.selectCard(selected)
    await model.loadPrintings(for: selected)

    await model.cachePrintingPreviewImages(for: model.selectedCardPrintings)
    await model.drainImageDownloadsForTesting()

    for printing in printings {
      let storedPrinting = try XCTUnwrap(database.card(id: printing.id))
      XCTAssertNotNil(storedPrinting.smallImagePath, printing.id)
      XCTAssertNotNil(storedPrinting.largeImagePath, printing.id)
    }
    XCTAssertTrue(model.selectedCardPrintings.allSatisfy { $0.detailImagePath == $0.largeImagePath })
  }

  func testStalePrintingLoadDoesNotOverwriteChangedSelection() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let first = CardRecord(
      id: "first",
      oracleID: "first-oracle",
      name: "First Card",
      releasedAt: "2024-01-01",
      setCode: "fst",
      setName: "First Set",
      setType: "expansion",
      collectorNumber: "1",
      collectorNumberNumber: 1,
      rarity: "rare",
      rarityRank: 2,
      colorSortKey: 1,
      layout: "normal",
      typeLine: "Creature",
      oracleText: "Draw.",
      isRealCard: true
    )
    let second = CardRecord(
      id: "second",
      oracleID: "second-oracle",
      name: "Second Card",
      releasedAt: "2024-01-01",
      setCode: "snd",
      setName: "Second Set",
      setType: "expansion",
      collectorNumber: "1",
      collectorNumberNumber: 1,
      rarity: "rare",
      rarityRank: 2,
      colorSortKey: 1,
      layout: "normal",
      typeLine: "Creature",
      oracleText: "Draw.",
      isRealCard: true
    )
    try database.replaceAllCards([first, second])
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    model.selectedCard = first
    let staleLoad = Task { await model.loadPrintings(for: first) }
    model.selectedCard = second
    await staleLoad.value

    XCTAssertEqual(model.selectedCardPrintings.map(\.id), ["second"])
  }

  func testVisibleImageCachingDownloadsSmallImageLazily() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest",
        name: "Alpha Forest",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        smallImageURL: "https://example.test/forest-small.jpg",
        normalImageURL: "https://example.test/forest-normal.jpg",
        largeImageURL: "https://example.test/forest-large.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = ModelTestImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    XCTAssertNil(initialCard.existingDisplayImagePath)

    await model.cacheVisibleImages(for: initialCard)
    await model.drainImageDownloadsForTesting()

    let updatedCard = try XCTUnwrap(cards(in: database, matching: "forest").first)
    XCTAssertNotNil(updatedCard.smallImagePath)
    XCTAssertNil(updatedCard.normalImagePath)
    XCTAssertNil(updatedCard.largeImagePath)
    XCTAssertEqual(model.cards.first?.displayImagePath, updatedCard.smallImagePath)
  }

  func testOverviewImageCachingDownloadsArtCropIndependently() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest",
        name: "Alpha Forest",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        smallImageURL: "https://example.test/forest-small.jpg",
        normalImageURL: "https://example.test/forest-normal.jpg",
        artCropImageURL: "https://example.test/forest-art-crop.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    XCTAssertNil(initialCard.listOverviewImagePath)

    await model.cacheVisibleImages(for: initialCard, quality: .artCrop)
    await model.drainImageDownloadsForTesting()

    let calls = await resolver.recordedCalls()
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.qualities, [.artCrop])
    XCTAssertEqual(
      calls.first?.remoteURLs.artCrop?.absoluteString,
      "https://example.test/forest-art-crop.jpg"
    )

    let updatedCard = try XCTUnwrap(cards(in: database, matching: "forest").first)
    XCTAssertNotNil(updatedCard.artCropImagePath)
    XCTAssertNil(updatedCard.smallImagePath)
    XCTAssertNil(updatedCard.normalImagePath)
    XCTAssertEqual(model.cards.first?.listOverviewImagePath, updatedCard.artCropImagePath)
  }

  func testZoomedVisibleImageCachingDownloadsNormalWhenSmallExists() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    let localSmallURL = imageDirectory.appendingPathComponent("existing-small.jpg")
    try modelTestImageData().write(to: localSmallURL, options: .atomic)
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest",
        name: "Alpha Forest",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        smallImagePath: localSmallURL.path,
        smallImageURL: "https://example.test/forest-small.jpg",
        normalImageURL: "https://example.test/forest-normal.jpg",
        largeImageURL: "https://example.test/forest-large.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    await model.cacheVisibleImages(for: initialCard, quality: .normal)
    await model.drainImageDownloadsForTesting()

    let calls = await resolver.recordedCalls()
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.qualities, [.normal])
    XCTAssertEqual(
      calls.first?.remoteURLs.normal?.absoluteString, "https://example.test/forest-normal.jpg")

    let updatedCard = try XCTUnwrap(cards(in: database, matching: "forest").first)
    XCTAssertEqual(updatedCard.smallImagePath, localSmallURL.path)
    XCTAssertNotNil(updatedCard.normalImagePath)
    XCTAssertNil(updatedCard.largeImagePath)
    XCTAssertEqual(model.cards.first?.displayImagePath, updatedCard.normalImagePath)
  }

  func testZoomedVisibleImageCachingSkipsWhenNormalAlreadyExists() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let existingNormalImage = imageDirectory.appendingPathComponent("existing-normal.jpg")
    try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    try modelTestImageData().write(to: existingNormalImage, options: .atomic)
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest",
        name: "Alpha Forest",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        normalImagePath: existingNormalImage.path,
        smallImageURL: "https://example.test/forest-small.jpg",
        normalImageURL: "https://example.test/forest-normal.jpg",
        largeImageURL: "https://example.test/forest-large.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    await model.cacheVisibleImages(for: initialCard, quality: .normal)
    await model.drainImageDownloadsForTesting()

    let calls = await resolver.recordedCalls()
    XCTAssertTrue(calls.isEmpty)
  }

  func testDuplicateImagePatchDoesNotPublishCollectionChanges() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let card = CardRecord(
      id: "same-image",
      oracleID: "same-image",
      name: "Same Image",
      releasedAt: "2024-01-01",
      setCode: "set",
      setName: "Set",
      setType: "expansion",
      collectorNumber: "1",
      collectorNumberNumber: 1,
      rarity: "common",
      rarityRank: 0,
      colorSortKey: 4,
      layout: "normal",
      typeLine: "Creature",
      oracleText: "Reach",
      isRealCard: true,
      normalImagePath: "/tmp/same-image-normal.jpg"
    )
    try database.replaceAllCards([card])
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()
    let existingCard = try XCTUnwrap(model.cards.first)
    XCTAssertEqual(model.cards, [existingCard])

    let noPublish = expectation(description: "Duplicate image patch should not publish changes")
    noPublish.isInverted = true
    let cancellable = model.objectWillChange.sink { _ in
      noPublish.fulfill()
    }

    model.patchImageUpdate(existingCard)

    await fulfillment(of: [noPublish], timeout: 0.1)
    cancellable.cancel()
    XCTAssertEqual(model.cards, [existingCard])
  }

	  func testVisibleImageCachingReturnsBeforeDelayedDownloadFinishes() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest",
        name: "Alpha Forest",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        smallImageURL: "https://example.test/forest-small.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = DelayedModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    await model.cacheVisibleImages(for: initialCard)
    await resolver.waitForStartedCount(1)

    XCTAssertNil(model.cards.first?.smallImagePath)

    await resolver.releaseAll()
    await model.drainImageDownloadsForTesting()

	    XCTAssertNotNil(model.cards.first?.smallImagePath)
	  }

  func testVisibleImageCachingRetriesTransientFailureWithoutScrolling() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let smallURL = URL(string: "https://example.test/forest-small.jpg")!
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest",
        name: "Alpha Forest",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        smallImageURL: smallURL.absoluteString
      )
    ])
    try markLibraryReady(database)
    let resolver = FlakyModelImageResolver(
      rootDirectory: imageDirectory,
      failureCounts: [smallURL: 1]
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          visibleConcurrency: 1,
          detailConcurrency: 1,
          visibleRetryAttemptCount: 3,
          visibleAttemptTimeoutNanoseconds: 0,
          visibleRetryDelayNanoseconds: [0, 0]
        )
      ))
    await model.drainSearchForTesting()

    await model.cacheVisibleImages(around: 0)
    await resolver.waitForCallCount(2)
    await model.drainImageDownloadsForTesting()

    let updatedCard = try XCTUnwrap(model.cards.first)
    XCTAssertNotNil(updatedCard.smallImagePath)
    XCTAssertFalse(model.isLoadingVisiblePreview(for: updatedCard, quality: .small))
    XCTAssertNil(model.visibleImageRequestStates[VisibleImageRequestKey(cardID: "forest", quality: .small)])
    let calls = await resolver.recordedCalls()
    XCTAssertEqual(calls.count, 2)
  }

  func testVisibleImageCachingStopsLoadingAfterPermanentFailure() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let smallURL = URL(string: "https://example.test/forest-small.jpg")!
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest",
        name: "Alpha Forest",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        smallImageURL: smallURL.absoluteString
      )
    ])
    try markLibraryReady(database)
    let resolver = FlakyModelImageResolver(
      rootDirectory: imageDirectory,
      failureCounts: [smallURL: 10]
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          visibleConcurrency: 1,
          detailConcurrency: 1,
          visibleRetryAttemptCount: 3,
          visibleAttemptTimeoutNanoseconds: 0,
          visibleRetryDelayNanoseconds: [0, 0]
        )
      ))
    await model.drainSearchForTesting()

    await model.cacheVisibleImages(around: 0)
    await resolver.waitForCallCount(3)
    await model.drainImageDownloadsForTesting()

    let card = try XCTUnwrap(model.cards.first)
    let key = VisibleImageRequestKey(cardID: "forest", quality: .small)
    let state = try XCTUnwrap(model.visibleImageRequestStates[key])
    XCTAssertEqual(state.phase, .failed)
    XCTAssertEqual(state.attempt, 3)
    XCTAssertNil(card.smallImagePath)
    XCTAssertFalse(model.isLoadingVisiblePreview(for: card, quality: .small))
    XCTAssertEqual(model.visiblePreviewAccessibilityValue(for: card, quality: .small), "Text Only")
  }

  func testVisibleImageCachingRetainsRecentRetryAfterLargeScrollJump() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let firstSmallURL = URL(string: "https://example.test/window-0-small.jpg")!
    try database.replaceAllCards(
      (0..<24).map { (index: Int) -> CardRecord in
        CardRecord(
          id: "window-\(index)",
          oracleID: "window-\(index)",
          name: "Window Card \(index)",
          releasedAt: "2024-01-01",
          setCode: "set",
          setName: "Set",
          setType: "expansion",
          collectorNumber: "\(index)",
          collectorNumberNumber: index,
          rarity: "common",
          rarityRank: 0,
          colorSortKey: 4,
          layout: "normal",
          typeLine: "Creature",
          oracleText: "Reach",
          isRealCard: true,
          smallImageURL: "https://example.test/window-\(index)-small.jpg"
        )
      })
    try markLibraryReady(database)
    let resolver = FlakyModelImageResolver(
      rootDirectory: imageDirectory,
      failureCounts: [firstSmallURL: 1]
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          visibleConcurrency: 1,
          detailConcurrency: 1,
          visibleRetryAttemptCount: 3,
          visibleAttemptTimeoutNanoseconds: 0,
          visibleRetryDelayNanoseconds: [150_000_000, 0]
        ),
        searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration(
          textDebounceNanoseconds: 0,
          prefetchesNextPage: false,
          imageLookaheadCount: 3
        )
      ))
    await model.drainSearchForTesting()

    await model.cacheVisibleImages(around: 0)
    await resolver.waitForCallCount(1)
    await waitForVisibleImagePhase(.retrying, cardID: "window-0", quality: .small, in: model)

    await model.cacheVisibleImages(around: 13)
    try? await Task.sleep(nanoseconds: 220_000_000)
    await model.drainImageDownloadsForTesting()

    let callCounts = await resolver.callCountsByCardID()
    XCTAssertEqual(callCounts["window-0"], 2)
    XCTAssertNotNil(model.cards.first?.smallImagePath)
  }

  func testListVisibleImageCachingRetriesTransientFailureWithoutScrolling() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let smallURL = URL(string: "https://example.test/list-small.jpg")!
    try database.replaceAllCards([
      CardRecord(
        id: "list-card",
        oracleID: "list-card",
        name: "List Card",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        smallImageURL: smallURL.absoluteString
      )
    ])
    let list = try database.createCardList(named: "Retry List")
    try database.appendCard("list-card", toList: list.id)
    try markLibraryReady(database)
    let resolver = FlakyModelImageResolver(
      rootDirectory: imageDirectory,
      failureCounts: [smallURL: 1]
    )
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          visibleConcurrency: 1,
          detailConcurrency: 1,
          visibleRetryAttemptCount: 3,
          visibleAttemptTimeoutNanoseconds: 0,
          visibleRetryDelayNanoseconds: [0, 0]
        )
      ))
    await model.drainSearchForTesting()
    model.selectCardList(id: list.id)

    let entry = try XCTUnwrap(model.selectedListEntries.first)
    await model.cacheVisibleListEntryImages(around: entry.id)
    await resolver.waitForCallCount(2)
    await model.drainImageDownloadsForTesting()

    let updatedEntry = try XCTUnwrap(model.selectedListEntries.first)
    let updatedCard = try XCTUnwrap(updatedEntry.card)
    XCTAssertNotNil(updatedCard.smallImagePath)
    XCTAssertFalse(model.isLoadingVisiblePreview(for: updatedCard, quality: .small))
    XCTAssertNil(model.visibleImageRequestStates[VisibleImageRequestKey(cardID: "list-card", quality: .small)])
  }

  func testVisibleImageCachingDeduplicatesAndRespectsConfiguredParallelism() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards(
      (0..<10).map { (index: Int) -> CardRecord in
        CardRecord(
          id: "card-\(index)",
          oracleID: "card-\(index)",
          name: "Card \(index)",
          releasedAt: "2024-01-01",
          setCode: "set",
          setName: "Set",
          setType: "expansion",
          collectorNumber: "\(index)",
          collectorNumberNumber: index,
          rarity: "common",
          rarityRank: 0,
          colorSortKey: 4,
          layout: "normal",
          typeLine: "Creature",
          oracleText: "Reach",
          isRealCard: true,
          smallImageURL: "https://example.test/card-\(index)-small.jpg"
        )
      })
    try markLibraryReady(database)
    let resolver = DelayedModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          visibleConcurrency: 3, detailConcurrency: 1)
      ))
    await model.drainSearchForTesting()

    for card in model.cards {
      await model.cacheVisibleImages(for: card)
    }
    if let first = model.cards.first {
      await model.cacheVisibleImages(for: first)
    }

    await resolver.waitForStartedCount(3)
    var counts = await resolver.counts()
    XCTAssertEqual(counts.started, 3)
    XCTAssertEqual(counts.active, 3)

    await resolver.releaseAll()
    await model.drainImageDownloadsForTesting()

    counts = await resolver.counts()
    XCTAssertEqual(counts.started, 10)
    XCTAssertLessThanOrEqual(counts.maxActive, 3)
    XCTAssertTrue(model.cards.allSatisfy { $0.smallImagePath != nil })
  }

  func testVisibleImageWindowRetainsNearbyQueuedDownloadsOnLargeScrollJump() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards(
      (0..<24).map { (index: Int) -> CardRecord in
        CardRecord(
          id: "window-\(index)",
          oracleID: "window-\(index)",
          name: "Window Card \(index)",
          releasedAt: "2024-01-01",
          setCode: "set",
          setName: "Set",
          setType: "expansion",
          collectorNumber: "\(index)",
          collectorNumberNumber: index,
          rarity: "common",
          rarityRank: 0,
          colorSortKey: 4,
          layout: "normal",
          typeLine: "Creature",
          oracleText: "Reach",
          isRealCard: true,
          smallImageURL: "https://example.test/window-\(index)-small.jpg"
        )
      })
    try markLibraryReady(database)
    let resolver = DelayedModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          visibleConcurrency: 1, detailConcurrency: 1),
        searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration(
          textDebounceNanoseconds: 0,
          prefetchesNextPage: false,
          imageLookaheadCount: 3
        )
      ))
    await model.drainSearchForTesting()

    await model.cacheVisibleImages(around: 0)
    await resolver.waitForStartedCount(1)
    await model.cacheVisibleImages(around: 13)

    await resolver.releaseAll()
    await model.drainImageDownloadsForTesting()

    let startedIDs = await resolver.startedIDs()
    let jumpedWindowIDs = model.cards[12..<16].map(\.id)
    let retainedWindowIDs = model.cards[1..<4].map(\.id)
    XCTAssertEqual(startedIDs, [model.cards[0].id] + jumpedWindowIDs + retainedWindowIDs)
  }

  func testVisibleImageWindowPrunesQueuedDownloadsAfterSearchReset() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards(
      (0..<24).map { (index: Int) -> CardRecord in
        CardRecord(
          id: "reset-window-\(index)",
          oracleID: "reset-window-\(index)",
          name: "Reset Window Card \(index)",
          releasedAt: "2024-01-01",
          setCode: "set",
          setName: "Set",
          setType: "expansion",
          collectorNumber: "\(index)",
          collectorNumberNumber: index,
          rarity: "common",
          rarityRank: 0,
          colorSortKey: 4,
          layout: "normal",
          typeLine: "Creature",
          oracleText: "Reach",
          isRealCard: true,
          smallImageURL: "https://example.test/reset-window-\(index)-small.jpg"
        )
      })
    try markLibraryReady(database)
    let resolver = DelayedModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          visibleConcurrency: 1, detailConcurrency: 1),
        searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration(
          textDebounceNanoseconds: 0,
          prefetchesNextPage: false,
          imageLookaheadCount: 3
        )
      ))
    await model.drainSearchForTesting()

    await model.cacheVisibleImages(around: 0)
    await resolver.waitForStartedCount(1)
    model.resetSearchVisibleImageRequests()
    await model.cacheVisibleImages(around: 13, forceRefresh: true)

    await resolver.releaseAll()
    await model.drainImageDownloadsForTesting()

    let startedIDs = await resolver.startedIDs()
    let jumpedWindowIDs = model.cards[12..<16].map(\.id)
    XCTAssertEqual(startedIDs, [model.cards[0].id] + jumpedWindowIDs)
  }

  func testListVisibleImageWindowRetainsNearbyQueuedDownloadsOnLargeScrollJump() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards(
      (0..<24).map { (index: Int) -> CardRecord in
        CardRecord(
          id: "list-window-\(index)",
          oracleID: "list-window-\(index)",
          name: "List Window Card \(index)",
          releasedAt: "2024-01-01",
          setCode: "set",
          setName: "Set",
          setType: "expansion",
          collectorNumber: "\(index)",
          collectorNumberNumber: index,
          rarity: "common",
          rarityRank: 0,
          colorSortKey: 4,
          layout: "normal",
          typeLine: "Creature",
          oracleText: "Reach",
          isRealCard: true,
          smallImageURL: "https://example.test/list-window-\(index)-small.jpg"
        )
      })
    let list = try database.createCardList(named: "Scroll List")
    for index in 0..<24 {
      try database.appendCard("list-window-\(index)", toList: list.id)
    }
    try markLibraryReady(database)
    let resolver = DelayedModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          visibleConcurrency: 1, detailConcurrency: 1),
        searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration(
          textDebounceNanoseconds: 0,
          prefetchesNextPage: false,
          imageLookaheadCount: 3
        )
      ))
    await model.drainSearchForTesting()
    model.selectCardList(id: list.id)

    await model.cacheVisibleListEntryImages(around: model.selectedListEntries[0].id)
    await resolver.waitForStartedCount(1)
    await model.cacheVisibleListEntryImages(around: model.selectedListEntries[13].id)

    await resolver.releaseAll()
    await model.drainImageDownloadsForTesting()

    let startedIDs = await resolver.startedIDs()
    let jumpedWindowIDs = model.selectedListEntries[12..<16].map(\.cardID)
    let retainedWindowIDs = model.selectedListEntries[1..<4].map(\.cardID)
    XCTAssertEqual(startedIDs, [model.selectedListEntries[0].cardID] + jumpedWindowIDs + retainedWindowIDs)
  }

  func testListVisibleImageWindowPrunesQueuedDownloadsAfterListReset() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards(
      (0..<24).map { (index: Int) -> CardRecord in
        CardRecord(
          id: "list-reset-window-\(index)",
          oracleID: "list-reset-window-\(index)",
          name: "List Reset Window Card \(index)",
          releasedAt: "2024-01-01",
          setCode: "set",
          setName: "Set",
          setType: "expansion",
          collectorNumber: "\(index)",
          collectorNumberNumber: index,
          rarity: "common",
          rarityRank: 0,
          colorSortKey: 4,
          layout: "normal",
          typeLine: "Creature",
          oracleText: "Reach",
          isRealCard: true,
          smallImageURL: "https://example.test/list-reset-window-\(index)-small.jpg"
        )
      })
    let list = try database.createCardList(named: "Reset Scroll List")
    for index in 0..<24 {
      try database.appendCard("list-reset-window-\(index)", toList: list.id)
    }
    try markLibraryReady(database)
    let resolver = DelayedModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver),
        imageDownloadConfiguration: GrimoraImageDownloadConfiguration(
          visibleConcurrency: 1, detailConcurrency: 1),
        searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration(
          textDebounceNanoseconds: 0,
          prefetchesNextPage: false,
          imageLookaheadCount: 3
        )
      ))
    await model.drainSearchForTesting()
    model.selectCardList(id: list.id)

    await model.cacheVisibleListEntryImages(around: model.selectedListEntries[0].id)
    await resolver.waitForStartedCount(1)
    model.resetListVisibleImageRequests()
    await model.cacheVisibleListEntryImages(
      around: model.selectedListEntries[13].id,
      forceRefresh: true
    )

    await resolver.releaseAll()
    await model.drainImageDownloadsForTesting()

    let startedIDs = await resolver.startedIDs()
    let jumpedWindowIDs = model.selectedListEntries[12..<16].map(\.cardID)
    XCTAssertEqual(startedIDs, [model.selectedListEntries[0].cardID] + jumpedWindowIDs)
  }

  func testVisibleImageCachingKeepsTextOnlyWhenSmallDownloadFails() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let failedSmallURL = URL(string: "https://example.test/forest-small.jpg")!
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest",
        name: "Alpha Forest",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        smallImageURL: failedSmallURL.absoluteString,
        normalImageURL: "https://example.test/forest-normal.jpg",
        largeImageURL: "https://example.test/forest-large.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = ModelTestImageResolver(
      rootDirectory: imageDirectory, failedURLs: [failedSmallURL])
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    await model.cacheVisibleImages(for: initialCard)
    await model.drainImageDownloadsForTesting()

    let updatedCard = try XCTUnwrap(cards(in: database, matching: "forest").first)
    XCTAssertNil(updatedCard.smallImagePath)
    XCTAssertNil(updatedCard.normalImagePath)
    XCTAssertNil(model.cards.first?.existingDisplayImagePath)
  }

  func testVisibleImageCachingDownloadsOnlyDisplayedSmallImageSource() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let face = CardFaceRecord(
      cardID: "split",
      faceIndex: 0,
      name: "Split Face",
      typeLine: "Instant",
      oracleText: "Draw.",
      smallImageURL: "https://example.test/face-small.jpg",
      largeImageURL: "https://example.test/face-large.jpg"
    )
    try database.replaceAllCards([
      CardRecord(
        id: "split",
        oracleID: "split",
        name: "Split Card",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 0,
        layout: "split",
        typeLine: "Instant",
        oracleText: "Draw.",
        isRealCard: true,
        smallImageURL: "https://example.test/card-small.jpg",
        largeImageURL: "https://example.test/card-large.jpg",
        faces: [face]
      )
    ])
    try markLibraryReady(database)
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    await model.cacheVisibleImages(for: initialCard)
    await model.drainImageDownloadsForTesting()

    let calls = await resolver.recordedCalls()
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.cardID, "split")
    XCTAssertNil(calls.first?.faceIndex)
    XCTAssertEqual(calls.first?.qualities, [.small])
    XCTAssertEqual(
      calls.first?.remoteURLs.small?.absoluteString, "https://example.test/card-small.jpg")
    XCTAssertNil(try cards(in: database, matching: "split").first?.faces.first?.smallImagePath)
  }

  func testVisibleImageCachingDownloadsAllDisplayableFaceImageSources() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards([
      CardRecord(
        id: "fable",
        oracleID: "fable",
        name: "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki",
        releasedAt: "2024-01-01",
        setCode: "neo",
        setName: "Kamigawa: Neon Dynasty",
        setType: "expansion",
        collectorNumber: "141",
        collectorNumberNumber: 141,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 1,
        layout: "transform",
        typeLine: "Enchantment — Saga // Enchantment Creature",
        oracleText: "",
        isRealCard: true,
        faces: [
          CardFaceRecord(
            cardID: "fable",
            faceIndex: 0,
            name: "Fable of the Mirror-Breaker",
            typeLine: "Enchantment — Saga",
            oracleText: "",
            smallImageURL: "https://example.test/fable-front-small.jpg"
          ),
          CardFaceRecord(
            cardID: "fable",
            faceIndex: 1,
            name: "Reflection of Kiki-Jiki",
            typeLine: "Enchantment Creature — Goblin Shaman",
            oracleText: "",
            smallImageURL: "https://example.test/fable-back-small.jpg"
          )
        ]
      )
    ])
    try markLibraryReady(database)
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    await model.cacheVisibleImages(for: initialCard)
    await model.drainImageDownloadsForTesting()

    let calls = await resolver.recordedCalls()
    XCTAssertEqual(calls.map(\.faceIndex), [0, 1])
    XCTAssertEqual(calls.map(\.qualities), [[.small], [.small]])

    let updatedCard = try XCTUnwrap(cards(in: database, matching: "fable").first)
    XCTAssertNotNil(updatedCard.faces.first?.smallImagePath)
    XCTAssertNotNil(updatedCard.faces.dropFirst().first?.smallImagePath)
  }

  func testVisibleImageCachingFallsBackToSmallWhenRequestedNormalImageIsMissing() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards([
      CardRecord(
        id: "fallback",
        oracleID: "fallback",
        name: "Fallback Preview",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Instant",
        oracleText: "Draw.",
        isRealCard: true,
        smallImageURL: "https://example.test/fallback-small.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    await model.cacheVisibleImages(around: 0, quality: .normal)
    await model.drainImageDownloadsForTesting()

    let calls = await resolver.recordedCalls()
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.qualities, [.small])
    XCTAssertEqual(
      calls.first?.remoteURLs.small?.absoluteString, "https://example.test/fallback-small.jpg")

    let updatedCard = try XCTUnwrap(cards(in: database, matching: "fallback").first)
    XCTAssertNotNil(updatedCard.smallImagePath)
    XCTAssertNil(updatedCard.normalImagePath)
    XCTAssertTrue(updatedCard.hasCachedDisplayImage(for: .normal))
    XCTAssertEqual(model.cards.first?.existingDisplayImagePath, updatedCard.smallImagePath)
  }

  func testVisibleImageCachingShowsLargeFallbackButStillDownloadsPreview() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let localLargeImage = imageDirectory.appendingPathComponent("existing-large.jpg")
    try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    try modelTestImageData().write(to: localLargeImage, options: .atomic)
    try database.replaceAllCards([
      CardRecord(
        id: "large-fallback",
        oracleID: "large-fallback",
        name: "Large Fallback",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Instant",
        oracleText: "Draw.",
        isRealCard: true,
        largeImagePath: localLargeImage.path,
        smallImageURL: "https://example.test/large-fallback-small.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    XCTAssertEqual(initialCard.existingDisplayImagePath, localLargeImage.path)
    XCTAssertFalse(initialCard.hasCachedDisplayImage(for: .small))

    await model.cacheVisibleImages(around: 0, quality: .small)
    await model.drainImageDownloadsForTesting()

    let calls = await resolver.recordedCalls()
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.qualities, [.small])

    let updatedCard = try XCTUnwrap(cards(in: database, matching: "Large").first)
    XCTAssertEqual(updatedCard.largeImagePath, localLargeImage.path)
    XCTAssertNotNil(updatedCard.smallImagePath)
    XCTAssertEqual(model.cards.first?.existingDisplayImagePath, localLargeImage.path)
  }

  func testVisibleImageCachingRepairsStaleStoredPreviewPath() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let stalePath = imageDirectory.appendingPathComponent("old-container/missing-small.jpg").path
    try database.replaceAllCards([
      CardRecord(
        id: "stale-preview",
        oracleID: "stale-preview",
        name: "Stale Preview",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Instant",
        oracleText: "Draw.",
        isRealCard: true,
        smallImagePath: stalePath,
        smallImageURL: "https://example.test/stale-small.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    XCTAssertEqual(initialCard.smallImagePath, stalePath)
    XCTAssertTrue(initialCard.hasCachedDisplayImage(for: .small))
    XCTAssertTrue(initialCard.hasMissingCachedDisplayImageFile(for: .small))

    await model.cacheVisibleImages(around: 0, quality: .small)
    await model.drainImageDownloadsForTesting()

    let calls = await resolver.recordedCalls()
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.qualities, [.small])

    let updatedCard = try XCTUnwrap(cards(in: database, matching: "stale").first)
    XCTAssertNotEqual(updatedCard.smallImagePath, stalePath)
    XCTAssertNotNil(updatedCard.smallImagePath)
    XCTAssertFalse(updatedCard.hasMissingCachedDisplayImageFile(for: .small))
    XCTAssertEqual(model.cards.first?.smallImagePath, updatedCard.smallImagePath)
  }

  func testVisibleImageCachingRepairsUnreadableStoredPreviewFile() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let smallURL = URL(string: "https://example.test/unreadable-small.jpg")!
    let cachedPreview = ImageStore(rootDirectory: imageDirectory).localURL(
      for: smallURL,
      cardID: "unreadable-preview",
      faceIndex: nil,
      quality: CardImageQuality.small.rawValue
    )
    try FileManager.default.createDirectory(
      at: cachedPreview.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not an image".utf8).write(to: cachedPreview, options: .atomic)
    try database.replaceAllCards([
      CardRecord(
        id: "unreadable-preview",
        oracleID: "unreadable-preview",
        name: "Unreadable Preview",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Instant",
        oracleText: "Draw.",
        isRealCard: true,
        smallImagePath: cachedPreview.path,
        smallImageURL: smallURL.absoluteString
      )
    ])
    try markLibraryReady(database)
    let resolver = RecordingModelImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    XCTAssertTrue(initialCard.hasCachedDisplayImage(for: .small))
    XCTAssertTrue(initialCard.hasUnavailableCachedDisplayImageFile(for: .small))

    await model.cacheVisibleImages(around: 0, quality: .small)
    await model.drainImageDownloadsForTesting()

    let calls = await resolver.recordedCalls()
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.qualities, [.small])
    XCTAssertEqual(try Data(contentsOf: cachedPreview), modelTestImageData())
  }

  func testDetailImageCachingDownloadsLargeImageOnlyWhenSmallImageExists() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let smallImageURL = imageDirectory.appendingPathComponent("small.jpg")
    try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    try modelTestImageData().write(to: smallImageURL, options: .atomic)
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest",
        name: "Alpha Forest",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        smallImagePath: smallImageURL.path,
        normalImageURL: "https://example.test/forest-normal.jpg",
        largeImageURL: "https://example.test/forest-large.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = ModelTestImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    await model.cacheDetailImages(for: initialCard)
    await model.drainImageDownloadsForTesting()

    let updatedCard = try XCTUnwrap(cards(in: database, matching: "forest").first)
    XCTAssertNil(updatedCard.normalImagePath)
    XCTAssertNotNil(updatedCard.largeImagePath)
    XCTAssertEqual(model.cards.first?.detailImagePath, updatedCard.largeImagePath)
  }

  func testDetailImageCachingDownloadsSmallThenLargeWhenLowResImageIsMissing() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest",
        name: "Alpha Forest",
        releasedAt: "2024-01-01",
        setCode: "set",
        setName: "Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 4,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Reach",
        isRealCard: true,
        smallImageURL: "https://example.test/forest-small.jpg",
        normalImageURL: "https://example.test/forest-normal.jpg",
        largeImageURL: "https://example.test/forest-large.jpg"
      )
    ])
    try markLibraryReady(database)
    let resolver = ModelTestImageResolver(rootDirectory: imageDirectory)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(database: database, imageResolver: resolver)
      ))
    await model.drainSearchForTesting()

    let initialCard = try XCTUnwrap(model.cards.first)
    await model.cacheDetailImages(for: initialCard)
    await model.drainImageDownloadsForTesting()

    let updatedCard = try XCTUnwrap(cards(in: database, matching: "forest").first)
    XCTAssertNotNil(updatedCard.smallImagePath)
    XCTAssertNil(updatedCard.normalImagePath)
    XCTAssertNotNil(updatedCard.largeImagePath)
    XCTAssertEqual(model.cards.first?.detailImagePath, updatedCard.largeImagePath)
  }

  func testModelCreatesRenamesDeletesAndUpdatesListEntryQuantities() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "  Deck Box  ", selectAfterCreate: true))
    XCTAssertEqual(list.name, "Deck Box")
    XCTAssertEqual(model.sidebarSelection, .list(list.id))
    XCTAssertEqual(model.selectedListID, list.id)
    XCTAssertEqual(model.selectedList?.entryCount, 0)

    let forest = try XCTUnwrap(model.cards.first { $0.id == "forest" })
    model.addCard(forest, toListID: list.id)
    model.addCard(forest, toListID: list.id)

    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["forest"])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [2])
    XCTAssertEqual(model.selectedListEntries.compactMap(\.card?.name), ["Alpha Forest"])
    XCTAssertEqual(model.selectedList?.entryCount, 2)

    let firstEntryID = model.selectedListEntries[0].id
    model.removeCardListEntry(id: firstEntryID)
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["forest"])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [1])
    XCTAssertEqual(model.selectedList?.entryCount, 1)

    model.renameCardList(id: list.id, to: "Deck Box")
    XCTAssertEqual(model.selectedList?.name, "Deck Box")

    model.deleteCardList(id: list.id)
    XCTAssertEqual(model.cardLists.map(\.name), ["Favourites"])
    XCTAssertEqual(model.sidebarSelection, .listsOverview)
    XCTAssertNil(model.selectedListID)
    XCTAssertTrue(model.selectedListEntries.isEmpty)
  }

  func testModelUndoRestoresListQuantityAndBulkActions() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "Undo Deck", selectAfterCreate: true))
    let category = try XCTUnwrap(model.createCardListCategory(named: "Ramp", inListID: list.id))
    let forest = try XCTUnwrap(model.cards.first { $0.id == "forest" })
    let beta = try XCTUnwrap(model.cards.first { $0.id == "beta" })
    model.addCard(forest, toListID: list.id)
    model.addCard(beta, toListID: list.id)
    let entryIDs = model.selectedListEntries.map(\.id)

    model.incrementCardListEntryQuantity(id: entryIDs[0])
    XCTAssertEqual(model.selectedListEntries.first?.quantity, 2)
    XCTAssertTrue(model.canUndoListAction)

    model.moveCardListEntries(ids: entryIDs, toCategoryID: category.id)
    XCTAssertEqual(Set(model.selectedListEntries.map(\.categoryID)), Set<String?>([category.id]))

    model.removeCardListEntriesCompletely(ids: entryIDs)
    XCTAssertTrue(model.selectedListEntries.isEmpty)

    model.undoLastListAction()
    XCTAssertEqual(model.selectedListEntries.map(\.id), entryIDs)
    XCTAssertEqual(Set(model.selectedListEntries.map(\.categoryID)), Set<String?>([category.id]))

    model.undoLastListAction()
    XCTAssertEqual(Set(model.selectedListEntries.map(\.categoryID)), Set<String?>([nil]))

    model.undoLastListAction()
    XCTAssertEqual(model.selectedListEntries.first?.quantity, 1)
  }

  func testModelUpdatesCardListDashboardPreferences() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "Dashboard", selectAfterCreate: true))
    XCTAssertFalse(model.selectedList?.showsDashboard ?? true)
    XCTAssertFalse(model.selectedList?.dashboardIncludesLands ?? true)

    model.setCardListDashboardVisibility(id: list.id, showsDashboard: true)
    XCTAssertTrue(model.selectedList?.showsDashboard ?? false)
    XCTAssertEqual(model.statusMessage, "Showing list stats.")

    model.setCardListDashboardVisibility(id: list.id, showsDashboard: false)
    XCTAssertFalse(model.selectedList?.showsDashboard ?? true)
    XCTAssertEqual(model.statusMessage, "Hid list stats.")

    model.setCardListDashboardIncludesLands(id: list.id, includesLands: true)
    XCTAssertTrue(model.selectedList?.dashboardIncludesLands ?? false)
    XCTAssertEqual(model.statusMessage, "Type stats include lands.")

    let persisted = try XCTUnwrap(database.cardList(id: list.id))
    XCTAssertFalse(persisted.showsDashboard)
    XCTAssertTrue(persisted.dashboardIncludesLands)
  }

  func testModelUpdatesPerListDisplaySortWithoutUndoOrEntryRepositioning() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let first = try database.createCardList(named: "First")
    try database.appendCard("forest", toList: first.id)
    try database.appendCard("beta", toList: first.id)
    let second = try database.createCardList(named: "Second")
    try database.appendCard("beta", toList: second.id)
    model.reloadCardLists(selecting: first.id, activatingSelection: true)
    XCTAssertFalse(model.canUndoListAction)

    let positionsBefore = try database.cardListEntries(forListID: first.id).map(\.position)
    model.setCardListDisplaySort(id: first.id, mode: .releaseDate, direction: .ascending)

    XCTAssertEqual(model.selectedList?.displaySortMode, .releaseDate)
    XCTAssertEqual(model.selectedList?.displaySortDirection, .ascending)
    XCTAssertEqual(
      model.statusMessage,
      "Sorted First by Release Date, Newest First."
    )
    XCTAssertFalse(model.canUndoListAction)
    XCTAssertEqual(try database.cardListEntries(forListID: first.id).map(\.position), positionsBefore)

    model.selectCardList(id: second.id)
    XCTAssertNil(model.selectedList?.displaySortMode)
    XCTAssertEqual(model.selectedList?.displaySortDirection, .ascending)

    model.setCardListDisplaySort(id: second.id, mode: .edhrecRank, direction: .descending)
    XCTAssertEqual(model.selectedList?.displaySortMode, .edhrecRank)
    XCTAssertEqual(model.selectedList?.displaySortDirection, .descending)

    model.selectCardList(id: first.id)
    XCTAssertEqual(model.selectedList?.displaySortMode, .releaseDate)
    XCTAssertEqual(model.selectedList?.displaySortDirection, .ascending)
  }

  func testModelPersistsPrintingSelectionOnlyForListEntries() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let olderPrinting = CardRecord(
      id: "tempo-old",
      oracleID: "tempo-oracle",
      name: "Tempo Mage",
      language: "en",
      releasedAt: "2021-01-01",
      setCode: "old",
      setName: "Old Set",
      setType: "expansion",
      collectorNumber: "7",
      collectorNumberNumber: 7,
      rarity: "uncommon",
      rarityRank: 1,
      colorSortKey: 1,
      layout: "normal",
      typeLine: "Creature",
      oracleText: "Draw.",
      isRealCard: true,
      smallImageURL: "https://example.test/tempo-old-small.jpg",
      largeImageURL: "https://example.test/tempo-old-large.jpg"
    )
    let currentPrinting = CardRecord(
      id: "tempo-current",
      oracleID: "tempo-oracle",
      name: "Tempo Mage",
      language: "en",
      releasedAt: "2024-01-01",
      setCode: "cur",
      setName: "Current Set",
      setType: "expansion",
      collectorNumber: "1",
      collectorNumberNumber: 1,
      rarity: "rare",
      rarityRank: 2,
      colorSortKey: 1,
      layout: "normal",
      typeLine: "Creature",
      oracleText: "Draw.",
      isRealCard: true
    )
    let promoPrinting = CardRecord(
      id: "tempo-promo",
      oracleID: "tempo-oracle",
      name: "Tempo Mage",
      language: "en",
      releasedAt: "2022-01-01",
      setCode: "prm",
      setName: "Promo Set",
      setType: "promo",
      collectorNumber: "12",
      collectorNumberNumber: 12,
      rarity: "rare",
      rarityRank: 2,
      colorSortKey: 1,
      layout: "normal",
      typeLine: "Creature",
      oracleText: "Draw.",
      isRealCard: true
    )
    try database.replaceAllCards([olderPrinting, currentPrinting, promoPrinting])
    try markLibraryReady(database)
    let model = GrimoraAppModel(
      environment: environment(
        database: database,
        imageCache: CardImageCache(
          database: database,
          imageResolver: ModelTestImageResolver(rootDirectory: imageDirectory)
        )
      ))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "Tempo Picks", selectAfterCreate: true))
    model.addCard(olderPrinting, toListID: list.id)
    let listEntry = try XCTUnwrap(model.selectedListEntries.first)
    let listEntryCard = try XCTUnwrap(listEntry.card)

    model.selectCard(listEntryCard, fromListEntryID: listEntry.id)
    await model.loadPrintings(for: listEntryCard)
    await model.cacheDetailImages(for: listEntryCard)
    await model.drainImageDownloadsForTesting()
    XCTAssertEqual(model.selectedCardListEntryID, listEntry.id)

    model.selectPrinting(promoPrinting)

    XCTAssertEqual(model.selectedCard?.id, promoPrinting.id)
    XCTAssertEqual(model.selectedCardListEntryID, model.selectedListEntries.first?.id)
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), [promoPrinting.id])
    XCTAssertEqual(model.selectedListEntries.compactMap(\.card?.id), [promoPrinting.id])

    model.selectCard(currentPrinting)
    model.selectPrinting(olderPrinting)

    XCTAssertNil(model.selectedCardListEntryID)
    XCTAssertEqual(model.selectedCard?.id, olderPrinting.id)
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), [promoPrinting.id])
  }

  func testModelPinsListsAndKeepsSidebarSelectionStable() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let first = try XCTUnwrap(model.createCardList(named: "First"))
    let second = try XCTUnwrap(model.createCardList(named: "Second"))
    _ = try XCTUnwrap(model.createCardList(named: "Third"))

    model.setCardListPinned(id: first.id, isPinned: true, now: Date(timeIntervalSince1970: 10))
    model.setCardListPinned(id: second.id, isPinned: true, now: Date(timeIntervalSince1970: 20))

    XCTAssertEqual(model.pinnedCardLists.map(\.name), ["Second", "First"])
    XCTAssertEqual(model.unpinnedCardLists.map(\.name), ["Third"])

    model.selectCardList(id: first.id)
    XCTAssertEqual(model.sidebarSelection, .list(first.id))
    model.selectSearch()
    XCTAssertEqual(model.sidebarSelection, .search)
    XCTAssertEqual(model.selectedListID, first.id)

    model.setCardListPinned(id: second.id, isPinned: false, now: Date(timeIntervalSince1970: 30))
    XCTAssertEqual(model.pinnedCardLists.map(\.name), ["First"])
    XCTAssertEqual(model.unpinnedCardLists.map(\.name), ["Second", "Third"])
    XCTAssertEqual(model.sidebarSelection, .search)
    XCTAssertEqual(model.selectedListID, first.id)

    model.selectCardList(id: first.id)
    model.deleteCardList(id: first.id)
    XCTAssertEqual(model.sidebarSelection, .listsOverview)
    XCTAssertNil(model.selectedListID)
  }

  func testModelMovesListsWithinAndAcrossSidebarSections() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let first = try XCTUnwrap(model.createCardList(named: "First"))
    let second = try XCTUnwrap(model.createCardList(named: "Second"))
    let third = try XCTUnwrap(model.createCardList(named: "Third"))

    model.setCardListPinned(id: first.id, isPinned: true, now: Date(timeIntervalSince1970: 10))
    model.setCardListPinned(id: second.id, isPinned: true, now: Date(timeIntervalSince1970: 20))
    XCTAssertEqual(model.pinnedCardLists.map(\.name), ["Second", "First"])
    XCTAssertEqual(model.unpinnedCardLists.map(\.name), ["Third"])

    model.selectCardList(id: first.id)
    model.moveCardList(id: first.id, toPosition: 0, isPinned: true)
    XCTAssertEqual(model.pinnedCardLists.map(\.name), ["First", "Second"])
    XCTAssertEqual(model.sidebarSelection, .list(first.id))
    XCTAssertEqual(model.selectedListID, first.id)

    model.moveCardList(id: third.id, toPosition: 1, isPinned: true)
    XCTAssertEqual(model.pinnedCardLists.map(\.name), ["First", "Third", "Second"])
    XCTAssertTrue(model.unpinnedCardLists.isEmpty)

    model.moveCardList(id: third.id, by: 1)
    XCTAssertEqual(model.pinnedCardLists.map(\.name), ["First", "Second", "Third"])

    model.moveCardList(id: first.id, toPosition: 0, isPinned: false)
    XCTAssertEqual(model.pinnedCardLists.map(\.name), ["Second", "Third"])
    XCTAssertEqual(model.unpinnedCardLists.map(\.name), ["First"])
    XCTAssertEqual(model.sidebarSelection, .list(first.id))
    XCTAssertEqual(model.selectedListID, first.id)
  }

  func testModelLoadsMissingListEntriesAndRejectsMissingCardAdds() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([uiRecords()[0]])
    try markLibraryReady(database)
    let list = try database.createCardList(named: "Archive")
    try database.appendCard("missing-print", toList: list.id)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    XCTAssertEqual(model.cardLists.map(\.name), ["Favourites", "Archive"])
    model.selectCardList(id: list.id)
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["missing-print"])
    XCTAssertNil(model.selectedListEntries.first?.card)

    model.addCardID("another-missing-print", toListID: list.id)

    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["missing-print"])
    XCTAssertEqual(model.selectedList?.entryCount, 1)
    XCTAssertEqual(model.statusMessage, "That card is no longer in the local library.")
  }

  func testModelManagesListCategoriesAndMovesEntries() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "Deck", selectAfterCreate: true))
    let ramp = try XCTUnwrap(model.createCardListCategory(named: "Ramp"))
    let removal = try XCTUnwrap(model.createCardListCategory(named: "Removal"))
    let utility = try XCTUnwrap(model.createCardListCategory(named: "Utility"))
    XCTAssertEqual(model.selectedListCategories.map(\.name), ["Ramp", "Removal", "Utility"])
    XCTAssertEqual(model.selectedListCategories.map(\.entryCount), [0, 0, 0])

    XCTAssertNil(model.createCardListCategory(named: "ramp"))
    XCTAssertEqual(model.statusMessage, "Category already exists.")

    let forest = try XCTUnwrap(model.cards.first { $0.id == "forest" })
    model.addCard(forest, toListID: list.id)
    XCTAssertEqual(model.selectedListEntries.map(\.categoryID), [nil])
    XCTAssertEqual(model.selectedList?.entryCount, 1)

    let entryID = try XCTUnwrap(model.selectedListEntries.first?.id)
    model.moveCardListEntry(id: entryID, toCategoryID: ramp.id)
    XCTAssertEqual(model.selectedListEntries.map(\.categoryID), [ramp.id])
    XCTAssertEqual(model.selectedListCategories.map(\.entryCount), [1, 0, 0])

    model.addCard(forest, toListID: list.id)
    XCTAssertEqual(model.selectedListEntries.map(\.categoryID), [ramp.id, nil])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [1, 1])

    let uncategorizedEntryID = try XCTUnwrap(model.selectedListEntries.first { $0.categoryID == nil }?.id)
    model.moveCardListEntry(id: uncategorizedEntryID, toCategoryID: ramp.id)
    XCTAssertEqual(model.selectedListEntries.map(\.categoryID), [ramp.id])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [2])
    XCTAssertEqual(model.selectedListCategories.map(\.entryCount), [2, 0, 0])

    model.renameCardListCategory(id: removal.id, to: "Interaction")
    XCTAssertEqual(model.selectedListCategories.map(\.name), ["Ramp", "Interaction", "Utility"])

    model.moveCardListCategory(id: utility.id, toPosition: 0)
    XCTAssertEqual(model.selectedListCategories.map(\.name), ["Utility", "Ramp", "Interaction"])

    model.moveCardListCategory(id: utility.id, toPosition: model.selectedListCategories.count - 1)
    XCTAssertEqual(model.selectedListCategories.map(\.name), ["Ramp", "Interaction", "Utility"])

    model.moveCardListCategory(id: removal.id, by: -1)
    XCTAssertEqual(model.selectedListCategories.map(\.name), ["Interaction", "Ramp", "Utility"])

    model.deleteCardListCategory(id: ramp.id)
    XCTAssertEqual(model.selectedListCategories.map(\.name), ["Interaction", "Utility"])
    XCTAssertEqual(model.selectedListEntries.map(\.categoryID), [nil])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [2])
  }

  func testModelBulkMovesAndRemovesListEntries() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "Deck", selectAfterCreate: true))
    let ramp = try XCTUnwrap(model.createCardListCategory(named: "Ramp"))
    let forest = try XCTUnwrap(model.cards.first { $0.id == "forest" })
    let beta = try XCTUnwrap(model.cards.first { $0.id == "beta" })

    model.addCard(forest, toListID: list.id)
    model.addCard(forest, toListID: list.id)
    let rampForestID = try XCTUnwrap(model.selectedListEntries.first { $0.cardID == forest.id }?.id)
    model.moveCardListEntry(id: rampForestID, toCategoryID: ramp.id)

    model.addCard(forest, toListID: list.id)
    model.addCard(beta, toListID: list.id)
    let uncategorizedForestID = try XCTUnwrap(
      model.selectedListEntries.first { $0.cardID == forest.id && $0.categoryID == nil }?.id)
    let uncategorizedBetaID = try XCTUnwrap(
      model.selectedListEntries.first { $0.cardID == beta.id && $0.categoryID == nil }?.id)

    model.moveCardListEntries(ids: [uncategorizedForestID, uncategorizedBetaID], toCategoryID: ramp.id)

    let rampForestEntry = try XCTUnwrap(
      model.selectedListEntries.first { $0.cardID == forest.id && $0.categoryID == ramp.id })
    let rampBetaEntry = try XCTUnwrap(
      model.selectedListEntries.first { $0.cardID == beta.id && $0.categoryID == ramp.id })
    XCTAssertEqual(model.selectedListEntries.count, 2)
    XCTAssertEqual(rampForestEntry.quantity, 3)
    XCTAssertEqual(rampBetaEntry.quantity, 1)
    XCTAssertEqual(model.selectedListCategories.map(\.entryCount), [4])
    XCTAssertEqual(model.statusMessage, "Moved 2 cards to Ramp.")

    model.removeCardListEntries(ids: [rampForestEntry.id, rampBetaEntry.id])

    XCTAssertEqual(model.selectedListEntries.map(\.cardID), [forest.id])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [2])
    XCTAssertEqual(model.selectedList?.entryCount, 2)
    XCTAssertEqual(model.selectedListCategories.map(\.entryCount), [2])
    XCTAssertEqual(model.statusMessage, "Removed 2 cards from list.")
  }

  func testModelRulesetWarningsZonesAndExactQuantityActions() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards([
      CardRecord(
        id: "forest",
        oracleID: "forest-oracle",
        name: "Alpha Forest",
        releasedAt: "2020-01-01",
        setCode: "abc",
        setName: "Alpha Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 0,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Forest sample.",
        legalities: ["modern": "legal"],
        isRealCard: true
      ),
      CardRecord(
        id: "beta",
        oracleID: "beta-oracle",
        name: "Beta Mage",
        releasedAt: "2020-01-02",
        setCode: "abc",
        setName: "Alpha Set",
        setType: "expansion",
        collectorNumber: "2",
        collectorNumberNumber: 2,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 1,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Mage sample.",
        legalities: ["modern": "legal"],
        isRealCard: true
      ),
    ])
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "Modern Deck", selectAfterCreate: true))
    model.setCardListRuleset(id: list.id, ruleset: .modern)
    XCTAssertEqual(model.statusMessage, "Set Modern Deck ruleset to Modern.")

    let forest = try XCTUnwrap(model.cards.first { $0.id == "forest" })
    let beta = try XCTUnwrap(model.cards.first { $0.id == "beta" })
    model.addCard(forest, toListID: list.id)
    model.addCard(beta, toListID: list.id)

    let forestEntryID = try XCTUnwrap(model.selectedListEntries.first { $0.cardID == forest.id }?.id)
    let betaEntryID = try XCTUnwrap(model.selectedListEntries.first { $0.cardID == beta.id }?.id)
    model.moveCardListEntry(id: betaEntryID, toZone: .sideboard)
    model.setCardListEntryQuantities(ids: [forestEntryID, betaEntryID], quantity: 5)

    XCTAssertEqual(model.selectedList?.ruleset, .modern)
    XCTAssertEqual(model.selectedListEntries.map(\.zone), [.mainboard, .sideboard])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [5, 5])
    XCTAssertEqual(model.selectedList?.entryCount, 10)

    let warningIDs = Set(model.selectedListRulesetWarnings.map(\.id))
    XCTAssertTrue(warningIDs.contains("modern-mainboard-size"))
    XCTAssertTrue(warningIDs.contains("modern-copy-limit-forest-oracle"))
    XCTAssertTrue(warningIDs.contains("modern-copy-limit-beta-oracle"))
  }

  func testModelSavesDescriptionsAndImportsGrimoraArchives() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "Archive Source", selectAfterCreate: true))
    let category = try XCTUnwrap(model.createCardListCategory(named: "Ramp"))
    let forest = try XCTUnwrap(model.cards.first { $0.id == "forest" })
    model.addCard(forest, toListID: list.id)
    model.addCard(forest, toListID: list.id)
    try database.appendCard("missing-print", toList: list.id, categoryID: category.id)
    model.saveCardListDescription(
      forListID: list.id,
      rtfdData: Data([0x10, 0x20, 0x30]),
      plainText: "Mulligan notes"
    )
    model.setCardListDashboardVisibility(id: list.id, showsDashboard: false)
    model.setCardListDashboardIncludesLands(id: list.id, includesLands: true)
    model.setCardListDisplaySort(id: list.id, mode: .edhrecRank, direction: .descending)
    model.setCardListViewMode(id: list.id, mode: .list)
    model.selectCardList(id: list.id)

    let sourceList = try XCTUnwrap(model.selectedList)
    let export = CardListExporter.export(
      list: sourceList,
      entries: model.selectedListEntries,
      categories: model.selectedListCategories,
      configuration: CardListExportConfiguration(format: .grimoraArchive)
    )
    let archiveData = try XCTUnwrap(export.data)

    let summary = try XCTUnwrap(model.importCardListArchive(data: archiveData))
    XCTAssertEqual(summary.listName, "Archive Source")
    XCTAssertEqual(summary.cardCount, 3)
    XCTAssertEqual(summary.categoryCount, 1)
    XCTAssertEqual(summary.missingCardIDs, ["missing-print"])

    XCTAssertEqual(model.cardLists.map(\.name), ["Favourites", "Archive Source", "Archive Source"])
    XCTAssertEqual(model.selectedList?.descriptionRTFDData, Data([0x10, 0x20, 0x30]))
    XCTAssertEqual(model.selectedList?.descriptionPlainText, "Mulligan notes")
    XCTAssertEqual(model.selectedList?.showsDashboard, false)
    XCTAssertEqual(model.selectedList?.dashboardIncludesLands, true)
    XCTAssertEqual(model.selectedList?.displaySortMode, .edhrecRank)
    XCTAssertEqual(model.selectedList?.displaySortDirection, .descending)
    XCTAssertEqual(model.selectedList?.viewMode, .list)
    XCTAssertEqual(model.selectedListCategories.map(\.name), ["Ramp"])
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["forest", "missing-print"])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [2, 1])
    XCTAssertNil(model.selectedListEntries.last?.card)
  }

  func testModelCreatesListFromArchidektTextAndReportsSkippedLines() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let importResult = await model.createCardListFromArchidektSource(
      """
      2x Alpha Forest (abc) 1 [Ramp] ^Have,#37d67a^
      1x Beta Mage (abc) 2 *F* [Removal] ^Have,#37d67a^
      1x Missing Card (abc) 999 [Core] ^Have,#37d67a^
      malformed line
      """,
      named: "Imported Deck"
    )
    let summary = try XCTUnwrap(importResult)

    XCTAssertEqual(summary.listName, "Imported Deck")
    XCTAssertEqual(summary.cardCount, 3)
    XCTAssertEqual(summary.categoryCount, 2)
    XCTAssertEqual(summary.skippedLines.count, 2)
    XCTAssertEqual(model.selectedList?.name, "Imported Deck")
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["forest", "beta"])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [2, 1])
    XCTAssertEqual(model.selectedListCategories.map(\.name), ["Ramp", "Removal"])
    XCTAssertEqual(model.selectedListCategories.map(\.entryCount), [2, 1])
    XCTAssertEqual(model.statusMessage, "Imported 3 cards into Imported Deck. 2 skipped.")
  }

  func testModelAppendsArchidektTextAndReusesCategoriesWithQuantities() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "Deck", selectAfterCreate: true))
    let ramp = try XCTUnwrap(model.createCardListCategory(named: "Ramp", inListID: list.id))

    let text = """
      1x Alpha Forest (abc) 1 [ramp] ^Have,#37d67a^
      1x Beta Mage (abc) 2 [Ramp,Removal] ^Have,#37d67a^
      """
    let firstImportResult = await model.importArchidektCards(from: text, intoListID: list.id)
    let secondImportResult = await model.importArchidektCards(from: text, intoListID: list.id)
    let firstImport = try XCTUnwrap(firstImportResult)
    let secondImport = try XCTUnwrap(secondImportResult)

    XCTAssertEqual(firstImport.cardCount, 2)
    XCTAssertEqual(secondImport.cardCount, 2)
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["forest", "beta"])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [2, 2])
    XCTAssertEqual(model.selectedListCategories.map(\.name), ["Ramp"])
    XCTAssertEqual(model.selectedListCategories.first?.id, ramp.id)
    XCTAssertEqual(model.selectedListCategories.first?.entryCount, 4)
  }

  func testModelImportsArchidektCommanderZonesWithoutSideboard() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let model = GrimoraAppModel(environment: environment(database: database))
    await model.drainSearchForTesting()

    let list = try XCTUnwrap(model.createCardList(named: "Commander Deck", selectAfterCreate: true))
    model.setCardListRuleset(id: list.id, ruleset: .commander)

    let importResult = await model.importArchidektCards(
      from: """
        1x Alpha Forest (abc) 1 [Commander] ^Have,#37d67a^
        1x Beta Mage (abc) 2 [Sideboard,Ramp] ^Have,#37d67a^
        1x Soldier Token (tok) 1 [Maybeboard] ^Have,#37d67a^
        """,
      intoListID: list.id
    )
    let summary = try XCTUnwrap(importResult)

    XCTAssertEqual(summary.cardCount, 3)
    XCTAssertEqual(summary.categoryCount, 1)
    XCTAssertEqual(model.selectedList?.ruleset, .commander)
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["forest", "beta", "token"])
    XCTAssertEqual(model.selectedListEntries.map(\.zone), [.commander, .mainboard, .maybeboard])
    XCTAssertEqual(model.selectedListCategories.map(\.name), ["Ramp"])
    XCTAssertEqual(model.selectedListCategories.map(\.zone), [.mainboard])
  }

  func testModelImportsArchidektDeckURLUsingMockedDeckResponse() async throws {
    let database = try CardDatabase(storage: .inMemory)
    try database.replaceAllCards(uiRecords())
    try markLibraryReady(database)
    let deckURL = URL(string: "https://archidekt.com/api/decks/21928855/")!
    let network = ModelTestNetworkClient(dataResponses: [
      deckURL: Data(
        """
        {
          "name": "Knives and Forks",
          "cards": [
            {
              "quantity": 2,
              "categories": ["Commander"],
              "card": {
                "uid": "forest",
                "collectorNumber": "1",
                "edition": { "editioncode": "abc" },
                "oracleCard": { "name": "Alpha Forest" }
              }
            }
          ]
        }
        """.utf8)
    ])
    let model = GrimoraAppModel(environment: environment(database: database, network: network))
    await model.drainSearchForTesting()

    let importResult = await model.createCardListFromArchidektSource(
      "https://archidekt.com/decks/21928855/knives_and_forks"
    )
    let summary = try XCTUnwrap(importResult)

    XCTAssertEqual(summary.listName, "Knives and Forks")
    XCTAssertEqual(summary.sourceName, "Knives and Forks")
    XCTAssertEqual(summary.cardCount, 2)
    XCTAssertEqual(summary.categoryCount, 0)
    XCTAssertEqual(model.selectedListEntries.map(\.cardID), ["forest"])
    XCTAssertEqual(model.selectedListEntries.map(\.quantity), [2])
    XCTAssertEqual(model.selectedListEntries.map(\.zone), [.mainboard])
    XCTAssertTrue(model.selectedListCategories.isEmpty)
  }

  func testLoadValueGuideReadsLocalMTGJSONSummaryForSelectedCard() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let card = valueTestCard(id: "scry-one", name: "Value Spell")
    try database.replaceAllCards([card])
    try await seedValueHistory(in: database, cardID: "scry-one", uuid: "uuid-one")

    let model = GrimoraAppModel(environment: environment(database: database))
    model.selectCard(card)
    await model.loadValueGuide(for: card)

    let guide = try XCTUnwrap(model.selectedCardValueGuide)
    XCTAssertEqual(guide.entries.map(\.finish), [.normal])
    let entry = try XCTUnwrap(guide.entries.first)
    XCTAssertEqual(entry.currentPrice, 2.50)
    XCTAssertEqual(try XCTUnwrap(entry.oneDay).delta, 0.50, accuracy: 0.0001)
  }

  func testSelectingDifferentCardResetsSelectedCardValueGuide() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let valueCard = valueTestCard(id: "scry-one", name: "Value Spell")
    let otherCard = valueTestCard(id: "scry-two", name: "Other Spell")
    try database.replaceAllCards([valueCard, otherCard])
    try await seedValueHistory(in: database, cardID: valueCard.id, uuid: "uuid-one")

    let model = GrimoraAppModel(environment: environment(database: database))
    model.selectCard(valueCard)
    await model.loadValueGuide(for: valueCard)
    XCTAssertNotNil(model.selectedCardValueGuide)

    model.selectCard(otherCard)

    XCTAssertNil(model.selectedCardValueGuide)
  }

  func testStaleValueGuideLoadDoesNotOverwriteSelection() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let valueCard = valueTestCard(id: "scry-one", name: "Value Spell")
    let otherCard = valueTestCard(id: "scry-two", name: "Other Spell")
    try database.replaceAllCards([valueCard, otherCard])
    try await seedValueHistory(in: database, cardID: valueCard.id, uuid: "uuid-one")

    let model = GrimoraAppModel(environment: environment(database: database))
    model.selectCard(valueCard)
    model.selectCard(otherCard)
    await model.loadValueGuide(for: valueCard)

    XCTAssertEqual(model.selectedCard?.id, otherCard.id)
    XCTAssertNil(model.selectedCardValueGuide)
  }

  func testValueGuideLoadReturnsUnavailableGuideWhenDatabaseReadFails() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let card = valueTestCard(id: "scry-one", name: "Value Spell")
    try database.replaceAllCards([card])
    try database.database.execute("DROP TABLE card_value_summaries")

    let model = GrimoraAppModel(environment: environment(database: database))
    model.selectCard(card)
    await model.loadValueGuide(for: card)

    let guide = try XCTUnwrap(model.selectedCardValueGuide)
    XCTAssertEqual(guide.cardID, card.id)
    XCTAssertFalse(guide.isAvailable)
  }

  func testValueGuideLoadingUsesLocalDatabaseWithoutPricingNetworkCalls() async throws {
    let database = try CardDatabase(storage: .inMemory)
    let card = valueTestCard(id: "scry-one", name: "Value Spell")
    try database.replaceAllCards([card])
    try await seedValueHistory(in: database, cardID: card.id, uuid: "uuid-one")
    let network = ModelTestNetworkClient(dataResponses: [:])

    let model = GrimoraAppModel(environment: environment(database: database, network: network))
    model.selectCard(card)
    await model.loadValueGuide(for: card)

    XCTAssertNotNil(model.selectedCardValueGuide)
    let requests = await network.requests()
    XCTAssertTrue(requests.isEmpty)
  }

  func testPriceHistoryStatusSuffixesDescribeImportResults() throws {
    let database = try CardDatabase(storage: .inMemory)
    let model = GrimoraAppModel(environment: environment(database: database))

    XCTAssertEqual(model.priceHistoryStatusSuffix(for: .notConfigured), "")
    XCTAssertEqual(model.priceHistoryStatusSuffix(for: .skipped), " Value history is current.")
    XCTAssertEqual(
      model.priceHistoryStatusSuffix(
        for: .imported(MTGJSONPriceImportSummary(mappedCards: 2, importedPricePoints: 7))
      ),
      " Indexed 7 value points."
    )
    XCTAssertEqual(
      model.priceHistoryStatusSuffix(for: .failed),
      " Value history could not be updated; card search is ready."
    )
  }

  private func valueTestCard(id: String, name: String) -> CardRecord {
    CardRecord(
      id: id,
      name: name,
      setCode: "tst",
      setName: "Test Set",
      setType: "expansion",
      collectorNumber: "1",
      rarity: "rare",
      colorSortKey: 0,
      layout: "normal",
      typeLine: "Instant",
      oracleText: ""
    )
  }

  private func seedValueHistory(in database: CardDatabase, cardID: String, uuid: String) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let printingsURL = directory.appendingPathComponent("AllPrintings.json")
    let pricesURL = directory.appendingPathComponent("AllPrices.json")
    try Data("""
    {
      "data": {
        "TST": {
          "cards": [
            {"uuid": "\(uuid)", "identifiers": {"scryfallId": "\(cardID)"}}
          ]
        }
      }
    }
    """.utf8).write(to: printingsURL, options: .atomic)
    try Data("""
    {
      "data": {
        "\(uuid)": {
          "paper": {
            "tcgplayer": {
              "retail": {
                "normal": {
                  "2026-03-31": 2.00,
                  "2026-04-01": 2.50
                }
              }
            }
          }
        }
      }
    }
    """.utf8).write(to: pricesURL, options: .atomic)

    let importer = MTGJSONPriceHistoryImporter(database: database)
    _ = try await importer.importHistory(
      meta: MTGJSONPriceHistoryMeta(date: "2026-05-13", version: "5.2.1"),
      allPrintingsJSONURL: printingsURL,
      allPricesJSONURL: pricesURL
    )
  }

  private func valueHistoryNetworkResponses(
    cardID: String,
    uuid: String? = nil,
    price: Double = 3.25,
    fullHistoryPrice: Double? = nil
  ) -> [URL: Data] {
    let uuid = uuid ?? "uuid-\(cardID)"
    return [
      MTGJSONPriceHistoryClient.metaURL: modelValueHistoryMetaJSON(),
      MTGJSONPriceHistoryClient.allPrintingsURL: modelGzipData(
        modelValueHistoryPrintingsJSON(cardID: cardID, uuid: uuid)
      ),
      MTGJSONPriceHistoryClient.allPricesTodayURL: modelGzipData(
        modelValueHistoryPricesJSON(uuid: uuid, price: price)
      ),
      MTGJSONPriceHistoryClient.allPricesURL: modelGzipData(
        fullHistoryPrice.map { modelValueHistoryPricesJSONWithHistory(uuid: uuid, currentPrice: $0) }
          ?? modelValueHistoryPricesJSON(uuid: uuid, price: price)
      ),
    ]
  }

  private func modelValueHistoryMetaJSON(date: String = "2026-05-13", version: String = "5.2.1")
    -> Data
  {
    Data("""
    {
      "meta": {
        "date": "\(date)",
        "version": "\(version)"
      }
    }
    """.utf8)
  }

  private func modelValueHistoryPrintingsJSON(cardID: String, uuid: String) -> Data {
    Data("""
    {
      "data": {
        "TST": {
          "cards": [
            {"uuid": "\(uuid)", "identifiers": {"scryfallId": "\(cardID)"}}
          ]
        }
      }
    }
    """.utf8)
  }

  private func modelValueHistoryPricesJSON(uuid: String, price: Double) -> Data {
    Data("""
    {
      "data": {
        "\(uuid)": {
          "paper": {
            "tcgplayer": {
              "retail": {
                "normal": {
                  "2026-04-01": \(price)
                }
              }
            }
          }
        }
      }
    }
    """.utf8)
  }

  private func modelValueHistoryPricesJSONWithHistory(uuid: String, currentPrice: Double) -> Data {
    Data("""
    {
      "data": {
        "\(uuid)": {
          "paper": {
            "tcgplayer": {
              "retail": {
                "normal": {
                  "2026-03-01": 2.00,
                  "2026-05-13": \(currentPrice)
                }
              }
            }
          }
        }
      }
    }
    """.utf8)
  }

  private func modelGzipData(_ data: Data) -> Data {
    var output = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
    output.append(0x01)
    let length = UInt16(data.count)
    appendLittleEndian(length, to: &output)
    appendLittleEndian(~length, to: &output)
    output.append(data)
    appendLittleEndian(modelCRC32(data), to: &output)
    appendLittleEndian(UInt32(data.count), to: &output)
    return output
  }

  private func appendLittleEndian(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
  }

  private func appendLittleEndian(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 24) & 0xff))
  }

  private func modelCRC32(_ data: Data) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for index in 0..<256 {
      var value = UInt32(index)
      for _ in 0..<8 {
        if value & 1 == 1 {
          value = 0xedb8_8320 ^ (value >> 1)
        } else {
          value >>= 1
        }
      }
      table[index] = value
    }

    var crc: UInt32 = 0xffff_ffff
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xff)
      crc = table[index] ^ (crc >> 8)
    }
    return crc ^ 0xffff_ffff
  }

  private func environment(
    database: CardDatabase,
    network: NetworkClient = BlockingNetworkClient(),
    importer: LibraryImporter? = nil,
    imageCache: CardImageCache? = nil,
    imageStore: ImageStore? = nil,
    imageDownloadConfiguration: GrimoraImageDownloadConfiguration =
      GrimoraImageDownloadConfiguration(),
    searchPerformanceConfiguration: GrimoraSearchPerformanceConfiguration =
      GrimoraSearchPerformanceConfiguration(textDebounceNanoseconds: 0, prefetchesNextPage: false),
    searchHistoryStore: GrimoraSearchHistoryStore? = nil,
    plainTextSearchHistoryStore: GrimoraSearchHistoryStore? = nil,
    plainTextSearchTranspiler: (any PlainTextSearchTranspiling)? = nil,
    priceHistoryEnabled: Bool = false,
    cloudSyncCoordinator: CloudSyncCoordinator? = nil,
    autoUpdateChecksEnabled: Bool = false
  ) -> GrimoraEnvironment {
    let bulkClient = BulkDataClient(network: network)
    let importer = importer ?? LibraryImporter(database: database, imageResolver: NoImageResolver())
    let imageStore = imageStore ?? ImageStore(
      rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
      )
    )
    let updateService = priceHistoryEnabled
      ? LibraryUpdateService(
        database: database,
        bulkDataClient: bulkClient,
        priceHistoryClient: MTGJSONPriceHistoryClient(network: network),
        priceHistoryImporter: MTGJSONPriceHistoryImporter(database: database)
      )
      : LibraryUpdateService(database: database, bulkDataClient: bulkClient)
    return GrimoraEnvironment(
      database: database,
      updateService: updateService,
      importer: importer,
      imageCache: imageCache
        ?? CardImageCache(database: database, imageResolver: NoImageResolver()),
      imageStore: imageStore,
      archidektDeckClient: ArchidektDeckClient(network: network),
      plainTextSearchTranspiler: plainTextSearchTranspiler
        ?? TestPlainTextSearchTranspiler(response: .failure("No test plain-text search response.")),
      imageDownloadConfiguration: imageDownloadConfiguration,
      searchPerformanceConfiguration: searchPerformanceConfiguration,
      temporaryDirectory: FileManager.default.temporaryDirectory,
      valueHistoryBackgroundDirectory: FileManager.default.temporaryDirectory
        .appendingPathComponent("ValueHistory-\(UUID().uuidString)", isDirectory: true),
      autoUpdateChecksEnabled: autoUpdateChecksEnabled,
      searchHistoryStore: searchHistoryStore ?? isolatedSearchHistoryStore(),
      plainTextSearchHistoryStore: plainTextSearchHistoryStore
        ?? GrimoraSearchHistoryStore(
          userDefaults: isolatedUserDefaults(),
          key: GrimoraSearchPreferences.plainTextSearchHistoryKey
        ),
      cloudSyncCoordinator: cloudSyncCoordinator
    )
  }

  private func isolatedSearchHistoryStore() -> GrimoraSearchHistoryStore {
    GrimoraSearchHistoryStore(userDefaults: isolatedUserDefaults())
  }

  private func isolatedUserDefaults() -> UserDefaults {
    let suiteName = "GrimoraAppModelTests-\(UUID().uuidString)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
      fatalError("Unable to create isolated user defaults suite.")
    }
    userDefaults.removePersistentDomain(forName: suiteName)
    return userDefaults
  }

  private func waitForVisibleImagePhase(
    _ phase: VisibleImageRequestPhase?,
    cardID: CardRecord.ID,
    quality: CardImageQuality,
    in model: GrimoraAppModel,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    let key = VisibleImageRequestKey(cardID: cardID, quality: quality)
    for _ in 0..<100 {
      if model.visibleImageRequestStates[key]?.phase == phase {
        return
      }

      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTFail(
      "Timed out waiting for visible image phase \(String(describing: phase)) for \(cardID).",
      file: file,
      line: line
    )
  }

  private func activityStep(_ id: String, in model: GrimoraAppModel) throws -> GrimoraLibraryActivityStep {
    try XCTUnwrap(model.libraryActivity?.steps.first { $0.id == id })
  }

  private func cards(in database: CardDatabase, matching text: String) throws -> [CardRecord] {
    let response = try database.search(CardSearchRequest(text: text, activeFilters: []))
    guard case .results(let cards, _) = response else {
      return []
    }
    return cards
  }

  private func markLibraryReady(_ database: CardDatabase) throws {
    try database.saveMetadataValue(
      "2026-04-25T09:09:59.477+00:00", forKey: MetadataKey.defaultCardsUpdatedAt.rawValue)
    try database.saveMetadataValue(
      CardDatabase.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
    try database.saveMetadataValue("true", forKey: MetadataKey.requiredImagesCached.rawValue)
  }

  private func manifestListJSON(downloadURL: URL) -> Data {
    Data(
      """
      {
        "object": "list",
        "has_more": false,
        "data": [
          {
            "object": "bulk_data",
            "id": "bulk-id",
            "type": "default_cards",
            "updated_at": "2026-04-25T09:09:59.477+00:00",
            "uri": "https://api.scryfall.com/bulk-data/bulk-id",
            "name": "Default Cards",
            "description": "Fixture",
            "size": 123,
            "download_uri": "\(downloadURL.absoluteString)",
            "content_type": "application/json",
            "content_encoding": "gzip"
          }
        ]
      }
      """.utf8)
  }

  private func setupCardsJSON() -> Data {
    Data(
      """
      [
        {
          "object": "card",
          "id": "setup-forest",
          "oracle_id": "setup-oracle",
          "name": "Setup Forest",
          "lang": "en",
          "released_at": "2024-01-01",
          "layout": "normal",
          "cmc": 2,
          "type_line": "Creature",
          "oracle_text": "Reach",
          "colors": ["G"],
          "color_identity": ["G"],
          "games": ["paper"],
          "digital": false,
          "oversized": false,
          "set": "set",
          "set_name": "Setup Set",
          "set_type": "expansion",
          "collector_number": "1",
          "rarity": "common",
          "image_uris": {
            "small": "https://example.test/setup-small.jpg",
            "normal": "https://example.test/setup-normal.jpg",
            "large": "https://example.test/setup-large.jpg"
          }
        }
      ]
      """.utf8)
  }

  private func pagedRecords(count: Int) -> [CardRecord] {
    (0..<count).map { index in
      let number = 1000 + index
      return CardRecord(
        id: "paged-\(number)",
        oracleID: "paged-\(number)",
        name: "Paged Card \(number)",
        releasedAt: "2020-01-01",
        setCode: "pgd",
        setName: "Paged Set",
        setType: "expansion",
        collectorNumber: "\(number)",
        collectorNumberNumber: number,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 0,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Paged sample.",
        isRealCard: true
      )
    }
  }

  private func uiRecords() -> [CardRecord] {
    [
      CardRecord(
        id: "forest",
        name: "Alpha Forest",
        releasedAt: "2020-01-01",
        setCode: "abc",
        setName: "Alpha Set",
        setType: "expansion",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        artist: "Zed Artist",
        colorSortKey: 0,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Forest sample.",
        isRealCard: true
      ),
      CardRecord(
        id: "beta",
        name: "Beta Mage",
        releasedAt: "2020-01-02",
        setCode: "abc",
        setName: "Alpha Set",
        setType: "expansion",
        collectorNumber: "2",
        collectorNumberNumber: 2,
        rarity: "rare",
        rarityRank: 2,
        artist: "Amy Artist",
        colorSortKey: 1,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Mage sample.",
        isRealCard: true
      ),
      CardRecord(
        id: "alchemy",
        name: "Digital Conjurer",
        releasedAt: "2020-01-03",
        setCode: "yabc",
        setName: "Alchemy Set",
        setType: "alchemy",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "rare",
        rarityRank: 2,
        colorSortKey: 2,
        layout: "normal",
        typeLine: "Creature",
        oracleText: "Conjure.",
        isAlchemy: true,
        isRealCard: false
      ),
      CardRecord(
        id: "token",
        name: "Soldier Token",
        releasedAt: "2020-01-04",
        setCode: "tok",
        setName: "Token Set",
        setType: "token",
        collectorNumber: "1",
        collectorNumberNumber: 1,
        rarity: "common",
        rarityRank: 0,
        colorSortKey: 0,
        layout: "token",
        typeLine: "Token Creature",
        oracleText: "",
        isRealCard: false
      ),
    ]
  }
}
