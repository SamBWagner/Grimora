import Foundation

public enum SearchQuery {
    public enum SQLBinding: Equatable, Sendable {
        case text(String)
        case int(Int)
        case double(Double)
    }

    public struct PostFilter: Equatable, Sendable {
        public enum Field: Equatable, Sendable {
            case name
            case type
            case oracle
            case flavor
        }

        public var field: Field
        public var pattern: String
        public var negated: Bool

        public func matches(_ card: CardRecord) -> Bool {
            let value: String
            switch field {
            case .name:
                value = card.name
            case .type:
                value = ([card.typeLine] + card.faces.map(\.typeLine)).joined(separator: " ")
            case .oracle:
                value = ([card.oracleText] + card.faces.map(\.oracleText)).joined(separator: " ")
            case .flavor:
                value = card.flavorText ?? ""
            }

            let match = (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
                .map { regex in
                    let range = NSRange(value.startIndex..<value.endIndex, in: value)
                    return regex.firstMatch(in: value, range: range) != nil
                } ?? false
            return negated ? !match : match
        }
    }

    public static func compile(_ text: String) -> Result<SearchQueryPlan, SearchQueryUnsupportedReason> {
        switch ScryfallSyntaxParser.parse(text) {
        case .success(let tree):
            return compileSyntaxTree(tree)
        case .failure(let diagnostic):
            return .failure(
                SearchQueryUnsupportedReason(
                    query: text,
                    token: diagnostic.token,
                    detail: diagnostic.message
                )
            )
        }
    }

    static func compileSyntaxTree(_ tree: ScryfallQuerySyntaxTree) -> Result<SearchQueryPlan, SearchQueryUnsupportedReason> {
        do {
            var compiler = Compiler(query: tree.query)
            let clause = try compiler.compile(tree.root)
            return .success(
                SearchQueryPlan(
                    whereSQL: clause.sql,
                    bindings: clause.bindings,
                    displayOptions: compiler.displayOptions,
                    postFilters: clause.postFilters
                ))
        } catch {
            return .failure((error as! QueryError).reason)
        }
    }

    public static func unsupportedReason(for text: String) -> SearchQueryUnsupportedReason? {
        if case .failure(let reason) = compile(text) {
            return reason
        }

        return nil
    }

    public static func explicitSyntaxUnsupportedReason(for text: String) -> SearchQueryUnsupportedReason? {
        let validation = ScryfallSyntaxValidator.validate(text)
        if let diagnostic = validation.diagnostics.first {
            return SearchQueryUnsupportedReason(
                query: text,
                token: diagnostic.token,
                detail: diagnostic.message
            )
        }
        return validation.unsupportedTerms.first?.reason
    }

    public static func ftsExpression(for text: String) -> String? {
        let words = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else {
            return nil
        }

        return words
            .map { "\($0)*" }
            .joined(separator: " AND ")
    }
}
