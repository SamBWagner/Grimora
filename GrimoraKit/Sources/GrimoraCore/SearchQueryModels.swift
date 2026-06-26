import Foundation

public enum PrintingDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case preferred
    case all
    case art

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .preferred:
            "Preferred Printings"
        case .all:
            "All Printings"
        case .art:
            "Unique Art"
        }
    }
}

public struct CardSearchRequest: Equatable, Sendable {
    public var text: String
    public var sortMode: SortMode
    public var sortDirection: SearchSortDirection
    public var printingDisplayMode: PrintingDisplayMode
    public var offset: Int
    public var limit: Int

    public init(
        text: String,
        sortMode: SortMode = .name,
        sortDirection: SearchSortDirection = .ascending,
        printingDisplayMode: PrintingDisplayMode = .preferred,
        offset: Int = 0,
        limit: Int = 250
    ) {
        self.text = text
        self.sortMode = sortMode
        self.sortDirection = sortDirection
        self.printingDisplayMode = printingDisplayMode
        self.offset = max(0, offset)
        self.limit = limit
    }
}

public enum CardSearchResponse: Equatable, Sendable {
    case results([CardRecord], totalCount: Int)
    case unsupported(SearchQueryUnsupportedReason)
}

public enum CardCollectionEntrySearchResponse: Equatable, Sendable {
    case results([CardCollectionEntryRecord])
    case unsupported(SearchQueryUnsupportedReason)
}

/// One list whose cards matched a cross-list search, together with the matching entries.
public struct CrossListSearchMatch: Equatable, Sendable {
    public var listID: String
    public var entries: [CardCollectionEntryRecord]

    public init(listID: String, entries: [CardCollectionEntryRecord]) {
        self.listID = listID
        self.entries = entries
    }

    /// Number of matching entries (distinct rows) within the list.
    public var matchedEntryCount: Int {
        entries.count
    }

    /// Total quantity of matching cards within the list.
    public var matchedCardQuantity: Int {
        entries.reduce(0) { $0 + $1.quantity }
    }
}

public enum CrossListSearchResponse: Equatable, Sendable {
    case results([CrossListSearchMatch])
    case unsupported(SearchQueryUnsupportedReason)
}

public struct SearchQueryUnsupportedReason: Error, Equatable, Sendable {
    public var query: String
    public var token: String
    public var detail: String? = nil

    public init(query: String, token: String, detail: String? = nil) {
        self.query = query
        self.token = token
        self.detail = detail
    }

    public var message: String {
        detail ?? "“\(token)” is Scryfall syntax that Grimora does not support offline yet."
    }
}

public enum SearchSortDirection: String, Equatable, Codable, Sendable {
    case ascending
    case descending
}

public enum SearchPreference: String, CaseIterable, Equatable, Hashable, Sendable {
    case oldest
    case newest
    case promo
    case defaultPrint
    case atypical
    case notUniversesBeyond
    case usdLow
    case usdHigh
}

public struct SearchDisplayOptions: Equatable, Sendable {
    public var printingDisplayMode: PrintingDisplayMode?
    public var sortMode: SortMode?
    public var sortDirection: SearchSortDirection?
    public var preferences: Set<SearchPreference>

    public init(
        printingDisplayMode: PrintingDisplayMode? = nil,
        sortMode: SortMode? = nil,
        sortDirection: SearchSortDirection? = nil,
        preferences: Set<SearchPreference> = []
    ) {
        self.printingDisplayMode = printingDisplayMode
        self.sortMode = sortMode
        self.sortDirection = sortDirection
        self.preferences = preferences
    }
}

public struct SearchQueryPlan: Equatable, Sendable {
    public var whereSQL: String?
    public var bindings: [SearchQuery.SQLBinding]
    public var displayOptions: SearchDisplayOptions
    public var postFilters: [SearchQuery.PostFilter]

    public var hasPostFilters: Bool {
        !postFilters.isEmpty
    }
}
