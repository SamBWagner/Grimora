#if canImport(Vision)
@testable import GrimoraCore
import CoreGraphics
import ImageIO
import XCTest

/// The full front-to-back pipeline on raw desk photos, against the **real**
/// Scryfall catalog (`ScryTestCatalog`): `ScryScanner` (detect the fully-in-frame
/// card, ignore partial neighbors and clutter → rectify → orientation → resolve).
///
/// - **Precision (hard gate):** never auto-accept the wrong card (real identity by
///   set + collector number against ~1,200 real cards).
/// - **Recall (hard gate):** each subject either auto-accepts correctly or falls to
///   disambiguation with the correct printing among the candidates. Picking a
///   partial neighbor, or losing the card, fails.
///
/// Some cards can't be auto-identified by OCR alone — an old frame with no printed
/// set code whose collector number won't OCR (Izzet Boilerworks has 24 printings)
/// correctly lands in disambiguation rather than guessing. That's the honest
/// outcome until art-embedding visual matching is added.
final class ScrySceneTests: XCTestCase {
  struct Manifest: Decodable { var entries: [Entry] }

  struct Entry: Decodable {
    var image: String
    var name: String
    var setCode: String
    var collectorNumber: String
    var foil: Bool?
    var notes: String?
  }

  func testDetectsAndResolvesSubjectInEachScene() throws {
    let manifest = try Self.loadManifest()
    try XCTSkipIf(manifest.entries.isEmpty, "No scenes — add photos to ScryCorpus/scenes and scenes-manifest.json.")

    let database = try XCTUnwrap(ScryTestCatalog.shared, "Could not build the real test catalog.")
    let scanner = ScryScanner(database: database)

    var autoCorrect = 0
    var disambiguated = 0
    var failures: [String] = []
    var report = "\nScry scene resolution (real catalog, \(try database.cardCount()) cards):\n"

    for entry in manifest.entries {
      guard let (image, orientation) = Self.loadImage(entry.image) else {
        XCTFail("Could not load scene \(entry.image)")
        continue
      }

      guard let scan = try scanner.scan(image, orientation: orientation) else {
        failures.append("\(entry.image): no fully-in-frame card detected")
        report += "  ✗ \(entry.image): no card detected\n"
        continue
      }
      let resolution = scan.resolution
      let read = "name=\"\(resolution.signals.name ?? "—")\" set=\(resolution.signals.setCode ?? "—")"
        + " num=\(resolution.signals.collectorNumber ?? "—")"
        + " area=\(String(format: "%.2f", scan.detectedCard.areaFraction))"

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
        disambiguated += 1
        let present = resolution.candidates.contains { Self.matches($0, entry) }
        report += "  ? \(entry.image)  disambiguate among \(resolution.candidates.count) (correct present: \(present))  \(read)\n"
        if !present {
          failures.append("\(entry.image): correct printing not among \(resolution.candidates.count) candidates  (\(read))")
        }
      case .none:
        report += "  – \(entry.image)  unresolved  \(read)\n"
        failures.append("\(entry.image): resolved to none  (\(read))")
      }
    }

    report += "auto-accepted correctly \(autoCorrect)/\(manifest.entries.count) · disambiguated \(disambiguated)\n"
    print(report)
    XCTAssertTrue(failures.isEmpty, "Scene failures:\n" + failures.joined(separator: "\n"))
  }

  // MARK: - Identity

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
    guard let url = corpusURL()?.appendingPathComponent("scenes-manifest.json"),
          FileManager.default.fileExists(atPath: url.path) else {
      return Manifest(entries: [])
    }
    return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
  }

  static func loadImage(_ name: String) -> (CGImage, CGImagePropertyOrientation)? {
    guard let url = corpusURL()?.appendingPathComponent("scenes").appendingPathComponent(name),
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
