import XCTest

@testable import GrimoraUI

#if os(macOS)
  import AppKit

  final class LocalCardImageLoaderTests: XCTestCase {
    override func setUp() {
      super.setUp()
      LocalCardImageLoader.shared.configure(
        countLimit: 2_048,
        totalCostLimit: 512 * 1_024 * 1_024,
        preloadConcurrency: 2
      )
      LocalCardImageLoader.shared.clearForTesting()
    }

    func testLoaderReturnsCachedImageAfterFileIsRemoved() async throws {
      let imageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("png")
      try makeFixtureImage(at: imageURL)

      let first = await LocalCardImageLoader.shared.image(atPath: imageURL.path)
      XCTAssertNotNil(first)

      try FileManager.default.removeItem(at: imageURL)

      let second = await LocalCardImageLoader.shared.image(atPath: imageURL.path)
      XCTAssertNotNil(second)
    }

    func testCachedImageLookupIsSynchronousAfterDecode() async throws {
      let imageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("png")
      try makeFixtureImage(at: imageURL)

      XCTAssertNil(LocalCardImageLoader.shared.cachedImage(atPath: imageURL.path))

      let loaded = await LocalCardImageLoader.shared.image(atPath: imageURL.path)
      XCTAssertNotNil(loaded)
      XCTAssertNotNil(LocalCardImageLoader.shared.cachedImage(atPath: imageURL.path))
    }

    func testCacheEvictsLeastRecentlyUsedImageWhenCountLimitIsExceeded() async throws {
      LocalCardImageLoader.shared.configure(
        countLimit: 2,
        totalCostLimit: 512 * 1_024 * 1_024,
        preloadConcurrency: 2
      )
      let imageURLs = try (0..<3).map { _ in
        let url = FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString)
          .appendingPathExtension("png")
        try makeFixtureImage(at: url)
        return url
      }

      for url in imageURLs.prefix(2) {
        let image = await LocalCardImageLoader.shared.image(atPath: url.path)
        XCTAssertNotNil(image)
      }
      XCTAssertNotNil(LocalCardImageLoader.shared.cachedImage(atPath: imageURLs[0].path))
      let thirdImage = await LocalCardImageLoader.shared.image(atPath: imageURLs[2].path)
      XCTAssertNotNil(thirdImage)

      XCTAssertNotNil(LocalCardImageLoader.shared.cachedImage(atPath: imageURLs[0].path))
      XCTAssertNil(LocalCardImageLoader.shared.cachedImage(atPath: imageURLs[1].path))
      XCTAssertNotNil(LocalCardImageLoader.shared.cachedImage(atPath: imageURLs[2].path))
      XCTAssertEqual(LocalCardImageLoader.shared.cachedPathCountForTesting(), 2)
    }

    func testRepeatedCacheHitsKeepEntryMostRecentlyUsed() async throws {
      LocalCardImageLoader.shared.configure(
        countLimit: 2,
        totalCostLimit: 512 * 1_024 * 1_024,
        preloadConcurrency: 2
      )
      let imageURLs = try (0..<3).map { _ in
        let url = FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString)
          .appendingPathExtension("png")
        try makeFixtureImage(at: url)
        return url
      }

      for url in imageURLs.prefix(2) {
        let image = await LocalCardImageLoader.shared.image(atPath: url.path)
        XCTAssertNotNil(image)
      }
      // Touch the first entry repeatedly so it is unambiguously the most recently used.
      for _ in 0..<5 {
        XCTAssertNotNil(LocalCardImageLoader.shared.cachedImage(atPath: imageURLs[0].path))
      }
      let thirdImage = await LocalCardImageLoader.shared.image(atPath: imageURLs[2].path)
      XCTAssertNotNil(thirdImage)

      XCTAssertNotNil(LocalCardImageLoader.shared.cachedImage(atPath: imageURLs[0].path))
      XCTAssertNil(LocalCardImageLoader.shared.cachedImage(atPath: imageURLs[1].path))
      XCTAssertNotNil(LocalCardImageLoader.shared.cachedImage(atPath: imageURLs[2].path))
      XCTAssertEqual(LocalCardImageLoader.shared.cachedPathCountForTesting(), 2)
    }

    func testCacheEvictsImagesWhenCostLimitIsExceeded() async throws {
      LocalCardImageLoader.shared.configure(
        countLimit: 100,
        totalCostLimit: 3_000,
        preloadConcurrency: 2
      )
      let imageURLs = try (0..<2).map { _ in
        let url = FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString)
          .appendingPathExtension("png")
        try makeFixtureImage(at: url)
        return url
      }

      for url in imageURLs {
        let image = await LocalCardImageLoader.shared.image(atPath: url.path)
        XCTAssertNotNil(image)
      }

      XCTAssertLessThanOrEqual(LocalCardImageLoader.shared.cachedPathCountForTesting(), 1)
    }

    func testPreloadWarmsDecodedImageCache() async throws {
      let imageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("png")
      try makeFixtureImage(at: imageURL)

      await LocalCardImageLoader.shared.preload(paths: [imageURL.path, imageURL.path])
      try FileManager.default.removeItem(at: imageURL)

      let image = await LocalCardImageLoader.shared.image(atPath: imageURL.path)
      XCTAssertNotNil(image)
    }

    func testPreloadSkipsAlreadyCachedPaths() async throws {
      let imageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("png")
      try makeFixtureImage(at: imageURL)

      XCTAssertEqual(
        LocalCardImageLoader.shared.uncachedPaths(from: [imageURL.path, imageURL.path]),
        [imageURL.path]
      )

      await LocalCardImageLoader.shared.preload(paths: [imageURL.path, imageURL.path])

      XCTAssertTrue(
        LocalCardImageLoader.shared.uncachedPaths(from: [imageURL.path, imageURL.path]).isEmpty)
    }

    func testLoaderAcceptsFileURLStrings() async throws {
      let imageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("png")
      try makeFixtureImage(at: imageURL)

      let image = await LocalCardImageLoader.shared.image(atPath: imageURL.absoluteString)

      XCTAssertNotNil(image)
    }

    private func makeFixtureImage(at url: URL) throws {
      let size = NSSize(width: 20, height: 28)
      let image = NSImage(size: size)
      image.lockFocus()
      NSColor.systemBlue.setFill()
      NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
      image.unlockFocus()

      guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let data = rep.representation(using: .png, properties: [:])
      else {
        throw NSError(domain: "LocalCardImageLoaderTests", code: 1)
      }

      try data.write(to: url, options: .atomic)
    }
  }
#endif
