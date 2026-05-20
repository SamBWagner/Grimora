import Foundation

extension Compiler {
    func regexPattern(from value: String) -> String? {
        guard value.hasPrefix("/"), value.hasSuffix("/"), value.count >= 2 else {
            return nil
        }
        return String(value.dropFirst().dropLast())
    }

    func canonicalField(_ field: String) -> String {
        switch field {
        case "c", "color":
            "color"
        case "id", "identity", "ci", "commander":
            "identity"
        case "t", "type":
            "type"
        case "o", "oracle":
            "oracle"
        case "fo", "fulloracle":
            "fulloracle"
        case "kw", "keyword":
            "keyword"
        case "m", "mana":
            "mana"
        case "mv", "cmc", "manavalue":
            "manavalue"
        case "pow", "power":
            "power"
        case "tou", "toughness":
            "toughness"
        case "loy", "loyalty":
            "loyalty"
        case "pt", "powtou":
            "powtou"
        case "r", "rarity":
            "rarity"
        case "s", "e", "set", "edition":
            "set"
        case "cn", "number":
            "number"
        case "st":
            "settype"
        case "b", "block":
            "block"
        case "f", "format":
            "format"
        case "a", "artist":
            "artist"
        case "ft", "flavor":
            "flavor"
        case "wm", "watermark":
            "watermark"
        case "lang", "language":
            "lang"
        case "game":
            "game"
        default:
            field
        }
    }

    func sqlOperator(for op: String, defaultOperator: String) -> String {
        switch op {
        case ":", "=":
            defaultOperator
        case "!=", ">", "<", ">=", "<=":
            op
        default:
            defaultOperator
        }
    }

    func colorSymbols(_ value: String) -> [String] {
        let normalized = value.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        if let nickname = colorNicknames[normalized] {
            return colorSymbols(nickname)
        }
        let named: [String: String] = ["white": "w", "blue": "u", "black": "b", "red": "r", "green": "g"]
        let source = named[normalized] ?? normalized
        return ["w", "u", "b", "r", "g"].filter { source.contains($0) }
    }

    func serializedColor(_ colors: [String]) -> String {
        "|\(colors.sorted().joined(separator: "|"))|"
    }

    func rarityRank(_ value: String) -> Int? {
        switch value {
        case "c", "common":
            0
        case "u", "uncommon":
            1
        case "r", "rare":
            2
        case "m", "mythic":
            3
        default:
            nil
        }
    }

    func canonicalMana(_ value: String) -> String {
        if value.contains("{") {
            return value.uppercased()
        }
        return value.map { "{\($0.uppercased())}" }.joined()
    }

    func estimatedManaValue(_ mana: String) -> Double? {
        let symbols = mana.split(separator: "{").compactMap { piece -> String? in
            guard let end = piece.firstIndex(of: "}") else {
                return nil
            }
            return String(piece[..<end])
        }
        guard !symbols.isEmpty else {
            return nil
        }
        return symbols.reduce(0) { total, symbol in
            if let number = Double(symbol) {
                return total + number
            }
            if symbol.uppercased() == "X" {
                return total
            }
            return total + 1
        }
    }

    func languageCode(_ value: String) -> String {
        [
            "english": "en", "japanese": "ja", "korean": "ko", "russian": "ru",
            "chinese": "zhs", "simplifiedchinese": "zhs", "traditionalchinese": "zht",
            "german": "de", "spanish": "es", "french": "fr", "italian": "it",
            "portuguese": "pt", "latin": "la", "ancientgreek": "grc", "hebrew": "he",
            "sanskrit": "sa", "arabic": "ar", "phyrexian": "ph"
        ][value] ?? value
    }

    static func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    var colorNicknames: [String: String] {
        [
            "azorius": "wu", "dimir": "ub", "rakdos": "br", "gruul": "rg", "selesnya": "gw",
            "orzhov": "wb", "izzet": "ur", "golgari": "bg", "boros": "rw", "simic": "gu",
            "bant": "wug", "esper": "wub", "grixis": "ubr", "jund": "brg", "naya": "rgw",
            "abzan": "wbg", "jeskai": "urw", "sultai": "bgu", "mardu": "rwb", "temur": "gur",
            "quandrix": "gu", "silverquill": "wb", "prismari": "ur", "witherbloom": "bg",
            "lorehold": "rw", "chaos": "ubr", "aggression": "brg", "altruism": "gwu",
            "growth": "wbg", "artifice": "urw"
        ]
    }

    var blockSets: [String: [String]] {
        [
            "iceage": ["ice", "all", "csp"],
            "mirage": ["mir", "vis", "wth"],
            "tempest": ["tmp", "sth", "exo"],
            "urza": ["usg", "ulg", "uds"],
            "masques": ["mmq", "nem", "pcy"],
            "invasion": ["inv", "pls", "apc"],
            "odyssey": ["ody", "tor", "jud"],
            "onslaught": ["ons", "lgn", "scg"],
            "mirrodin": ["mrd", "dst", "5dn"],
            "kamigawa": ["chk", "bok", "sok"],
            "ravnica": ["rav", "gpt", "dis"],
            "timespiral": ["tsp", "plc", "fut"],
            "lorwyn": ["lrw", "mor"],
            "shadowmoor": ["shm", "eve"],
            "alara": ["ala", "con", "arb"],
            "zendikar": ["zen", "wwk", "roe"],
            "scars": ["som", "mbs", "nph"],
            "innistrad": ["isd", "dka", "avr"],
            "returntoravnica": ["rtr", "gtc", "dgm"],
            "return-to-ravnica": ["rtr", "gtc", "dgm"],
            "theros": ["ths", "bng", "jou"],
            "tarkir": ["ktk", "frf", "dtk"],
            "battleforzendikar": ["bfz", "ogw"],
            "battle-for-zendikar": ["bfz", "ogw"],
            "shadows over innistrad": ["soi", "emn"],
            "amonkhet": ["akh", "hou"],
            "ixalan": ["xln", "rix"]
        ]
    }
}
