import GrimoraCore
import SwiftUI

struct CardListsOverviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: GrimoraAppModel
    @State private var createListFeedbackTrigger = 0

    var onCreateList: () -> Void
    var onSelectList: (CardListRecord.ID) -> Void

    var body: some View {
        let items = model.filteredCardListOverviewItems

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let unsupportedMessage = model.dashboardSearchUnsupportedMessage {
                    dashboardSearchNotice(unsupportedMessage)
                }

                if items.isEmpty {
                    overviewEmptyState
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: verticalSpacing) {
                        ForEach(items) { item in
                            CardListOverviewTile(
                                item: item,
                                palette: palette,
                                isSystemList: model.isProtectedFavouritesList(item.list)
                            ) {
                                model.selectCardList(id: item.list.id)
                                onSelectList(item.list.id)
                            }
                            .task(id: overviewImageTaskID(for: item)) {
                                guard let card = item.topCard else {
                                    return
                                }
                                await model.cacheVisibleImages(for: card, quality: .artCrop)
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
        .navigationTitle("Lists")
        .accessibilityIdentifier("card-lists-overview")
        #if os(macOS)
        .searchable(
            text: dashboardSearchTextBinding,
            placement: .toolbar,
            prompt: Text("Filter lists by card")
        )
        #elseif os(iOS)
        .searchable(
            text: dashboardSearchTextBinding,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Filter lists by card")
        )
        #elseif os(visionOS)
        .searchable(
            text: dashboardSearchTextBinding,
            prompt: Text("Filter lists by card")
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

    @ViewBuilder
    private var overviewEmptyState: some View {
        if model.hasActiveDashboardSearch {
            ContentUnavailableView.search(text: model.dashboardSearchText)
                .frame(maxWidth: .infinity, minHeight: 320)
                .accessibilityIdentifier("dashboard-search-no-matches")
        } else {
            ContentUnavailableView("No Lists", systemImage: "square.grid.2x2")
                .frame(maxWidth: .infinity, minHeight: 320)
                .accessibilityIdentifier("empty-lists-overview")
        }
    }

    private func dashboardSearchNotice(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(palette.secondaryText.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard-search-unsupported")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Lists")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(palette.primaryText.color)
                    .lineLimit(1)

                Text(listCountText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
                    .accessibilityIdentifier("card-lists-overview-count")
            }

            Spacer(minLength: 0)

            Button {
                createListFeedbackTrigger += 1
                onCreateList()
            } label: {
                Label("New List", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("create-list-button")
            .grimoraSelectionFeedback(trigger: createListFeedbackTrigger)
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
        let total = model.cardListOverviewItems.count
        if model.hasActiveDashboardSearch, model.dashboardListMatchIDs != nil {
            let shown = model.filteredCardListOverviewItems.count
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

    private func overviewImageTaskID(for item: CardListOverviewItem) -> String {
        [
            item.list.id,
            item.topCard?.id ?? "empty",
            item.topCard?.listOverviewImagePath ?? "missing"
        ].joined(separator: ":")
    }
}

private struct CardListOverviewTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var item: CardListOverviewItem
    var palette: GrimoraPalette
    var isSystemList: Bool
    var onSelect: () -> Void

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
                artwork

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
        .accessibilityValue(entryCountText)
    }

    private var artwork: some View {
        Color.clear
            .aspectRatio(Self.artworkAspectRatio, contentMode: .fit)
            .overlay {
                artworkContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.hairline.color, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowYOffset)
    }

    private static let artworkAspectRatio: CGFloat = 8.0 / 5.0

    @ViewBuilder
    private var artworkContent: some View {
        if let imagePath = item.topCard?.listOverviewImagePath {
            LocalCardImage(
                path: imagePath,
                cornerRadius: 8,
                contentMode: .fill
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.placeholderFill.color)

                Image(systemName: isSystemList ? "star" : "rectangle.stack")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(palette.secondaryText.color)
                    .accessibilityHidden(true)
            }
        }
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
