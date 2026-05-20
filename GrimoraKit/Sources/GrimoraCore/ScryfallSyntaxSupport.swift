import Foundation

let scryfallConditionOperators = ["<=", ">=", "!=", ":", "=", "<", ">"]

extension Character {
    var isScryfallQuoteDelimiter: Bool {
        self == "\"" || self == "\u{201C}" || self == "\u{201D}"
    }
}

extension String {
    var isReadyToStartScryfallRegex: Bool {
        for marker in scryfallConditionOperators {
            guard let range = range(of: marker) else {
                continue
            }
            return self[range.upperBound...].isEmpty
        }
        return false
    }

    var normalizedScryfallSyntaxKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
