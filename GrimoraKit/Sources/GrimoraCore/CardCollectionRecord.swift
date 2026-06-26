import Foundation

public enum CardCollectionRuleset: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case commander
    case standard
    case pioneer
    case modern
    case legacy
    case vintage
    case pauper

    public var id: Self { self }

    public var title: String {
        switch self {
        case .none:
            "No Ruleset"
        case .commander:
            "Commander"
        case .standard:
            "Standard"
        case .pioneer:
            "Pioneer"
        case .modern:
            "Modern"
        case .legacy:
            "Legacy"
        case .vintage:
            "Vintage"
        case .pauper:
            "Pauper"
        }
    }

    public var legalityKey: String? {
        switch self {
        case .none:
            nil
        case .commander:
            "commander"
        case .standard:
            "standard"
        case .pioneer:
            "pioneer"
        case .modern:
            "modern"
        case .legacy:
            "legacy"
        case .vintage:
            "vintage"
        case .pauper:
            "pauper"
        }
    }

    public var isConstructed: Bool {
        switch self {
        case .standard, .pioneer, .modern, .legacy, .vintage, .pauper:
            true
        case .none, .commander:
            false
        }
    }

    public var allowedZones: [CardCollectionZone] {
        switch self {
        case .commander:
            [.commander, .mainboard, .maybeboard]
        case .standard, .pioneer, .modern, .legacy, .vintage, .pauper:
            [.mainboard, .sideboard, .maybeboard]
        case .none:
            [.mainboard, .maybeboard]
        }
    }

    public func normalizedZone(_ zone: CardCollectionZone) -> CardCollectionZone {
        if allowedZones.contains(zone) {
            return zone
        }

        return .mainboard
    }

    public init(rawValueOrDefault rawValue: String?) {
        self = rawValue.flatMap(Self.init(rawValue:)) ?? .none
    }
}

public enum CardCollectionZone: String, CaseIterable, Codable, Identifiable, Sendable {
    case commander
    case mainboard
    case sideboard
    case maybeboard

    public var id: Self { self }

    public var title: String {
        switch self {
        case .commander:
            "Commander"
        case .mainboard:
            "Mainboard"
        case .sideboard:
            "Sideboard"
        case .maybeboard:
            "Maybeboard"
        }
    }

    public init(rawValueOrDefault rawValue: String?) {
        self = rawValue.flatMap(Self.init(rawValue:)) ?? .mainboard
    }
}

public enum CardCollectionViewMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case grid
    case list

    public var id: Self { self }

    public init(rawValueOrDefault rawValue: String?) {
        self = rawValue.flatMap(Self.init(rawValue:)) ?? .grid
    }
}

public struct CardCollectionRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var ruleset: CardCollectionRuleset
    public var descriptionRTFDData: Data?
    public var descriptionPlainText: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var pinnedAt: Date?
    public var position: Int
    public var showsDashboard: Bool
    public var dashboardIncludesLands: Bool
    public var displaySortMode: SortMode?
    public var displaySortDirection: SearchSortDirection
    public var viewMode: CardCollectionViewMode
    public var entryCount: Int

    public init(
        id: String,
        name: String,
        ruleset: CardCollectionRuleset = .none,
        descriptionRTFDData: Data? = nil,
        descriptionPlainText: String = "",
        createdAt: Date,
        updatedAt: Date,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        position: Int = 0,
        showsDashboard: Bool = false,
        dashboardIncludesLands: Bool = false,
        displaySortMode: SortMode? = nil,
        displaySortDirection: SearchSortDirection = .ascending,
        viewMode: CardCollectionViewMode = .grid,
        entryCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.ruleset = ruleset
        self.descriptionRTFDData = descriptionRTFDData
        self.descriptionPlainText = descriptionPlainText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.position = position
        self.showsDashboard = showsDashboard
        self.dashboardIncludesLands = dashboardIncludesLands
        self.displaySortMode = displaySortMode
        self.displaySortDirection = displaySortDirection
        self.viewMode = viewMode
        self.entryCount = entryCount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case ruleset
        case descriptionRTFDData
        case descriptionPlainText
        case createdAt
        case updatedAt
        case isPinned
        case pinnedAt
        case position
        case showsDashboard
        case dashboardIncludesLands
        case displaySortMode
        case displaySortDirection
        case viewMode
        case entryCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ruleset = try container.decodeIfPresent(CardCollectionRuleset.self, forKey: .ruleset) ?? .none
        descriptionRTFDData = try container.decodeIfPresent(Data.self, forKey: .descriptionRTFDData)
        descriptionPlainText = try container.decodeIfPresent(String.self, forKey: .descriptionPlainText) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        showsDashboard = try container.decodeIfPresent(Bool.self, forKey: .showsDashboard) ?? false
        dashboardIncludesLands = try container.decodeIfPresent(Bool.self, forKey: .dashboardIncludesLands) ?? false
        displaySortMode = try container.decodeIfPresent(SortMode.self, forKey: .displaySortMode)
        displaySortDirection =
            try container.decodeIfPresent(SearchSortDirection.self, forKey: .displaySortDirection) ?? .ascending
        viewMode = try container.decodeIfPresent(CardCollectionViewMode.self, forKey: .viewMode) ?? .grid
        entryCount = try container.decodeIfPresent(Int.self, forKey: .entryCount) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(ruleset, forKey: .ruleset)
        try container.encodeIfPresent(descriptionRTFDData, forKey: .descriptionRTFDData)
        try container.encode(descriptionPlainText, forKey: .descriptionPlainText)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
        try container.encode(position, forKey: .position)
        try container.encode(showsDashboard, forKey: .showsDashboard)
        try container.encode(dashboardIncludesLands, forKey: .dashboardIncludesLands)
        try container.encodeIfPresent(displaySortMode, forKey: .displaySortMode)
        try container.encode(displaySortDirection, forKey: .displaySortDirection)
        try container.encode(viewMode, forKey: .viewMode)
        try container.encode(entryCount, forKey: .entryCount)
    }
}

public struct CardCollectionEntryRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var listID: String
    public var zone: CardCollectionZone
    public var categoryID: String?
    public var cardID: String
    public var position: Int
    public var quantity: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var card: CardRecord?

    public init(
        id: String,
        listID: String,
        zone: CardCollectionZone = .mainboard,
        categoryID: String? = nil,
        cardID: String,
        position: Int,
        quantity: Int = 1,
        createdAt: Date,
        updatedAt: Date? = nil,
        card: CardRecord? = nil
    ) {
        self.id = id
        self.listID = listID
        self.zone = zone
        self.categoryID = categoryID
        self.cardID = cardID
        self.position = position
        self.quantity = quantity
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.card = card
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case listID
        case zone
        case categoryID
        case cardID
        case position
        case quantity
        case createdAt
        case updatedAt
        case card
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        listID = try container.decode(String.self, forKey: .listID)
        zone = try container.decodeIfPresent(CardCollectionZone.self, forKey: .zone) ?? .mainboard
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
        cardID = try container.decode(String.self, forKey: .cardID)
        position = try container.decode(Int.self, forKey: .position)
        quantity = max(1, try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 1)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        card = try container.decodeIfPresent(CardRecord.self, forKey: .card)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(listID, forKey: .listID)
        try container.encode(zone, forKey: .zone)
        try container.encodeIfPresent(categoryID, forKey: .categoryID)
        try container.encode(cardID, forKey: .cardID)
        try container.encode(position, forKey: .position)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(card, forKey: .card)
    }
}

public struct CardCollectionCategoryRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var listID: String
    public var zone: CardCollectionZone
    public var name: String
    public var position: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var entryCount: Int

    public init(
        id: String,
        listID: String,
        zone: CardCollectionZone = .mainboard,
        name: String,
        position: Int,
        createdAt: Date,
        updatedAt: Date,
        entryCount: Int = 0
    ) {
        self.id = id
        self.listID = listID
        self.zone = zone
        self.name = name
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entryCount = entryCount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case listID
        case zone
        case name
        case position
        case createdAt
        case updatedAt
        case entryCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        listID = try container.decode(String.self, forKey: .listID)
        zone = try container.decodeIfPresent(CardCollectionZone.self, forKey: .zone) ?? .mainboard
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(Int.self, forKey: .position)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        entryCount = try container.decodeIfPresent(Int.self, forKey: .entryCount) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(listID, forKey: .listID)
        try container.encode(zone, forKey: .zone)
        try container.encode(name, forKey: .name)
        try container.encode(position, forKey: .position)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(entryCount, forKey: .entryCount)
    }
}

public struct CardCollectionLibrarySnapshot: Codable, Equatable, Sendable {
    public var lists: [CardCollectionRecord]
    public var categories: [CardCollectionCategoryRecord]
    public var entries: [CardCollectionEntryRecord]

    public init(
        lists: [CardCollectionRecord],
        categories: [CardCollectionCategoryRecord],
        entries: [CardCollectionEntryRecord]
    ) {
        self.lists = lists
        self.categories = categories
        self.entries = entries
    }
}

public enum CardCollectionDatabaseError: Error, Equatable, Sendable {
    case emptyName
    case listNotFound
    case categoryNotFound
    case entryNotFound
    case duplicateName
}
