import Foundation

public enum ScryfallSyntaxFieldRegistry {
    public static let fields: [ScryfallSyntaxField] = [
        .init(canonicalName: "color", aliases: ["c", "color"], valueRule: .color),
        .init(canonicalName: "identity", aliases: ["id", "identity", "ci", "commander"], valueRule: .color),
        .init(canonicalName: "type", aliases: ["t", "type"], valueRule: .regexText),
        .init(canonicalName: "oracle", aliases: ["o", "oracle"], valueRule: .regexText),
        .init(canonicalName: "fulloracle", aliases: ["fo", "fulloracle"], valueRule: .regexText),
        .init(canonicalName: "keyword", aliases: ["kw", "keyword"]),
        .init(canonicalName: "mana", aliases: ["m", "mana"]),
        .init(canonicalName: "manavalue", aliases: ["mv", "cmc", "manavalue"]),
        .init(canonicalName: "devotion", aliases: ["devotion"]),
        .init(canonicalName: "produces", aliases: ["produces"], valueRule: .color),
        .init(canonicalName: "power", aliases: ["pow", "power"]),
        .init(canonicalName: "toughness", aliases: ["tou", "toughness"]),
        .init(canonicalName: "powtou", aliases: ["pt", "powtou"]),
        .init(canonicalName: "loyalty", aliases: ["loy", "loyalty"]),
        .init(canonicalName: "is", aliases: ["is"]),
        .init(canonicalName: "has", aliases: ["has"]),
        .init(canonicalName: "new", aliases: ["new"], valueRule: .newFlag),
        .init(canonicalName: "not", aliases: ["not"]),
        .init(canonicalName: "rarity", aliases: ["r", "rarity"], valueRule: .rarity),
        .init(canonicalName: "in", aliases: ["in"]),
        .init(canonicalName: "set", aliases: ["s", "e", "set", "edition"]),
        .init(canonicalName: "number", aliases: ["cn", "number"]),
        .init(canonicalName: "block", aliases: ["b", "block"]),
        .init(canonicalName: "settype", aliases: ["st", "settype"]),
        .init(canonicalName: "cube", aliases: ["cube"]),
        .init(canonicalName: "format", aliases: ["f", "format", "legal"], valueRule: .legality),
        .init(canonicalName: "banned", aliases: ["banned"], valueRule: .legality),
        .init(canonicalName: "restricted", aliases: ["restricted"], valueRule: .legality),
        .init(canonicalName: "usd", aliases: ["usd"]),
        .init(canonicalName: "eur", aliases: ["eur"]),
        .init(canonicalName: "tix", aliases: ["tix"]),
        .init(canonicalName: "cheapest", aliases: ["cheapest"]),
        .init(canonicalName: "artist", aliases: ["a", "artist"]),
        .init(canonicalName: "artists", aliases: ["artists"]),
        .init(canonicalName: "flavor", aliases: ["ft", "flavor"], valueRule: .regexText),
        .init(canonicalName: "watermark", aliases: ["wm", "watermark"]),
        .init(canonicalName: "illustrations", aliases: ["illustrations"]),
        .init(canonicalName: "border", aliases: ["border"]),
        .init(canonicalName: "frame", aliases: ["frame"]),
        .init(canonicalName: "stamp", aliases: ["stamp"]),
        .init(canonicalName: "game", aliases: ["game"]),
        .init(canonicalName: "year", aliases: ["year"]),
        .init(canonicalName: "date", aliases: ["date"]),
        .init(canonicalName: "art", aliases: ["art"]),
        .init(canonicalName: "atag", aliases: ["atag", "arttag"]),
        .init(canonicalName: "function", aliases: ["function"]),
        .init(canonicalName: "otag", aliases: ["otag", "oracletag"]),
        .init(canonicalName: "prints", aliases: ["prints"]),
        .init(canonicalName: "sets", aliases: ["sets"]),
        .init(canonicalName: "paperprints", aliases: ["paperprints"]),
        .init(canonicalName: "papersets", aliases: ["papersets"]),
        .init(canonicalName: "lang", aliases: ["lang", "language"]),
        .init(canonicalName: "unique", aliases: ["unique"], valueRule: .display),
        .init(canonicalName: "display", aliases: ["display"], valueRule: .display),
        .init(canonicalName: "order", aliases: ["order"], valueRule: .display),
        .init(canonicalName: "prefer", aliases: ["prefer"], valueRule: .display),
        .init(canonicalName: "direction", aliases: ["direction"], valueRule: .direction),
        .init(canonicalName: "include", aliases: ["include"], valueRule: .include),
        .init(canonicalName: "name", aliases: ["name"], valueRule: .regexText)
    ]

    public static func field(for name: String) -> ScryfallSyntaxField? {
        fieldByAlias[name.normalizedScryfallSyntaxKey]
    }

    private static let fieldByAlias: [String: ScryfallSyntaxField] = {
        var result: [String: ScryfallSyntaxField] = [:]
        for field in fields {
            for alias in field.aliases {
                result[alias.normalizedScryfallSyntaxKey] = field
            }
        }
        return result
    }()
}
