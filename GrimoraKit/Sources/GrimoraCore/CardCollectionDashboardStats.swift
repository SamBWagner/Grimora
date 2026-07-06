import Foundation

public enum CardCollectionColorBucket: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case white
    case blue
    case black
    case red
    case green
    case multicolor
    case colorless

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .white:
            "White"
        case .blue:
            "Blue"
        case .black:
            "Black"
        case .red:
            "Red"
        case .green:
            "Green"
        case .multicolor:
            "Multicolor"
        case .colorless:
            "Colorless"
        }
    }

    public var symbol: String {
        switch self {
        case .white:
            "W"
        case .blue:
            "U"
        case .black:
            "B"
        case .red:
            "R"
        case .green:
            "G"
        case .multicolor:
            "M"
        case .colorless:
            "C"
        }
    }
}

public struct CardCollectionColorStat: Equatable, Identifiable, Sendable {
    public var bucket: CardCollectionColorBucket
    public var quantity: Int
    public var percentage: Double

    public var id: CardCollectionColorBucket {
        bucket
    }

    public init(bucket: CardCollectionColorBucket, quantity: Int, percentage: Double) {
        self.bucket = bucket
        self.quantity = quantity
        self.percentage = percentage
    }
}

public struct CardCollectionTypeStat: Equatable, Identifiable, Sendable {
    public var name: String
    public var quantity: Int
    public var percentage: Double

    public var id: String {
        name
    }

    public init(name: String, quantity: Int, percentage: Double) {
        self.name = name
        self.quantity = quantity
        self.percentage = percentage
    }
}

public struct CardCollectionDashboardStats: Equatable, Sendable {
    public var totalQuantity: Int
    public var pricedQuantity: Int
    public var unpricedQuantity: Int
    public var unavailableQuantity: Int
    public var totalPriceUSD: Double
    public var colorDistribution: [CardCollectionColorStat]
    public var topTypes: [CardCollectionTypeStat]

    public init(
        totalQuantity: Int,
        pricedQuantity: Int,
        unpricedQuantity: Int,
        unavailableQuantity: Int,
        totalPriceUSD: Double,
        colorDistribution: [CardCollectionColorStat],
        topTypes: [CardCollectionTypeStat]
    ) {
        self.totalQuantity = totalQuantity
        self.pricedQuantity = pricedQuantity
        self.unpricedQuantity = unpricedQuantity
        self.unavailableQuantity = unavailableQuantity
        self.totalPriceUSD = totalPriceUSD
        self.colorDistribution = colorDistribution
        self.topTypes = topTypes
    }

    public static func make(
        entries: [CardCollectionEntryRecord],
        includeLandsInTypes: Bool
    ) -> CardCollectionDashboardStats {
        var totalQuantity = 0
        var pricedQuantity = 0
        var unpricedQuantity = 0
        var unavailableQuantity = 0
        var totalPriceUSD: Double = 0
        var colorCounts: [CardCollectionColorBucket: Int] = [:]
        var typeCounts: [String: Int] = [:]

        for entry in entries {
            let quantity = max(1, entry.quantity)
            totalQuantity += quantity

            guard let card = entry.card else {
                unavailableQuantity += quantity
                continue
            }

            colorCounts[colorBucket(for: card), default: 0] += quantity

            if let priceUSD = card.priceUSD {
                pricedQuantity += quantity
                totalPriceUSD += priceUSD * Double(quantity)
            } else {
                unpricedQuantity += quantity
            }

            for type in topLevelTypes(for: card, includeLandsInTypes: includeLandsInTypes) {
                typeCounts[type, default: 0] += quantity
            }
        }

        let colorTotal = colorCounts.values.reduce(0, +)
        let colorDistribution: [CardCollectionColorStat] = CardCollectionColorBucket.allCases.compactMap { bucket in
            guard let quantity = colorCounts[bucket], quantity > 0 else {
                return nil
            }
            return CardCollectionColorStat(
                bucket: bucket,
                quantity: quantity,
                percentage: percentage(quantity, of: colorTotal)
            )
        }

        let typeTotal = typeCounts.values.reduce(0, +)
        let topTypes = typeCounts
            .map { CardCollectionTypeStat(name: $0.key, quantity: $0.value, percentage: percentage($0.value, of: typeTotal)) }
            .sorted { lhs, rhs in
                if lhs.quantity != rhs.quantity {
                    return lhs.quantity > rhs.quantity
                }
                return lhs.name < rhs.name
            }
            .prefix(5)

        return CardCollectionDashboardStats(
            totalQuantity: totalQuantity,
            pricedQuantity: pricedQuantity,
            unpricedQuantity: unpricedQuantity,
            unavailableQuantity: unavailableQuantity,
            totalPriceUSD: totalPriceUSD,
            colorDistribution: colorDistribution,
            topTypes: Array(topTypes)
        )
    }

    private static func colorBucket(for card: CardRecord) -> CardCollectionColorBucket {
        let symbols = card.colorIdentity.isEmpty ? card.colors : card.colorIdentity
        let recognizedSymbols = Set(symbols.compactMap { Self.normalizedColorSymbol($0) })

        if recognizedSymbols.isEmpty {
            return .colorless
        }
        if recognizedSymbols.count > 1 {
            return .multicolor
        }
        return Self.colorSymbolBuckets[recognizedSymbols.first ?? ""] ?? .colorless
    }

    private static func normalizedColorSymbol(_ value: String) -> String? {
        let symbol = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return Self.colorSymbolBuckets[symbol] == nil ? nil : symbol
    }

    private static func topLevelTypes(
        for card: CardRecord,
        includeLandsInTypes: Bool
    ) -> [String] {
        var types: Set<String> = []
        for typeLine in typeLines(for: card) {
            for type in topLevelTypes(in: typeLine) {
                guard includeLandsInTypes || type != "Land" else {
                    continue
                }
                types.insert(type)
            }
        }
        return types.sorted()
    }

    private static func typeLines(for card: CardRecord) -> [String] {
        let typeLine = card.typeLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typeLine.isEmpty {
            return [typeLine]
        }
        return card.faces
            .map(\.typeLine)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func topLevelTypes(in typeLine: String) -> [String] {
        var types: Set<String> = []
        for part in typeLine.components(separatedBy: "//") {
            let frontMatter = part.components(separatedBy: "\u{2014}").first ?? part
            for word in frontMatter.split(whereSeparator: { !$0.isLetter }) {
                if let type = MTGCardTypeCategory.recognizedTypeByLowercase[String(word).lowercased()] {
                    types.insert(type)
                }
            }
        }
        return types.sorted()
    }

    private static func percentage(_ quantity: Int, of total: Int) -> Double {
        guard total > 0 else {
            return 0
        }
        return Double(quantity) / Double(total)
    }

    private static let colorSymbolBuckets: [String: CardCollectionColorBucket] = [
        "W": .white,
        "U": .blue,
        "B": .black,
        "R": .red,
        "G": .green,
    ]
}
