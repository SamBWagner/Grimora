import Foundation

/// How a single top-level clause of a Scryfall query should be coloured while the
/// user is typing. Mirrors the teaching behaviour from the "Search field syntax
/// validation" brief: white while a clause is still being typed, faint green once a
/// completed clause is valid, red when it is invalid/unsupported, and yellow while a
/// multi-stage clause (e.g. an unclosed `(...)` group) is still being assembled.
public enum ScryfallClauseHighlight: Equatable, Sendable {
    /// White — the clause is still being typed and has not been evaluated yet.
    case pending
    /// Faint green — the completed clause is valid Scryfall syntax.
    case valid
    /// Red — the completed clause is not valid/recognized Scryfall syntax.
    case invalid
    /// Yellow — a multi-stage clause (unclosed group, quote, or regex) is unfinished.
    case incomplete
}

/// A coloured slice of a query string spanning a single top-level clause.
public struct ScryfallHighlightSegment: Equatable, Sendable {
    public let range: Range<String.Index>
    public let text: String
    public let highlight: ScryfallClauseHighlight

    public init(range: Range<String.Index>, text: String, highlight: ScryfallClauseHighlight) {
        self.range = range
        self.text = text
        self.highlight = highlight
    }
}

/// Classifies the top-level clauses of a draft Scryfall query so search fields can
/// colour-code them live. Reuses ``ScryfallSyntaxValidator/validate(_:)`` for the
/// valid/invalid decision and the same top-level chunking rules as
/// `SearchQuery+Editing`.
public enum ScryfallSyntaxHighlighter {
    public static func segments(for query: String) -> [ScryfallHighlightSegment] {
        let chunks = topLevelChunks(in: query)
        guard let lastIndex = chunks.indices.last else {
            return []
        }
        // A trailing chunk is still being typed only when nothing (not even a space)
        // follows it; a completing space turns it into an evaluated clause.
        let hasTrailingWhitespace = query.last?.isWhitespace ?? false

        return chunks.enumerated().map { offset, range in
            let text = String(query[range])
            let highlight = classify(
                text: text,
                isActiveTrailing: offset == lastIndex && !hasTrailingWhitespace
            )
            return ScryfallHighlightSegment(range: range, text: text, highlight: highlight)
        }
    }

    /// Number of clauses currently flagged invalid (red). Search fields compare this
    /// across keystrokes to fire a light haptic when a clause turns red.
    public static func invalidClauseCount(for query: String) -> Int {
        segments(for: query).reduce(into: 0) { count, segment in
            if segment.highlight == .invalid {
                count += 1
            }
        }
    }

    private static func classify(
        text: String,
        isActiveTrailing: Bool
    ) -> ScryfallClauseHighlight {
        if hasUnfinishedGrouping(in: text) {
            return .incomplete
        }
        // A plain token is held white until a space completes it. A multi-stage clause
        // (a `(...)` group) instead evaluates the moment it closes, so the trailing-space
        // rule does not apply to it.
        if isActiveTrailing, !text.contains("(") {
            return .pending
        }
        return ScryfallSyntaxValidator.validate(text).isValidScryfall ? .valid : .invalid
    }

    /// True when a clause holds an unclosed group, quote, or regular expression and so
    /// cannot be evaluated yet (the yellow, mid-typing state).
    private static func hasUnfinishedGrouping(in text: String) -> Bool {
        var depth = 0
        var quote: Character?
        var isRegex = false
        var isEscaped = false

        for character in text {
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
        }

        return depth > 0 || quote != nil || isRegex
    }

    /// Splits a query into the index ranges of its top-level clauses, ignoring spaces
    /// inside groups, quotes, and regular expressions. Matches the chunking used by
    /// `SearchQuery.topLevelChunks(in:)`, but preserves ranges for colouring.
    private static func topLevelChunks(in query: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var index = query.startIndex
        var depth = 0
        var quote: Character?
        var isRegex = false
        var isEscaped = false

        func appendChunk(endingAt end: String.Index) {
            guard let start, start < end else {
                return
            }
            ranges.append(start..<end)
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
        return ranges
    }
}
