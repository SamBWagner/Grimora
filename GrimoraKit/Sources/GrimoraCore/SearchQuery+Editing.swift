import Foundation

extension SearchQuery {
    public static func appending(_ refinement: SearchRefinement, to query: String) -> String {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contains(refinement, in: normalizedQuery) else {
            return normalizedQuery
        }
        guard !normalizedQuery.isEmpty else {
            return refinement.queryFragment
        }
        return "\(normalizedQuery) \(refinement.queryFragment)"
    }

    public static func contains(_ refinement: SearchRefinement, in query: String) -> Bool {
        guard case .success(let tree) = ScryfallSyntaxParser.parse(query) else {
            return query
                .split(whereSeparator: \.isWhitespace)
                .contains { $0.caseInsensitiveCompare(refinement.queryFragment) == .orderedSame }
        }

        let canonicalField =
            ScryfallSyntaxFieldRegistry.field(for: refinement.field)?.canonicalName
            ?? refinement.field.normalizedScryfallSyntaxKey
        return contains(
            refinement,
            canonicalField: canonicalField,
            in: tree.root,
            isNegated: false
        )
    }

    public static func state(
        for refinement: SearchRefinement,
        in query: String
    ) -> SearchRefinementState {
        guard !hasTopLevelOr(in: query) else {
            return .neutral
        }
        for chunk in topLevelChunks(in: query) {
            guard let condition = directCondition(in: chunk.text),
                  condition.matches(refinement)
            else {
                continue
            }
            return condition.intent == .exclude ? .exclude : .include
        }
        return .neutral
    }

    public static func applying(
        _ updates: [SearchRefinementUpdate],
        to query: String
    ) -> String {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let canRemoveExistingTerms = !hasTopLevelOr(in: normalizedQuery)
        let updatedRefinements = updates.map(\.refinement)
        var chunks = topLevelChunks(in: normalizedQuery)

        if canRemoveExistingTerms {
            chunks.removeAll { chunk in
                guard let condition = directCondition(in: chunk.text) else {
                    return false
                }
                return updatedRefinements.contains { condition.matches($0) }
            }
            chunks = removingOrphanedAndOperators(from: chunks)
        }

        var result = chunks.map(\.text).joined(separator: " ")
        for update in updates {
            guard let intent = update.state.intent else {
                continue
            }
            result = appending(update.refinement.withIntent(intent), to: result)
        }
        return result
    }

    private static func contains(
        _ refinement: SearchRefinement,
        canonicalField: String,
        in node: ScryfallQueryNode,
        isNegated: Bool
    ) -> Bool {
        switch node {
        case .all:
            false
        case .term(.condition(let condition)):
            condition.canonicalField == canonicalField
                && ["=", ":"].contains(condition.operatorToken)
                && condition.value.text.caseInsensitiveCompare(refinement.value) == .orderedSame
                && isNegated == (refinement.intent == .exclude)
        case .term:
            false
        case .and(let nodes), .or(let nodes):
            nodes.contains {
                contains(
                    refinement,
                    canonicalField: canonicalField,
                    in: $0,
                    isNegated: isNegated
                )
            }
        case .not(let child):
            contains(
                refinement,
                canonicalField: canonicalField,
                in: child,
                isNegated: !isNegated
            )
        }
    }

    private struct TopLevelChunk {
        var text: String
    }

    private struct DirectCondition {
        var canonicalField: String
        var value: String
        var intent: RefinementIntent

        func matches(_ refinement: SearchRefinement) -> Bool {
            let refinementField =
                ScryfallSyntaxFieldRegistry.field(for: refinement.field)?.canonicalName
                ?? refinement.field.normalizedScryfallSyntaxKey
            return canonicalField == refinementField
                && value.caseInsensitiveCompare(refinement.value) == .orderedSame
        }
    }

    private static func directCondition(in text: String) -> DirectCondition? {
        guard case .success(let tree) = ScryfallSyntaxParser.parse(text) else {
            return nil
        }
        switch tree.root {
        case .term(.condition(let condition)):
            guard ["=", ":"].contains(condition.operatorToken) else {
                return nil
            }
            return DirectCondition(
                canonicalField: condition.canonicalField,
                value: condition.value.text,
                intent: .include
            )
        case .not(.term(.condition(let condition))):
            guard ["=", ":"].contains(condition.operatorToken) else {
                return nil
            }
            return DirectCondition(
                canonicalField: condition.canonicalField,
                value: condition.value.text,
                intent: .exclude
            )
        default:
            return nil
        }
    }

    private static func hasTopLevelOr(in query: String) -> Bool {
        topLevelChunks(in: query).contains {
            $0.text.normalizedScryfallSyntaxKey == "or"
        }
    }

    private static func removingOrphanedAndOperators(
        from chunks: [TopLevelChunk]
    ) -> [TopLevelChunk] {
        var result: [TopLevelChunk] = []
        for chunk in chunks {
            let isAnd = chunk.text.normalizedScryfallSyntaxKey == "and"
            if isAnd, result.isEmpty {
                continue
            }
            if isAnd,
               result.last?.text.normalizedScryfallSyntaxKey == "and"
            {
                continue
            }
            result.append(chunk)
        }
        if result.last?.text.normalizedScryfallSyntaxKey == "and" {
            result.removeLast()
        }
        return result
    }

    private static func topLevelChunks(in query: String) -> [TopLevelChunk] {
        var chunks: [TopLevelChunk] = []
        var start: String.Index?
        var index = query.startIndex
        var depth = 0
        var quote: Character?
        var isRegex = false
        var isEscaped = false

        func appendChunk(endingAt end: String.Index) {
            guard let start else {
                return
            }
            let text = String(query[start..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                chunks.append(TopLevelChunk(text: text))
            }
        }

        while index < query.endIndex {
            let character = query[index]

            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if let activeQuote = quote {
                if character == activeQuote || character.isScryfallQuoteDelimiter {
                    quote = nil
                }
            } else if isRegex {
                if character == "/" {
                    isRegex = false
                }
            } else if character.isScryfallQuoteDelimiter {
                quote = character
            } else if character == "/" {
                isRegex = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            }

            if character.isWhitespace, depth == 0, quote == nil, !isRegex {
                appendChunk(endingAt: index)
                start = nil
            } else if start == nil {
                start = index
            }
            query.formIndex(after: &index)
        }
        appendChunk(endingAt: query.endIndex)
        return chunks
    }
}
