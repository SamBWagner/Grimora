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

    /// The macOS off-main decode rasterises the scan by hand (AppKit has no `preparingForDisplay()`),
    /// which is the kind of thing that silently flips or colour-shifts an image. Load the same file
    /// raw and through the loader (decoded) and assert the two rasterise to identical pixels, so a
    /// flip or colour regression fails here rather than in the UI.
    func testDecodePreservesImageOrientationAndColor() async throws {
      let imageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("png")
      try makeCornerPatternImage(at: imageURL)

      let raw = try XCTUnwrap(NSImage(contentsOfFile: imageURL.path))
      LocalCardImageLoader.shared.clearForTesting()
      let decodedImage = await LocalCardImageLoader.shared.image(atPath: imageURL.path)
      let decoded = try XCTUnwrap(decodedImage)

      let rawPixels = try XCTUnwrap(rasterizedRGBA(raw))
      let decodedPixels = try XCTUnwrap(rasterizedRGBA(decoded))
      XCTAssertEqual(rawPixels.count, decodedPixels.count)

      let maxDelta = zip(rawPixels, decodedPixels).reduce(0) { partial, pair in
        max(partial, abs(Int(pair.0) - Int(pair.1)))
      }
      XCTAssertLessThanOrEqual(
        maxDelta, 2, "decoded image differs from the original — flip or color regression")
    }

    /// Draws `image` into a fixed 16×16 device-RGB buffer and returns its raw RGBA bytes.
    private func rasterizedRGBA(_ image: NSImage) -> [UInt8]? {
      let dimension = 16
      guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
      }
      var buffer = [UInt8](repeating: 0, count: dimension * dimension * 4)
      let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress,
          let context = CGContext(
            data: base,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: dimension * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
        else {
          return false
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
        return true
      }
      return drew ? buffer : nil
    }

    /// A 16×16 PNG whose four quadrants are distinct opaque colors, so any flip/rotation of the
    /// decoded copy shows up as a pixel mismatch.
    private func makeCornerPatternImage(at url: URL) throws {
      let size = NSSize(width: 16, height: 16)
      let image = NSImage(size: size)
      image.lockFocus()
      NSColor.red.setFill()
      NSRect(x: 0, y: 8, width: 8, height: 8).fill()
      NSColor.green.setFill()
      NSRect(x: 8, y: 8, width: 8, height: 8).fill()
      NSColor.blue.setFill()
      NSRect(x: 0, y: 0, width: 8, height: 8).fill()
      NSColor.yellow.setFill()
      NSRect(x: 8, y: 0, width: 8, height: 8).fill()
      image.unlockFocus()

      guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let data = rep.representation(using: .png, properties: [:])
      else {
        throw NSError(domain: "LocalCardImageLoaderTests", code: 1)
      }

      try data.write(to: url, options: .atomic)
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
