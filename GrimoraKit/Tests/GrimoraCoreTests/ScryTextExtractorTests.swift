#if canImport(Vision)
@testable import GrimoraCore
import CoreGraphics
import CoreText
import XCTest

/// Exercises the Vision OCR path end-to-end on the host by rendering known text
/// to a bitmap and asserting the extractor reads it back. This validates the
/// extractor independently of the real-photo corpus (which needs the user's
/// device photos to be present).
final class ScryTextExtractorTests: XCTestCase {
  func testExtractsNameSetCodeAndCollectorNumberFromRenderedCard() throws {
    let image = Self.makeCardImage(
      name: "Lightning Bolt",
      bottomLines: ["123/350 R", "NEO EN"]
    )

    let signals = try ScryTextExtractor().extractSignals(from: image)

    XCTAssertEqual(signals.setCode, "neo")
    XCTAssertEqual(signals.collectorNumber, "123")
    let name = try XCTUnwrap(signals.name)
    XCTAssertGreaterThan(
      ScryStringSimilarity.nameSimilarity(name, "Lightning Bolt"),
      0.8,
      "OCR'd name was \(name)"
    )
  }

  func testDoesNotReadTypeLineAsName() throws {
    // Reproduces the on-device Izzet failure: when the title doesn't OCR, the
    // topmost line can be the type line "Land" — which must NOT become the name
    // (that produced a bogus list of unrelated land cards).
    let image = Self.makeCardImage(name: "Land", bottomLines: ["278/318", "CMD EN"])

    let signals = try ScryTextExtractor().extractSignals(from: image)

    XCTAssertNil(signals.name, "type line 'Land' must not be read as a name; got \(signals.name ?? "nil")")
    XCTAssertEqual(signals.collectorNumber, "278")
  }

  // MARK: - Rendering helpers

  /// A white canvas with the name near the top and the collector/set lines near
  /// the bottom — the rough layout of a real card's printed text.
  static func makeCardImage(
    name: String,
    bottomLines: [String],
    size: CGSize = CGSize(width: 720, height: 1008)
  ) -> CGImage {
    let context = CGContext(
      data: nil,
      width: Int(size.width),
      height: Int(size.height),
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))

    // CG origin is bottom-left, so a high y draws near the top.
    drawLine(name, in: context, at: CGPoint(x: 48, y: size.height - 110), fontSize: 56)

    var y: CGFloat = 80
    for line in bottomLines.reversed() {
      drawLine(line, in: context, at: CGPoint(x: 48, y: y), fontSize: 30)
      y += 48
    }

    return context.makeImage()!
  }

  private static func drawLine(
    _ string: String,
    in context: CGContext,
    at point: CGPoint,
    fontSize: CGFloat
  ) {
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    let attributes = [
      kCTFontAttributeName as String: font,
      kCTForegroundColorAttributeName as String: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    ] as CFDictionary
    let attributed = CFAttributedStringCreate(kCFAllocatorDefault, string as CFString, attributes)!
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = point
    CTLineDraw(line, context)
  }
}
#endif
