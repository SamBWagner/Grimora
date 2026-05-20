import Foundation

struct QueryError: Error {
    var reason: SearchQueryUnsupportedReason

    static func unsupported(query: String, token: String, message: String? = nil) -> QueryError {
        QueryError(reason: SearchQueryUnsupportedReason(query: query, token: token, detail: message))
    }
}

extension SearchPreference {
    init?(scryfallValue: String) {
        switch scryfallValue {
        case "oldest":
            self = .oldest
        case "newest":
            self = .newest
        case "promo":
            self = .promo
        case "default":
            self = .defaultPrint
        case "atypical":
            self = .atypical
        case "notuniversesbeyond", "notub":
            self = .notUniversesBeyond
        case "usd-low":
            self = .usdLow
        case "usd-high":
            self = .usdHigh
        default:
            return nil
        }
    }
}

extension String {
    var normalizedQueryKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
