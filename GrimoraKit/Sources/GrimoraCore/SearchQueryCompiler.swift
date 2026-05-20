import Foundation

struct CompiledClause: Equatable {
    var sql: String?
    var bindings: [SearchQuery.SQLBinding] = []
    var postFilters: [SearchQuery.PostFilter] = []
}

struct Compiler {
    var query: String
    var displayOptions = SearchDisplayOptions()

    mutating func compile(_ node: ScryfallQueryNode) throws -> CompiledClause {
        switch node {
        case .all:
            return CompiledClause()
        case .term(let term):
            return try compileTermNode(term)
        case .and(let nodes):
            let clauses = try nodes.map { try compile($0) }
            let sql = clauses.compactMap(\.sql).filter { !$0.isEmpty }
            return CompiledClause(
                sql: sql.isEmpty ? nil : sql.map { "(\($0))" }.joined(separator: " AND "),
                bindings: clauses.flatMap(\.bindings),
                postFilters: clauses.flatMap(\.postFilters)
            )
        case .or(let nodes):
            let clauses = try nodes.map { try compile($0) }
            guard clauses.allSatisfy({ $0.postFilters.isEmpty }) else {
                throw QueryError.unsupported(query: query, token: "OR", message: "Regular expression searches cannot be combined with OR offline yet.")
            }
            let sql = clauses.compactMap(\.sql).filter { !$0.isEmpty }
            return CompiledClause(
                sql: sql.isEmpty ? nil : sql.map { "(\($0))" }.joined(separator: " OR "),
                bindings: clauses.flatMap(\.bindings)
            )
        case .not(let node):
            return try negate(compile(node))
        }
    }

    private mutating func compileTermNode(_ term: ScryfallQueryTerm) throws -> CompiledClause {
        switch term {
        case .bare(let value):
            return try compileTerm(value)
        case .exactName(let value):
            return CompiledClause(sql: "display_name_key = ?", bindings: [.text(value.normalizedQueryKey)])
        case .condition(let condition):
            let field = condition.field
            let op = condition.operatorToken
            let value = condition.value.text
            let original = condition.original
            if field == "not" {
                return try negate(compileCondition(field: "is", op: op, value: value, original: original))
            }
            return try compileCondition(field: field, op: op, value: value, original: original)
        }
    }

    private func negate(_ clause: CompiledClause) -> CompiledClause {
        CompiledClause(
            sql: clause.sql.map { "NOT (\($0))" },
            bindings: clause.bindings,
            postFilters: clause.postFilters.map {
                SearchQuery.PostFilter(field: $0.field, pattern: $0.pattern, negated: !$0.negated)
            }
        )
    }

    private mutating func compileTerm(_ value: String) throws -> CompiledClause {
        let normalized = value.normalizedQueryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return CompiledClause()
        }
        return compileNameContains(column: "display_name_key", value: value)
    }

    private mutating func compileCondition(field rawField: String, op rawOp: String, value rawValue: String, original: String) throws -> CompiledClause {
        let field = canonicalField(rawField)
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = value.normalizedQueryKey

        if ["cube", "art", "atag", "arttag", "function", "otag", "oracletag"].contains(field) {
            throw QueryError.unsupported(query: query, token: original)
        }

        if handleDisplay(field: field, value: normalizedValue, original: original) {
            return CompiledClause()
        }

        if field == "include" {
            if ["extras", "extra", "multilingual", "variations"].contains(normalizedValue) {
                displayOptions.includeExtras = true
                return CompiledClause()
            }
            throw QueryError.unsupported(query: query, token: original)
        }

        if field == "is" {
            return try compileFlag(normalizedValue, original: original)
        }

        if field == "has" {
            return try compileHas(normalizedValue, original: original)
        }

        if field == "new" {
            return try compileNew(normalizedValue, original: original)
        }

        if field == "color" {
            return try compileColor(column: "colors_key", countColumn: "color_count", op: rawOp, value: normalizedValue, original: original)
        }

        if field == "identity" {
            return try compileIdentity(op: rawOp, value: normalizedValue, original: original)
        }

        if field == "produces" {
            return try compileColor(column: "produced_mana_key", countColumn: "produced_mana_count", op: rawOp, value: normalizedValue, original: original)
        }

        switch field {
        case "name":
            if let pattern = regexPattern(from: value) {
                return CompiledClause(postFilters: [SearchQuery.PostFilter(field: .name, pattern: pattern, negated: false)])
            }
            return compileNameContains(column: "name_key", value: value)
        case "type":
            return compileText(column: "type_line_key", value: value, original: original, regexField: .type)
        case "oracle", "fulloracle":
            return compileText(column: "oracle_text_key", value: value.replacingOccurrences(of: "~", with: ""), original: original, regexField: .oracle)
        case "keyword":
            return compileListContains(column: "keywords_key", value: normalizedValue)
        case "mana":
            return compileMana(op: rawOp, value: value, original: original)
        case "manavalue":
            return compileNumeric(column: "mana_value", op: rawOp, value: normalizedValue, original: original)
        case "power":
            return compileNumericOrColumn(column: "power_value", op: rawOp, value: normalizedValue, original: original)
        case "toughness":
            return compileNumericOrColumn(column: "toughness_value", op: rawOp, value: normalizedValue, original: original)
        case "loyalty":
            return compileNumeric(column: "loyalty_value", op: rawOp, value: normalizedValue, original: original)
        case "powtou":
            return compileNumeric(column: "(COALESCE(power_value, 0) + COALESCE(toughness_value, 0))", op: rawOp, value: normalizedValue, original: original)
        case "artist":
            return compileText(column: "artist_key", value: value, original: original, regexField: nil)
        case "flavor":
            return compileText(column: "flavor_text_key", value: value, original: original, regexField: .flavor)
        case "watermark":
            return compileScalar(column: "watermark", op: rawOp, value: normalizedValue)
        case "rarity":
            return compileRarity(op: rawOp, value: normalizedValue, original: original)
        case "set":
            return compileScalar(column: "set_code", op: rawOp, value: normalizedValue)
        case "number":
            return compileCollectorNumber(op: rawOp, value: normalizedValue)
        case "settype":
            return compileScalar(column: "set_type", op: rawOp, value: normalizedValue)
        case "block":
            return try compileBlock(value: normalizedValue, original: original)
        case "in":
            return try compileIn(value: normalizedValue, op: rawOp, original: original)
        case "format", "legal":
            return compileLegality(format: normalizedValue, status: "legal")
        case "banned":
            return compileLegality(format: normalizedValue, status: "banned")
        case "restricted":
            return compileLegality(format: normalizedValue, status: "restricted")
        case "usd":
            return compileNumeric(column: "price_usd", op: rawOp, value: normalizedValue, original: original)
        case "eur":
            return compileNumeric(column: "price_eur", op: rawOp, value: normalizedValue, original: original)
        case "tix":
            return compileNumeric(column: "price_tix", op: rawOp, value: normalizedValue, original: original)
        case "border":
            return compileScalar(column: "border_color", op: rawOp, value: normalizedValue)
        case "frame":
            return compileFrame(value: normalizedValue, op: rawOp)
        case "stamp":
            return compileScalar(column: "security_stamp", op: rawOp, value: normalizedValue)
        case "game":
            return compileListContains(column: "games_key", value: normalizedValue)
        case "year":
            return compileYear(op: rawOp, value: normalizedValue, original: original)
        case "date":
            return compileDate(op: rawOp, value: normalizedValue)
        case "lang", "language":
            if normalizedValue == "any" {
                displayOptions.printingDisplayMode = .all
                return CompiledClause()
            }
            return compileScalar(column: "lang", op: rawOp, value: languageCode(normalizedValue))
        case "devotion":
            return compileDevotion(value: normalizedValue)
        case "artists":
            return compileNumeric(column: "artist_count", op: rawOp, value: normalizedValue, original: original)
        case "illustrations":
            return compileNumeric(column: "illustration_count", op: rawOp, value: normalizedValue, original: original)
        case "prints":
            return compileNumeric(column: "print_count", op: rawOp, value: normalizedValue, original: original)
        case "sets":
            return compileNumeric(column: "set_count", op: rawOp, value: normalizedValue, original: original)
        case "paperprints":
            return compileNumeric(column: "paper_print_count", op: rawOp, value: normalizedValue, original: original)
        case "papersets":
            return compileNumeric(column: "paper_set_count", op: rawOp, value: normalizedValue, original: original)
        default:
            throw QueryError.unsupported(query: query, token: original)
        }
    }

    private mutating func handleDisplay(field: String, value: String, original: String) -> Bool {
        switch field {
        case "unique":
            switch value {
            case "cards":
                displayOptions.printingDisplayMode = .preferred
            case "prints":
                displayOptions.printingDisplayMode = .all
            case "art":
                displayOptions.printingDisplayMode = .art
            default:
                break
            }
            return true
        case "order":
            displayOptions.sortMode = SortMode(scryfallOrder: value)
            return true
        case "direction":
            if ["desc", "descending"].contains(value) {
                displayOptions.sortDirection = .descending
            } else if ["asc", "ascending"].contains(value) {
                displayOptions.sortDirection = .ascending
            }
            return true
        case "prefer":
            if let preference = SearchPreference(scryfallValue: value) {
                displayOptions.preferences.insert(preference)
            }
            return true
        case "display":
            return true
        case "cheapest":
            displayOptions.sortMode = SortMode(scryfallOrder: value)
            if value == "usd" {
                displayOptions.preferences.insert(.usdLow)
            }
            return true
        default:
            return false
        }
    }
}
