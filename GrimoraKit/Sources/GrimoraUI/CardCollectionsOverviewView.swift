import GrimoraCore
import SwiftUI

struct CardCollectionsOverviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(GrimoraAppModel.self) private var model

    var onCreateList: () -> Void
    var onSelectList: (CardCollectionRecord.ID) -> Void
    var onRenameList: (CardCollectionRecord) -> Void = { _ in }

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
                    LazyVGrid(columns: columns, alignment: .leading, spacing: verticalSpacing) {
                        ForEach(items) { item in
                            CardCollectionOverviewTile(
                                item: item,
                                palette: palette,
                                isSystemList: model.isProtectedFavouritesList(item.list),
                                matchPreview: matchPreview(for: item.list.id)
                            ) {
                                model.selectCardCollection(id: item.list.id)
                                onSelectList(item.list.id)
                            }
                            .task(id: overviewImageTaskID(for: item)) {
                                guard let card = item.topCard else {
                                    return
                                }
                                await model.cacheVisibleImages(for: card, quality: .artCrop)
                            }
                            // Tiles live in a LazyVGrid, so `.swipeActions` (List-only) doesn't
                            // apply here — the context menu is the dashboard's action affordance
                            // (long-press on iOS/visionOS, right-click on macOS).
                            .contextMenu {
                                CardCollectionOverviewActions(
                                    model: model,
                                    item: item,
                                    onRenameList: onRenameList
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: tileMinimumWidth, maximum: tileMaximumWidth),
                spacing: horizontalSpacing,
                alignment: .topLeading
            )
        ]
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

    private var tileMinimumWidth: CGFloat {
        #if os(visionOS)
        280
        #elseif os(macOS)
        260
        #else
        170
        #endif
    }

    private var tileMaximumWidth: CGFloat {
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

private struct CardCollectionOverviewTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var item: CardCollectionOverviewItem
    var palette: GrimoraPalette
    var isSystemList: Bool
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
                        if isSystemList {
                            Image(systemName: "star.fill")
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
        guard let matchPreview else {
            return entryCountText
        }
        return "\(entryCountText), \(matchSummaryText(matchPreview))"
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
