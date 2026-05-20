import Foundation

struct ScryfallSyntaxTreeParser {
    var tokens: [ScryfallRawToken]
    var query: String
    var index = 0

    mutating func parse() throws -> ScryfallQueryNode {
        guard !tokens.isEmpty else {
            return .all
        }
        let node = try parseOr()
        if index < tokens.count {
            throw ScryfallSyntaxDiagnostic(
                query: query,
                token: tokenText(tokens[index]),
                message: "The search query has an unexpected token."
            )
        }
        return node
    }

    private mutating func parseOr() throws -> ScryfallQueryNode {
        var nodes = [try parseAnd()]
        while case .word(let word) = peek(), word.text.normalizedScryfallSyntaxKey == "or" {
            index += 1
            nodes.append(try parseAnd())
        }
        return nodes.count == 1 ? nodes[0] : .or(nodes)
    }

    private mutating func parseAnd() throws -> ScryfallQueryNode {
        var nodes: [ScryfallQueryNode] = []
        while let token = peek(), token.startsExpression {
            if case .word(let word) = token, word.text.normalizedScryfallSyntaxKey == "or" {
                break
            }
            if case .word(let word) = token, word.text.normalizedScryfallSyntaxKey == "and" {
                index += 1
                continue
            }
            nodes.append(try parseUnary())
        }
        return nodes.isEmpty ? .all : (nodes.count == 1 ? nodes[0] : .and(nodes))
    }

    mutating func parseUnary() throws -> ScryfallQueryNode {
        guard let token = peek() else {
            return .all
        }
        if case .word(let word) = token, word.text == "-" {
            index += 1
            return .not(try parseUnary())
        }
        return try parsePrimary()
    }

    mutating func parsePrimary() throws -> ScryfallQueryNode {
        guard let token = peek() else {
            return .all
        }
        index += 1

        switch token {
        case .leftParen:
            let node = try parseOr()
            guard case .rightParen = peek() else {
                throw ScryfallSyntaxDiagnostic(
                    query: query,
                    token: "(",
                    message: "The search query has an unclosed parenthesis."
                )
            }
            index += 1
            return node
        case .rightParen:
            index -= 1
            return .all
        case .word(let raw):
            if raw.text.hasPrefix("-"), raw.text.count > 1 {
                let trimmed = ScryfallWordToken(
                    text: String(raw.text.dropFirst()),
                    source: raw.source.hasPrefix("-") ? String(raw.source.dropFirst()) : raw.source
                )
                return .not(try node(for: trimmed))
            }
            return try node(for: raw)
        }
    }

    private func node(for raw: ScryfallWordToken) throws -> ScryfallQueryNode {
        if raw.text.hasPrefix("!") {
            let value = String(raw.text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                throw ScryfallSyntaxDiagnostic(
                    query: query,
                    token: raw.source,
                    message: "Exact-name searches need a card name after `!`."
                )
            }
            return .term(.exactName(value))
        }

        if let condition = splitCondition(raw) {
            return .term(.condition(condition))
        }

        return .term(.bare(raw.text))
    }

    func splitCondition(_ raw: ScryfallWordToken) -> ScryfallSyntaxCondition? {
        for marker in scryfallConditionOperators {
            guard let textRange = raw.text.range(of: marker) else {
                continue
            }
            let field = String(raw.text[..<textRange.lowerBound]).normalizedScryfallSyntaxKey
            guard !field.isEmpty, field.contains(where: { $0.isLetter || $0 == "_" }) else {
                continue
            }

            let rawValue = String(raw.text[textRange.upperBound...])
            let sourceValue: String
            if let sourceRange = raw.source.range(of: marker) {
                sourceValue = String(raw.source[sourceRange.upperBound...])
            } else {
                sourceValue = rawValue
            }
            let canonicalField = ScryfallSyntaxFieldRegistry.field(for: field)?.canonicalName ?? field
            return ScryfallSyntaxCondition(
                field: field,
                canonicalField: canonicalField,
                operatorToken: marker,
                value: value(text: rawValue, source: sourceValue),
                original: raw.source
            )
        }
        return nil
    }

    private func value(text: String, source: String) -> ScryfallSyntaxValue {
        if source.count >= 2,
           source.first?.isScryfallQuoteDelimiter == true,
           source.last?.isScryfallQuoteDelimiter == true {
            return .quoted(text)
        }
        if text.hasPrefix("/"), text.hasSuffix("/"), text.count >= 2 {
            return .regularExpression(String(text.dropFirst().dropLast()))
        }
        return .bare(text)
    }

    private func peek() -> ScryfallRawToken? {
        index < tokens.count ? tokens[index] : nil
    }

    func tokenText(_ token: ScryfallRawToken) -> String {
        switch token {
        case .word(let value):
            value.source
        case .leftParen:
            "("
        case .rightParen:
            ")"
        }
    }
}
