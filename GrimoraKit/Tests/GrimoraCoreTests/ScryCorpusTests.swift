#if canImport(Vision)
@testable import GrimoraCore
import CoreGraphics
import ImageIO
import XCTest

/// Runs the pipeline (`ScryTextExtractor` → `ScryCardResolver`) over the labeled
/// single-card crops against the **real** Scryfall catalog (`ScryTestCatalog`),
/// and enforces the product contract:
///
/// - **Precision (hard gate):** never auto-accept the *wrong* card. Identity is
///   checked by real (set code, collector number) against ~1,200 real cards, so a
///   correct result has to beat genuine reprints and set-mates — not a handful of
///   planted answers.
/// - **Recall (hard gate here):** these are clean single-card crops, so every one
///   must auto-accept the correct card.
///
/// Crucially, the resolver is handed only the image-derived signals and the full
/// catalog; the expected answer is used *only* in the assertion.
final class ScryCorpusTests: XCTestCase {
  struct Manifest: Decodable { var entries: [Entry] }

  struct Entry: Decodable {
    var image: String
    var name: String
    var setCode: String
    var collectorNumber: String
    var foil: Bool?
    var sleeved: Bool?
    var background: String?
    var notes: String?
  }

  func testCorpusResolvesEveryCropAgainstRealCatalog() throws {
    let manifest = try Self.loadManifest()
    try XCTSkipIf(
      manifest.entries.isEmpty,
      "Scry corpus is empty — add labeled crops to ScryCorpus/images and manifest.json."
    )

    let database = try XCTUnwrap(ScryTestCatalog.shared, "Could not build the real test catalog.")
    let resolver = ScryCardResolver(database: database)
    let extractor = ScryTextExtractor()

    var autoCorrect = 0
    var failures: [String] = []
    var report = "\nScry crop resolution (real catalog, \(try database.cardCount()) cards):\n"

    for entry in manifest.entries {
      guard let (image, orientation) = Self.loadImage(entry.image) else {
        XCTFail("Could not load corpus image \(entry.image)")
        continue
      }

      let signals = try extractor.extractSignals(from: image, orientation: orientation)
      let resolution = try resolver.resolve(signals)
      let read = "set=\(signals.setCode ?? "—") num=\(signals.collectorNumber ?? "—")"

      switch resolution.confidence {
      case .auto:
        if Self.matches(resolution.card, entry) {
          autoCorrect += 1
          report += "  ✓ \(entry.image)  [\(resolution.method.rawValue)]  \(read)\n"
        } else {
          failures.append("\(entry.image): auto-accepted \(Self.describe(resolution.card)), expected \(entry.setCode) \(entry.collectorNumber)")
          report += "  ✗ WRONG \(entry.image)  got \(Self.describe(resolution.card))\n"
        }
      case .ambiguous:
        let present = resolution.candidates.contains { Self.matches($0, entry) }
        report += "  ? \(entry.image)  disambiguate (correct present: \(present))  \(read)\n"
        failures.append("\(entry.image): expected a clean auto-accept but got disambiguation  (\(read))")
      case .none:
        report += "  – \(entry.image)  unresolved  \(read)\n"
        failures.append("\(entry.image): resolved to none  (\(read))")
      }
    }

    report += "auto-accepted correctly \(autoCorrect)/\(manifest.entries.count)\n"
    print(report)
    XCTAssertTrue(failures.isEmpty, "Crop failures:\n" + failures.joined(separator: "\n"))
  }

  // MARK: - Identity (real set code + collector number)

  static func matches(_ card: CardRecord?, _ entry: Entry) -> Bool {
    guard let card else { return false }
    return card.setCode.lowercased() == entry.setCode.lowercased()
      && card.collectorNumber == entry.collectorNumber
  }

  static func describe(_ card: CardRecord?) -> String {
    guard let card else { return "nil" }
    return "\(card.name) [\(card.setCode) \(card.collectorNumber)]"
  }

  // MARK: - Loading

  private static func corpusURL() -> URL? {
    Bundle.module.resourceURL?.appendingPathComponent("ScryCorpus", isDirectory: true)
  }

  static func loadManifest() throws -> Manifest {
    guard let url = corpusURL()?.appendingPathComponent("manifest.json"),
          FileManager.default.fileExists(atPath: url.path) else {
      return Manifest(entries: [])
    }
    return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
  }

  static func loadImage(_ name: String) -> (CGImage, CGImagePropertyOrientation)? {
    guard let url = corpusURL()?.appendingPathComponent("images").appendingPathComponent(name),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return nil
    }
    var orientation = CGImagePropertyOrientation.up
    if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
       let raw = props[kCGImagePropertyOrientation] as? UInt32,
       let parsed = CGImagePropertyOrientation(rawValue: raw) {
      orientation = parsed
    }
    return (image, orientation)
  }
}
#endif
