import Foundation

enum ScryfallCardNormalizer {
    static func normalize(
        _ card: ScryfallCardDTO,
        topLevelImages: LocalImagePair = LocalImagePair(),
        faceImages: [Int: LocalImagePair] = [:]
    ) -> CardRecord {
        let layout = card.layout ?? "unknown"
        let setType = card.setType ?? "unknown"
        let games = Set((card.games ?? []).map { $0.lowercased() })
        let promoTypes = Set((card.promoTypes ?? []).map { $0.lowercased() })
        let frameEffects = Set((card.frameEffects ?? []).map { $0.lowercased() })
        let securityStamp = card.securityStamp?.lowercased()
        let collectorNumber = card.collectorNumber ?? ""
        let rarity = card.rarity ?? "unknown"
        let colors = card.colors ?? []
        let colorIdentity = card.colorIdentity ?? []
        let producedMana = card.producedMana ?? []
        let colorIndicator = card.colorIndicator ?? []
        let finishes = card.finishes ?? []

        let faces = (card.cardFaces ?? []).enumerated().map { index, face in
            let images = faceImages[index] ?? LocalImagePair()
            return CardFaceRecord(
                cardID: card.id,
                faceIndex: index,
                name: face.name ?? "",
                typeLine: face.typeLine ?? "",
                oracleText: face.oracleText ?? "",
                smallImagePath: images.smallPath,
                normalImagePath: images.normalPath,
                largeImagePath: images.largePath,
                artCropImagePath: images.artCropPath,
                smallImageURL: Self.imageURLs(for: face.imageURIs).small?.absoluteString,
                normalImageURL: Self.imageURLs(for: face.imageURIs).normal?.absoluteString,
                largeImageURL: Self.imageURLs(for: face.imageURIs).large?.absoluteString,
                artCropImageURL: Self.imageURLs(for: face.imageURIs).artCrop?.absoluteString
            )
        }

        return CardRecord(
            id: card.id,
            oracleID: card.oracleID,
            name: card.name,
            language: card.lang,
            releasedAt: card.releasedAt,
            setCode: card.set ?? "",
            setName: card.setName ?? "",
            setType: setType,
            collectorNumber: collectorNumber,
            collectorNumberNumber: Self.leadingInteger(in: collectorNumber),
            rarity: rarity,
            rarityRank: Self.rarityRank(for: rarity),
            artist: card.artist,
            edhrecRank: card.edhrecRank,
            pennyRank: card.pennyRank,
            mtgoID: card.mtgoID,
            manaCost: card.manaCost ?? "",
            manaValue: card.cmc,
            power: card.power,
            powerValue: Self.numericValue(card.power),
            toughness: card.toughness,
            toughnessValue: Self.numericValue(card.toughness),
            loyalty: card.loyalty,
            loyaltyValue: Self.numericValue(card.loyalty),
            priceUSD: Self.price(card.prices?.usd),
            priceTIX: Self.price(card.prices?.tix),
            priceEUR: Self.price(card.prices?.eur),
            colorSortKey: Self.colorSortKey(colors: colors, colorIdentity: colorIdentity),
            colors: Self.normalizedSymbols(colors),
            colorIdentity: Self.normalizedSymbols(colorIdentity),
            producedMana: Self.normalizedSymbols(producedMana),
            colorIndicator: Self.normalizedSymbols(colorIndicator),
            layout: layout,
            typeLine: card.typeLine ?? "",
            oracleText: card.oracleText ?? "",
            keywords: Self.normalizedValues(card.keywords ?? []),
            flavorText: card.flavorText,
            watermark: card.watermark,
            legalities: Self.normalizedLegalities(card.legalities ?? [:]),
            games: Self.normalizedValues(card.games ?? []),
            finishes: Self.normalizedValues(finishes),
            promoTypes: Self.normalizedValues(card.promoTypes ?? []),
            frameEffects: Self.normalizedValues(card.frameEffects ?? []),
            artistIDs: Self.normalizedValues(card.artistIDs ?? []),
            illustrationID: card.illustrationID,
            borderColor: card.borderColor?.lowercased(),
            frame: card.frame?.lowercased(),
            securityStamp: securityStamp,
            isDigital: card.digital ?? false,
            isOversized: card.oversized ?? false,
            isUniversesBeyond: promoTypes.contains("universesbeyond") || securityStamp == "triangle",
            isAlchemy: Self.isAlchemy(setType: setType, promoTypes: promoTypes, games: games, digital: card.digital ?? false),
            isRealCard: Self.isRealCard(
                games: games,
                digital: card.digital ?? false,
                oversized: card.oversized ?? false,
                layout: layout,
                setType: setType
            ),
            isPromo: card.promo ?? false,
            isVariation: card.variation ?? false,
            isBoosterFun: Self.isBoosterFun(
                promoTypes: promoTypes,
                frameEffects: frameEffects,
                fullArt: card.fullArt ?? false,
                textless: card.textless ?? false,
                borderColor: card.borderColor
            ),
            isReserved: card.reserved ?? false,
            isGameChanger: card.gameChanger ?? false,
            isReprint: card.reprint ?? false,
            isBooster: card.booster ?? false,
            isStorySpotlight: card.storySpotlight ?? false,
            isFullArt: card.fullArt ?? false,
            isTextless: card.textless ?? false,
            isFoil: card.foil ?? finishes.contains("foil"),
            isNonfoil: card.nonfoil ?? finishes.contains("nonfoil"),
            isHighResolution: card.highresImage ?? false,
            smallImagePath: topLevelImages.smallPath,
            normalImagePath: topLevelImages.normalPath,
            largeImagePath: topLevelImages.largePath,
            artCropImagePath: topLevelImages.artCropPath,
            smallImageURL: Self.imageURLs(for: card.imageURIs).small?.absoluteString,
            normalImageURL: Self.imageURLs(for: card.imageURIs).normal?.absoluteString,
            largeImageURL: Self.imageURLs(for: card.imageURIs).large?.absoluteString,
            artCropImageURL: Self.imageURLs(for: card.imageURIs).artCrop?.absoluteString,
            faces: faces
        )
    }

    static func imageURLs(for imageURIs: ScryfallImageURIs?) -> ImageURLPair {
        ImageURLPair(
            small: imageURIs?.small.flatMap(URL.init(string:)),
            normal: imageURIs?.normal.flatMap(URL.init(string:)),
            large: imageURIs?.large.flatMap(URL.init(string:)),
            artCrop: imageURIs?.artCrop.flatMap(URL.init(string:))
        )
    }

    static func leadingInteger(in collectorNumber: String) -> Int? {
        let digits = collectorNumber.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    static func rarityRank(for rarity: String) -> Int? {
        switch rarity.lowercased() {
        case "common":
            0
        case "uncommon":
            1
        case "rare":
            2
        case "mythic":
            3
        default:
            nil
        }
    }

    static func numericValue(_ value: String?) -> Double? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Double(trimmed) {
            return direct
        }

        if trimmed.contains("+") {
            return nil
        }

        if trimmed.contains("*") {
            return nil
        }

        return nil
    }

    static func price(_ value: String?) -> Double? {
        guard let value else {
            return nil
        }
        return Double(value)
    }

    static func colorSortKey(colors: [String], colorIdentity: [String]) -> Int {
        let values = colors.isEmpty ? colorIdentity : colors
        let unique = Set(values.map { $0.uppercased() })

        if unique.isEmpty {
            return 6
        }

        if unique.count > 1 {
            return 5
        }

        switch unique.first {
        case "W":
            return 0
        case "U":
            return 1
        case "B":
            return 2
        case "R":
            return 3
        case "G":
            return 4
        default:
            return 6
        }
    }

    static func normalizedSymbols(_ values: [String]) -> [String] {
        values.map { $0.uppercased() }.sorted()
    }

    static func normalizedValues(_ values: [String]) -> [String] {
        values.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased() }.sorted()
    }

    static func normalizedLegalities(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { result, pair in
            result[pair.key.lowercased()] = pair.value.lowercased()
        }
    }

    static func isAlchemy(
        setType: String,
        promoTypes: Set<String>,
        games: Set<String>,
        digital: Bool
    ) -> Bool {
        setType.lowercased() == "alchemy"
            || promoTypes.contains("alchemy")
            || (digital && games == ["arena"])
            || (digital && games.contains("arena") && !games.contains("paper"))
    }

    static func isRealCard(
        games: Set<String>,
        digital: Bool,
        oversized: Bool,
        layout: String,
        setType: String
    ) -> Bool {
        guard games.contains("paper"), !digital, !oversized else {
            return false
        }

        if nonPlayableLayouts.contains(layout.lowercased()) {
            return false
        }

        if nonPlayableSetTypes.contains(setType.lowercased()) {
            return false
        }

        return true
    }

    static func isBoosterFun(
        promoTypes: Set<String>,
        frameEffects: Set<String>,
        fullArt: Bool,
        textless: Bool,
        borderColor: String?
    ) -> Bool {
        if fullArt || textless || borderColor?.lowercased() == "borderless" {
            return true
        }

        if !promoTypes.isDisjoint(with: boosterFunPromoTypes) {
            return true
        }

        if !frameEffects.isDisjoint(with: boosterFunFrameEffects) {
            return true
        }

        return false
    }

    private static let nonPlayableLayouts: Set<String> = [
        "art_series",
        "double_faced_token",
        "emblem",
        "planar",
        "scheme",
        "token",
        "vanguard"
    ]

    private static let nonPlayableSetTypes: Set<String> = [
        "archenemy",
        "memorabilia",
        "minigame",
        "planechase",
        "token",
        "vanguard"
    ]

    private static let boosterFunPromoTypes: Set<String> = [
        "boosterfun",
        "borderless",
        "doublerainbow",
        "extendedart",
        "serialized",
        "showcase"
    ]

    private static let boosterFunFrameEffects: Set<String> = [
        "borderless",
        "colorshifted",
        "etched",
        "extendedart",
        "inverted",
        "showcase"
    ]
}
