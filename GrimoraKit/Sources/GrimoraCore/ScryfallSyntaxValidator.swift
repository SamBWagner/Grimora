import Foundation

public enum ScryfallSyntaxValidator {
    public static func validate(_ text: String) -> ScryfallSyntaxValidation {
        switch ScryfallSyntaxParser.parse(text) {
        case .failure(let diagnostic):
            return ScryfallSyntaxValidation(
                query: text,
                syntaxTree: nil,
                isValidScryfall: false,
                isSupportedOffline: false,
                diagnostics: [diagnostic],
                unsupportedTerms: []
            )
        case .success(let tree):
            let diagnostics = validateScryfallSyntax(tree.root, query: text)
            guard diagnostics.isEmpty else {
                return ScryfallSyntaxValidation(
                    query: text,
                    syntaxTree: tree,
                    isValidScryfall: false,
                    isSupportedOffline: false,
                    diagnostics: diagnostics,
                    unsupportedTerms: []
                )
            }

            switch SearchQuery.compileSyntaxTree(tree) {
            case .success:
                return ScryfallSyntaxValidation(
                    query: text,
                    syntaxTree: tree,
                    isValidScryfall: true,
                    isSupportedOffline: true,
                    diagnostics: [],
                    unsupportedTerms: []
                )
            case .failure(let reason):
                return ScryfallSyntaxValidation(
                    query: text,
                    syntaxTree: tree,
                    isValidScryfall: true,
                    isSupportedOffline: false,
                    diagnostics: [],
                    unsupportedTerms: [ScryfallUnsupportedSyntaxTerm(token: reason.token, reason: reason)]
                )
            }
        }
    }

    private static func validateScryfallSyntax(
        _ node: ScryfallQueryNode,
        query: String
    ) -> [ScryfallSyntaxDiagnostic] {
        switch node {
        case .all:
            return []
        case .term(let term):
            return validateTerm(term, query: query).map { [$0] } ?? []
        case .and(let nodes), .or(let nodes):
            return nodes.flatMap { validateScryfallSyntax($0, query: query) }
        case .not(let node):
            return validateScryfallSyntax(node, query: query)
        }
    }

    private static func validateTerm(
        _ term: ScryfallQueryTerm,
        query: String
    ) -> ScryfallSyntaxDiagnostic? {
        guard case .condition(let condition) = term else {
            return nil
        }

        guard let field = ScryfallSyntaxFieldRegistry.field(for: condition.field) else {
            return ScryfallSyntaxDiagnostic(
                query: query,
                token: condition.original,
                message: "“\(condition.original)” is not a recognized Scryfall search term."
            )
        }

        let value = condition.value.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return ScryfallSyntaxDiagnostic(
                query: query,
                token: condition.original,
                message: "“\(condition.original)” needs a value after `\(condition.operatorToken)`."
            )
        }

        if condition.value.isRegularExpression, field.valueRule != .regexText {
            return ScryfallSyntaxDiagnostic(
                query: query,
                token: condition.original,
                message: "Regular expressions are only valid for name, type, oracle, or flavor searches."
            )
        }

        switch field.valueRule {
        case .color:
            guard isValidColorValue(value) else {
                return ScryfallSyntaxDiagnostic(
                    query: query,
                    token: condition.original,
                    message: colorDiagnosticMessage(for: condition)
                )
            }
        case .direction:
            guard ["asc", "ascending", "desc", "descending"].contains(value.normalizedScryfallSyntaxKey) else {
                return ScryfallSyntaxDiagnostic(
                    query: query,
                    token: condition.original,
                    message: "“\(condition.original)” must use `direction:asc` or `direction:desc`."
                )
            }
        case .include:
            guard ["extras", "extra", "multilingual", "variations"].contains(value.normalizedScryfallSyntaxKey) else {
                return ScryfallSyntaxDiagnostic(
                    query: query,
                    token: condition.original,
                    message: "“\(condition.original)” is not a supported Scryfall include option."
                )
            }
        case .legality:
            guard validFormatValues.contains(value.normalizedScryfallSyntaxKey) else {
                return ScryfallSyntaxDiagnostic(
                    query: query,
                    token: condition.original,
                    message: "“\(condition.original)” does not name a recognized Scryfall format."
                )
            }
        case .newFlag:
            guard ["art", "artist", "flavor", "rarity", "frame", "language"].contains(value.normalizedScryfallSyntaxKey) else {
                return ScryfallSyntaxDiagnostic(
                    query: query,
                    token: condition.original,
                    message: "“\(condition.original)” is not a recognized `new:` Scryfall flag."
                )
            }
        case .rarity:
            guard validRarityValues.contains(value.normalizedScryfallSyntaxKey) else {
                return ScryfallSyntaxDiagnostic(
                    query: query,
                    token: condition.original,
                    message: "“\(condition.original)” does not name a recognized Scryfall rarity."
                )
            }
        case .display, .regexText, .any:
            break
        }

        return nil
    }

    private static func isValidColorValue(_ value: String) -> Bool {
        let normalized = value.normalizedScryfallSyntaxKey
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        if Int(normalized) != nil {
            return true
        }
        if ["c", "colorless", "m", "multicolor"].contains(normalized) {
            return true
        }
        if colorNicknames[normalized] != nil {
            return true
        }
        let named: Set<String> = ["white", "blue", "black", "red", "green"]
        if named.contains(normalized) {
            return true
        }
        return !normalized.isEmpty && normalized.allSatisfy { ["w", "u", "b", "r", "g"].contains(String($0)) }
    }

    private static func colorDiagnosticMessage(for condition: ScryfallSyntaxCondition) -> String {
        let normalizedField = condition.field.normalizedScryfallSyntaxKey
        let normalizedValue = condition.value.text.normalizedScryfallSyntaxKey
        if ["c", "color"].contains(normalizedField) {
            var detail =
                "`c:` searches card colors and only accepts W/U/B/R/G, colorless, multicolor, or color nicknames."
            if normalizedValue == "token" {
                detail += " For cards that create creature tokens, use `o:\"creature token\"`."
            }
            return detail
        }
        return "“\(condition.original)” does not use a recognized Scryfall color value."
    }

    private static let colorNicknames: [String: String] = [
        "azorius": "wu", "dimir": "ub", "rakdos": "br", "gruul": "rg", "selesnya": "gw",
        "orzhov": "wb", "izzet": "ur", "golgari": "bg", "boros": "rw", "simic": "gu",
        "bant": "wug", "esper": "wub", "grixis": "ubr", "jund": "brg", "naya": "rgw",
        "abzan": "wbg", "jeskai": "urw", "sultai": "bgu", "mardu": "rwb", "temur": "gur",
        "quandrix": "gu", "silverquill": "wb", "prismari": "ur", "witherbloom": "bg",
        "lorehold": "rw", "chaos": "ubr", "aggression": "brg", "altruism": "gwu",
        "growth": "wbg", "artifice": "urw"
    ]

    private static let validFormatValues: Set<String> = [
        "standard", "future", "historic", "timeless", "gladiator", "pioneer", "modern",
        "legacy", "pauper", "vintage", "penny", "commander", "oathbreaker",
        "standardbrawl", "brawl", "alchemy", "paupercommander", "duel", "duelcommander",
        "oldschool", "premodern", "predh", "tlr"
    ]

    private static let validRarityValues: Set<String> = [
        "c", "common", "u", "uncommon", "r", "rare", "m", "mythic", "special", "bonus"
    ]
}
