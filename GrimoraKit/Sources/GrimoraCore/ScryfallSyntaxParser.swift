import Foundation

public enum ScryfallSyntaxParser {
    public static func parse(_ text: String) -> Result<ScryfallQuerySyntaxTree, ScryfallSyntaxDiagnostic> {
        do {
            let tokens = try ScryfallSyntaxTokenizer(text: text).tokens()
            var parser = ScryfallSyntaxTreeParser(tokens: tokens, query: text)
            return .success(ScryfallQuerySyntaxTree(query: text, root: try parser.parse()))
        } catch {
            let diagnostic = error as! ScryfallSyntaxDiagnostic
            return .failure(diagnostic)
        }
    }
}
