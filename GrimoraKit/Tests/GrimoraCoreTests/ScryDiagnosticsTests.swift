#if canImport(Vision)
@testable import GrimoraCore
import CoreGraphics
import ImageIO
import Vision
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

    let sweep = ProcessInfo.processInfo.environment["SCRY_DIAG_RADII"]
      .map { $0.split(separator: ",").compactMap { Double($0) } } ?? [0.0, 2.0, 3.0, 4.0, 5.0]
    for radius in sweep {
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
        if retry {
          for line in signals.rawTextLines { print("      | \(line)") }
        }
      }
    }
  }

  /// `SCRY_DETECT_IMAGE=<path>` — every raw rectangle/document-segmentation
  /// observation (before the detector's in-frame + card-aspect filter) plus the
  /// merged production candidates, to see why the wrong quad (a text box, a
  /// neighbor) is winning the subject.
  func testDetectCandidates() throws {
    guard let path = ProcessInfo.processInfo.environment["SCRY_DETECT_IMAGE"] else {
      throw XCTSkip("Set SCRY_DETECT_IMAGE to a scene image path")
    }
    let url = URL(fileURLWithPath: path)
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var orientation = CGImagePropertyOrientation.up
    if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
       let raw = props[kCGImagePropertyOrientation] as? UInt32,
       let parsed = CGImagePropertyOrientation(rawValue: raw) {
      orientation = parsed
    }
    let upright = ScryTextExtractor.makeUpright(image, orientation: orientation)
    let w = Double(upright.width), h = Double(upright.height)
    print("image \(image.width)x\(image.height) exif \(orientation.rawValue) → upright \(upright.width)x\(upright.height)")

    func describe(_ obs: VNRectangleObservation, _ tag: String) {
      let corners = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
      let inFrame = corners.allSatisfy { $0.x >= 0.015 && $0.x <= 0.985 && $0.y >= 0.015 && $0.y <= 0.985 }
      let px = corners.map { CGPoint(x: $0.x * w, y: $0.y * h) }
      let aspect = ScryCardDetector.aspectRatio(of: px)
      let area = ScryCardDetector.polygonArea(px) / (w * h)
      let c = ScryCardDetector.centroid(corners)
      let minX = corners.map(\.x).min() ?? 0, maxX = corners.map(\.x).max() ?? 0
      let minY = corners.map(\.y).min() ?? 0, maxY = corners.map(\.y).max() ?? 0
      print(String(format: "  [%@] area=%.3f aspect=%.3f conf=%.2f inFrame=%@ center=(%.2f,%.2f) x[%.3f…%.3f] y[%.3f…%.3f]",
                   tag, area, aspect, obs.confidence, inFrame ? "Y" : "N", c.x, c.y, minX, maxX, minY, maxY))
    }

    let rect = VNDetectRectanglesRequest()
    rect.minimumAspectRatio = 0.2
    rect.quadratureTolerance = 45
    rect.minimumSize = 0.08
    rect.minimumConfidence = 0.3
    rect.maximumObservations = 20
    let doc = VNDetectDocumentSegmentationRequest()
    try VNImageRequestHandler(cgImage: upright, options: [:]).perform([rect, doc])

    print("RAW RECTANGLES (\(rect.results?.count ?? 0)):")
    for o in rect.results ?? [] { describe(o, "rect") }
    print("RAW DOC-SEG (\(doc.results?.count ?? 0)):")
    for o in (doc.results ?? []) { describe(o, "doc") }

    let merged = try ScryCardDetector().detectCards(in: upright, orientation: .up)
    print("MERGED (production filter) → \(merged.count) subject candidate(s), largest first:")
    for card in merged {
      let c = ScryCardDetector.centroid(card.normalizedCorners)
      print(String(format: "  area=%.3f aspect=%.3f conf=%.2f center=(%.2f,%.2f)",
                   card.areaFraction, card.aspectRatio, card.confidence, c.x, c.y))
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
