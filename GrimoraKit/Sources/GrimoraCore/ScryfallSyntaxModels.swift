import Foundation

public struct ScryfallQuerySyntaxTree: Equatable, Sendable {
    public var query: String
    public var root: ScryfallQueryNode

    public init(query: String, root: ScryfallQueryNode) {
        self.query = query
        self.root = root
    }
}

public indirect enum ScryfallQueryNode: Equatable, Sendable {
    case all
    case term(ScryfallQueryTerm)
    case and([ScryfallQueryNode])
    case or([ScryfallQueryNode])
    case not(ScryfallQueryNode)
}

public enum ScryfallQueryTerm: Equatable, Sendable {
    case bare(String)
    case exactName(String)
    case condition(ScryfallSyntaxCondition)
}

public struct ScryfallSyntaxCondition: Equatable, Sendable {
    public var field: String
    public var canonicalField: String
    public var operatorToken: String
    public var value: ScryfallSyntaxValue
    public var original: String

    public init(
        field: String,
        canonicalField: String,
        operatorToken: String,
        value: ScryfallSyntaxValue,
        original: String
    ) {
        self.field = field
        self.canonicalField = canonicalField
        self.operatorToken = operatorToken
        self.value = value
        self.original = original
    }
}

public enum ScryfallSyntaxValue: Equatable, Sendable {
    case bare(String)
    case quoted(String)
    case regularExpression(String)

    public var text: String {
        switch self {
        case .bare(let value), .quoted(let value):
            value
        case .regularExpression(let pattern):
            "/\(pattern)/"
        }
    }

    public var isRegularExpression: Bool {
        if case .regularExpression = self {
            return true
        }
        return false
    }
}

public struct ScryfallSyntaxDiagnostic: Error, Equatable, Sendable {
    public var query: String
    public var token: String
    public var message: String

    public init(query: String, token: String, message: String) {
        self.query = query
        self.token = token
        self.message = message
    }
}

public struct ScryfallSyntaxValidation: Equatable, Sendable {
    public var query: String
    public var syntaxTree: ScryfallQuerySyntaxTree?
    public var isValidScryfall: Bool
    public var isSupportedOffline: Bool
    public var diagnostics: [ScryfallSyntaxDiagnostic]
    public var unsupportedTerms: [ScryfallUnsupportedSyntaxTerm]

    public init(
        query: String,
        syntaxTree: ScryfallQuerySyntaxTree?,
        isValidScryfall: Bool,
        isSupportedOffline: Bool,
        diagnostics: [ScryfallSyntaxDiagnostic],
        unsupportedTerms: [ScryfallUnsupportedSyntaxTerm]
    ) {
        self.query = query
        self.syntaxTree = syntaxTree
        self.isValidScryfall = isValidScryfall
        self.isSupportedOffline = isSupportedOffline
        self.diagnostics = diagnostics
        self.unsupportedTerms = unsupportedTerms
    }
}

public struct ScryfallUnsupportedSyntaxTerm: Equatable, Sendable {
    public var token: String
    public var reason: SearchQueryUnsupportedReason

    public init(token: String, reason: SearchQueryUnsupportedReason) {
        self.token = token
        self.reason = reason
    }
}

public enum ScryfallSyntaxValueRule: String, Equatable, Sendable {
    case any
    case color
    case display
    case direction
    case include
    case legality
    case newFlag
    case rarity
    case regexText
}

public struct ScryfallSyntaxField: Equatable, Sendable {
    public var canonicalName: String
    public var aliases: [String]
    public var valueRule: ScryfallSyntaxValueRule

    public init(canonicalName: String, aliases: [String], valueRule: ScryfallSyntaxValueRule = .any) {
        self.canonicalName = canonicalName
        self.aliases = aliases
        self.valueRule = valueRule
    }
}
