import Foundation

extension Compiler {
    func compileIn(value: String, op: String, original: String) throws -> CompiledClause {
        if ["paper", "arena", "mtgo"].contains(value) {
            return compileListContains(column: "games_key", value: value)
        }
        if rarityRank(value) != nil || ["common", "uncommon", "rare", "mythic", "special", "bonus"].contains(value) {
            return compileRarity(op: op, value: value, original: original)
        }
        if languageCode(value) != value || value.count == 2 || value == "zhs" || value == "zht" {
            return compileScalar(column: "lang", op: op, value: languageCode(value))
        }
        if ["core", "expansion", "masters", "commander", "alchemy", "promo", "token", "funny"].contains(value) {
            return compileScalar(column: "set_type", op: op, value: value)
        }
        return compileScalar(column: "set_code", op: op, value: value)
    }

    func compileBlock(value: String, original: String) throws -> CompiledClause {
        guard let sets = blockSets[value] else {
            throw QueryError.unsupported(
                query: query,
                token: original,
                message: "“\(original)” refers to block metadata Grimora does not have for that block yet."
            )
        }
        let placeholders = Array(repeating: "?", count: sets.count).joined(separator: ", ")
        return CompiledClause(
            sql: "set_code IN (\(placeholders))",
            bindings: sets.map { .text($0) }
        )
    }

    func compileFrame(value: String, op: String) -> CompiledClause {
        if ["colorshifted", "tombstone", "legendary", "enchantment", "extendedart", "showcase", "etched"].contains(value) {
            return compileListContains(column: "frame_effects_key", value: value)
        }
        return compileScalar(column: "frame", op: op, value: value)
    }

    func compileYear(op: String, value: String, original: String) -> CompiledClause {
        guard let year = Int(value) else {
            return CompiledClause(sql: "0 = 1")
        }
        return CompiledClause(sql: "CAST(substr(released_at, 1, 4) AS INTEGER) \(sqlOperator(for: op, defaultOperator: "=")) ?", bindings: [.int(year)])
    }

    func compileDate(op: String, value: String) -> CompiledClause {
        let resolved = (value == "now" || value == "today") ? Self.currentDateString() : value
        if resolved.range(of: #"^\d{4}(-\d{2}-\d{2})?$"#, options: .regularExpression) != nil {
            let date = resolved.count == 4 ? "\(resolved)-01-01" : resolved
            return CompiledClause(sql: "released_at \(sqlOperator(for: op, defaultOperator: "=")) ?", bindings: [.text(date)])
        }
        return CompiledClause(
            sql: "released_at \(sqlOperator(for: op, defaultOperator: "=")) (SELECT MIN(released_at) FROM cards WHERE set_code = ?)",
            bindings: [.text(value)]
        )
    }

    func compileDevotion(value: String) -> CompiledClause {
        let colors = colorSymbols(value)
        guard !colors.isEmpty else {
            return CompiledClause()
        }
        return CompiledClause(
            sql: colors.map { _ in "mana_cost LIKE ?" }.joined(separator: " AND "),
            bindings: colors.map { .text("%{\($0.uppercased())}%") }
        )
    }
}
