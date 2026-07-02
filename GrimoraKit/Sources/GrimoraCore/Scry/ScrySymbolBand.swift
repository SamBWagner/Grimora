import CoreGraphics
import Foundation

/// Where to look for the set symbol, on the scan and on reference images.
///
/// Scan side: the symbol sits right of the type line, so when OCR anchored a
/// type line the band comes from the card's own geometry (`ScryLineMap`) — that
/// is what makes sagas and classes (type line ~87% down) work without special
/// cases. Without an anchor, fall back to the standard-frame band.
///
/// Reference side: references are perfectly-framed Scryfall scans, so the band
/// is chosen from the candidate's own **metadata** (`card.layout`) — cheaper and
/// more deterministic than OCR-ing every reference.
public enum ScrySymbolBand {
  /// Right end of the type line on every standard frame era (1993–2015+),
  /// top-left-origin normalized. Verified by cropping real scans.
  public static let standard = CGRect(x: 0.70, y: 0.535, width: 0.26, height: 0.10)

  /// Sagas, classes and cases put the type line — and the symbol — low on the
  /// card (symbol measured at y ≈ 0.85–0.89 on DOM sagas and AFR classes).
  public static let low = CGRect(x: 0.70, y: 0.82, width: 0.26, height: 0.11)

  /// Layouts whose faces are rotated or unconventional enough that a fixed
  /// reference band would crop frame furniture, not the symbol. Candidates with
  /// these layouts can't be measured, which (by the matcher's full-coverage
  /// rule) keeps their pickers unrefined rather than wrongly promoted.
  public static let unsupportedLayouts: Set<String> = ["split", "flip", "battle", "art_series"]

  /// The band to crop from the scanned card.
  public static func scanBand(from lineMap: ScryLineMap?) -> CGRect {
    lineMap?.symbolBand ?? standard
  }

  /// The band to crop from a candidate's reference image, or `nil` when the
  /// candidate's layout defeats band cropping.
  public static func referenceBand(for card: CardRecord) -> CGRect? {
    guard !unsupportedLayouts.contains(card.layout) else { return nil }
    // Battles are layout "transform" on Scryfall but physically landscape —
    // a portrait band would crop frame furniture, so gate by type line.
    if card.typeLine.hasPrefix("Battle") { return nil }
    switch card.layout {
    case "saga", "class", "case":
      return low
    default:
      return standard
    }
  }
}
