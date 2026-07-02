#if canImport(Vision)
import CoreGraphics
import CoreImage
import Foundation
import Vision

/// The full result of reading one card image: the parsed identification signals
/// plus the text geometry they were read from (for symbol-band anchoring and
/// diagnostics).
public struct ScryExtraction: Sendable {
  public var signals: ScrySignals
  public var lineMap: ScryLineMap

  public init(signals: ScrySignals, lineMap: ScryLineMap) {
    self.signals = signals
    self.lineMap = lineMap
  }
}

/// Runs Vision text recognition over a rectified, roughly card-filling image and
/// turns the result into `ScrySignals` + a `ScryLineMap` of the card's text
/// geometry.
///
/// One OCR pass over the whole card: the title gives the name, and the bottom
/// `SET • LANG` / `collector` lines feed `ScryCollectorLineParser`. On a tight
/// card crop — which is what rectangle detection + rectification produce — that
/// pass reads the modern collector line well. When it finds no collector number,
/// a **zoomed retry** runs, aimed at the copyright line's own bounding box when
/// the full pass saw that line (pre-2015 frames print the collector info in tiny
/// serif type at its end, the first casualty of camera blur), else at the bottom
/// strip of the card.
///
/// The extractor intentionally does NOT try to be perfect about the set code:
/// when OCR mangles it (e.g. "OTJ" → "OTS" under foil glare) it simply won't
/// resolve to a real printing, and `ScryCardResolver` recovers via the
/// reliably-read name + collector number.
public struct ScryTextExtractor: Sendable {
  public var recognitionLevel: VNRequestTextRecognitionLevel

  /// Whether to re-OCR a zoomed crop when the whole-card pass read no collector
  /// number. Costs one extra OCR pass, so the live preview loop turns it off;
  /// the tap-to-scan path keeps it on.
  public var usesBottomStripRetry: Bool

  /// Fraction of the card height (from the bottom) the fallback retry strip
  /// covers when no copyright line anchored a tighter crop.
  public var bottomStripFraction: Double

  public init(
    recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
    usesBottomStripRetry: Bool = true,
    bottomStripFraction: Double = 0.16
  ) {
    self.recognitionLevel = recognitionLevel
    self.usesBottomStripRetry = usesBottomStripRetry
    self.bottomStripFraction = bottomStripFraction
  }

  public func extractSignals(
    from image: CGImage,
    orientation: CGImagePropertyOrientation = .up
  ) throws -> ScrySignals {
    try extract(from: image, orientation: orientation).signals
  }

  public func extract(
    from image: CGImage,
    orientation: CGImagePropertyOrientation = .up
  ) throws -> ScryExtraction {
    let upright = Self.makeUpright(image, orientation: orientation)
    let lines = try recognizeLines(in: upright).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    let lineMap = ScryLineMap(lines: lines)
    var rawTextLines = lines.map(\.text)
    var parsed = ScryCollectorLineParser.parse(lines: rawTextLines)

    if usesBottomStripRetry, parsed.collectorNumber == nil,
       let crop = Self.retryCrop(of: upright, lineMap: lineMap, bottomFraction: bottomStripFraction),
       let retryLines = try? recognizeLines(in: crop) {
      let retryTexts = retryLines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }.map(\.text)
      let retryParsed = ScryCollectorLineParser.parse(lines: retryTexts)
      parsed.setCode = parsed.setCode ?? retryParsed.setCode
      parsed.collectorNumber = retryParsed.collectorNumber
      parsed.setTotal = parsed.setTotal ?? retryParsed.setTotal
      parsed.copyrightYear = parsed.copyrightYear ?? retryParsed.copyrightYear
      rawTextLines += retryTexts
    }

    let signals = ScrySignals(
      name: lineMap.nameLine?.text,
      setCode: parsed.setCode,
      collectorNumber: parsed.collectorNumber,
      setTotal: parsed.setTotal,
      copyrightYear: parsed.copyrightYear,
      colors: [],
      rawTextLines: rawTextLines
    )
    return ScryExtraction(signals: signals, lineMap: lineMap)
  }

  /// OCR lines, top-to-bottom — for corpus tuning and diagnostics.
  func diagnosticLines(
    from image: CGImage,
    orientation: CGImagePropertyOrientation = .up
  ) throws -> [String] {
    let upright = Self.makeUpright(image, orientation: orientation)
    return try recognizeLines(in: upright)
      .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
      .map(\.text)
  }

  // MARK: - OCR

  private func recognizeLines(in image: CGImage) throws -> [ScryRecognizedLine] {
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
      return ScryRecognizedLine(text: text, boundingBox: observation.boundingBox)
    }
  }

  // MARK: - Zoomed retry

  /// The retry crop, magnified: the copyright line's own box (padded a line
  /// height each side, full card width — its collector fragment sits at the end
  /// and OCR may have boxed only part of the line) when the full pass saw it,
  /// else the blind bottom strip.
  static func retryCrop(
    of image: CGImage,
    lineMap: ScryLineMap,
    bottomFraction: Double
  ) -> CGImage? {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    if let line = lineMap.copyrightLine?.boundingBox {
      // Vision box (bottom-left origin, y up) → pixel rect (top-left origin).
      let pad = line.height
      let top = (1 - line.maxY - pad) * height
      let rect = CGRect(
        x: 0,
        y: top,
        width: width,
        height: (line.height + pad * 2) * height
      ).intersection(CGRect(x: 0, y: 0, width: width, height: height))
      // A line crop is short, so it affords more magnification than the strip.
      if let crop = zoomedCrop(of: image, rect: rect, maxScale: 6) {
        return crop
      }
    }

    let stripHeight = (height * CGFloat(bottomFraction)).rounded(.up)
    let strip = CGRect(x: 0, y: height - stripHeight, width: width, height: stripHeight)
    return zoomedCrop(of: image, rect: strip, maxScale: 3)
  }

  /// Crops a pixel-space (top-left origin) rect and Lanczos-upscales it so tiny
  /// print reads at a size Vision handles well. Returns `nil` when cropping fails.
  static func zoomedCrop(
    of image: CGImage,
    rect: CGRect,
    maxScale: CGFloat,
    maxScaledWidth: CGFloat = 3600
  ) -> CGImage? {
    guard rect.width >= 8, rect.height >= 8 else { return nil }
    guard let cropped = image.cropping(to: rect.integral) else { return nil }

    let scale = min(maxScale, maxScaledWidth / rect.width)
    guard scale > 1.05 else { return cropped }

    let filter = CIFilter(name: "CILanczosScaleTransform")
    filter?.setValue(CIImage(cgImage: cropped), forKey: kCIInputImageKey)
    filter?.setValue(scale, forKey: kCIInputScaleKey)
    filter?.setValue(1.0, forKey: kCIInputAspectRatioKey)
    guard let output = filter?.outputImage else { return cropped }

    let context = CIContext(options: nil)
    return context.createCGImage(output, from: output.extent) ?? cropped
  }

  /// Bakes EXIF orientation so OCR sees the card upright.
  public static func makeUpright(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage {
    guard orientation != .up else { return image }
    let oriented = CIImage(cgImage: image).oriented(orientation)
    let context = CIContext(options: nil)
    return context.createCGImage(oriented, from: oriented.extent) ?? image
  }
}
#endif
