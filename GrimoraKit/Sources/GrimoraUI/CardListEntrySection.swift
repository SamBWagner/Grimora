import Foundation
import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct CardListEntrySection: Equatable, Identifiable {
    static let uncategorizedID = "uncategorized"

    var id: String
    var zone: CardListZone
    var title: String
    var category: CardListCategoryRecord?
    var entries: [CardListEntryRecord]
    var categoryIndex: Int?
    var categoryCount: Int

    var entryCountText: String {
        let count = entries.reduce(0) { $0 + $1.quantity }
        let noun = count == 1 ? "card" : "cards"
        return "\(count.formatted()) \(noun)"
    }
}

enum CardListEntrySectionBuilder {
    static func sections(
        entries: [CardListEntryRecord],
        categories: [CardListCategoryRecord],
        ruleset: CardListRuleset = .none,
        displaySortMode: SortMode? = nil,
        displaySortDirection: SearchSortDirection = .ascending
    ) -> [CardListEntrySection] {
        var sections: [CardListEntrySection] = []

        for zone in ruleset.allowedZones {
            let zoneEntries = entries.filter { $0.zone == zone }
            let zoneCategories = categories.filter { $0.zone == zone }
            guard !zoneEntries.isEmpty || !zoneCategories.isEmpty || zone == .mainboard else {
                continue
            }

            var uncategorizedEntries: [CardListEntryRecord] = []
            var entriesByCategoryID: [CardListCategoryRecord.ID: [CardListEntryRecord]] = [:]

            for entry in zoneEntries {
                if let categoryID = entry.categoryID {
                    entriesByCategoryID[categoryID, default: []].append(entry)
                } else {
                    uncategorizedEntries.append(entry)
                }
            }

            if !uncategorizedEntries.isEmpty || zoneCategories.isEmpty {
                sections.append(
                    CardListEntrySection(
                        id: "\(zone.rawValue)-\(CardListEntrySection.uncategorizedID)",
                        zone: zone,
                        title: title(for: zone, categoryName: "Uncategorized"),
                        category: nil,
                        entries: sortedEntries(
                            uncategorizedEntries,
                            mode: displaySortMode,
                            direction: displaySortDirection
                        ),
                        categoryIndex: nil,
                        categoryCount: zoneCategories.count
                    )
                )
            }

            for (index, category) in zoneCategories.enumerated() {
                sections.append(
                    CardListEntrySection(
                        id: category.id,
                        zone: zone,
                        title: title(for: zone, categoryName: category.name),
                        category: category,
                        entries: sortedEntries(
                            entriesByCategoryID[category.id, default: []],
                            mode: displaySortMode,
                            direction: displaySortDirection
                        ),
                        categoryIndex: index,
                        categoryCount: zoneCategories.count
                    )
                )
            }
        }

        return sections
    }

    private static func title(for zone: CardListZone, categoryName: String) -> String {
        zone == .mainboard ? categoryName : "\(zone.title) - \(categoryName)"
    }

    private static func sortedEntries(
        _ entries: [CardListEntryRecord],
        mode: SortMode?,
        direction: SearchSortDirection
    ) -> [CardListEntryRecord] {
        guard let mode else {
            return entries
        }

        return entries.enumerated()
            .sorted { lhs, rhs in
                let comparison = compare(lhs.element, rhs.element, mode: mode, direction: direction)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func compare(
        _ lhs: CardListEntryRecord,
        _ rhs: CardListEntryRecord,
        mode: SortMode,
        direction: SearchSortDirection
    ) -> ComparisonResult {
        guard let lhsCard = lhs.card else {
            return rhs.card == nil ? storedOrderComparison(lhs, rhs) : .orderedDescending
        }
        guard let rhsCard = rhs.card else {
            return .orderedAscending
        }

        let primary: ComparisonResult
        switch mode {
        case .name:
            primary = firstNonEqual([
                stringComparison(nameKey(lhsCard), nameKey(rhsCard), direction: direction),
                optionalStringComparison(lhsCard.releasedAt, rhsCard.releasedAt, direction: .descending),
                stringComparison(lhsCard.setCode, rhsCard.setCode, direction: .ascending),
                optionalIntComparison(
                    lhsCard.collectorNumberNumber,
                    rhsCard.collectorNumberNumber,
                    direction: .ascending
                ),
                stringComparison(lhsCard.collectorNumber, rhsCard.collectorNumber, direction: .ascending),
            ])
        case .releaseDate:
            primary = firstNonEqual([
                optionalStringComparison(
                    lhsCard.releasedAt,
                    rhsCard.releasedAt,
                    direction: direction == .ascending ? .descending : .ascending
                ),
                nameComparison(lhsCard, rhsCard),
            ])
        case .setNumber:
            primary = firstNonEqual([
                stringComparison(lhsCard.setCode, rhsCard.setCode, direction: direction),
                optionalIntComparison(
                    lhsCard.collectorNumberNumber,
                    rhsCard.collectorNumberNumber,
                    direction: direction
                ),
                stringComparison(lhsCard.collectorNumber, rhsCard.collectorNumber, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .rarity:
            primary = firstNonEqual([
                optionalIntComparison(lhsCard.rarityRank, rhsCard.rarityRank, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .color:
            primary = firstNonEqual([
                intComparison(lhsCard.colorSortKey, rhsCard.colorSortKey, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .priceUSD:
            primary = firstNonEqual([
                optionalDoubleComparison(lhsCard.priceUSD, rhsCard.priceUSD, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .priceTIX:
            primary = firstNonEqual([
                optionalDoubleComparison(lhsCard.priceTIX, rhsCard.priceTIX, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .priceEUR:
            primary = firstNonEqual([
                optionalDoubleComparison(lhsCard.priceEUR, rhsCard.priceEUR, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .manaValue:
            primary = firstNonEqual([
                optionalDoubleComparison(lhsCard.manaValue, rhsCard.manaValue, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .power:
            primary = firstNonEqual([
                optionalDoubleComparison(lhsCard.powerValue, rhsCard.powerValue, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .toughness:
            primary = firstNonEqual([
                optionalDoubleComparison(lhsCard.toughnessValue, rhsCard.toughnessValue, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .artistName:
            primary = firstNonEqual([
                optionalStringComparison(lhsCard.artist.map(sortKey), rhsCard.artist.map(sortKey), direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .edhrecRank:
            primary = firstNonEqual([
                optionalIntComparison(lhsCard.edhrecRank, rhsCard.edhrecRank, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        case .pennyRank:
            primary = firstNonEqual([
                optionalIntComparison(lhsCard.pennyRank, rhsCard.pennyRank, direction: direction),
                nameComparison(lhsCard, rhsCard),
            ])
        }

        guard primary == .orderedSame else {
            return primary
        }
        return storedOrderComparison(lhs, rhs)
    }

    private static func firstNonEqual(_ comparisons: [ComparisonResult]) -> ComparisonResult {
        comparisons.first { $0 != .orderedSame } ?? .orderedSame
    }

    private static func nameComparison(_ lhs: CardRecord, _ rhs: CardRecord) -> ComparisonResult {
        stringComparison(nameKey(lhs), nameKey(rhs), direction: .ascending)
    }

    private static func nameKey(_ card: CardRecord) -> String {
        card.displayNameKey.isEmpty ? sortKey(card.name) : sortKey(card.displayNameKey)
    }

    private static func storedOrderComparison(
        _ lhs: CardListEntryRecord,
        _ rhs: CardListEntryRecord
    ) -> ComparisonResult {
        firstNonEqual([
            intComparison(lhs.position, rhs.position, direction: .ascending),
            dateComparison(lhs.createdAt, rhs.createdAt, direction: .ascending),
            stringComparison(lhs.id, rhs.id, direction: .ascending),
        ])
    }

    private static func optionalStringComparison(
        _ lhs: String?,
        _ rhs: String?,
        direction: SearchSortDirection
    ) -> ComparisonResult {
        optionalComparison(lhs, rhs) { lhs, rhs in
            stringComparison(lhs, rhs, direction: direction)
        }
    }

    private static func optionalIntComparison(
        _ lhs: Int?,
        _ rhs: Int?,
        direction: SearchSortDirection
    ) -> ComparisonResult {
        optionalComparison(lhs, rhs) { lhs, rhs in
            intComparison(lhs, rhs, direction: direction)
        }
    }

    private static func optionalDoubleComparison(
        _ lhs: Double?,
        _ rhs: Double?,
        direction: SearchSortDirection
    ) -> ComparisonResult {
        optionalComparison(lhs, rhs) { lhs, rhs in
            valueComparison(lhs, rhs, direction: direction)
        }
    }

    private static func optionalComparison<Value>(
        _ lhs: Value?,
        _ rhs: Value?,
        compare: (Value, Value) -> ComparisonResult
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.none, .none):
            return .orderedSame
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        case (.some(let lhs), .some(let rhs)):
            return compare(lhs, rhs)
        }
    }

    private static func stringComparison(
        _ lhs: String,
        _ rhs: String,
        direction: SearchSortDirection
    ) -> ComparisonResult {
        directedComparison(sortKey(lhs).compare(sortKey(rhs)), direction: direction)
    }

    private static func intComparison(
        _ lhs: Int,
        _ rhs: Int,
        direction: SearchSortDirection
    ) -> ComparisonResult {
        valueComparison(lhs, rhs, direction: direction)
    }

    private static func dateComparison(
        _ lhs: Date,
        _ rhs: Date,
        direction: SearchSortDirection
    ) -> ComparisonResult {
        valueComparison(lhs, rhs, direction: direction)
    }

    private static func valueComparison<Value: Comparable>(
        _ lhs: Value,
        _ rhs: Value,
        direction: SearchSortDirection
    ) -> ComparisonResult {
        let comparison: ComparisonResult
        if lhs < rhs {
            comparison = .orderedAscending
        } else if lhs > rhs {
            comparison = .orderedDescending
        } else {
            comparison = .orderedSame
        }
        return directedComparison(comparison, direction: direction)
    }

    private static func directedComparison(
        _ comparison: ComparisonResult,
        direction: SearchSortDirection
    ) -> ComparisonResult {
        guard direction == .descending else {
            return comparison
        }

        switch comparison {
        case .orderedAscending:
            return .orderedDescending
        case .orderedDescending:
            return .orderedAscending
        case .orderedSame:
            return .orderedSame
        }
    }

    private static func sortKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
