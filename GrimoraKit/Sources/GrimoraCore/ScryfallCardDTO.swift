import Foundation

struct ScryfallCardDTO: Decodable, Equatable {
    var id: String
    var oracleID: String?
    var name: String
    var lang: String?
    var releasedAt: String?
    var layout: String?
    var manaCost: String?
    var cmc: Double?
    var typeLine: String?
    var oracleText: String?
    var power: String?
    var toughness: String?
    var colors: [String]?
    var colorIdentity: [String]?
    var games: [String]?
    var digital: Bool?
    var oversized: Bool?
    var set: String?
    var setName: String?
    var setType: String?
    var collectorNumber: String?
    var rarity: String?
    var artist: String?
    var artistIDs: [String]?
    var illustrationID: String?
    var edhrecRank: Int?
    var pennyRank: Int?
    var mtgoID: Int?
    var prices: ScryfallPrices?
    var imageURIs: ScryfallImageURIs?
    var cardFaces: [ScryfallCardFaceDTO]?
    var keywords: [String]?
    var producedMana: [String]?
    var colorIndicator: [String]?
    var legalities: [String: String]?
    var finishes: [String]?
    var foil: Bool?
    var nonfoil: Bool?
    var reserved: Bool?
    var gameChanger: Bool?
    var reprint: Bool?
    var booster: Bool?
    var storySpotlight: Bool?
    var highresImage: Bool?
    var flavorText: String?
    var watermark: String?
    var loyalty: String?
    var promoTypes: [String]?
    var securityStamp: String?
    var promo: Bool?
    var variation: Bool?
    var fullArt: Bool?
    var textless: Bool?
    var borderColor: String?
    var frame: String?
    var frameEffects: [String]?

    init(
        id: String,
        oracleID: String? = nil,
        name: String,
        lang: String? = nil,
        releasedAt: String? = nil,
        layout: String? = nil,
        manaCost: String? = nil,
        cmc: Double? = nil,
        typeLine: String? = nil,
        oracleText: String? = nil,
        power: String? = nil,
        toughness: String? = nil,
        colors: [String]? = nil,
        colorIdentity: [String]? = nil,
        games: [String]? = nil,
        digital: Bool? = nil,
        oversized: Bool? = nil,
        set: String? = nil,
        setName: String? = nil,
        setType: String? = nil,
        collectorNumber: String? = nil,
        rarity: String? = nil,
        artist: String? = nil,
        artistIDs: [String]? = nil,
        illustrationID: String? = nil,
        edhrecRank: Int? = nil,
        pennyRank: Int? = nil,
        mtgoID: Int? = nil,
        prices: ScryfallPrices? = nil,
        imageURIs: ScryfallImageURIs? = nil,
        cardFaces: [ScryfallCardFaceDTO]? = nil,
        keywords: [String]? = nil,
        producedMana: [String]? = nil,
        colorIndicator: [String]? = nil,
        legalities: [String: String]? = nil,
        finishes: [String]? = nil,
        foil: Bool? = nil,
        nonfoil: Bool? = nil,
        reserved: Bool? = nil,
        gameChanger: Bool? = nil,
        reprint: Bool? = nil,
        booster: Bool? = nil,
        storySpotlight: Bool? = nil,
        highresImage: Bool? = nil,
        flavorText: String? = nil,
        watermark: String? = nil,
        loyalty: String? = nil,
        promoTypes: [String]? = nil,
        securityStamp: String? = nil,
        promo: Bool? = nil,
        variation: Bool? = nil,
        fullArt: Bool? = nil,
        textless: Bool? = nil,
        borderColor: String? = nil,
        frame: String? = nil,
        frameEffects: [String]? = nil
    ) {
        self.id = id
        self.oracleID = oracleID
        self.name = name
        self.lang = lang
        self.releasedAt = releasedAt
        self.layout = layout
        self.manaCost = manaCost
        self.cmc = cmc
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.power = power
        self.toughness = toughness
        self.colors = colors
        self.colorIdentity = colorIdentity
        self.games = games
        self.digital = digital
        self.oversized = oversized
        self.set = set
        self.setName = setName
        self.setType = setType
        self.collectorNumber = collectorNumber
        self.rarity = rarity
        self.artist = artist
        self.artistIDs = artistIDs
        self.illustrationID = illustrationID
        self.edhrecRank = edhrecRank
        self.pennyRank = pennyRank
        self.mtgoID = mtgoID
        self.prices = prices
        self.imageURIs = imageURIs
        self.cardFaces = cardFaces
        self.keywords = keywords
        self.producedMana = producedMana
        self.colorIndicator = colorIndicator
        self.legalities = legalities
        self.finishes = finishes
        self.foil = foil
        self.nonfoil = nonfoil
        self.reserved = reserved
        self.gameChanger = gameChanger
        self.reprint = reprint
        self.booster = booster
        self.storySpotlight = storySpotlight
        self.highresImage = highresImage
        self.flavorText = flavorText
        self.watermark = watermark
        self.loyalty = loyalty
        self.promoTypes = promoTypes
        self.securityStamp = securityStamp
        self.promo = promo
        self.variation = variation
        self.fullArt = fullArt
        self.textless = textless
        self.borderColor = borderColor
        self.frame = frame
        self.frameEffects = frameEffects
    }

    enum CodingKeys: String, CodingKey {
        case id
        case oracleID = "oracle_id"
        case name
        case lang
        case releasedAt = "released_at"
        case layout
        case manaCost = "mana_cost"
        case cmc
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case power
        case toughness
        case colors
        case colorIdentity = "color_identity"
        case games
        case digital
        case oversized
        case set
        case setName = "set_name"
        case setType = "set_type"
        case collectorNumber = "collector_number"
        case rarity
        case artist
        case artistIDs = "artist_ids"
        case illustrationID = "illustration_id"
        case edhrecRank = "edhrec_rank"
        case pennyRank = "penny_rank"
        case mtgoID = "mtgo_id"
        case prices
        case imageURIs = "image_uris"
        case cardFaces = "card_faces"
        case keywords
        case producedMana = "produced_mana"
        case colorIndicator = "color_indicator"
        case legalities
        case finishes
        case foil
        case nonfoil
        case reserved
        case gameChanger = "game_changer"
        case reprint
        case booster
        case storySpotlight = "story_spotlight"
        case highresImage = "highres_image"
        case flavorText = "flavor_text"
        case watermark
        case loyalty
        case promoTypes = "promo_types"
        case securityStamp = "security_stamp"
        case promo
        case variation
        case fullArt = "full_art"
        case textless
        case borderColor = "border_color"
        case frame
        case frameEffects = "frame_effects"
    }
}

struct ScryfallCardFaceDTO: Decodable, Equatable {
    var name: String?
    var typeLine: String?
    var oracleText: String?
    var imageURIs: ScryfallImageURIs?

    enum CodingKeys: String, CodingKey {
        case name
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case imageURIs = "image_uris"
    }
}

struct ScryfallImageURIs: Decodable, Equatable {
    var small: String?
    var normal: String?
    var large: String?
    var artCrop: String?

    enum CodingKeys: String, CodingKey {
        case small
        case normal
        case large
        case artCrop = "art_crop"
    }
}

struct ScryfallPrices: Decodable, Equatable {
    var usd: String?
    var eur: String?
    var tix: String?
}

public struct ImageURLPair: Equatable, Sendable {
    public var small: URL?
    public var normal: URL?
    public var large: URL?
    public var artCrop: URL?

    public init(small: URL? = nil, normal: URL?, large: URL?, artCrop: URL? = nil) {
        self.small = small
        self.normal = normal
        self.large = large
        self.artCrop = artCrop ?? Self.derivedArtCropURL(from: normal ?? large ?? small)
    }

    public static func derivedArtCropURL(from url: URL?) -> URL? {
        guard let url,
              let host = url.host?.lowercased(),
              host.contains("scryfall"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        var pathComponents = url.pathComponents
        guard let qualityIndex = pathComponents.firstIndex(where: { component in
            Self.fullCardImagePathComponents.contains(component)
        }) else {
            return nil
        }

        pathComponents[qualityIndex] = "art_crop"
        let prefix = pathComponents.first == "/" ? "/" : ""
        let joinedPath = pathComponents
            .filter { $0 != "/" }
            .joined(separator: "/")
        components.path = prefix + joinedPath
        return components.url
    }

    private static let fullCardImagePathComponents: Set<String> = [
        "small", "normal", "large", "png", "border_crop"
    ]
}

public struct LocalImagePair: Equatable, Sendable {
    public var smallPath: String?
    public var normalPath: String?
    public var largePath: String?
    public var artCropPath: String?

    public init(
        smallPath: String? = nil,
        normalPath: String? = nil,
        largePath: String? = nil,
        artCropPath: String? = nil
    ) {
        self.smallPath = smallPath
        self.normalPath = normalPath
        self.largePath = largePath
        self.artCropPath = artCropPath
    }
}
