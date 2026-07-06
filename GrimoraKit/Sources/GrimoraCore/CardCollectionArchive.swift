import Foundation

public enum CardCollectionArchiveError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
}

public struct CardCollectionArchiveDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var list: CardCollectionArchiveList
    public var categories: [CardCollectionArchiveCategory]
    public var entries: [CardCollectionArchiveEntry]

    public init(
        schemaVersion: Int = CardCollectionArchiveCoder.currentSchemaVersion,
        list: CardCollectionArchiveList,
        categories: [CardCollectionArchiveCategory],
        entries: [CardCollectionArchiveEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.list = list
        self.categories = categories
        self.entries = entries
    }
}

public struct CardCollectionArchiveList: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var ruleset: CardCollectionRuleset
    public var descriptionRTFDData: Data?
    public var descriptionPlainText: String
    public var createdAt: Date
    public var updatedAt: Date
    public var showsDashboard: Bool
    public var dashboardIncludesLands: Bool
    public var displaySortMode: SortMode?
    public var displaySortDirection: SearchSortDirection
    public var viewMode: CardCollectionViewMode

    public init(
        id: String,
        name: String,
        ruleset: CardCollectionRuleset = .none,
        descriptionRTFDData: Data? = nil,
        descriptionPlainText: String = "",
        createdAt: Date,
        updatedAt: Date,
        showsDashboard: Bool = false,
        dashboardIncludesLands: Bool = false,
        displaySortMode: SortMode? = nil,
        displaySortDirection: SearchSortDirection = .ascending,
        viewMode: CardCollectionViewMode = .grid
    ) {
        self.id = id
        self.name = name
        self.ruleset = ruleset
        self.descriptionRTFDData = descriptionRTFDData
        self.descriptionPlainText = descriptionPlainText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.showsDashboard = showsDashboard
        self.dashboardIncludesLands = dashboardIncludesLands
        self.displaySortMode = displaySortMode
        self.displaySortDirection = displaySortDirection
        self.viewMode = viewMode
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case ruleset
        case descriptionRTFDData
        case descriptionPlainText
        case createdAt
        case updatedAt
        case showsDashboard
        case dashboardIncludesLands
        case displaySortMode
        case displaySortDirection
        case viewMode
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
        showsDashboard = try container.decodeIfPresent(Bool.self, forKey: .showsDashboard) ?? false
        dashboardIncludesLands = try container.decodeIfPresent(Bool.self, forKey: .dashboardIncludesLands) ?? false
        displaySortMode = try container.decodeIfPresent(SortMode.self, forKey: .displaySortMode)
        displaySortDirection =
            try container.decodeIfPresent(SearchSortDirection.self, forKey: .displaySortDirection) ?? .ascending
        viewMode = try container.decodeIfPresent(CardCollectionViewMode.self, forKey: .viewMode) ?? .grid
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
        try container.encode(showsDashboard, forKey: .showsDashboard)
        try container.encode(dashboardIncludesLands, forKey: .dashboardIncludesLands)
        try container.encodeIfPresent(displaySortMode, forKey: .displaySortMode)
        try container.encode(displaySortDirection, forKey: .displaySortDirection)
        try container.encode(viewMode, forKey: .viewMode)
    }
}

public struct CardCollectionArchiveCategory: Codable, Equatable, Sendable {
    public var id: String
    public var zone: CardCollectionZone
    public var name: String
    public var position: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        zone: CardCollectionZone = .mainboard,
        name: String,
        position: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.zone = zone
        self.name = name
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case zone
        case name
        case position
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        zone = try container.decodeIfPresent(CardCollectionZone.self, forKey: .zone) ?? .mainboard
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(Int.self, forKey: .position)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(zone, forKey: .zone)
        try container.encode(name, forKey: .name)
        try container.encode(position, forKey: .position)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct CardCollectionArchiveEntry: Codable, Equatable, Sendable {
    public var id: String
    public var zone: CardCollectionZone
    public var categoryID: String?
    public var secondaryCategoryIDs: [String]
    public var cardID: String
    public var cardName: String?
    public var position: Int
    public var quantity: Int
    public var createdAt: Date

    public init(
        id: String,
        zone: CardCollectionZone = .mainboard,
        categoryID: String? = nil,
        secondaryCategoryIDs: [String] = [],
        cardID: String,
        cardName: String? = nil,
        position: Int,
        quantity: Int = 1,
        createdAt: Date
    ) {
        self.id = id
        self.zone = zone
        self.categoryID = categoryID
        self.secondaryCategoryIDs = secondaryCategoryIDs
        self.cardID = cardID
        self.cardName = cardName
        self.position = position
        self.quantity = max(1, quantity)
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case zone
        case categoryID
        case secondaryCategoryIDs
        case cardID
        case cardName
        case position
        case quantity
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        zone = try container.decodeIfPresent(CardCollectionZone.self, forKey: .zone) ?? .mainboard
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
        secondaryCategoryIDs = try container.decodeIfPresent([String].self, forKey: .secondaryCategoryIDs) ?? []
        cardID = try container.decode(String.self, forKey: .cardID)
        cardName = try container.decodeIfPresent(String.self, forKey: .cardName)
        position = try container.decode(Int.self, forKey: .position)
        quantity = max(1, try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 1)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(zone, forKey: .zone)
        try container.encodeIfPresent(categoryID, forKey: .categoryID)
        if !secondaryCategoryIDs.isEmpty {
            try container.encode(secondaryCategoryIDs, forKey: .secondaryCategoryIDs)
        }
        try container.encode(cardID, forKey: .cardID)
        try container.encodeIfPresent(cardName, forKey: .cardName)
        try container.encode(position, forKey: .position)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public enum CardCollectionArchiveCoder {
    public static let currentSchemaVersion = 2

    public static func document(
        list: CardCollectionRecord,
        entries: [CardCollectionEntryRecord],
        categories: [CardCollectionCategoryRecord]
    ) -> CardCollectionArchiveDocument {
        CardCollectionArchiveDocument(
            list: CardCollectionArchiveList(
                id: list.id,
                name: list.name,
                ruleset: list.ruleset,
                descriptionRTFDData: list.descriptionRTFDData,
                descriptionPlainText: list.descriptionPlainText,
                createdAt: list.createdAt,
                updatedAt: list.updatedAt,
                showsDashboard: list.showsDashboard,
                dashboardIncludesLands: list.dashboardIncludesLands,
                displaySortMode: list.displaySortMode,
                displaySortDirection: list.displaySortDirection,
                viewMode: list.viewMode
            ),
            categories: categories.map { category in
                CardCollectionArchiveCategory(
                    id: category.id,
                    zone: category.zone,
                    name: category.name,
                    position: category.position,
                    createdAt: category.createdAt,
                    updatedAt: category.updatedAt
                )
            },
            entries: entries.map { entry in
                CardCollectionArchiveEntry(
                    id: entry.id,
                    zone: entry.zone,
                    categoryID: entry.categoryID,
                    secondaryCategoryIDs: entry.secondaryCategoryIDs,
                    cardID: entry.cardID,
                    cardName: entry.card?.name,
                    position: entry.position,
                    quantity: entry.quantity,
                    createdAt: entry.createdAt
                )
            }
        )
    }

    public static func encode(_ document: CardCollectionArchiveDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> CardCollectionArchiveDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(CardCollectionArchiveDocument.self, from: data)
        guard (1...currentSchemaVersion).contains(document.schemaVersion) else {
            throw CardCollectionArchiveError.unsupportedVersion(document.schemaVersion)
        }
        return document
    }
}
