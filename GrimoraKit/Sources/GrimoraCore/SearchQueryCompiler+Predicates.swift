import Foundation

extension Compiler {
    func compileText(column: String, value: String, original: String, regexField: SearchQuery.PostFilter.Field?) -> CompiledClause {
        if let regexField, let pattern = regexPattern(from: value) {
            return CompiledClause(postFilters: [SearchQuery.PostFilter(field: regexField, pattern: pattern, negated: false)])
        }
        return CompiledClause(sql: "\(column) LIKE ?", bindings: [.text("%\(value.normalizedQueryKey)%")])
    }

    func compileNameContains(column: String, value: String) -> CompiledClause {
        let normalized = value.normalizedQueryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ftsExpression = SearchQuery.ftsExpression(for: value) else {
            return CompiledClause(sql: "\(column) LIKE ?", bindings: [.text("%\(normalized)%")])
        }

        return CompiledClause(
            sql: """
            id IN (
                SELECT card_id
                FROM cards_name_fts
                WHERE cards_name_fts MATCH ?
            )
            AND \(column) LIKE ?
            """,
            bindings: [.text(ftsExpression), .text("%\(normalized)%")]
        )
    }

    func compileScalar(column: String, op: String, value: String) -> CompiledClause {
        let sqlOperator = sqlOperator(for: op, defaultOperator: "=")
        return CompiledClause(sql: "\(column) \(sqlOperator) ?", bindings: [.text(value)])
    }

    func compileListContains(column: String, value: String) -> CompiledClause {
        CompiledClause(sql: "\(column) LIKE ?", bindings: [.text("%|\(value)|%")])
    }

    func compileLegality(format: String, status: String) -> CompiledClause {
        CompiledClause(sql: "legalities_key LIKE ?", bindings: [.text("%|\(format):\(status)|%")])
    }

    func compileColor(column: String, countColumn: String, op: String, value: String, original: String) throws -> CompiledClause {
        if let count = Int(value) {
            return compileNumeric(column: countColumn, op: op, value: String(count), original: original)
        }
        let colors = colorSymbols(value)
        if value == "m" || value == "multicolor" {
            return CompiledClause(sql: "\(countColumn) > 1")
        }
        if value == "c" || value == "colorless" {
            return CompiledClause(sql: "\(countColumn) = 0")
        }
        guard !colors.isEmpty else {
            throw unsupportedColorValue(original: original, value: value)
        }
        let exact = serializedColor(colors)
        switch op {
        case ":", "=":
            return CompiledClause(sql: "\(column) = ?", bindings: [.text(exact)])
        case "!=":
            return CompiledClause(sql: "\(column) != ?", bindings: [.text(exact)])
        case ">=", ">":
            let parts = colors.map { _ in "\(column) LIKE ?" }
            let strict = op == ">" ? " AND \(countColumn) > \(colors.count)" : ""
            return CompiledClause(sql: parts.joined(separator: " AND ") + strict, bindings: colors.map { .text("%|\($0)|%") })
        case "<=", "<":
            let excluded = ["w", "u", "b", "r", "g"].filter { !colors.contains($0) }
            let parts = excluded.map { _ in "\(column) NOT LIKE ?" }
            let strict = op == "<" ? " AND \(countColumn) < \(colors.count)" : ""
            return CompiledClause(sql: (parts.isEmpty ? "1 = 1" : parts.joined(separator: " AND ")) + strict, bindings: excluded.map { .text("%|\($0)|%") })
        default:
            return CompiledClause(sql: "\(column) = ?", bindings: [.text(exact)])
        }
    }

    func unsupportedColorValue(original: String, value: String) -> QueryError {
        let normalizedField = conditionFieldName(from: original)
        let normalizedValue = value.normalizedQueryKey
        if ["c", "color"].contains(normalizedField) {
            var detail =
                "`c:` searches card colors and only accepts W/U/B/R/G, colorless, multicolor, or color nicknames."
            if normalizedValue == "token" {
                detail += " For cards that create creature tokens, use `o:\"creature token\"`."
            }
            return QueryError.unsupported(query: query, token: original, message: detail)
        }

        return QueryError.unsupported(query: query, token: original)
    }

    func conditionFieldName(from original: String) -> String {
        for marker in ["<=", ">=", "!=", ":", "=", "<", ">"] {
            guard let range = original.range(of: marker) else {
                continue
            }
            return String(original[..<range.lowerBound]).normalizedQueryKey
        }
        return ""
    }

    func compileIdentity(op: String, value: String, original: String) throws -> CompiledClause {
        if let count = Int(value) {
            return compileNumeric(column: "color_identity_count", op: op, value: String(count), original: original)
        }

        let identityOp = op == ":" ? "<=" : op
        return try compileColor(
            column: "color_identity_key",
            countColumn: "color_identity_count",
            op: identityOp,
            value: value,
            original: original
        )
    }

    func compileMana(op: String, value: String, original: String) -> CompiledClause {
        let canonical = canonicalMana(value)
        if let manaValue = estimatedManaValue(canonical), [">", ">=", "<", "<=", "=", "!="].contains(op) {
            return compileNumeric(column: "mana_value", op: op, value: String(manaValue), original: original)
        }
        if op == "!=" {
            return CompiledClause(sql: "mana_cost != ?", bindings: [.text(canonical)])
        }
        return CompiledClause(sql: "mana_cost LIKE ?", bindings: [.text("%\(canonical)%")])
    }

    func compileNumeric(column: String, op: String, value: String, original: String) -> CompiledClause {
        if value == "even" {
            return CompiledClause(sql: "CAST(\(column) AS INTEGER) % 2 = 0")
        }
        if value == "odd" {
            return CompiledClause(sql: "CAST(\(column) AS INTEGER) % 2 = 1")
        }
        guard let number = Double(value) else {
            return CompiledClause(sql: "0 = 1")
        }
        return CompiledClause(sql: "\(column) \(sqlOperator(for: op, defaultOperator: "=")) ?", bindings: [.double(number)])
    }

    func compileNumericOrColumn(column: String, op: String, value: String, original: String) -> CompiledClause {
        if ["power", "pow"].contains(value) {
            return CompiledClause(sql: "\(column) \(sqlOperator(for: op, defaultOperator: "=")) power_value")
        }
        if ["toughness", "tou"].contains(value) {
            return CompiledClause(sql: "\(column) \(sqlOperator(for: op, defaultOperator: "=")) toughness_value")
        }
        return compileNumeric(column: column, op: op, value: value, original: original)
    }

    func compileRarity(op: String, value: String, original: String) -> CompiledClause {
        guard let rank = rarityRank(value) else {
            return compileScalar(column: "rarity", op: op, value: value)
        }
        return compileNumeric(column: "rarity_rank", op: op, value: String(rank), original: original)
    }

    func compileCollectorNumber(op: String, value: String) -> CompiledClause {
        if let number = Int(value), op != ":" && op != "=" && op != "!=" {
            return CompiledClause(sql: "collector_number_number \(sqlOperator(for: op, defaultOperator: "=")) ?", bindings: [.int(number)])
        }
        return CompiledClause(sql: "collector_number \(sqlOperator(for: op, defaultOperator: "=")) ?", bindings: [.text(value)])
    }

}
