import Foundation

enum ScryfallRawToken: Equatable {
    case word(ScryfallWordToken)
    case leftParen
    case rightParen

    var startsExpression: Bool {
        switch self {
        case .word, .leftParen:
            true
        case .rightParen:
            false
        }
    }
}

struct ScryfallWordToken: Equatable {
    var text: String
    var source: String
}

struct ScryfallSyntaxTokenizer {
    var text: String

    func tokens() throws -> [ScryfallRawToken] {
        var tokens: [ScryfallRawToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                text.formIndex(after: &index)
                continue
            }

            if character == "(" {
                tokens.append(.leftParen)
                text.formIndex(after: &index)
                continue
            }

            if character == ")" {
                tokens.append(.rightParen)
                text.formIndex(after: &index)
                continue
            }

            tokens.append(.word(try readWord(startingAt: &index)))
        }

        return tokens
    }

    private func readWord(startingAt index: inout String.Index) throws -> ScryfallWordToken {
        let tokenStart = index
        var value = ""
        var isQuoted = false
        var isRegex = false
        var isEscaped = false

        if text[index].isScryfallQuoteDelimiter {
            text.formIndex(after: &index)
            while index < text.endIndex {
                let character = text[index]
                text.formIndex(after: &index)
                if character.isScryfallQuoteDelimiter {
                    return ScryfallWordToken(text: value, source: String(text[tokenStart..<index]))
                }
                value.append(character)
            }
            throw ScryfallSyntaxDiagnostic(
                query: text,
                token: value,
                message: "The search query has an unterminated quoted string."
            )
        }

        while index < text.endIndex {
            let character = text[index]
            if isRegex {
                value.append(character)
                text.formIndex(after: &index)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "/" {
                    isRegex = false
                }
                continue
            }

            if isQuoted {
                text.formIndex(after: &index)
                if isEscaped {
                    value.append(character)
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character.isScryfallQuoteDelimiter {
                    isQuoted = false
                } else {
                    value.append(character)
                }
                continue
            }

            if character.isWhitespace || character == "(" || character == ")" {
                break
            }

            if character.isScryfallQuoteDelimiter {
                isQuoted = true
                text.formIndex(after: &index)
                continue
            }

            if character == "/", value.isReadyToStartScryfallRegex {
                isRegex = true
            }

            value.append(character)
            text.formIndex(after: &index)
        }

        if isQuoted {
            throw ScryfallSyntaxDiagnostic(
                query: text,
                token: value,
                message: "The search query has an unterminated quoted string."
            )
        }
        if isRegex {
            throw ScryfallSyntaxDiagnostic(
                query: text,
                token: value,
                message: "The search query has an unterminated regular expression."
            )
        }

        return ScryfallWordToken(text: value, source: String(text[tokenStart..<index]))
    }
}
