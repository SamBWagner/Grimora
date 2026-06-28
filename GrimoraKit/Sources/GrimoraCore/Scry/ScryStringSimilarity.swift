import Foundation

/// Fuzzy name comparison used to corroborate noisy OCR against database names.
///
/// There is no fuzzy-matcher elsewhere in the codebase; this is the one place
/// Scry needs it. Comparison is case- and diacritic-insensitive via the shared
/// `normalizedQueryKey` so it lines up with how the search layer normalizes names.
public enum ScryStringSimilarity {
  /// Similarity in `0...1` based on Levenshtein edit distance over normalized text.
  ///
  /// `1` means identical after normalization, `0` means completely different.
  public static func nameSimilarity(_ lhs: String, _ rhs: String) -> Double {
    let a = Array(lhs.normalizedQueryKey)
    let b = Array(rhs.normalizedQueryKey)
    if a.isEmpty, b.isEmpty { return 1 }
    if a.isEmpty || b.isEmpty { return 0 }
    let distance = levenshtein(a, b)
    let maxLength = max(a.count, b.count)
    return 1 - (Double(distance) / Double(maxLength))
  }

  /// Classic two-row Levenshtein edit distance.
  static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)

    for i in 1...a.count {
      current[0] = i
      for j in 1...b.count {
        let substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1
        current[j] = min(
          previous[j] + 1,        // deletion
          current[j - 1] + 1,     // insertion
          previous[j - 1] + substitutionCost  // substitution
        )
      }
      swap(&previous, &current)
    }

    return previous[b.count]
  }
}
