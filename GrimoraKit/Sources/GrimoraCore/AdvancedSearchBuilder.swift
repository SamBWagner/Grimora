import Foundation

/// A WUBRG colour used by the advanced-search form. Cases are declared in the
/// canonical Scryfall ordering so `allCases` already reads W → U → B → R → G.
public enum ScryfallColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case white = "W"
    case blue = "U"
    case black = "B"
    case red = "R"
    case green = "G"

    public var id: String { rawValue }

    /// The single-letter Scryfall symbol (`W`, `U`, `B`, `R`, `G`).
    public var symbol: String { rawValue }

    public var displayName: String {
        switch self {
        case .white: "White"
        case .blue: "Blue"
        case .black: "Black"
        case .red: "Red"
        case .green: "Green"
        }
    }
}

/// How a set of colours should be matched, mirroring Scryfall's advanced-search
/// colour options.
public enum AdvancedSearchColorMatch: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Exactly these colours and no others (`=`).
    case exactly
    /// These colours or fewer (`<=`).
    case atMost
    /// At least these colours (`>=`).
    case including

    public var id: String { rawValue }

    /// The Scryfall comparison operator used in the generated clause.
    public var operatorToken: String {
        switch self {
        case .exactly: "="
        case .atMost: "<="
        case .including: ">="
        }
    }

    public var displayName: String {
        switch self {
        case .exactly: "Exactly these colours"
        case .atMost: "At most these colours"
        case .including: "Including these colours"
        }
    }
}

/// A free-text criterion (card name, type line, oracle text) with an optional
/// negation, matching the form's per-row "negate" affordance.
public struct AdvancedSearchTextCriterion: Codable, Equatable, Sendable {
    public var text: String
    public var isNegated: Bool

    public init(text: String = "", isNegated: Bool = false) {
        self.text = text
        self.isNegated = isNegated
    }

    var intent: RefinementIntent {
        isNegated ? .exclude : .include
    }
}

/// A colour or colour-identity criterion: a chosen set of colours, a match
/// mode, and an optional negation.
public struct AdvancedSearchColorCriterion: Codable, Equatable, Sendable {
    public var colors: Set<ScryfallColor>
    public var match: AdvancedSearchColorMatch
    public var isNegated: Bool

    public init(
        colors: Set<ScryfallColor> = [],
        match: AdvancedSearchColorMatch = .including,
        isNegated: Bool = false
    ) {
        self.colors = colors
        self.match = match
        self.isNegated = isNegated
    }

    /// The colours in canonical WUBRG order, joined into a Scryfall value.
    var value: String {
        ScryfallColor.allCases.filter(colors.contains).map(\.symbol).joined()
    }
}

/// A numeric card stat that can be range-filtered in the form.
public enum AdvancedSearchStat: String, CaseIterable, Codable, Identifiable, Sendable {
    case manaValue
    case power
    case toughness

    public var id: String { rawValue }

    /// The canonical Scryfall field key.
    public var field: String {
        switch self {
        case .manaValue: "mv"
        case .power: "pow"
        case .toughness: "tou"
        }
    }

    public var displayName: String {
        switch self {
        case .manaValue: "Mana value"
        case .power: "Power"
        case .toughness: "Toughness"
        }
    }
}

/// A numeric comparison operator for a stat constraint.
public enum AdvancedSearchComparison: String, CaseIterable, Codable, Identifiable, Sendable {
    case equal
    case notEqual
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual

    public var id: String { rawValue }

    /// The Scryfall operator token.
    public var token: String {
        switch self {
        case .equal: "="
        case .notEqual: "!="
        case .lessThan: "<"
        case .lessThanOrEqual: "<="
        case .greaterThan: ">"
        case .greaterThanOrEqual: ">="
        }
    }

    public var displayName: String {
        switch self {
        case .equal: "is"
        case .notEqual: "is not"
        case .lessThan: "less than"
        case .lessThanOrEqual: "at most"
        case .greaterThan: "greater than"
        case .greaterThanOrEqual: "at least"
        }
    }
}

/// One row of a stat range filter. The form supports "Add another", so the
/// builder holds an array of these.
public struct AdvancedSearchStatConstraint: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var stat: AdvancedSearchStat
    public var comparison: AdvancedSearchComparison
    public var value: String
    public var isNegated: Bool

    public init(
        id: UUID = UUID(),
        stat: AdvancedSearchStat = .manaValue,
        comparison: AdvancedSearchComparison = .equal,
        value: String = "",
        isNegated: Bool = false
    ) {
        self.id = id
        self.stat = stat
        self.comparison = comparison
        self.value = value
        self.isNegated = isNegated
    }

    /// The Scryfall clause for this row, or `nil` when no value is entered.
    var clause: String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let prefix = isNegated ? "-" : ""
        return "\(prefix)\(stat.field)\(comparison.token)\(trimmed)"
    }
}

/// A Magic card rarity selectable in the form.
public enum AdvancedSearchRarity: String, CaseIterable, Codable, Identifiable, Sendable {
    case common
    case uncommon
    case rare
    case mythic

    public var id: String { rawValue }

    /// The Scryfall rarity value.
    public var scryfallValue: String { rawValue }

    public var displayName: String { rawValue.capitalized }
}

/// Whether a format constraint matches cards that are legal, banned, or
/// restricted in the chosen format.
public enum AdvancedSearchFormatStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case legal
    case banned
    case restricted

    public var id: String { rawValue }

    /// The Scryfall field used for this legality query.
    public var field: String {
        switch self {
        case .legal: "f"
        case .banned: "banned"
        case .restricted: "restricted"
        }
    }

    public var displayName: String { rawValue.capitalized }
}

/// A play format selectable in the form. Values are kept in sync with the
/// formats `ScryfallSyntaxValidator` recognises, so generated queries are
/// always valid.
public enum AdvancedSearchFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard
    case pioneer
    case modern
    case legacy
    case vintage
    case pauper
    case commander
    case oathbreaker
    case brawl
    case alchemy
    case historic
    case timeless
    case penny
    case premodern
    case oldschool

    public var id: String { rawValue }

    public var scryfallValue: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: "Standard"
        case .pioneer: "Pioneer"
        case .modern: "Modern"
        case .legacy: "Legacy"
        case .vintage: "Vintage"
        case .pauper: "Pauper"
        case .commander: "Commander"
        case .oathbreaker: "Oathbreaker"
        case .brawl: "Brawl"
        case .alchemy: "Alchemy"
        case .historic: "Historic"
        case .timeless: "Timeless"
        case .penny: "Penny Dreadful"
        case .premodern: "Premodern"
        case .oldschool: "Old School"
        }
    }
}

/// Form state for the advanced/simple search builder. Holds the structured
/// choices a user makes and compiles them into a Scryfall query string via
/// ``scryfallQuery``, reusing the existing `SearchRefinement` fragment logic so
/// values are quoted and negated consistently with the rest of the app.
public struct AdvancedSearchBuilder: Codable, Equatable, Sendable {
    public var name: AdvancedSearchTextCriterion
    public var typeLine: AdvancedSearchTextCriterion
    public var oracleText: AdvancedSearchTextCriterion

    public var colors: AdvancedSearchColorCriterion
    public var colorIdentity: AdvancedSearchColorCriterion

    public var rarities: Set<AdvancedSearchRarity>

    public var format: AdvancedSearchFormat?
    public var formatStatus: AdvancedSearchFormatStatus

    public var stats: [AdvancedSearchStatConstraint]

    public init(
        name: AdvancedSearchTextCriterion = .init(),
        typeLine: AdvancedSearchTextCriterion = .init(),
        oracleText: AdvancedSearchTextCriterion = .init(),
        colors: AdvancedSearchColorCriterion = .init(),
        colorIdentity: AdvancedSearchColorCriterion = .init(match: .atMost),
        rarities: Set<AdvancedSearchRarity> = [],
        format: AdvancedSearchFormat? = nil,
        formatStatus: AdvancedSearchFormatStatus = .legal,
        stats: [AdvancedSearchStatConstraint] = []
    ) {
        self.name = name
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.colors = colors
        self.colorIdentity = colorIdentity
        self.rarities = rarities
        self.format = format
        self.formatStatus = formatStatus
        self.stats = stats
    }

    /// The Scryfall query string described by the current form state. Returns an
    /// empty string when no criteria are set.
    public var scryfallQuery: String {
        var clauses: [String] = []

        clauses.append(contentsOf: [
            textClause(field: "name", name),
            colorClause(field: "c", colors),
            colorClause(field: "id", colorIdentity),
            textClause(field: "t", typeLine),
            textClause(field: "o", oracleText),
        ].compactMap { $0 })

        clauses.append(contentsOf: stats.compactMap(\.clause))

        if let rarityClause {
            clauses.append(rarityClause)
        }

        if let formatClause {
            clauses.append(formatClause)
        }

        return clauses.joined(separator: " ")
    }

    /// Whether the form currently describes any search criteria.
    public var isEmpty: Bool {
        scryfallQuery.isEmpty
    }

    /// Appends a new, empty stat row (the "Add another" action).
    public mutating func addStat() {
        stats.append(AdvancedSearchStatConstraint())
    }

    /// Resets the form back to its empty state.
    public mutating func reset() {
        self = AdvancedSearchBuilder()
    }

    private func textClause(field: String, _ criterion: AdvancedSearchTextCriterion) -> String? {
        let value = criterion.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        return SearchRefinement(
            field: field,
            value: value,
            intent: criterion.intent,
            displayLabel: value
        ).queryFragment
    }

    private func colorClause(field: String, _ criterion: AdvancedSearchColorCriterion) -> String? {
        let value = criterion.value
        guard !value.isEmpty else {
            return nil
        }
        let prefix = criterion.isNegated ? "-" : ""
        return "\(prefix)\(field)\(criterion.match.operatorToken)\(value)"
    }

    private var rarityClause: String? {
        let ordered = AdvancedSearchRarity.allCases.filter(rarities.contains)
        guard !ordered.isEmpty else {
            return nil
        }
        let terms = ordered.map { "r:\($0.scryfallValue)" }
        guard terms.count > 1 else {
            return terms[0]
        }
        return "(\(terms.joined(separator: " or ")))"
    }

    private var formatClause: String? {
        guard let format else {
            return nil
        }
        return SearchRefinement(
            field: formatStatus.field,
            value: format.scryfallValue,
            intent: .include,
            displayLabel: format.displayName
        ).queryFragment
    }
}
