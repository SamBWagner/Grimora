#if canImport(Vision)
@testable import GrimoraCore
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest

/// Soft-focus regression. The bulk-scan rig (phone fixed over a box) produces
/// blurry frames, which is why some cards "struggle" — the collector number stops
/// OCR'ing, so they fall to a printing picker instead of auto-identifying.
///
/// Rather than feed in the device screenshots (which have the UI overlay baked in
/// and aren't what the pipeline actually sees), this blurs the clean corpus crops
/// to simulate the same condition. The contract under blur:
///
/// - **Precision (hard gate):** blur must NEVER cause a *wrong* auto-accept.
/// - **Recall (reported):** how many still resolve correctly as focus degrades —
///   the metric the camera focus-lock work is meant to improve on-device.
final class ScrySoftFocusTests: XCTestCase {
  func testSoftFocusNeverCausesWrongAutoAccept() throws {
    let manifest = try ScryCorpusTests.loadManifest()
    try XCTSkipIf(manifest.entries.isEmpty, "empty corpus")

    let database = try ScryTestCatalog.requireShared()
    let resolver = ScryCardResolver(database: database)
    let extractor = ScryTextExtractor()

    var report = "\nSoft-focus degradation (real catalog):\n"

    for radius in [3.0, 6.0, 10.0] {
      var wrong: [String] = []
      var resolvable = 0

      for entry in manifest.entries {
        guard let (image, orientation) = ScryCorpusTests.loadImage(entry.image),
              let blurred = Self.blurred(image, radius: radius) else { continue }

        let signals = try extractor.extractSignals(from: blurred, orientation: orientation)
        let resolution = try resolver.resolve(signals)

        switch resolution.confidence {
        case .auto:
          if ScryCorpusTests.matches(resolution.card, entry) {
            resolvable += 1
          } else {
            wrong.append("\(entry.image) @r\(radius): auto-accepted \(ScryCorpusTests.describe(resolution.card))")
          }
        case .ambiguous:
          if resolution.candidates.contains(where: { ScryCorpusTests.matches($0, entry) }) {
            resolvable += 1
          }
        case .none:
          break
        }
      }

      report += "  blur r=\(Int(radius)): correctly resolvable \(resolvable)/\(manifest.entries.count)"
        + ", wrong auto-accepts \(wrong.count)\n"

      // The cardinal invariant: even badly blurred, never auto-accept a wrong card.
      XCTAssertTrue(wrong.isEmpty, "Soft focus caused a WRONG auto-accept:\n" + wrong.joined(separator: "\n"))
    }

    print(report)
  }

  private static func blurred(_ image: CGImage, radius: Double) -> CGImage? {
    let input = CIImage(cgImage: image)
    let filter = CIFilter.gaussianBlur()
    filter.inputImage = input
    filter.radius = Float(radius)
    guard let output = filter.outputImage else { return nil }
    // Gaussian blur grows the extent; crop back to the original frame.
    return CIContext().createCGImage(output, from: input.extent)
  }
}
#endif
