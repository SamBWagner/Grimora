import Foundation
import SwiftUI

#if os(macOS)
  @preconcurrency import AppKit
#elseif os(iOS) || os(visionOS)
  @preconcurrency import UIKit
#endif

struct LocalCardImage: View {
  @Environment(\.colorScheme) private var colorScheme
  @State private var platformImage: PlatformImage?
  @State private var loadState = LocalCardImageLoadState.idle

  var path: String?
  var cornerRadius: CGFloat = 8
  var contentMode: LocalCardImageContentMode = .fit
  var accessibilityHidden = true
  var onImageSizeChange: ((CGSize) -> Void)? = nil

  init(
    path: String?,
    cornerRadius: CGFloat = 8,
    contentMode: LocalCardImageContentMode = .fit,
    accessibilityHidden: Bool = true,
    onImageSizeChange: ((CGSize) -> Void)? = nil
  ) {
    self.path = path
    self.cornerRadius = cornerRadius
    self.contentMode = contentMode
    self.accessibilityHidden = accessibilityHidden
    self.onImageSizeChange = onImageSizeChange
    _platformImage = State(initialValue: LocalCardImageLoader.shared.cachedImage(atPath: path))
  }

  var body: some View {
    let clipShape = CardArtClipShape(minimumRadius: cornerRadius)
    Group {
      if let image = platformImage {
        imageView(image)
      } else {
        clipShape
          .fill(palette.placeholderFill.color)
          .overlay {
            placeholderContent
          }
          .overlay {
            clipShape
              .stroke(palette.hairline.color, lineWidth: 1)
          }
      }
    }
    .clipShape(clipShape)
    .accessibilityHidden(accessibilityHidden)
    .task(id: path) {
      guard let path else {
        platformImage = nil
        loadState = .idle
        return
      }

      if let cachedImage = LocalCardImageLoader.shared.cachedImage(atPath: path) {
        platformImage = cachedImage
        loadState = .loaded
        onImageSizeChange?(Self.size(of: cachedImage))
        return
      }

      platformImage = nil
      loadState = .loading

      for attempt in 0...Self.loadRetryCount {
        let image = await LocalCardImageLoader.shared.image(atPath: path)
        guard !Task.isCancelled else {
          return
        }

        if let image {
          platformImage = image
          loadState = .loaded
          onImageSizeChange?(Self.size(of: image))
          return
        }

        guard attempt < Self.loadRetryCount else {
          break
        }

        do {
          try await Task.sleep(nanoseconds: Self.loadRetryDelayNanoseconds)
        } catch {
          return
        }
      }

      loadState = .failed
    }
  }

  private static let loadRetryCount = 1
  private static let loadRetryDelayNanoseconds: UInt64 = 120_000_000

  private var palette: GrimoraPalette {
    GrimoraPalette(colorScheme: colorScheme)
  }

  @ViewBuilder
  private var placeholderContent: some View {
    if loadState == .loading {
      ProgressView()
        .controlSize(.small)
        .tint(palette.accent.color)
    } else {
      Image(systemName: "rectangle.portrait")
        .font(.largeTitle)
        .foregroundStyle(palette.secondaryText.color)
    }
  }

  @ViewBuilder
  private func imageView(_ image: PlatformImage) -> some View {
    #if os(macOS)
      let image = Image(nsImage: image)
        .resizable()
    #elseif os(iOS) || os(visionOS)
      let image = Image(uiImage: image)
        .resizable()
    #endif

    switch contentMode {
    case .fit:
      image.scaledToFit()
    case .fill:
      image.scaledToFill()
    }
  }

  private static func size(of image: PlatformImage) -> CGSize {
    #if os(macOS)
      image.size
    #elseif os(iOS) || os(visionOS)
      image.size
    #endif
  }
}

enum LocalCardImageContentMode {
  case fit
  case fill
}

/// A rounded rectangle that masks card art with a *circular* corner matching a
/// Magic card's true (round) die-cut, rather than a `.continuous` squircle. A
/// continuous corner dips inward less along the diagonal, which exposes the
/// scan's white background corner — the source of the "white fringing" on tiles.
///
/// The radius is the larger of `minimumRadius` (the caller's design radius, so
/// small art still nests inside surrounding chrome) and a fixed fraction of the
/// art's short side (so large/detail art rounds enough to clip the scan corner).
struct CardArtClipShape: Shape {
  /// Fraction of a card image's short side taken up by its printed corner radius.
  /// Magic card scans from Scryfall are rectangular and leave a small white
  /// triangle in each corner, outside the card's rounded die-cut. Measured from
  /// modern scans the arc radius is ~0.029 of the width; this is set a touch
  /// higher so a circular clip always reaches *past* that white corner across
  /// card eras (older cards have a less aggressive radius) and display sizes.
  static let cardCornerRadiusFraction: CGFloat = 0.04

  var minimumRadius: CGFloat
  var radiusFraction: CGFloat = CardArtClipShape.cardCornerRadiusFraction

  func path(in rect: CGRect) -> Path {
    let radius = cardArtClipRadius(
      forShortSide: min(rect.width, rect.height),
      minimumRadius: minimumRadius,
      fraction: radiusFraction
    )
    return RoundedRectangle(cornerRadius: radius, style: .circular).path(in: rect)
  }
}

/// Resolves the corner radius used to mask card art. Factored out as a pure
/// function so the radius policy can be unit-tested without rendering a view.
func cardArtClipRadius(
  forShortSide shortSide: CGFloat,
  minimumRadius: CGFloat,
  fraction: CGFloat = CardArtClipShape.cardCornerRadiusFraction
) -> CGFloat {
  let floor = max(0, minimumRadius)
  guard shortSide.isFinite, shortSide > 0, fraction > 0 else {
    return floor
  }

  return max(floor, shortSide * fraction)
}

#if os(macOS)
  typealias PlatformImage = NSImage
#elseif os(iOS) || os(visionOS)
  typealias PlatformImage = UIImage
#endif

private enum LocalCardImageLoadState {
  case idle
  case loading
  case loaded
  case failed
}

final class LocalCardImageLoader: @unchecked Sendable {
  static let shared = LocalCardImageLoader()

  private let lock = NSLock()
  private var cache: [String: PlatformImageBox] = [:]
  private var accessOrder: [String] = []
  private var inFlightLoads: [String: Task<PlatformImageBox?, Never>] = [:]
  private var totalCost = 0
  private var countLimit: Int
  private var totalCostLimit: Int
  private var preloadConcurrency: Int

  init(
    countLimit: Int = 2_048,
    totalCostLimit: Int = 512 * 1_024 * 1_024,
    preloadConcurrency: Int = 2
  ) {
    self.countLimit = max(1, countLimit)
    self.totalCostLimit = max(1, totalCostLimit)
    self.preloadConcurrency = max(1, preloadConcurrency)
  }

  func configure(
    countLimit: Int,
    totalCostLimit: Int,
    preloadConcurrency: Int
  ) {
    lock.withLock {
      self.countLimit = max(1, countLimit)
      self.totalCostLimit = max(1, totalCostLimit)
      self.preloadConcurrency = max(1, preloadConcurrency)
      pruneIfNeeded()
    }
  }

  func cachedImage(atPath path: String?) -> PlatformImage? {
    guard let path else {
      return nil
    }

    return cachedBox(forFilePath: Self.fileSystemPath(from: path))?.image
  }

  func image(atPath path: String?) async -> PlatformImage? {
    guard let path else {
      return nil
    }
    guard !Task.isCancelled else {
      return nil
    }

    let filePath = Self.fileSystemPath(from: path)
    if let cached = cachedBox(forFilePath: filePath) {
      return cached.image
    }

    let task = loadTask(forFilePath: filePath)
    let box = await task.value
    if let box {
      store(box, forFilePath: filePath)
    }
    clearInFlightLoad(forFilePath: filePath)

    return box?.image
  }

  func preload(paths: [String]) async {
    let pathsToPreload = uncachedPaths(from: paths)
    guard !pathsToPreload.isEmpty, !Task.isCancelled else {
      return
    }

    let concurrency = currentPreloadConcurrency()
    await withTaskGroup(of: Void.self) { group in
      var iterator = pathsToPreload.makeIterator()
      for _ in 0..<concurrency {
        guard let path = iterator.next() else {
          break
        }
        group.addTask {
          guard !Task.isCancelled else {
            return
          }
          _ = await self.image(atPath: path)
        }
      }

      while await group.next() != nil {
        guard !Task.isCancelled else {
          group.cancelAll()
          return
        }
        guard let path = iterator.next() else {
          continue
        }
        group.addTask {
          guard !Task.isCancelled else {
            return
          }
          _ = await self.image(atPath: path)
        }
      }
    }
  }

  func uncachedPaths(from paths: [String]) -> [String] {
    var seenPaths: Set<String> = []
    return paths.filter { path in
      let filePath = Self.fileSystemPath(from: path)
      guard seenPaths.insert(filePath).inserted else {
        return false
      }

      return cachedBox(forFilePath: filePath) == nil
    }
  }

  func clear() {
    lock.withLock {
      cache.removeAll()
      accessOrder.removeAll()
      totalCost = 0
      inFlightLoads.removeAll()
    }
  }

  func clearForTesting() {
    clear()
  }

  func cachedPathCountForTesting() -> Int {
    lock.withLock {
      cache.count
    }
  }

  func isCachedForTesting(path: String) -> Bool {
    cachedImage(atPath: path) != nil
  }

  static func fileSystemPath(from storedPath: String) -> String {
    guard let url = URL(string: storedPath), url.isFileURL else {
      return storedPath
    }

    return url.path
  }

  private func cachedBox(forFilePath filePath: String) -> PlatformImageBox? {
    lock.withLock {
      guard let box = cache[filePath] else {
        return nil
      }

      markRecentlyUsed(filePath)
      return box
    }
  }

  private func loadTask(forFilePath filePath: String) -> Task<PlatformImageBox?, Never> {
    lock.withLock {
      if let task = inFlightLoads[filePath] {
        return task
      }

      let task = Task.detached(priority: .utility) {
        PlatformImage(contentsOfFile: filePath).map { image in
          PlatformImageBox(image: image, cost: Self.estimatedCost(of: image))
        }
      }
      inFlightLoads[filePath] = task
      return task
    }
  }

  private func clearInFlightLoad(forFilePath filePath: String) {
    lock.withLock {
      inFlightLoads[filePath] = nil
    }
  }

  private func store(_ box: PlatformImageBox, forFilePath filePath: String) {
    lock.withLock {
      if let existing = cache[filePath] {
        totalCost -= existing.cost
      }
      cache[filePath] = box
      totalCost += box.cost
      markRecentlyUsed(filePath)
      pruneIfNeeded()
    }
  }

  private func markRecentlyUsed(_ filePath: String) {
    accessOrder.removeAll { $0 == filePath }
    accessOrder.insert(filePath, at: 0)
  }

  private func pruneIfNeeded() {
    while cache.count > countLimit || totalCost > totalCostLimit {
      guard let path = accessOrder.popLast() else {
        cache.removeAll()
        totalCost = 0
        return
      }
      if let removed = cache.removeValue(forKey: path) {
        totalCost -= removed.cost
      }
    }
  }

  private func currentPreloadConcurrency() -> Int {
    lock.withLock {
      preloadConcurrency
    }
  }

  private static func estimatedCost(of image: PlatformImage) -> Int {
    #if os(macOS)
      let pixelCount = image.representations.reduce(0) { partial, representation in
        max(partial, representation.pixelsWide * representation.pixelsHigh)
      }
      let fallbackPixels = Int(max(1, image.size.width) * max(1, image.size.height))
      return max(1, max(pixelCount, fallbackPixels) * 4)
    #elseif os(iOS) || os(visionOS)
      let pixels = Int(max(1, image.size.width * image.scale) * max(1, image.size.height * image.scale))
      return max(1, pixels * 4)
    #endif
  }
}

enum VisibleImageCacheTaskDeferral {
  static func waitBeforeStarting() async -> Bool {
    #if os(iOS) || os(visionOS)
      do {
        try await Task.sleep(nanoseconds: 180_000_000)
      } catch {
        return false
      }
      return !Task.isCancelled
    #else
      return !Task.isCancelled
    #endif
  }
}

private final class PlatformImageBox: @unchecked Sendable {
  let image: PlatformImage
  let cost: Int

  init(image: PlatformImage, cost: Int) {
    self.image = image
    self.cost = cost
  }
}

private extension NSLock {
  func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
    lock()
    defer { unlock() }
    return try body()
  }
}
