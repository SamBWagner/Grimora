import GrimoraCore
import SwiftUI

struct ControlPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(GrimoraAppModel.self) private var model
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

            if let status = model.managedCatalogMigrationStatus {
                ManagedCatalogMigrationCallout(status: status, palette: palette)
            } else if let manifest = model.updateManifest {
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

private struct ManagedCatalogMigrationCallout: View {
    @Environment(GrimoraAppModel.self) private var model

    var status: ManagedCatalogMigrationStatus
    var palette: GrimoraPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)

            Text(message)
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)

            if case .failed = status {
                Button("Retry Catalog Download") {
                    Task { await model.stageManagedCatalogMigration() }
                }
                .buttonStyle(.bordered)
                .disabled(model.isManagedCatalogMigrationInProgress)
                .accessibilityIdentifier("retry-catalog-migration-button")
            }
        }
        .padding(10)
        .background(palette.cardSurface.color, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("catalog-migration-callout")
    }

    private var title: String {
        switch status {
        case .checking, .downloading, .validating:
            "Preparing Grimora 1.2"
        case .restartRequired:
            "Upgrade Ready"
        case .failed:
            "Upgrade Paused"
        }
    }

    private var symbol: String {
        switch status {
        case .checking, .downloading, .validating:
            "arrow.down.circle"
        case .restartRequired:
            "arrow.clockwise.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var message: String {
        switch status {
        case .checking:
            return "Checking for the managed card catalog. Your current library remains available."
        case .downloading(let completedBytes, let totalBytes):
            if let totalBytes, totalBytes > 0 {
                let completed = ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                return "Downloading \(completed) of \(total). You can keep using Grimora."
            }
            return "Downloading the managed catalog. You can keep using Grimora."
        case .validating:
            return "Checking the downloaded catalog before it can be activated."
        case .restartRequired:
            return "Quit and reopen Grimora to finish upgrading. Your lists remain available until then."
        case .failed(let message):
            return message
        }
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
    @Environment(GrimoraAppModel.self) private var model
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
