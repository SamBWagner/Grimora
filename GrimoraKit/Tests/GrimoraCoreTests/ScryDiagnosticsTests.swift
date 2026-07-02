#if canImport(Vision)
@testable import GrimoraCore
import CoreGraphics
import ImageIO
import XCTest

/// Developer diagnostics, skipped unless their env var is set. Point them at a
/// reported failing photo to see what the pipeline reads before deciding what
/// (parser rule, threshold, corpus entry) needs to change.
///
/// - `SCRY_DIAG_IMAGE=<path>` — extract signals from one card image across a
///   blur sweep, with the bottom-strip retry off and on.
/// - `SCRY_SYMBOL_DIR=<dir>` — feature-print distances from `query.jpg` to every
///   `ref-*.jpg`, using the production symbol band.
/// - `SCRY_SCAN_DIR=<dir>` — full EXIF-aware `ScryScanner.scan` over every image
///   in a directory against the real test catalog (triage a fresh harness
///   capture batch before importing it); set `SCRY_SCAN_DUMP=<dir>` to also
///   write each rectified crop for eyeballing.
final class ScryDiagnosticsTests: XCTestCase {
  func testScanDirectory() throws {
    guard let dir = ProcessInfo.processInfo.environment["SCRY_SCAN_DIR"] else {
      throw XCTSkip("Set SCRY_SCAN_DIR to a directory of card photos")
    }
    let database = try ScryTestCatalog.requireShared()
    let scanner = ScryScanner(database: database)
    let dumpDir = ProcessInfo.processInfo.environment["SCRY_SCAN_DUMP"].map(URL.init(fileURLWithPath:))
    if let dumpDir {
      try FileManager.default.createDirectory(at: dumpDir, withIntermediateDirectories: true)
    }

    let files = try FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil
    )
    .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

    for url in files {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("  ✗ \(url.lastPathComponent): could not load")
        continue
      }
      var orientation = CGImagePropertyOrientation.up
      if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
         let raw = props[kCGImagePropertyOrientation] as? UInt32,
         let parsed = CGImagePropertyOrientation(rawValue: raw) {
        orientation = parsed
      }
      guard let scan = try scanner.scan(image, orientation: orientation) else {
        print("  – \(url.lastPathComponent) (exif \(orientation.rawValue)): no card detected")
        continue
      }
      let resolution = scan.resolution
      let outcome: String = switch resolution.confidence {
      case .auto:
        "auto \(resolution.card.map { "\($0.name) [\($0.setCode) \($0.collectorNumber)]" } ?? "?") via \(resolution.method.rawValue)"
      case .ambiguous:
        "ambiguous ×\(resolution.candidates.count) (top: \(resolution.candidates.first?.name ?? "?"))"
      case .none:
        "unresolved"
      }
      let signals = resolution.signals
      print("  • \(url.lastPathComponent) (exif \(orientation.rawValue)): \(outcome)  [name=\(signals.name ?? "—") set=\(signals.setCode ?? "—") num=\(signals.collectorNumber ?? "—")]")
      if let dumpDir, let rectified = scan.rectified {
        let upright = ScryTextExtractor.makeUpright(rectified, orientation: scan.orientation)
        let destination = dumpDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-rectified.jpg")
        if let dest = CGImageDestinationCreateWithURL(destination as CFURL, "public.jpeg" as CFString, 1, nil) {
          CGImageDestinationAddImage(dest, upright, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
          CGImageDestinationFinalize(dest)
        }
      }
    }
  }

  func testDiagnoseImage() throws {
    guard let path = ProcessInfo.processInfo.environment["SCRY_DIAG_IMAGE"] else {
      throw XCTSkip("Set SCRY_DIAG_IMAGE to an image path")
    }
    let url = URL(fileURLWithPath: path)
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

    for radius in [0.0, 2.0, 3.0, 4.0, 5.0] {
      let input: CGImage
      if radius > 0 {
        input = try XCTUnwrap(Self.blurred(image, radius: radius))
      } else {
        input = image
      }
      for retry in [false, true] {
        var extractor = ScryTextExtractor()
        extractor.usesBottomStripRetry = retry
        let signals = try extractor.extractSignals(from: input)
        print("r=\(radius) retry=\(retry): name=\(signals.name ?? "—") set=\(signals.setCode ?? "—") num=\(signals.collectorNumber ?? "—") total=\(signals.setTotal.map(String.init) ?? "—") year=\(signals.copyrightYear.map(String.init) ?? "—")")
      }
    }
  }

  func testSymbolDistances() throws {
    guard let dir = ProcessInfo.processInfo.environment["SCRY_SYMBOL_DIR"] else {
      throw XCTSkip("Set SCRY_SYMBOL_DIR to a directory with query.jpg + ref-*.jpg")
    }
    let directory = URL(fileURLWithPath: dir)
    func load(_ name: String) throws -> CGImage {
      let url = directory.appendingPathComponent(name)
      let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), name)
      return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), name)
    }
    let matcher = ScrySymbolMatcher()
    let query = try load("query.jpg")
    let queryCrop = try XCTUnwrap(ScrySymbolMatcher.crop(query, band: matcher.band))
    let queryPrint = try ScrySymbolMatcher.featurePrint(of: queryCrop)

    let refs = try FileManager.default.contentsOfDirectory(atPath: dir)
      .filter { $0.hasPrefix("ref-") }.sorted()
    for ref in refs {
      let image = try load(ref)
      let crop = try XCTUnwrap(ScrySymbolMatcher.crop(image, band: matcher.band))
      let print = try ScrySymbolMatcher.featurePrint(of: crop)
      var distance: Float = 0
      try queryPrint.computeDistance(&distance, to: print)
      Swift.print(String(format: "  %@ -> %.4f", ref, distance))
    }
  }

  private static func blurred(_ image: CGImage, radius: Double) -> CGImage? {
    let input = CIImage(cgImage: image)
    guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(Float(radius), forKey: kCIInputRadiusKey)
    guard let output = filter.outputImage else { return nil }
    return CIContext().createCGImage(output, from: input.extent)
  }
}
#endif
