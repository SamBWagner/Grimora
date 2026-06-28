import CoreGraphics
import SwiftUI

struct AdaptiveCardGrid<Item, ID: Hashable, Content: View>: View {
    var items: [Item]
    var id: (Item) -> ID
    var landscapeItemIDs: Set<ID>
    var minimumColumnWidth: CGFloat
    var maximumColumnWidth: CGFloat
    var horizontalAlignment: AdaptiveCardGridHorizontalAlignment
    var fillsSingleColumn: Bool
    var horizontalSpacing: CGFloat = 18
    var verticalSpacing: CGFloat = 14
    let content: (Item) -> Content

    @State private var measuredWidth: CGFloat = 0

    init(
        items: [Item],
        id: @escaping (Item) -> ID,
        landscapeItemIDs: Set<ID>,
        minimumColumnWidth: CGFloat,
        maximumColumnWidth: CGFloat,
        horizontalAlignment: AdaptiveCardGridHorizontalAlignment = .leading,
        fillsSingleColumn: Bool = false,
        horizontalSpacing: CGFloat = 18,
        verticalSpacing: CGFloat = 14,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.id = id
        self.landscapeItemIDs = landscapeItemIDs
        self.minimumColumnWidth = minimumColumnWidth
        self.maximumColumnWidth = maximumColumnWidth
        self.horizontalAlignment = horizontalAlignment
        self.fillsSingleColumn = fillsSingleColumn
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content
    }

    var body: some View {
        // The LazyVStack is the *direct* content (not an overlay measured by a height-preference
        // feedback loop) so that, inside the enclosing ScrollView, it only realises the rows that
        // are actually visible. Width is measured via a background GeometryReader — the stack fills
        // `maxWidth: .infinity`, so this reports the available column width without forcing the
        // rows to lay out, keeping the stack lazy.
        LazyVStack(alignment: horizontalAlignment.stackAlignment, spacing: verticalSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: horizontalSpacing) {
                    ForEach(row, id: \.id) { entry in
                        content(entry.item)
                            .frame(width: entry.width, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: horizontalAlignment.frameAlignment)
            }
        }
        .frame(maxWidth: .infinity, alignment: horizontalAlignment.frameAlignment)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: AdaptiveCardGridWidthPreferenceKey.self,
                    value: sanitizedAdaptiveCardGridWidth(proxy.size.width)
                )
            }
        }
        .onPreferenceChange(AdaptiveCardGridWidthPreferenceKey.self) { width in
            measuredWidth = width
        }
    }

    private var rows: [[AdaptiveCardGridEntry<Item, ID>]] {
        adaptiveCardGridRows(
            items: items,
            id: id,
            landscapeItemIDs: landscapeItemIDs,
            availableWidth: measuredWidth,
            minimumColumnWidth: minimumColumnWidth,
            maximumColumnWidth: maximumColumnWidth,
            fillsSingleColumn: fillsSingleColumn,
            spacing: horizontalSpacing
        )
    }
}

enum AdaptiveCardGridHorizontalAlignment {
    case leading
    case center

    var stackAlignment: HorizontalAlignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading:
            return .topLeading
        case .center:
            return .top
        }
    }
}

struct AdaptiveCardGridEntry<Item, ID: Hashable> {
    var id: ID
    var item: Item
    var width: CGFloat
}

private struct AdaptiveCardGridPendingEntry<Item, ID: Hashable> {
    var id: ID
    var item: Item
    var widthWeight: CGFloat
}

func adaptiveCardGridRows<Item, ID: Hashable>(
    items: [Item],
    id: (Item) -> ID,
    landscapeItemIDs: Set<ID>,
    availableWidth: CGFloat,
    minimumColumnWidth: CGFloat,
    maximumColumnWidth: CGFloat,
    fillsSingleColumn: Bool = false,
    spacing: CGFloat
) -> [[AdaptiveCardGridEntry<Item, ID>]] {
    guard !items.isEmpty else {
        return []
    }

    let contentWidth = sanitizedAdaptiveCardGridWidth(availableWidth)
    let portraitWidth = adaptiveCardGridColumnWidth(
        availableWidth: contentWidth,
        minimumColumnWidth: minimumColumnWidth,
        maximumColumnWidth: maximumColumnWidth,
        fillsSingleColumn: fillsSingleColumn,
        spacing: spacing
    )
    let minimumUnitWidth = max(1, minimumColumnWidth)
    let resolvedSpacing = max(0, spacing)
    var rows: [[AdaptiveCardGridEntry<Item, ID>]] = []
    var currentRow: [AdaptiveCardGridPendingEntry<Item, ID>] = []
    var currentRowMinimumWidth: CGFloat = 0

    func resolvedRow(
        from pendingEntries: [AdaptiveCardGridPendingEntry<Item, ID>],
        fillsAvailableWidth: Bool
    ) -> [AdaptiveCardGridEntry<Item, ID>] {
        adaptiveCardGridResolvedRow(
            pendingEntries,
            availableWidth: contentWidth,
            preferredUnitWidth: portraitWidth,
            minimumUnitWidth: minimumUnitWidth,
            spacing: resolvedSpacing,
            fillsAvailableWidth: fillsAvailableWidth
        )
    }

    for item in items {
        let itemID = id(item)
        let widthWeight = adaptiveCardGridItemWidthWeight(
            usesLandscapeLayout: landscapeItemIDs.contains(itemID)
        )
        let minimumItemWidth = min(contentWidth, minimumUnitWidth * widthWeight)
        let entry = AdaptiveCardGridPendingEntry(
            id: itemID,
            item: item,
            widthWeight: widthWeight
        )
        let spacingBeforeItem = currentRow.isEmpty ? 0 : resolvedSpacing
        let proposedRowWidth = currentRowMinimumWidth + spacingBeforeItem + minimumItemWidth

        if !currentRow.isEmpty, proposedRowWidth > contentWidth {
            rows.append(resolvedRow(from: currentRow, fillsAvailableWidth: true))
            currentRow = [entry]
            currentRowMinimumWidth = minimumItemWidth
        } else {
            currentRow.append(entry)
            currentRowMinimumWidth = proposedRowWidth
        }
    }

    if !currentRow.isEmpty {
        rows.append(resolvedRow(from: currentRow, fillsAvailableWidth: false))
    }

    return rows
}

private func adaptiveCardGridResolvedRow<Item, ID: Hashable>(
    _ pendingEntries: [AdaptiveCardGridPendingEntry<Item, ID>],
    availableWidth: CGFloat,
    preferredUnitWidth: CGFloat,
    minimumUnitWidth: CGFloat,
    spacing: CGFloat,
    fillsAvailableWidth: Bool
) -> [AdaptiveCardGridEntry<Item, ID>] {
    guard !pendingEntries.isEmpty else {
        return []
    }

    let resolvedSpacing = max(0, spacing)
    let availableItemWidth = max(
        1,
        availableWidth - (CGFloat(max(0, pendingEntries.count - 1)) * resolvedSpacing)
    )
    let totalWeight = pendingEntries.reduce(CGFloat(0)) { result, entry in
        result + max(0.0001, entry.widthWeight)
    }
    let fittingUnitWidth = availableItemWidth / max(0.0001, totalWeight)
    let desiredUnitWidth = fillsAvailableWidth ? fittingUnitWidth : preferredUnitWidth
    let resolvedUnitWidth = min(
        max(1, fittingUnitWidth),
        max(minimumUnitWidth, desiredUnitWidth)
    )

    return pendingEntries.map { entry in
        AdaptiveCardGridEntry(
            id: entry.id,
            item: entry.item,
            width: max(1, resolvedUnitWidth * max(0.0001, entry.widthWeight))
        )
    }
}

func adaptiveCardGridColumnWidth(
    availableWidth: CGFloat,
    minimumColumnWidth: CGFloat,
    maximumColumnWidth: CGFloat,
    fillsSingleColumn: Bool = false,
    spacing: CGFloat
) -> CGFloat {
    let fallbackWidth = max(1, minimumColumnWidth)
    guard availableWidth.isFinite, availableWidth > 0 else {
        return fallbackWidth
    }

    let minimumWidth = fallbackWidth
    let maximumWidth = max(minimumWidth, maximumColumnWidth)
    let resolvedSpacing = max(0, spacing)
    let columnCount = max(Int((availableWidth + resolvedSpacing) / (minimumWidth + resolvedSpacing)), 1)
    let rawWidth = (availableWidth - (CGFloat(columnCount - 1) * resolvedSpacing)) / CGFloat(columnCount)

    if fillsSingleColumn, columnCount == 1 {
        return max(1, rawWidth)
    }

    return min(max(rawWidth, minimumWidth), maximumWidth)
}

func adaptiveCardGridItemWidth(
    portraitWidth: CGFloat,
    availableWidth: CGFloat,
    usesLandscapeLayout: Bool
) -> CGFloat {
    guard usesLandscapeLayout else {
        return portraitWidth
    }

    let landscapeWidth = cardArtworkReservedLayoutWidth(
        baseWidth: portraitWidth,
        aspectRatio: cardArtworkAspectRatio,
        hasVisualOverflow: true
    )
    return min(max(portraitWidth, landscapeWidth), max(1, availableWidth))
}

private func adaptiveCardGridItemWidthWeight(
    usesLandscapeLayout: Bool,
    aspectRatio: CGFloat = cardArtworkAspectRatio
) -> CGFloat {
    guard usesLandscapeLayout,
          aspectRatio.isFinite,
          aspectRatio > 0
    else {
        return 1
    }

    return 1 / aspectRatio
}

private struct AdaptiveCardGridWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private func sanitizedAdaptiveCardGridWidth(_ width: CGFloat) -> CGFloat {
    guard width.isFinite, width > 0 else {
        return 0
    }

    return width
}
