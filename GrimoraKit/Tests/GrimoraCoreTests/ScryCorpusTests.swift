#if canImport(Vision)
@testable import GrimoraCore
import CoreGraphics
import ImageIO
import XCTest

/// Runs the pipeline (`ScryTextExtractor` → `ScryCardResolver`) over the labeled
/// single-card crops against the **real** Scryfall catalog (`ScryTestCatalog`),
/// and enforces the product contract:
///
/// - **Precision (hard gate, every entry):** never auto-accept the *wrong* card.
///   Identity is checked by real (set code, collector number) against the real
///   catalog, so a correct result has to beat genuine reprints and set-mates —
///   not a handful of planted answers.
/// - **Recall (per-entry `expectation`):** `auto` entries (the default) must
///   auto-accept the correct card. `disambiguation` entries only have to surface
///   the correct printing among the candidates — the honest outcome for cards
///   whose printed signals can't uniquely identify them (a 1994 card with no
///   collector number, say). Upgrading an entry to `auto` is the recall ratchet;
///   the test reports `disambiguation` entries that already auto-accept.
///
/// Crucially, the resolver is handed only the image-derived signals and the full
/// catalog; the expected answer is used *only* in the assertion.
final class ScryCorpusTests: XCTestCase {
  struct Manifest: Decodable { var entries: [Entry] }

  enum Expectation: String, Decodable {
    /// Must auto-accept the correct printing (default).
    case auto
    /// Must surface the correct printing among the disambiguation candidates;
    /// auto-accepting the correct printing is also fine (and worth upgrading).
    case disambiguation
    /// A documented engine failure captured on-device (wrong auto-accept,
    /// correct card missing from candidates, or unresolved), stored with the
    /// correct ground truth. Exempt from both the precision gate and recall —
    /// reported only, and flagged loudly once it starts passing (the ratchet:
    /// upgrade it to `auto`/`disambiguation` then).
    case knownFailure
  }

  struct Entry: Decodable {
    var image: String
    var name: String
    var setCode: String
    var collectorNumber: String
    var expectation: Expectation?
    var foil: Bool?
    var sleeved: Bool?
    var background: String?
    var notes: String?

    var resolvedExpectation: Expectation { expectation ?? .auto }
  }

  func testCorpusResolvesEveryCropAgainstRealCatalog() throws {
    let manifest = try Self.loadManifest()
    try XCTSkipIf(
      manifest.entries.isEmpty,
      "Scry corpus is empty — add labeled crops to ScryCorpus/images and manifest.json."
    )
    // The images themselves are a gitignored local-only asset store; a checkout
    // without them skips rather than fails. A *partially* present store still
    // fails per-entry below — that's accidental deletion, not a fresh clone.
    try XCTSkipIf(
      Self.corpusURL().map { !FileManager.default.fileExists(atPath: $0.appendingPathComponent("images").path) } ?? true,
      "ScryCorpus/images not on this checkout — local-only assets (see ScryCorpus/README.md)"
    )

    let database = try ScryTestCatalog.requireShared()
    let scanner = ScryScanner(database: database)

    var autoCorrect = 0
    var failures: [String] = []
    var report = "\nScry crop resolution (real catalog, \(try database.cardCount()) cards):\n"

    for entry in manifest.entries {
      guard let (image, orientation) = Self.loadImage(entry.image) else {
        XCTFail("Could not load corpus image \(entry.image)")
        continue
      }

      // The production path for an already-rectified crop: the 4-rotation
      // identify loop (which split/battle layouts need), not a single upright
      // extraction.
      let upright = ScryTextExtractor.makeUpright(image, orientation: orientation)
      let result = try scanner.identify(rectified: upright, detectedCard: Self.placeholderCard)
      let resolution = result.resolution
      let signals = resolution.signals
      let read = "set=\(signals.setCode ?? "—") num=\(signals.collectorNumber ?? "—")"
      let expectation = entry.resolvedExpectation

      if expectation == .knownFailure {
        let nowAuto = resolution.confidence == .auto && Self.matches(resolution.card, entry)
        let nowPresent = resolution.confidence == .ambiguous
          && resolution.candidates.contains { Self.matches($0, entry) }
        if nowAuto || nowPresent {
          report += "  ! \(entry.image)  knownFailure NOW PASSING (\(nowAuto ? "auto" : "disambiguation")) — upgrade the expectation\n"
        } else {
          report += "  ✗ \(entry.image)  knownFailure (still failing: \(Self.describe(resolution.card)) / \(resolution.confidence))  \(read)\n"
        }
        continue
      }

      switch resolution.confidence {
      case .auto:
        if Self.matches(resolution.card, entry) {
          autoCorrect += 1
          let ratchet = expectation == .disambiguation ? "  (exceeds expectation — consider upgrading to auto)" : ""
          report += "  ✓ \(entry.image)  [\(resolution.method.rawValue)]  \(read)\(ratchet)\n"
        } else {
          // Precision is the hard gate for every expectation level.
          failures.append("\(entry.image): auto-accepted \(Self.describe(resolution.card)), expected \(entry.setCode) \(entry.collectorNumber)")
          report += "  ✗ WRONG \(entry.image)  got \(Self.describe(resolution.card))\n"
        }
      case .ambiguous:
        let present = resolution.candidates.contains { Self.matches($0, entry) }
        report += "  ? \(entry.image)  disambiguate (correct present: \(present))  \(read)\n"
        switch expectation {
        case .auto:
          failures.append("\(entry.image): expected a clean auto-accept but got disambiguation  (\(read))")
        case .disambiguation:
          if !present {
            failures.append("\(entry.image): correct printing missing from disambiguation candidates  (\(read))")
          }
        case .knownFailure:
          break  // handled (and `continue`d) above
        }
      case .none:
        report += "  – \(entry.image)  unresolved  \(read)\n"
        failures.append("\(entry.image): resolved to none  (\(read))")
      }
    }

    report += "auto-accepted correctly \(autoCorrect)/\(manifest.entries.count)\n"
    print(report)
    // The test runner truncates large print buffers; SCRY_REPORT_DIR gets the
    // full report on disk (the corpus is big enough now that this matters).
    if let dir = ProcessInfo.processInfo.environment["SCRY_REPORT_DIR"] {
      try? report.write(
        to: URL(fileURLWithPath: dir).appendingPathComponent("crops.txt"),
        atomically: true, encoding: .utf8
      )
    }
    XCTAssertTrue(failures.isEmpty, "Crop failures:\n" + failures.joined(separator: "\n"))
  }

  /// `identify` only reads the detection for bookkeeping; corpus crops are
  /// already rectified, so a synthetic full-frame quad stands in.
  static let placeholderCard = ScryDetectedCard(
    normalizedCorners: [
      CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)
    ],
    areaFraction: 1,
    aspectRatio: 0.714,
    confidence: 1
  )

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
