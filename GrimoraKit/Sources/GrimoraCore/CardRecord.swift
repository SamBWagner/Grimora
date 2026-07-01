import Foundation

public struct CardRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var oracleID: String?
    public var name: String
    public var displayNameKey: String
    public var language: String?
    public var releasedAt: String?
    public var setCode: String
    public var setName: String
    public var setType: String
    public var collectorNumber: String
    public var collectorNumberNumber: Int?
    public var rarity: String
    public var rarityRank: Int?
    public var artist: String?
    public var edhrecRank: Int?
    public var pennyRank: Int?
    public var mtgoID: Int?
    public var manaCost: String
    public var manaValue: Double?
    public var power: String?
    public var powerValue: Double?
    public var toughness: String?
    public var toughnessValue: Double?
    public var loyalty: String?
    public var loyaltyValue: Double?
    public var priceUSD: Double?
    public var priceTIX: Double?
    public var priceEUR: Double?
    public var colorSortKey: Int
    public var colors: [String]
    public var colorIdentity: [String]
    public var producedMana: [String]
    public var colorIndicator: [String]
    public var layout: String
    public var typeLine: String
    public var oracleText: String
    public var keywords: [String]
    public var flavorText: String?
    public var watermark: String?
    public var legalities: [String: String]
    public var games: [String]
    public var finishes: [String]
    public var promoTypes: [String]
    public var frameEffects: [String]
    public var artistIDs: [String]
    public var illustrationID: String?
    public var borderColor: String?
    public var frame: String?
    public var securityStamp: String?
    public var isDigital: Bool
    public var isOversized: Bool
    public var isUniversesBeyond: Bool
    public var isAlchemy: Bool
    public var isRealCard: Bool
    public var isPromo: Bool
    public var isVariation: Bool
    public var isBoosterFun: Bool
    public var isBasePrinting: Bool
    public var isReserved: Bool
    public var isGameChanger: Bool
    public var isReprint: Bool
    public var isBooster: Bool
    public var isStorySpotlight: Bool
    public var isFullArt: Bool
    public var isTextless: Bool
    public var isFoil: Bool
    public var isNonfoil: Bool
    public var isHighResolution: Bool
    public var printCount: Int
    public var setCount: Int
    public var paperPrintCount: Int
    public var paperSetCount: Int
    public var artistCount: Int
    public var illustrationCount: Int
    public var isNewArt: Bool
    public var isNewArtist: Bool
    public var isNewFlavor: Bool
    public var isNewRarity: Bool
    public var isNewFrame: Bool
    public var isNewLanguage: Bool
    public var smallImagePath: String?
    public var normalImagePath: String?
    public var largeImagePath: String?
    public var artCropImagePath: String?
    public var smallImageURL: String?
    public var normalImageURL: String?
    public var largeImageURL: String?
    public var artCropImageURL: String?
    public var faces: [CardFaceRecord]

    public init(
        id: String,
        oracleID: String? = nil,
        name: String,
        displayNameKey: String? = nil,
        language: String? = nil,
        releasedAt: String? = nil,
        setCode: String,
        setName: String,
        setType: String,
        collectorNumber: String,
        collectorNumberNumber: Int? = nil,
        rarity: String,
        rarityRank: Int? = nil,
        artist: String? = nil,
        edhrecRank: Int? = nil,
        pennyRank: Int? = nil,
        mtgoID: Int? = nil,
        manaCost: String = "",
        manaValue: Double? = nil,
        power: String? = nil,
        powerValue: Double? = nil,
        toughness: String? = nil,
        toughnessValue: Double? = nil,
        loyalty: String? = nil,
        loyaltyValue: Double? = nil,
        priceUSD: Double? = nil,
        priceTIX: Double? = nil,
        priceEUR: Double? = nil,
        colorSortKey: Int,
        colors: [String] = [],
        colorIdentity: [String] = [],
        producedMana: [String] = [],
        colorIndicator: [String] = [],
        layout: String,
        typeLine: String,
        oracleText: String,
        keywords: [String] = [],
        flavorText: String? = nil,
        watermark: String? = nil,
        legalities: [String: String] = [:],
        games: [String] = [],
        finishes: [String] = [],
        promoTypes: [String] = [],
        frameEffects: [String] = [],
        artistIDs: [String] = [],
        illustrationID: String? = nil,
        borderColor: String? = nil,
        frame: String? = nil,
        securityStamp: String? = nil,
        isDigital: Bool = false,
        isOversized: Bool = false,
        isUniversesBeyond: Bool = false,
        isAlchemy: Bool = false,
        isRealCard: Bool = true,
        isPromo: Bool = false,
        isVariation: Bool = false,
        isBoosterFun: Bool = false,
        isBasePrinting: Bool? = nil,
        isReserved: Bool = false,
        isGameChanger: Bool = false,
        isReprint: Bool = false,
        isBooster: Bool = false,
        isStorySpotlight: Bool = false,
        isFullArt: Bool = false,
        isTextless: Bool = false,
        isFoil: Bool = false,
        isNonfoil: Bool = false,
        isHighResolution: Bool = false,
        printCount: Int = 1,
        setCount: Int = 1,
        paperPrintCount: Int = 0,
        paperSetCount: Int = 0,
        artistCount: Int = 0,
        illustrationCount: Int = 0,
        isNewArt: Bool = false,
        isNewArtist: Bool = false,
        isNewFlavor: Bool = false,
        isNewRarity: Bool = false,
        isNewFrame: Bool = false,
        isNewLanguage: Bool = false,
        smallImagePath: String? = nil,
        normalImagePath: String? = nil,
        largeImagePath: String? = nil,
        artCropImagePath: String? = nil,
        smallImageURL: String? = nil,
        normalImageURL: String? = nil,
        largeImageURL: String? = nil,
        artCropImageURL: String? = nil,
        faces: [CardFaceRecord] = []
    ) {
        self.id = id
        self.oracleID = oracleID
        self.name = name
        self.displayNameKey = displayNameKey ?? Self.defaultDisplayNameKey(
            name: name,
            layout: layout,
            faces: faces
        )
        self.language = language
        self.releasedAt = releasedAt
        self.setCode = setCode
        self.setName = setName
        self.setType = setType
        self.collectorNumber = collectorNumber
        self.collectorNumberNumber = collectorNumberNumber
        self.rarity = rarity
        self.rarityRank = rarityRank
        self.artist = artist
        self.edhrecRank = edhrecRank
        self.pennyRank = pennyRank
        self.mtgoID = mtgoID
        self.manaCost = manaCost
        self.manaValue = manaValue
        self.power = power
        self.powerValue = powerValue
        self.toughness = toughness
        self.toughnessValue = toughnessValue
        self.loyalty = loyalty
        self.loyaltyValue = loyaltyValue
        self.priceUSD = priceUSD
        self.priceTIX = priceTIX
        self.priceEUR = priceEUR
        self.colorSortKey = colorSortKey
        self.colors = colors
        self.colorIdentity = colorIdentity
        self.producedMana = producedMana
        self.colorIndicator = colorIndicator
        self.layout = layout
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.keywords = keywords
        self.flavorText = flavorText
        self.watermark = watermark
        self.legalities = legalities
        self.games = games
        self.finishes = finishes
        self.promoTypes = promoTypes
        self.frameEffects = frameEffects
        self.artistIDs = artistIDs
        self.illustrationID = illustrationID
        self.borderColor = borderColor
        self.frame = frame
        self.securityStamp = securityStamp
        self.isDigital = isDigital
        self.isOversized = isOversized
        self.isUniversesBeyond = isUniversesBeyond
        self.isAlchemy = isAlchemy
        self.isRealCard = isRealCard
        self.isPromo = isPromo
        self.isVariation = isVariation
        self.isBoosterFun = isBoosterFun
        self.isBasePrinting = isBasePrinting ?? Self.defaultIsBasePrinting(
            setType: setType,
            isRealCard: isRealCard,
            isUniversesBeyond: isUniversesBeyond,
            isPromo: isPromo,
            isVariation: isVariation,
            isBoosterFun: isBoosterFun
        )
        self.isReserved = isReserved
        self.isGameChanger = isGameChanger
        self.isReprint = isReprint
        self.isBooster = isBooster
        self.isStorySpotlight = isStorySpotlight
        self.isFullArt = isFullArt
        self.isTextless = isTextless
        self.isFoil = isFoil
        self.isNonfoil = isNonfoil
        self.isHighResolution = isHighResolution
        self.printCount = printCount
        self.setCount = setCount
        self.paperPrintCount = paperPrintCount
        self.paperSetCount = paperSetCount
        self.artistCount = artistCount
        self.illustrationCount = illustrationCount
        self.isNewArt = isNewArt
        self.isNewArtist = isNewArtist
        self.isNewFlavor = isNewFlavor
        self.isNewRarity = isNewRarity
        self.isNewFrame = isNewFrame
        self.isNewLanguage = isNewLanguage
        self.smallImagePath = smallImagePath
        self.normalImagePath = normalImagePath
        self.largeImagePath = largeImagePath
        self.artCropImagePath = artCropImagePath
        self.smallImageURL = smallImageURL
        self.normalImageURL = normalImageURL
        self.largeImageURL = largeImageURL
        self.artCropImageURL = artCropImageURL
        self.faces = faces
    }

    /// Whether this printing can exist as a foil. Scryfall reports availability via
    /// the `finishes` array; `isFoil` is the legacy boolean. Either signalling foil
    /// means the foil toggle should be enabled for this printing.
    public var supportsFoil: Bool {
        isFoil || finishes.contains("foil")
    }

    /// Whether this printing can exist as a non-foil. Mirror of `supportsFoil` for the
    /// `nonfoil` finish so callers can tell a foil-only printing from a both-finishes one.
    public var supportsNonfoil: Bool {
        isNonfoil || finishes.contains("nonfoil")
    }

    /// Whether this printing exists *only* as a foil — it supports foil and offers no
    /// non-foil finish. Such a printing is inherently foil: it should default to foil and the
    /// foil toggle should be locked on. (An empty/unknown `finishes` with both legacy flags
    /// false is treated as not foil-only.)
    public var isFoilOnly: Bool {
        supportsFoil && !supportsNonfoil
    }

    /// Whether this printing can exist as an etched foil. Scryfall reports etched in the
    /// `finishes` array on the *same* card object as the normal/foil version (e.g. MH2 #271
    /// Wonder), but some sets carry it as a frame effect instead — accept either.
    public var supportsEtched: Bool {
        finishes.contains("etched") || frameEffects.contains("etched")
    }

    /// The selectable finishes this printing offers, in display order (Normal → Foil → Etched),
    /// derived from `finishes` plus the legacy booleans. Drives the detail-view finish picker.
    public var availableFinishes: [CardValueFinish] {
        var result: [CardValueFinish] = []
        if supportsNonfoil { result.append(.normal) }
        if supportsFoil { result.append(.foil) }
        if supportsEtched { result.append(.etched) }
        return result
    }

    /// The finish a printing should default to when the user hasn't chosen one. A printing that
    /// offers exactly one finish (foil-only, etched-only, or plain non-foil) is inherently that
    /// finish; anything else defaults to non-foil. Unknown/empty finish data defaults to normal.
    public var defaultFinish: CardValueFinish {
        let available = availableFinishes
        return available.count == 1 ? available[0] : .normal
    }

    /// The special promo-type foil treatment intrinsic to this printing (halo, surge, galaxy, …),
    /// if any. Independent of the selected finish — it's a property of the printing itself.
    public var specialFoilTreatment: CardFoilTreatment? {
        CardFoilTreatment.from(promoTypes: promoTypes)
    }

    /// Resolves the foil treatment to *render* for a chosen finish. Non-foil shows nothing;
    /// etched shows the etched treatment; foil shows this printing's special treatment if it has
    /// one (a halo-foil printing is always foil), otherwise plain `.standard` foil.
    public func foilTreatment(for finish: CardValueFinish) -> CardFoilTreatment {
        switch finish {
        case .normal:
            return .none
        case .etched:
            return .etched
        case .foil:
            return specialFoilTreatment ?? .standard
        }
    }

    public var displayImagePath: String? {
        firstPath([
            normalImagePath,
            largeImagePath,
            smallImagePath,
            faces.first?.normalImagePath,
            faces.first?.largeImagePath,
            faces.first?.smallImagePath
        ])
    }

    public var detailImagePath: String? {
        firstPath([
            largeImagePath,
            normalImagePath,
            smallImagePath,
            faces.first?.largeImagePath,
            faces.first?.normalImagePath,
            faces.first?.smallImagePath
        ])
    }

    public var existingDisplayImagePath: String? {
        displayImagePath
    }

    public var listOverviewImagePath: String? {
        if let artCropPath = firstPath([
            artCropImagePath,
            faces.first?.artCropImagePath
        ]) {
            return artCropPath
        }

        if remoteImageURLs.artCrop != nil || faces.first?.remoteImageURLs.artCrop != nil {
            return nil
        }

        return displayImagePath
    }

    private var preferredDisplayImagePath: String? {
        firstPath([
            normalImagePath,
            smallImagePath,
            faces.first?.normalImagePath,
            faces.first?.smallImagePath
        ])
    }

    public var hasExistingDisplayImage: Bool {
        existingDisplayImagePath != nil
    }

    public func hasMissingCachedDisplayImageFile(
        for quality: CardImageQuality,
        fileManager: FileManager = .default
    ) -> Bool {
        hasUnavailableCachedDisplayImageFile(for: quality, fileManager: fileManager)
    }

    public func hasUnavailableCachedDisplayImageFile(
        for quality: CardImageQuality,
        fileManager: FileManager = .default
    ) -> Bool {
        let paths = cachedDisplayImagePaths(for: quality)
        guard !paths.isEmpty else {
            return false
        }

        return paths.allSatisfy {
            !LocalImageFileValidator.isUsableCachedImageFile(atPath: $0, fileManager: fileManager)
        }
    }

    public func hasCachedDisplayImage(for quality: CardImageQuality) -> Bool {
        switch quality {
        case .small:
            if preferredDisplayImagePath != nil {
                return true
            }
            return !hasRemoteImage(for: .small) && displayImagePath != nil
        case .normal:
            if firstPath([
                normalImagePath,
                faces.first?.normalImagePath
            ]) != nil {
                return true
            }
            guard !hasRemoteImage(for: .normal) else {
                return false
            }
            if preferredDisplayImagePath != nil {
                return true
            }
            return !hasRemoteImage(for: .small) && displayImagePath != nil
        case .large:
            if firstPath([
                largeImagePath,
                faces.first?.largeImagePath
            ]) != nil {
                return true
            }
            guard !hasRemoteImage(for: .large) else {
                return false
            }
            if hasRemoteImage(for: .normal) {
                return firstPath([
                    normalImagePath,
                    faces.first?.normalImagePath
                ]) != nil
            }
            return detailImagePath != nil
        case .artCrop:
            if firstPath([
                artCropImagePath,
                faces.first?.artCropImagePath
            ]) != nil {
                return true
            }
            guard !hasRemoteImage(for: .artCrop) else {
                return false
            }
            return displayImagePath != nil
        }
    }

    private func cachedDisplayImagePaths(for quality: CardImageQuality) -> [String] {
        switch quality {
        case .small:
            return compactPaths([
                normalImagePath,
                smallImagePath,
                faces.first?.normalImagePath,
                faces.first?.smallImagePath
            ])
        case .normal:
            let normalPaths = compactPaths([
                normalImagePath,
                faces.first?.normalImagePath
            ])
            guard normalPaths.isEmpty else {
                return normalPaths
            }
            return hasRemoteImage(for: .normal) ? [] : cachedDisplayImagePaths(for: .small)
        case .large:
            let largePaths = compactPaths([
                largeImagePath,
                faces.first?.largeImagePath
            ])
            guard largePaths.isEmpty else {
                return largePaths
            }
            guard !hasRemoteImage(for: .large) else {
                return []
            }
            if hasRemoteImage(for: .normal) {
                return compactPaths([
                    normalImagePath,
                    faces.first?.normalImagePath
                ])
            }
            return compactPaths([
                largeImagePath,
                normalImagePath,
                smallImagePath,
                faces.first?.largeImagePath,
                faces.first?.normalImagePath,
                faces.first?.smallImagePath
            ])
        case .artCrop:
            let artCropPaths = compactPaths([
                artCropImagePath,
                faces.first?.artCropImagePath
            ])
            guard artCropPaths.isEmpty else {
                return artCropPaths
            }
            return hasRemoteImage(for: .artCrop) ? [] : cachedDisplayImagePaths(for: .normal)
        }
    }

    private func hasRemoteImage(for quality: CardImageQuality) -> Bool {
        switch quality {
        case .small:
            return firstPath([
                smallImageURL,
                faces.first?.smallImageURL
            ]) != nil
        case .normal:
            return firstPath([
                normalImageURL,
                faces.first?.normalImageURL
            ]) != nil
        case .large:
            return firstPath([
                largeImageURL,
                faces.first?.largeImageURL
            ]) != nil
        case .artCrop:
            return remoteImageURLs.artCrop != nil
        }
    }

    var searchText: String {
        let faceText = faces.map { "\($0.name) \($0.typeLine) \($0.oracleText)" }.joined(separator: " ")
        return [
            name,
            manaCost,
            typeLine,
            oracleText,
            keywords.joined(separator: " "),
            flavorText ?? "",
            setName,
            artist ?? "",
            faceText
        ]
            .joined(separator: " ")
    }

    var remoteImageURLs: ImageURLPair {
        ImageURLPair(
            small: smallImageURL.flatMap(URL.init(string:)),
            normal: normalImageURL.flatMap(URL.init(string:)),
            large: largeImageURL.flatMap(URL.init(string:)),
            artCrop: artCropImageURL.flatMap(URL.init(string:))
        )
    }

    var hasRemoteSmallImage: Bool {
        smallImageURL != nil || faces.contains { $0.smallImageURL != nil }
    }

    mutating func applyLocalImagePaths(_ paths: LocalImagePair) -> Bool {
        var didChange = false

        if let smallPath = paths.smallPath, smallImagePath != smallPath {
            smallImagePath = smallPath
            didChange = true
        }

        if let normalPath = paths.normalPath, normalImagePath != normalPath {
            normalImagePath = normalPath
            didChange = true
        }

        if let largePath = paths.largePath, largeImagePath != largePath {
            largeImagePath = largePath
            didChange = true
        }

        if let artCropPath = paths.artCropPath, artCropImagePath != artCropPath {
            artCropImagePath = artCropPath
            didChange = true
        }

        return didChange
    }

    static func defaultDisplayNameKey(
        name: String,
        layout: String,
        faces: [CardFaceRecord]
    ) -> String {
        let normalizedLayout = layout.normalizedCardKey
        if normalizedLayout == "prepare", let firstFaceName = faces.first?.name, !firstFaceName.isEmpty {
            return firstFaceName.normalizedCardKey
        }

        if normalizedLayout == "reversible_card" {
            let parts = name
                .components(separatedBy: " // ")
                .map { $0.normalizedCardKey }
                .filter { !$0.isEmpty }
            if let first = parts.first, parts.allSatisfy({ $0 == first }) {
                return first
            }
        }

        return name.normalizedCardKey
    }

    static func defaultIsBasePrinting(
        setType: String,
        isRealCard: Bool,
        isUniversesBeyond: Bool,
        isPromo: Bool,
        isVariation: Bool,
        isBoosterFun: Bool
    ) -> Bool {
        isRealCard
            && !isUniversesBeyond
            && !isPromo
            && !isVariation
            && !isBoosterFun
            && basePrintingSetTypes.contains(setType.normalizedCardKey)
    }

    private static let basePrintingSetTypes: Set<String> = [
        "commander",
        "core",
        "draft_innovation",
        "duel_deck",
        "expansion",
        "masters",
        "starter"
    ]
}

public struct CardFaceRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(cardID)-face-\(faceIndex)" }
    public var cardID: String
    public var faceIndex: Int
    public var name: String
    public var typeLine: String
    public var oracleText: String
    public var smallImagePath: String?
    public var normalImagePath: String?
    public var largeImagePath: String?
    public var artCropImagePath: String?
    public var smallImageURL: String?
    public var normalImageURL: String?
    public var largeImageURL: String?
    public var artCropImageURL: String?

    public init(
        cardID: String,
        faceIndex: Int,
        name: String,
        typeLine: String,
        oracleText: String,
        smallImagePath: String? = nil,
        normalImagePath: String? = nil,
        largeImagePath: String? = nil,
        artCropImagePath: String? = nil,
        smallImageURL: String? = nil,
        normalImageURL: String? = nil,
        largeImageURL: String? = nil,
        artCropImageURL: String? = nil
    ) {
        self.cardID = cardID
        self.faceIndex = faceIndex
        self.name = name
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.smallImagePath = smallImagePath
        self.normalImagePath = normalImagePath
        self.largeImagePath = largeImagePath
        self.artCropImagePath = artCropImagePath
        self.smallImageURL = smallImageURL
        self.normalImageURL = normalImageURL
        self.largeImageURL = largeImageURL
        self.artCropImageURL = artCropImageURL
    }

    var remoteImageURLs: ImageURLPair {
        ImageURLPair(
            small: smallImageURL.flatMap(URL.init(string:)),
            normal: normalImageURL.flatMap(URL.init(string:)),
            large: largeImageURL.flatMap(URL.init(string:)),
            artCrop: artCropImageURL.flatMap(URL.init(string:))
        )
    }

    mutating func applyLocalImagePaths(_ paths: LocalImagePair) -> Bool {
        var didChange = false

        if let smallPath = paths.smallPath, smallImagePath != smallPath {
            smallImagePath = smallPath
            didChange = true
        }

        if let normalPath = paths.normalPath, normalImagePath != normalPath {
            normalImagePath = normalPath
            didChange = true
        }

        if let largePath = paths.largePath, largeImagePath != largePath {
            largeImagePath = largePath
            didChange = true
        }

        if let artCropPath = paths.artCropPath, artCropImagePath != artCropPath {
            artCropImagePath = artCropPath
            didChange = true
        }

        return didChange
    }
}

private extension String {
    var normalizedCardKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

private func firstPath(_ paths: [String?]) -> String? {
    paths.compactMap { $0 }.first
}

private func compactPaths(_ paths: [String?]) -> [String] {
    paths.compactMap { $0 }
}
