import Foundation

/// Pure heuristics for deciding whether an OCR'd line is a card *name* (the title)
/// versus something that masquerades as one — most importantly the **type line**.
///
/// This exists because of a real on-device failure: when an old card's title
/// didn't OCR cleanly, the extractor fell back to the type line "Land", and a
/// name search for "Land" returned a list of unrelated land cards. Better to read
/// no name than the wrong one.
public enum ScryNameHeuristics {
  /// Card types / supertypes that appear on the type line. A bare one of these is
  /// never a card name, and a line beginning with one before a "—" is a type line.
  static let typeWords: Set<String> = [
    "land", "creature", "artifact", "instant", "sorcery", "enchantment",
    "planeswalker", "battle", "token", "tribal", "kindred", "basic", "legendary",
    "snow", "conspiracy", "scheme", "plane", "phenomenon", "vanguard", "emblem",
    "dungeon", "summon", "interrupt", "world", "ongoing", "host"
  ]

  /// A line worth considering as a name: it has at least a couple of letters.
  public static func isNameLike(_ text: String) -> Bool {
    text.filter(\.isLetter).count >= 2
  }

  /// True when the line is a type line or bare type word rather than a card name.
  public static func looksLikeTypeLine(_ text: String) -> Bool {
    // Strip stray punctuation so "creature." (rules-text fragment with OCR
    // noise) is judged by its words, not its period.
    let normalized = text.normalizedQueryKey
      .trimmingCharacters(in: .whitespaces)
      .trimmingCharacters(in: .punctuationCharacters)
    guard !normalized.isEmpty else { return false }

    if typeWords.contains(normalized) {
      return true  // a bare "Land" / "Artifact"
    }

    let firstWord = normalized.split(separator: " ").first.map(String.init) ?? normalized

    // An aura's "Enchant creature" / "Enchant land" ability line sits directly
    // under the type line and reads like a name when the title is lost (a real
    // clipped-crop failure). No Magic card's name starts with the word
    // "enchant", so the first word alone is decisive.
    if firstWord == "enchant" {
      return true
    }

    // Same trap on equipment: a crop that clipped the title reads the keyword
    // cost line "Equip 2 (2: Attach to target creature…)" as the name (a real
    // Beamtown Beatstick capture). No card name's first word is bare "equip"
    // ("Equipoise" is one word, so it survives this check).
    if firstWord == "equip" {
      return true
    }

    // A type line like "Land — Desert" or "Creature — Goblin Sorcerer".
    if text.contains("—") || text.contains("–") || text.contains(" - ") {
      if typeWords.contains(firstWord) { return true }
    }

    return false
  }

  /// Whether a line is acceptable as the card name.
  public static func isAcceptableName(_ text: String) -> Bool {
    isNameLike(text) && !looksLikeTypeLine(text)
  }
}
