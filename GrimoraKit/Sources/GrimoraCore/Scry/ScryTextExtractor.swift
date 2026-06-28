#if canImport(Vision)
import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Runs Vision text recognition over a rectified, roughly card-filling image and
/// turns the result into `ScrySignals`.
///
/// One OCR pass over the whole card: the title gives the name, and the bottom
/// `SET • LANG` / `collector` lines feed `ScryCollectorLineParser`. (An earlier
/// version added a zoomed bottom-corner pass to read the tiny collector line, but
/// once the input is a tight card crop — which is what rectangle detection +
/// rectification produce — the whole-card pass reads it better, and the parser is
/// precision-first so it ignores what it can't trust.)
///
/// The extractor intentionally does NOT try to be perfect about the set code:
/// when OCR mangles it (e.g. "OTJ" → "OTS" under foil glare) it simply won't
/// resolve to a real printing, and `ScryCardResolver` recovers via the
/// reliably-read name + collector number.
public struct ScryTextExtractor: Sendable {
  public var recognitionLevel: VNRequestTextRecognitionLevel

  /// Fraction of the text span (from the top) treated as the name region.
  public var nameRegionTopFraction: Double

  public init(
    recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
    nameRegionTopFraction: Double = 0.32
  ) {
    self.recognitionLevel = recognitionLevel
    self.nameRegionTopFraction = nameRegionTopFraction
  }

  public func extractSignals(
    from image: CGImage,
    orientation: CGImagePropertyOrientation = .up
  ) throws -> ScrySignals {
    let upright = Self.makeUpright(image, orientation: orientation)
    let lines = try recognizeLines(in: upright).sorted { $0.midY > $1.midY }
    let rawTextLines = lines.map(\.text)
    let parsed = ScryCollectorLineParser.parse(lines: rawTextLines)

    return ScrySignals(
      name: pickName(from: lines),
      setCode: parsed.setCode,
      collectorNumber: parsed.collectorNumber,
      colors: [],
      rawTextLines: rawTextLines
    )
  }

  /// OCR lines, top-to-bottom — for corpus tuning and diagnostics.
  func diagnosticLines(
    from image: CGImage,
    orientation: CGImagePropertyOrientation = .up
  ) throws -> [String] {
    let upright = Self.makeUpright(image, orientation: orientation)
    return try recognizeLines(in: upright).sorted { $0.midY > $1.midY }.map(\.text)
  }

  // MARK: - OCR

  private func recognizeLines(in image: CGImage) throws -> [RecognizedLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = recognitionLevel
    // Card names, set codes and collector numbers are not dictionary words;
    // language correction "fixes" them into the wrong thing.
    request.usesLanguageCorrection = false

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    return (request.results ?? []).compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      return RecognizedLine(text: text, midY: Double(observation.boundingBox.midY))
    }
  }

  /// The card title is the topmost acceptable name line within the name region.
  /// Returns `nil` rather than falling back to a type line ("Land") or other
  /// non-name text — a wrong name produces a confidently-wrong search.
  private func pickName(from topToBottom: [RecognizedLine]) -> String? {
    guard let maxY = topToBottom.map(\.midY).max(),
          let minY = topToBottom.map(\.midY).min() else { return nil }
    let span = Swift.max(maxY - minY, 0.0001)
    let threshold = maxY - nameRegionTopFraction * span
    let region = topToBottom.filter { $0.midY >= threshold }
    return region.first { ScryNameHeuristics.isAcceptableName($0.text) }?.text
  }

  /// Bakes EXIF orientation so OCR sees the card upright.
  static func makeUpright(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage {
    guard orientation != .up else { return image }
    let oriented = CIImage(cgImage: image).oriented(orientation)
    let context = CIContext(options: nil)
    return context.createCGImage(oriented, from: oriented.extent) ?? image
  }

  private struct RecognizedLine {
    var text: String
    var midY: Double
  }
}
#endif
