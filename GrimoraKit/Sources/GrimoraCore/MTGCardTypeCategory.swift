import Foundation

/// Classifies a card by its primary card type and supplies the category names and
/// ordering Grimora uses when auto-organizing a deck "by type".
///
/// A Magic type line reads `[supertypes] [types] — [subtypes]`. The *primary type* is
/// the first real card type in reading order on the card's front face, so
/// "Enchantment Creature" → Enchantment, "Battle — Siege" → Battle, and
/// "Instant // Land" → Instant. Supertypes (Legendary, Basic, Snow, …), subtypes, and
/// the Kindred/Tribal modifier are skipped because they aren't the card's main type —
/// e.g. "Kindred Sorcery" classifies as Sorcery, not Kindred.
public enum MTGCardTypeCategory {
    /// Every card type Grimora recognizes when *counting* the types on a card (used by
    /// the collection dashboard). Broader than the set used to pick a single primary
    /// type — it includes the Kindred modifier and the un-set/gimmick types.
    public static let allRecognizedTypes: [String] = [
        "Artifact",
        "Battle",
        "Conspiracy",
        "Creature",
        "Dungeon",
        "Enchantment",
        "Instant",
        "Kindred",
        "Land",
        "Phenomenon",
        "Plane",
        "Planeswalker",
        "Scheme",
        "Sorcery",
        "Vanguard",
    ]

    /// Lowercased type word → canonical capitalized spelling, for parsing type lines.
    /// Shared with `CardCollectionDashboardStats` so the two stay in lock-step.
    static let recognizedTypeByLowercase: [String: String] =
        Dictionary(uniqueKeysWithValues: allRecognizedTypes.map { ($0.lowercased(), $0) })

    /// The real card types a deck is organized by, in the order categories should be
    /// created so a reorganized deck reads top-to-bottom in a familiar order. Membership
    /// in this set is what makes a word eligible to be a card's *primary* type.
    public static let primaryTypeOrder: [String] = [
        "Creature",
        "Planeswalker",
        "Battle",
        "Instant",
        "Sorcery",
        "Artifact",
        "Enchantment",
        "Land",
    ]

    private static let primaryTypeByLowercase: [String: String] =
        Dictionary(uniqueKeysWithValues: primaryTypeOrder.map { ($0.lowercased(), $0) })

    /// The primary card type of `card` — the first real card type on its front face — or
    /// `nil` when the type line has no recognizable card type (e.g. a stray token).
    public static func primaryType(for card: CardRecord) -> String? {
        for typeLine in typeLines(for: card) {
            if let type = primaryType(inTypeLine: typeLine) {
                return type
            }
        }
        return nil
    }

    /// The first real card type in `typeLine`, scanning the front face (text before the
    /// first `//`) and ignoring subtypes (text after the em-dash). Case-insensitive.
    public static func primaryType(inTypeLine typeLine: String) -> String? {
        let frontFace = typeLine.components(separatedBy: "//").first ?? typeLine
        let frontMatter = frontFace.components(separatedBy: "\u{2014}").first ?? frontFace
        for word in frontMatter.split(whereSeparator: { !$0.isLetter }) {
            if let type = primaryTypeByLowercase[word.lowercased()] {
                return type
            }
        }
        return nil
    }

    /// The category name a card of `type` is filed under (a pluralized display name,
    /// e.g. Creature → "Creatures", Sorcery → "Sorceries", Land → "Lands").
    public static func categoryName(forType type: String) -> String {
        irregularPlurals[type] ?? "\(type)s"
    }

    /// Stable ordering key used when creating type categories. Types not in
    /// `primaryTypeOrder` sort after the known ones.
    public static func canonicalIndex(forType type: String) -> Int {
        primaryTypeOrder.firstIndex(of: type) ?? primaryTypeOrder.count
    }

    private static let irregularPlurals: [String: String] = [
        "Sorcery": "Sorceries",
    ]

    /// The type lines to consider for `card`: its own line, or its faces' lines when the
    /// card has no top-level type line (MDFC/split). Mirrors the dashboard's logic so a
    /// double-faced card classifies by its front face.
    private static func typeLines(for card: CardRecord) -> [String] {
        let typeLine = card.typeLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typeLine.isEmpty {
            return [typeLine]
        }
        return card.faces
            .map(\.typeLine)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
