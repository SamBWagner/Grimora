import Foundation

public enum RefinementIntent: String, Codable, Equatable, Hashable, Sendable {
    case include
    case exclude
}

public enum SearchRefinementState: String, CaseIterable, Equatable, Sendable {
    case neutral
    case include
    case exclude

    public var intent: RefinementIntent? {
        switch self {
        case .neutral:
            nil
        case .include:
            .include
        case .exclude:
            .exclude
        }
    }

    public var next: SearchRefinementState {
        switch self {
        case .neutral:
            .include
        case .include:
            .exclude
        case .exclude:
            .neutral
        }
    }
}

public struct SearchRefinementUpdate: Equatable, Sendable {
    public var refinement: SearchRefinement
    public var state: SearchRefinementState

    public init(refinement: SearchRefinement, state: SearchRefinementState) {
        self.refinement = refinement
        self.state = state
    }
}

public struct SearchRefinement: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var field: String
    public var value: String
    public var intent: RefinementIntent
    public var displayLabel: String

    public init(
        field: String,
        value: String,
        intent: RefinementIntent,
        displayLabel: String
    ) {
        self.field = field
        self.value = value
        self.intent = intent
        self.displayLabel = displayLabel
    }

    public var id: String {
        "\(intent.rawValue):\(field.lowercased()):\(value.lowercased())"
    }

    public var queryFragment: String {
        let prefix = intent == .exclude ? "-" : ""
        return "\(prefix)\(field):\(Self.quotedValue(value))"
    }

    public func withIntent(_ intent: RefinementIntent) -> SearchRefinement {
        var copy = self
        copy.intent = intent
        return copy
    }

    public static func forKeyword(
        _ keyword: String,
        intent: RefinementIntent = .include
    ) -> SearchRefinement {
        SearchRefinement(
            field: "keyword",
            value: keyword,
            intent: intent,
            displayLabel: keyword
        )
    }

    public static func forTypeWord(
        _ typeWord: String,
        intent: RefinementIntent = .include
    ) -> SearchRefinement {
        SearchRefinement(field: "t", value: typeWord, intent: intent, displayLabel: typeWord)
    }

    public static func forColorIdentity(
        _ colors: [String],
        intent: RefinementIntent = .include
    ) -> SearchRefinement {
        let normalizedColors = colors.map { $0.uppercased() }.sorted {
            Self.colorOrder($0) < Self.colorOrder($1)
        }
        let value = normalizedColors.isEmpty ? "C" : normalizedColors.joined()
        return SearchRefinement(
            field: "ci",
            value: value,
            intent: intent,
            displayLabel: normalizedColors.isEmpty ? "Colorless" : value
        )
    }

    public static func forManaValue(
        _ manaValue: Double,
        intent: RefinementIntent = .include
    ) -> SearchRefinement {
        let value = manaValue.formatted(
            .number.grouping(.never).precision(.fractionLength(0...2))
        )
        return SearchRefinement(
            field: "mv",
            value: value,
            intent: intent,
            displayLabel: "Mana value \(value)"
        )
    }

    public static func forRarity(
        _ rarity: String,
        intent: RefinementIntent = .include
    ) -> SearchRefinement {
        SearchRefinement(
            field: "r",
            value: rarity,
            intent: intent,
            displayLabel: rarity.capitalized
        )
    }

    public static func forSet(
        code: String,
        name: String,
        intent: RefinementIntent = .include
    ) -> SearchRefinement {
        SearchRefinement(field: "set", value: code, intent: intent, displayLabel: name)
    }

    public static func forSelectedOracleText(
        _ text: String,
        intent: RefinementIntent = .include
    ) -> SearchRefinement {
        let normalized = normalizedSelectedText(text)
        return SearchRefinement(field: "o", value: normalized, intent: intent, displayLabel: normalized)
    }

    public static func normalizedSelectedText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    public static func normalizedHiddenTerms(
        _ refinements: [SearchRefinement]
    ) -> [SearchRefinement] {
        var seen: Set<SearchRefinement.ID> = []
        return refinements.compactMap { refinement in
            let value = refinement.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }
            var excluded = refinement.withIntent(.exclude)
            excluded.value = value
            guard seen.insert(excluded.id).inserted else {
                return nil
            }
            return excluded
        }
    }

    private static func quotedValue(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return "\"\""
        }
        let canRemainBare = normalized.allSatisfy {
            $0.isLetter || $0.isNumber || "-_{}./".contains($0)
        }
        guard !canRemainBare else {
            return normalized
        }
        return "\"\(normalized.replacing("\\", with: "\\\\").replacing("\"", with: "\\\""))\""
    }

    private static func colorOrder(_ color: String) -> Int {
        ["W", "U", "B", "R", "G"].firstIndex(of: color) ?? Int.max
    }
}
