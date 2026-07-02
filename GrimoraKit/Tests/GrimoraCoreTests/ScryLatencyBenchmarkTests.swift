#if canImport(Vision)
@testable import GrimoraCore
import CoreGraphics
import Vision
import XCTest

/// Report-only latency benchmark for the recognition pipeline, skipped unless
/// `SCRY_BENCHMARK=1`. No assertions — the printed table is the before/after
/// instrument for speed work (host numbers aren't device numbers, but relative
/// deltas track).
///
///   SCRY_BENCHMARK=1 swift test --package-path GrimoraKit --filter ScryLatencyBenchmarkTests
final class ScryLatencyBenchmarkTests: XCTestCase {
  func testReportPipelineLatencies() throws {
    guard ProcessInfo.processInfo.environment["SCRY_BENCHMARK"] == "1" else {
      throw XCTSkip("Set SCRY_BENCHMARK=1 to run the latency report")
    }

    let database = try ScryTestCatalog.requireShared()
    var report = "\nScry latency report (host):\n"

    // 1. Extractor per corpus crop, .accurate vs .fast.
    let manifest = try ScryCorpusTests.loadManifest()
    for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
      let extractor = ScryTextExtractor(recognitionLevel: level)
      var total: Duration = .zero
      var count = 0
      for entry in manifest.entries {
        guard let (image, orientation) = ScryCorpusTests.loadImage(entry.image) else { continue }
        let clock = ContinuousClock()
        total += clock.measure { _ = try? extractor.extractSignals(from: image, orientation: orientation) }
        count += 1
      }
      if count > 0 {
        report += String(
          format: "  extractSignals(%@): %.0f ms/crop over %d crops\n",
          level == .accurate ? "accurate" : "fast", Self.milliseconds(total) / Double(count), count
        )
      }
    }

    // 2. Full scan per scene (detection + rotation search + resolve).
    let scanner = ScryScanner(database: database)
    let scenes = try Self.sceneImages()
    var scanTotal: Duration = .zero
    for image in scenes {
      let clock = ContinuousClock()
      scanTotal += clock.measure { _ = try? scanner.scan(image) }
    }
    if !scenes.isEmpty {
      report += String(
        format: "  ScryScanner.scan: %.0f ms/scene over %d scenes\n",
        Self.milliseconds(scanTotal) / Double(scenes.count), scenes.count
      )
    }

    // 3. Symbol matcher over the reference fixtures.
    let references = try Self.referenceImages()
    if let scan = references.values.first, references.count > 1 {
      let candidates = try Self.captainCandidates(database: database)
      let refsByID = try ScrySymbolMatcherTests.references(for: candidates)
      let matcher = ScrySymbolMatcher()
      let clock = ContinuousClock()
      let elapsed = clock.measure {
        _ = matcher.distances(scan: scan, candidates: candidates, referenceImages: refsByID)
      }
      report += String(
        format: "  ScrySymbolMatcher.distances: %.0f ms for %d candidates\n",
        Self.milliseconds(elapsed), candidates.count
      )
    }

    print(report)
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000
      + Double(duration.components.attoseconds) / 1e15
  }

  private static func sceneImages() throws -> [CGImage] {
    let scenesURL = try ScrySymbolMatcherTests.corpusURL().appendingPathComponent("scenes")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: scenesURL.path)) ?? []
    return files.sorted().compactMap {
      try? ScrySymbolMatcherTests.loadImage(scenesURL.appendingPathComponent($0))
    }
  }

  private static func referenceImages() throws -> [String: CGImage] {
    let referencesURL = try ScrySymbolMatcherTests.corpusURL().appendingPathComponent("references")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: referencesURL.path)) ?? []
    var images: [String: CGImage] = [:]
    for file in files where file.hasSuffix(".jpg") {
      images[file] = try? ScrySymbolMatcherTests.loadImage(referencesURL.appendingPathComponent(file))
    }
    return images
  }

  private static func captainCandidates(database: CardDatabase) throws -> [CardRecord] {
    let resolver = ScryCardResolver(database: database)
    return try resolver.nameCandidates(for: "Captain of the Watch")
  }
}
#endif
