import GrimoraCore
import SwiftUI

struct CardCollectionsOverviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(GrimoraAppModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var measuredGridWidth: CGFloat = 0

    var gridZoom: GridZoomController
    var onCreateList: () -> Void
    var onSelectList: (CardCollectionRecord.ID) -> Void
    var onRenameList: (CardCollectionRecord) -> Void = { _ in }

    /// The list currently being dragged in the tile grid (nil when no drag is in flight). Drives
    /// the lifted-tile opacity and the drop-commit haptic.
    @State private var draggedListID: CardCollectionRecord.ID?
    @State private var reorderFeedbackTrigger = 0

    var body: some View {
        let items = model.filteredCardCollectionOverviewItems

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CardCollectionsOverviewHeader(
                    countText: listCountText,
                    palette: palette,
                    onCreateList: onCreateList
                )

                if let unsupportedMessage = model.dashboardSearchUnsupportedMessage {
                    CardCollectionsOverviewSearchNotice(message: unsupportedMessage, palette: palette)
                }

                if items.isEmpty {
                    CardCollectionsOverviewEmptyState(
                        hasActiveSearch: model.hasActiveDashboardSearch,
                        searchText: model.dashboardSearchText
                    )
                } else {
                    tilesGrid(items)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CollectionsGridWidthPreferenceKey.self,
                        value: proxy.size.width
                    )
                }
            }
            .onPreferenceChange(CollectionsGridWidthPreferenceKey.self) { width in
                measuredGridWidth = width
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .gridZoomPinch(gridZoom)
        .cloudSyncRefreshable(model)
        .onChange(of: draggedListID) { oldValue, newValue in
            // A drag just completed (something was being dragged, now nothing is): confirm the
            // reorder/pin with a success haptic.
            if oldValue != nil, newValue == nil {
                reorderFeedbackTrigger += 1
            }
        }
        .grimoraDropSuccessFeedback(trigger: reorderFeedbackTrigger)
        .background {
            GrimoraAppBackground(palette: palette)
        }
        .navigationTitle("Collections")
        .accessibilityIdentifier("card-lists-overview")
        #if os(macOS)
        .searchable(
            text: dashboardSearchTextBinding,
            placement: .toolbar,
            prompt: Text("Filter collections by card")
        )
        #elseif os(iOS)
        .searchable(
            text: dashboardSearchTextBinding,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Filter collections by card")
        )
        #elseif os(visionOS)
        .searchable(
            text: dashboardSearchTextBinding,
            prompt: Text("Filter collections by card")
        )
        #endif
    }

    private var dashboardSearchTextBinding: Binding<String> {
        Binding {
            model.dashboardSearchText
        } set: { newValue in
            model.setDashboardSearchDraft(newValue)
        }
    }

    // One continuous grid, already ordered system -> pinned -> unpinned. A pin glyph marks pinned
    // tiles (see `systemSymbol` below); long-press-drag reorders, and dropping a tile onto one of the
    // opposite pin-state flips it (pin/unpin) via `CardCollectionDropDelegate`.
    @ViewBuilder
    private func tilesGrid(_ items: [CardCollectionOverviewItem]) -> some View {
        // The drop delegate reorders within a section using that section's slice, so precompute the
        // user-pinned and unpinned records (system lists are excluded — they aren't reorderable).
        let pinnedUser = items.filter { $0.list.isPinned && !model.isSystemList($0.list) }.map(\.list)
        let unpinnedUser = items.filter { !$0.list.isPinned && !model.isSystemList($0.list) }.map(\.list)
        // Reordering a filtered subset is confusing, so drag is suppressed while a cross-list search
        // narrows the tiles. (Dropping cards onto a tile still works — that path ignores this.)
        let canReorder = !model.hasActiveDashboardSearch

        LazyVGrid(columns: columns, alignment: .leading, spacing: verticalSpacing) {
            ForEach(items) { item in
                CardCollectionOverviewTile(
                    item: item,
                    palette: palette,
                    isSystemList: model.isSystemList(item.list),
                    systemSymbol: model.systemSymbol(for: item.list)
                        ?? (item.list.isPinned ? "pin.fill" : nil),
                    matchPreview: matchPreview(for: item.list.id)
                ) {
                    model.selectCardCollection(id: item.list.id)
                    onSelectList(item.list.id)
                }
                .task(id: overviewImageTaskID(for: item)) {
                    guard let card = item.topCard else { return }
                    await model.cacheVisibleImages(for: card, quality: .artCrop)
                }
                // Tiles live in a LazyVGrid, so `.swipeActions` (List-only) doesn't
                // apply here — the context menu is the dashboard's action affordance
                // (long-press on iOS/visionOS, right-click on macOS), including explicit Pin/Unpin.
                .contextMenu {
                    CardCollectionOverviewActions(
                        model: model,
                        item: item,
                        onRenameList: onRenameList
                    )
                }
                // System lists (Favourites/Scanned) can't be dragged; dropping another list onto one
                // pins that list to the top so drag-to-pin works even with no user pins yet.
                .draggableList(
                    if: canReorder && !model.isSystemList(item.list),
                    draggedListID: $draggedListID,
                    listID: item.list.id
                )
                .onDrop(
                    of: CardCollectionDropDelegate.supportedContentTypes,
                    delegate: CardCollectionDropDelegate(
                        targetList: item.list,
                        targetIsPinned: item.list.isPinned,
                        lists: item.list.isPinned ? pinnedUser : unpinnedUser,
                        draggedListID: $draggedListID,
                        model: model,
                        pinsWhenDroppedOnSystemList: true
                    )
                )
                .opacity(draggedListID == item.list.id ? 0.35 : 1)
            }
        }
    }

    // Compact iPhone widths hold a single, full-width column in portrait at the default zoom (via
    // `baseTileMinimumWidth`).
    private var isCompactPhoneLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    // A lone `.adaptive` GridItem clamps each column to `tileMaximumWidth`, so when a single
    // column fits on a narrow phone the tile sits at its max width with dead space along its
    // trailing edge — and just above that width it forms a cramped, half-empty second column
    // (the system/user split leaves only a tile or two per section). Measuring the content
    // width and sizing the columns via the shared grid math instead lets iOS fill the lone
    // column edge-to-edge (`fillsSingleColumn`); the wider compact minimum keeps portrait
    // phones at one full-width column until the user pinches to zoom out or rotates to a wide
    // (landscape / iPad) layout that genuinely fits several tiles. Before the first
    // measurement lands we fall back to the adaptive item so the grid still renders.
    private var columns: [GridItem] {
        guard measuredGridWidth > 0 else {
            return [
                GridItem(
                    .adaptive(minimum: tileMinimumWidth, maximum: tileMaximumWidth),
                    spacing: horizontalSpacing,
                    alignment: .topLeading
                )
            ]
        }
        let columnWidth = adaptiveCardGridColumnWidth(
            availableWidth: measuredGridWidth,
            minimumColumnWidth: tileMinimumWidth,
            maximumColumnWidth: tileMaximumWidth,
            fillsSingleColumn: gridFillsSingleColumn,
            spacing: horizontalSpacing
        )
        let columnCount = max(
            1,
            Int((measuredGridWidth + horizontalSpacing) / (max(1, tileMinimumWidth) + horizontalSpacing))
        )
        return Array(
            repeating: GridItem(.fixed(columnWidth), spacing: horizontalSpacing, alignment: .topLeading),
            count: columnCount
        )
    }

    // Fill the single column edge-to-edge on iPhone/iPad (touch); macOS and visionOS keep
    // the clamp-to-max behaviour they had before. (On iPad a single column never occurs, so
    // this only takes effect on a phone.)
    private var gridFillsSingleColumn: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private var listCountText: String {
        let total = model.cardCollectionOverviewItems.count
        if model.hasActiveDashboardSearch, model.dashboardListMatchIDs != nil {
            let shown = model.filteredCardCollectionOverviewItems.count
            let noun = total == 1 ? "list" : "lists"
            return "\(shown.formatted()) of \(total.formatted()) \(noun)"
        }
        let noun = total == 1 ? "list" : "lists"
        return "\(total.formatted()) \(noun)"
    }

    private var horizontalPadding: CGFloat {
        #if os(visionOS)
        34
        #elseif os(macOS)
        30
        #else
        20
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(visionOS)
        32
        #else
        24
        #endif
    }

    private var horizontalSpacing: CGFloat {
        #if os(visionOS)
        38
        #elseif os(macOS)
        30
        #else
        20
        #endif
    }

    private var verticalSpacing: CGFloat {
        #if os(visionOS)
        40
        #else
        32
        #endif
    }

    // Pinch-to-zoom scales the tile footprint off the same shared GridZoomController
    // used by the card grids, so the user's zoom preference is consistent everywhere.
    private var tileMinimumWidth: CGFloat {
        baseTileMinimumWidth * gridZoom.scale
    }

    private var tileMaximumWidth: CGFloat {
        baseTileMaximumWidth * gridZoom.scale
    }

    private var baseTileMinimumWidth: CGFloat {
        #if os(visionOS)
        280
        #elseif os(macOS)
        260
        #else
        // A compact iPhone holds one full-width column in portrait at the default zoom: 200
        // keeps a second tile from squeezing in until ~440pt of content (wider than any phone
        // portrait), while pinch-to-zoom-out or a landscape/iPad width still forms several
        // columns. iPad (regular) keeps the denser 170 it used before.
        isCompactPhoneLayout ? 200 : 170
        #endif
    }

    private var baseTileMaximumWidth: CGFloat {
        #if os(visionOS)
        420
        #elseif os(macOS)
        380
        #else
        300
        #endif
    }

    // L6c: while a cross-list search is active, surface which cards matched on each
    // tile. The matched entries already carry their CardRecord, so this needs no extra
    // fetch; we cap the preview at the first few names to keep it cheap.
    private func matchPreview(for listID: CardCollectionRecord.ID) -> CardCollectionOverviewTile.MatchPreview? {
        guard model.hasActiveDashboardSearch,
              let match = model.dashboardListMatches[listID]
        else {
            return nil
        }
        let names = match.entries.prefix(3).compactMap { $0.card?.name }
        return CardCollectionOverviewTile.MatchPreview(count: match.matchedEntryCount, names: Array(names))
    }

    private func overviewImageTaskID(for item: CardCollectionOverviewItem) -> String {
        [
            item.list.id,
            item.topCard?.id ?? "empty",
            item.topCard?.listOverviewImagePath ?? "missing"
        ].joined(separator: ":")
    }
}

private struct CollectionsGridWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct CardCollectionOverviewTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var item: CardCollectionOverviewItem
    var palette: GrimoraPalette
    var isSystemList: Bool
    /// SF Symbol shown next to the name — star for Favourites, tray for Scanned, or `pin.fill` for a
    /// user-pinned collection; `nil` for an unpinned collection.
    var systemSymbol: String? = nil
    var matchPreview: MatchPreview? = nil
    var onSelect: () -> Void

    struct MatchPreview: Equatable {
        var count: Int
        var names: [String]
    }

    #if os(macOS) || os(visionOS)
    @State private var isHovered = false
    #endif
    @State private var openFeedbackTrigger = 0

    var body: some View {
        Button {
            openFeedbackTrigger += 1
            onSelect()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                CardCollectionOverviewTileArtwork(
                    item: item,
                    isSystemList: isSystemList,
                    palette: palette,
                    shadowOpacity: shadowOpacity,
                    shadowRadius: shadowRadius,
                    shadowYOffset: shadowYOffset
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let systemSymbol {
                            Image(systemName: systemSymbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.accent.color)
                                .accessibilityHidden(true)
                        }

                        Text(item.list.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(palette.primaryText.color)
                            .lineLimit(1)
                    }

                    Text(entryCountText)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText.color)
                        .lineLimit(1)

                    if let matchPreview {
                        Label(matchSummaryText(matchPreview), systemImage: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(palette.accent.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityHidden(true)
                            .accessibilityIdentifier("card-list-overview-tile-matches-\(item.list.name)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .scaleEffect(isHovered && !reduceMotion ? 1.05 : 1)
        .zIndex(isHovered ? 1 : 0)
        .animation(reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.hoverSpring, value: isHovered)
        .onHover { isHovered = $0 }
        #elseif os(visionOS)
        .scaleEffect(isHovered && !reduceMotion ? 1.025 : 1)
        .zIndex(isHovered ? 1 : 0)
        .animation(reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.hoverSpring, value: isHovered)
        .onHover { isHovered = $0 }
        #elseif os(iOS)
        .hoverEffect(.lift)
        #endif
        .grimoraOpenFeedback(trigger: openFeedbackTrigger)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("card-list-overview-tile-\(item.list.name)")
        .accessibilityLabel(item.list.name)
        .accessibilityValue(accessibilityValueText)
    }

    private func matchSummaryText(_ preview: MatchPreview) -> String {
        let countText = "\(preview.count) \(preview.count == 1 ? "match" : "matches")"
        guard !preview.names.isEmpty else {
            return countText
        }
        return "\(countText) · \(preview.names.joined(separator: ", "))"
    }

    private var accessibilityValueText: String {
        var parts = [entryCountText]
        if item.list.isPinned, !isSystemList {
            parts.append("Pinned")
        }
        if let matchPreview {
            parts.append(matchSummaryText(matchPreview))
        }
        return parts.joined(separator: ", ")
    }

    private var shadowOpacity: Double {
        #if os(macOS)
        isHovered ? 0.26 : 0.10
        #else
        0.12
        #endif
    }

    private var shadowRadius: CGFloat {
        #if os(macOS)
        isHovered ? 18 : 12
        #else
        12
        #endif
    }

    private var shadowYOffset: CGFloat {
        #if os(macOS)
        isHovered ? 10 : 6
        #else
        6
        #endif
    }

    private var entryCountText: String {
        let count = item.list.entryCount
        let noun = count == 1 ? "card" : "cards"
        return "\(count.formatted()) \(noun)"
    }
}
