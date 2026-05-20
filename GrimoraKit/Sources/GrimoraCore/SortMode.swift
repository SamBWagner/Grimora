import Foundation

public enum SortMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case name
    case releaseDate
    case setNumber
    case rarity
    case color
    case priceUSD
    case priceTIX
    case priceEUR
    case manaValue
    case power
    case toughness
    case artistName
    case edhrecRank
    case pennyRank

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .name:
            "Name"
        case .releaseDate:
            "Release Date"
        case .setNumber:
            "Set/Number"
        case .rarity:
            "Rarity"
        case .color:
            "Color"
        case .priceUSD:
            "Price: USD"
        case .priceTIX:
            "Price: TIX"
        case .priceEUR:
            "Price: EUR"
        case .manaValue:
            "Mana Value"
        case .power:
            "Power"
        case .toughness:
            "Toughness"
        case .artistName:
            "Artist Name"
        case .edhrecRank:
            "EDHREC Rank"
        case .pennyRank:
            "Penny Rank"
        }
    }

    var sqlOrderClause: String {
        sqlOrderClause(direction: .ascending)
    }

    func sqlOrderClause(direction: SearchSortDirection) -> String {
        let order = direction == .descending ? "DESC" : "ASC"
        switch self {
        case .name:
            return direction == .descending
                ? "name_key DESC, released_at DESC, set_code ASC, collector_number_number IS NULL ASC, collector_number_number ASC, collector_number ASC"
                : "name_key ASC, released_at DESC, set_code ASC, collector_number_number IS NULL ASC, collector_number_number ASC, collector_number ASC"
        case .releaseDate:
            return "released_at IS NULL ASC, released_at \(direction == .ascending ? "DESC" : "ASC"), name_key ASC"
        case .setNumber:
            return "set_code \(order), collector_number_number IS NULL ASC, collector_number_number \(order), collector_number \(order), name_key ASC"
        case .rarity:
            return "rarity_rank IS NULL ASC, rarity_rank \(order), name_key ASC"
        case .color:
            return "color_sort_key \(order), name_key ASC"
        case .priceUSD:
            return "price_usd IS NULL ASC, price_usd \(order), name_key ASC"
        case .priceTIX:
            return "price_tix IS NULL ASC, price_tix \(order), name_key ASC"
        case .priceEUR:
            return "price_eur IS NULL ASC, price_eur \(order), name_key ASC"
        case .manaValue:
            return "mana_value IS NULL ASC, mana_value \(order), name_key ASC"
        case .power:
            return "power_value IS NULL ASC, power_value \(order), name_key ASC"
        case .toughness:
            return "toughness_value IS NULL ASC, toughness_value \(order), name_key ASC"
        case .artistName:
            return "artist_key IS NULL ASC, artist_key \(order), name_key ASC"
        case .edhrecRank:
            return "edhrec_rank IS NULL ASC, edhrec_rank \(order), name_key ASC"
        case .pennyRank:
            return "penny_rank IS NULL ASC, penny_rank \(order), name_key ASC"
        }
    }

    init?(scryfallOrder: String) {
        switch scryfallOrder {
        case "name":
            self = .name
        case "released", "spoiled":
            self = .releaseDate
        case "set":
            self = .setNumber
        case "rarity":
            self = .rarity
        case "color":
            self = .color
        case "usd":
            self = .priceUSD
        case "tix":
            self = .priceTIX
        case "eur":
            self = .priceEUR
        case "cmc", "mv", "manavalue":
            self = .manaValue
        case "power":
            self = .power
        case "toughness":
            self = .toughness
        case "artist":
            self = .artistName
        case "edhrec":
            self = .edhrecRank
        case "penny", "review":
            self = .pennyRank
        default:
            return nil
        }
    }
}
