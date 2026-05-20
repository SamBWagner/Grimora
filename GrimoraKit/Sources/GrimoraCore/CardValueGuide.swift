import Foundation

public enum CardValueFinish: String, CaseIterable, Codable, Equatable, Sendable {
    case normal
    case foil
    case etched

    public var title: String {
        switch self {
        case .normal:
            "Normal"
        case .foil:
            "Foil"
        case .etched:
            "Etched"
        }
    }
}

public struct CardValueMovement: Codable, Equatable, Sendable {
    public var days: Int
    public var previousPrice: Double
    public var delta: Double
    public var percent: Double?

    public init(days: Int, currentPrice: Double, previousPrice: Double) {
        self.days = days
        self.previousPrice = previousPrice
        self.delta = currentPrice - previousPrice
        self.percent = previousPrice == 0 ? nil : (currentPrice - previousPrice) / previousPrice
    }
}

public struct CardValueHistoryPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: String { date }
    public var date: String
    public var price: Double

    public init(date: String, price: Double) {
        self.date = date
        self.price = price
    }
}

public struct CardValueGuideEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: CardValueFinish { finish }
    public var finish: CardValueFinish
    public var currentPrice: Double
    public var currentDate: String
    public var oneDay: CardValueMovement?
    public var sevenDay: CardValueMovement?
    public var thirtyDay: CardValueMovement?
    public var ninetyDay: CardValueMovement?
    public var history: [CardValueHistoryPoint]

    public init(
        finish: CardValueFinish,
        currentPrice: Double,
        currentDate: String,
        oneDay: CardValueMovement? = nil,
        sevenDay: CardValueMovement? = nil,
        thirtyDay: CardValueMovement? = nil,
        ninetyDay: CardValueMovement? = nil,
        history: [CardValueHistoryPoint] = []
    ) {
        self.finish = finish
        self.currentPrice = currentPrice
        self.currentDate = currentDate
        self.oneDay = oneDay
        self.sevenDay = sevenDay
        self.thirtyDay = thirtyDay
        self.ninetyDay = ninetyDay
        self.history = history
    }

    public var highestPrice: Double {
        history.map(\.price).max() ?? currentPrice
    }

    public func movement(days: Int) -> CardValueMovement? {
        switch days {
        case 1:
            oneDay
        case 7:
            sevenDay
        case 30:
            thirtyDay
        case 90:
            ninetyDay
        default:
            nil
        }
    }
}

public struct CardValueGuide: Codable, Equatable, Sendable {
    public var cardID: CardRecord.ID
    public var sourceName: String
    public var entries: [CardValueGuideEntry]

    public init(
        cardID: CardRecord.ID,
        sourceName: String = "TCGplayer via MTGJSON",
        entries: [CardValueGuideEntry] = []
    ) {
        self.cardID = cardID
        self.sourceName = sourceName
        self.entries = entries
    }

    public var isAvailable: Bool {
        !entries.isEmpty
    }
}
