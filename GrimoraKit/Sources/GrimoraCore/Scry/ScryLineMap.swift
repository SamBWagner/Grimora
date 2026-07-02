import CoreGraphics
import Foundation

/// One OCR'd text line with its position on the card.
public struct ScryRecognizedLine: Equatable, Sendable {
  public var text: String
  /// Vision-normalized bounding box: origin bottom-left, y up, `[0, 1]`.
  public var boundingBox: CGRect

  public init(text: String, boundingBox: CGRect) {
    self.text = text
    self.boundingBox = boundingBox
  }
}

/// The card's own text geometry, derived from one OCR pass — the anchors that
/// let the pipeline adapt to any frame instead of assuming the modern layout.
///
/// Fixed-fraction anchors (name = top 32% of the text span, symbol band at a
/// hardcoded height) only fit normal frames. But every frame *prints its own
/// map*: the type line locates the name region (above it) and the set symbol
/// (right of it) — which is how sagas and classes, whose type line sits ~87%
/// down the card, work without special cases. Every anchor is optional, and
/// consumers fall back to the fixed-fraction rules when one is missing.
public struct ScryLineMap: Equatable, Sendable {
  /// All recognized lines, top to bottom.
  public var lines: [ScryRecognizedLine]
  /// The topmost type line ("Creature — Human Soldier"). Topmost matters: it
  /// skips an adventure's second type box and a flip card's inverted half.
  public var typeLine: ScryRecognizedLine?
  /// The title: the topmost acceptable name above the type line.
  public var nameLine: ScryRecognizedLine?
  /// The copyright line ("™ & © 1993–2009 Wizards of the Coast LLC 6/249") —
  /// the zoom-retry target when its collector fragment didn't parse.
  public var copyrightLine: ScryRecognizedLine?
  /// Where the set symbol sits: right of the type line, vertically centered on
  /// it. **Top-left-origin** normalized (ready for `ScrySymbolMatcher.crop`).
  public var symbolBand: CGRect?

  /// Fraction of the text span (from the top) treated as the name region when
  /// no type line anchors it — the pre-line-map rule, kept as the fallback.
  public static let nameRegionTopFraction = 0.32

  public init(lines topToBottom: [ScryRecognizedLine]) {
    lines = topToBottom
    typeLine = topToBottom.first { ScryNameHeuristics.looksLikeTypeLine($0.text) }
    copyrightLine = topToBottom.first { ScryCollectorLineParser.isCopyrightLine($0.text) }
    nameLine = Self.nameLine(in: topToBottom, above: typeLine)
    symbolBand = typeLine.flatMap(Self.symbolBand(rightOf:))
  }

  /// The topmost acceptable name above the type line; without a type line, the
  /// topmost acceptable name within the top fraction of the text span.
  static func nameLine(
    in topToBottom: [ScryRecognizedLine],
    above typeLine: ScryRecognizedLine?
  ) -> ScryRecognizedLine? {
    if let typeLine {
      // "Above" with a little slack: an angled crop can tilt boxes enough that
      // the title's midY dips toward the type line's top edge.
      let floor = typeLine.boundingBox.maxY - typeLine.boundingBox.height * 0.25
      return topToBottom.first {
        $0.boundingBox.midY > floor && ScryNameHeuristics.isAcceptableName($0.text)
      }
    }

    guard let maxY = topToBottom.map(\.boundingBox.midY).max(),
          let minY = topToBottom.map(\.boundingBox.midY).min() else { return nil }
    let span = Swift.max(maxY - minY, 0.0001)
    let threshold = maxY - nameRegionTopFraction * span
    return topToBottom.first {
      $0.boundingBox.midY >= threshold && ScryNameHeuristics.isAcceptableName($0.text)
    }
  }

  /// The symbol band to the right of a type line, converted to top-left-origin
  /// normalized coordinates. `nil` when the type line leaves no room (it runs
  /// to the card edge) or its box is degenerate.
  static func symbolBand(rightOf typeLine: ScryRecognizedLine) -> CGRect? {
    let box = typeLine.boundingBox
    guard box.height > 0.005 else { return nil }

    let left = box.maxX + 0.005
    let right = 0.97
    guard right - left >= 0.04 else { return nil }

    let height = min(max(box.height * 2.2, 0.05), 0.14)
    let centerY = box.midY
    // Vision y-up center → top-left-origin top edge.
    let top = 1 - (centerY + height / 2)
    return CGRect(x: left, y: min(max(top, 0), 1 - height), width: right - left, height: height)
  }
}
