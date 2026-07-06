import Foundation

public struct CardCollectionRulesetWarning: Identifiable, Equatable, Sendable {
    public var id: String
    public var message: String

    public init(id: String, message: String) {
        self.id = id
        self.message = message
    }
}

public enum CardCollectionRulesetValidator {
    public static func warnings(
        for list: CardCollectionRecord,
        entries: [CardCollectionEntryRecord]
    ) -> [CardCollectionRulesetWarning] {
        switch list.ruleset {
        case .none:
            return []
        case .commander:
            return commanderWarnings(entries: entries)
        }
    }

    private static func commanderWarnings(entries: [CardCollectionEntryRecord]) -> [CardCollectionRulesetWarning] {
        var warnings: [CardCollectionRulesetWarning] = []
        let commanderQuantity = quantity(in: entries, zones: [.commander])
        let deckQuantity = quantity(in: entries, zones: [.commander, .mainboard])

        if commanderQuantity < 1 {
            warnings.append(.init(id: "commander-missing", message: "Commander needs at least 1 commander."))
        } else if commanderQuantity > 2 {
            warnings.append(.init(id: "commander-too-many", message: "Commander allows at most 2 commanders."))
        }

        if deckQuantity != 100 {
            warnings.append(.init(id: "commander-size", message: "Commander decks must contain exactly 100 cards including commanders."))
        }

        warnings.append(contentsOf: legalityWarnings(ruleset: .commander, entries: entries))
        warnings.append(contentsOf: copyLimitWarnings(
            entries: entries.filter { [.commander, .mainboard].contains($0.zone) },
            maximumCopies: 1,
            warningIDPrefix: "commander-singleton",
            message: { name, quantity in
                "Commander allows only 1 copy of \(name); this collection has \(quantity)."
            }
        ))

        return warnings
    }

    private static func legalityWarnings(
        ruleset: CardCollectionRuleset,
        entries: [CardCollectionEntryRecord]
    ) -> [CardCollectionRulesetWarning] {
        guard let legalityKey = ruleset.legalityKey else {
            return []
        }

        var warnings: [CardCollectionRulesetWarning] = []
        var warnedKeys: Set<String> = []
        for entry in entries {
            guard let card = entry.card else {
                continue
            }
            let identity = identityKey(for: card)
            guard warnedKeys.insert(identity).inserted else {
                continue
            }
            guard card.legalities[legalityKey] == "legal" else {
                warnings.append(.init(
                    id: "\(ruleset.rawValue)-legality-\(identity)",
                    message: "\(card.name) is not legal in \(ruleset.title)."
                ))
                continue
            }
        }
        return warnings
    }

    private static func copyLimitWarnings(
        entries: [CardCollectionEntryRecord],
        maximumCopies: Int,
        warningIDPrefix: String,
        message: (String, Int) -> String
    ) -> [CardCollectionRulesetWarning] {
        var groups: [String: (name: String, quantity: Int, exempt: Bool)] = [:]

        for entry in entries {
            guard let card = entry.card else {
                continue
            }
            let key = identityKey(for: card)
            let existing = groups[key] ?? (name: card.name, quantity: 0, exempt: isCopyLimitExempt(card))
            groups[key] = (
                name: existing.name,
                quantity: existing.quantity + entry.quantity,
                exempt: existing.exempt || isCopyLimitExempt(card)
            )
        }

        return groups
            .filter { _, value in !value.exempt && value.quantity > maximumCopies }
            .sorted { lhs, rhs in lhs.value.name.localizedCaseInsensitiveCompare(rhs.value.name) == .orderedAscending }
            .map { key, value in
                CardCollectionRulesetWarning(
                    id: "\(warningIDPrefix)-\(key)",
                    message: message(value.name, value.quantity)
                )
            }
    }

    private static func quantity(in entries: [CardCollectionEntryRecord], zones: Set<CardCollectionZone>) -> Int {
        entries.reduce(0) { total, entry in
            zones.contains(entry.zone) ? total + entry.quantity : total
        }
    }

    /// The oracle identity used to group printings of the same card. Two different
    /// printings share an identity, so singleton/copy limits apply across art swaps.
    public static func identityKey(for card: CardRecord) -> String {
        card.oracleID ?? (card.displayNameKey.isEmpty ? card.name.sortKey : card.displayNameKey)
    }

    /// Whether a card may appear in unlimited quantity regardless of a format's copy
    /// limit — basic lands and cards that say "a deck can have any number of cards
    /// named …" (e.g. Relentless Rats). Everything else is a singleton in Commander.
    public static func isCopyLimitExempt(_ card: CardRecord) -> Bool {
        let typeLine = card.typeLine.sortKey
        let oracleText = card.oracleText.sortKey
        return typeLine.contains("basic") && typeLine.contains("land")
            || oracleText.contains("a deck can have any number of cards named")
    }
}
