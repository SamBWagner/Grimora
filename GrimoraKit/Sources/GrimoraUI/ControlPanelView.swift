import GrimoraCore
import SwiftUI

struct ControlPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: GrimoraAppModel
    @State private var draggedListID: CardListRecord.ID?
    @State private var navigationFeedbackTrigger = 0
    @State private var createListFeedbackTrigger = 0

    var onCreateList: () -> Void
    var onRenameList: (CardListRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GrimoraBrandHeaderView(palette: palette)

            SidebarSection("Actions", palette: palette) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        navigationFeedbackTrigger += 1
                        model.selectSearch()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SidebarNavigationButtonStyle(isSelected: model.sidebarSelection == .search, palette: palette))
                    .accessibilityIdentifier("search-sidebar-button")

                    Button {
                        navigationFeedbackTrigger += 1
                        model.selectListsOverview()
                    } label: {
                        Label("Lists", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(
                        SidebarNavigationButtonStyle(
                            isSelected: model.sidebarSelection == .listsOverview,
                            palette: palette
                        )
                    )
                    .accessibilityIdentifier("lists-overview-sidebar-button")

                    #if !os(macOS)
                    LibraryMaintenanceMenu()
                        .buttonStyle(SidebarNavigationButtonStyle(isSelected: false, palette: palette))
                    #endif
                }
            }

            SidebarDivider(palette: palette)

            if let favourites = model.favouritesList {
                SidebarSection("Favourites", palette: palette) {
                    CardListsSidebarContent(
                        lists: [favourites],
                        isPinnedSection: false,
                        emptyTitle: "No Favourites",
                        emptyAccessibilityIdentifier: "empty-favourites-sidebar",
                        palette: palette,
                        draggedListID: $draggedListID,
                        onRenameList: onRenameList
                    )
                }

                SidebarDivider(palette: palette)
            }

            SidebarSection("Pinned Lists", palette: palette) {
                CardListsSidebarContent(
                    lists: model.pinnedCardLists,
                    isPinnedSection: true,
                    emptyTitle: "No Pinned Lists",
                    emptyAccessibilityIdentifier: "empty-pinned-lists-sidebar",
                    palette: palette,
                    draggedListID: $draggedListID,
                    onRenameList: onRenameList
                )
            }

            SidebarDivider(palette: palette)

            SidebarSection("Lists", palette: palette) {
                CardListsSidebarContent(
                    lists: model.unpinnedCardLists,
                    isPinnedSection: false,
                    emptyTitle: model.pinnedCardLists.isEmpty ? "No Lists" : "All Lists Pinned",
                    emptyAccessibilityIdentifier: "empty-lists-sidebar",
                    palette: palette,
                    draggedListID: $draggedListID,
                    onRenameList: onRenameList
                )
            }

            if let manifest = model.updateManifest {
                UpdateCalloutView(manifest: manifest, palette: palette)
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .accessibilityIdentifier("status-message")
            }

            Spacer(minLength: 0)

            Button {
                createListFeedbackTrigger += 1
                onCreateList()
            } label: {
                Label("New List", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SidebarNavigationButtonStyle(isSelected: model.sidebarSelection == .newList, palette: palette))
            .accessibilityIdentifier("create-list-button")
            .grimoraSelectionFeedback(trigger: createListFeedbackTrigger)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.sidebarBackground.color)
        .grimoraSelectionFeedback(trigger: navigationFeedbackTrigger)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}

private struct GrimoraBrandHeaderView: View {
    var palette: GrimoraPalette

    var body: some View {
        HStack(spacing: 8) {
            GrimoraLogoView(size: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text("Grimora")
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("grimora-brand-header")
    }
}

private struct SidebarSection<Content: View>: View {
    var title: String
    var palette: GrimoraPalette
    var content: () -> Content

    init(
        _ title: String,
        palette: GrimoraPalette,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.palette = palette
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText.color)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarDivider: View {
    var palette: GrimoraPalette

    var body: some View {
        Rectangle()
            .fill(palette.hairline.color.opacity(0.6))
            .frame(height: 1)
            .padding(.vertical, 2)
    }
}

private struct UpdateCalloutView: View {
    @EnvironmentObject private var model: GrimoraAppModel
    var manifest: BulkDataManifest
    var palette: GrimoraPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(manifest.name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)
            Text(ByteCountFormatter.string(fromByteCount: Int64(manifest.size), countStyle: .file))
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
            Button {
                Task { await model.importAvailableUpdate() }
            } label: {
                Text("Import")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("import-update-button")
            .disabled(model.isWorking)

            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("import-progress")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.cardSurface.color.opacity(0.82))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
