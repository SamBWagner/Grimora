import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

enum CardCollectionsBrowserRoute: Hashable {
    case overview
    case newList
    case list(CardCollectionRecord.ID)
}

struct CardCollectionsBrowserView: View {
    @Environment(GrimoraAppModel.self) private var model
    var gridZoom: GridZoomController

    var onCreateList: () -> Void
    var onCancelCreateList: () -> Void = {}
    var onCompleteCreateList: () -> Void = {}
    var onRenameList: (CardCollectionRecord) -> Void
    var onSelectCard: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: ([CardRecord.ID]) -> Void = { _ in }
    var onCreateCategory: (CardCollectionRecord) -> Void = { _ in }
    var onRenameCategory: (CardCollectionCategoryRecord) -> Void = { _ in }

    var body: some View {
        CardCollectionsOverviewView(
            onCreateList: onCreateList,
            onSelectList: { _ in },
            onRenameList: onRenameList
        )
        .navigationDestination(for: CardCollectionsBrowserRoute.self) { route in
            switch route {
            case .overview:
                CardCollectionsOverviewView(
                    onCreateList: onCreateList,
                    onSelectList: { _ in },
                    onRenameList: onRenameList
                )
            case .newList:
                CardCollectionCreateDestinationView(
                    onCancel: onCancelCreateList,
                    onComplete: onCompleteCreateList
                )
                .navigationTitle("New Collection")
            case .list(let listID):
                CardCollectionDetailView(
                    gridZoom: gridZoom,
                    onSelect: onSelectCard,
                    onCreateListForCard: onCreateListForCard,
                    onCreateListForCards: onCreateListForCards,
                    onRenameList: onRenameList,
                    onCreateCategory: onCreateCategory,
                    onRenameCategory: onRenameCategory
                )
                .cardCollectionBrowserDetailNavigationTitle(model.cardCollections.first { $0.id == listID }?.name ?? "Collection")
                .onAppear {
                    model.selectCardCollection(id: listID)
                }
                .onDisappear {
                    // Popping back to the dashboard leaves `selectedCollectionID` set, so
                    // re-tapping the tile we just left wouldn't change it and the
                    // navigation-driving `onChange(of: selectedCollectionID)` never fires —
                    // the tile looks dead. Clearing the selection on the way out keeps
                    // every tile tappable. Skip when the selection already moved on
                    // (e.g. switching tabs or jumping straight to another list) so we
                    // don't clobber that destination.
                    if model.sidebarSelection == .list(listID) {
                        model.selectListsOverview()
                    }
                }
            }
        }
    }

}

struct CardCollectionsBrowserSidebarView: View {
    @Environment(GrimoraAppModel.self) private var model

    var onCreateList: () -> Void
    var onRenameList: (CardCollectionRecord) -> Void

    var body: some View {
        List(selection: sidebarRouteSelection) {
            Section {
                NavigationLink(value: CardCollectionsBrowserRoute.overview) {
                    Label("Collections", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("card-lists-overview-sidebar-button")

                NavigationLink(value: CardCollectionsBrowserRoute.newList) {
                    Label("New Collection", systemImage: "plus")
                }
                .accessibilityIdentifier("create-list-button")
            }

            Section("Collections") {
                if model.cardCollections.isEmpty {
                    ContentUnavailableView("No Collections", systemImage: "list.bullet.rectangle")
                        .accessibilityIdentifier("empty-lists-browser")
                } else {
                    ForEach(model.cardCollections) { list in
                        NavigationLink(value: CardCollectionsBrowserRoute.list(list.id)) {
                            CardCollectionBrowserRowLabel(list: list)
                        }
                        .accessibilityIdentifier("card-list-row-\(list.name)")
                        .accessibilityValue(entryCountText(for: list))
                        .cardCollectionBrowserRowActions(for: list, onRenameList: onRenameList)
                    }
                }
            }
        }
        .accessibilityIdentifier("card-lists-split-sidebar")
    }

    private var sidebarRouteSelection: Binding<CardCollectionsBrowserRoute?> {
        Binding {
            switch model.sidebarSelection {
            case .listsOverview:
                return .overview
            case .newList:
                return .newList
            case .list(let id):
                return .list(id)
            case .search:
                return .overview
            }
        } set: { route in
            switch route {
            case .overview:
                model.selectListsOverview()
            case .newList:
                onCreateList()
            case .list(let id):
                model.selectCardCollection(id: id)
            case nil:
                model.selectListsOverview()
            }
        }
    }
}

private struct CardCollectionBrowserRowLabel: View {
    @Environment(GrimoraAppModel.self) private var model

    var list: CardCollectionRecord

    var body: some View {
        HStack(spacing: 10) {
            if model.isProtectedFavouritesList(list) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.secondary)
            } else if list.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .lineLimit(1)
                Text(entryCountText(for: list))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CardCollectionBrowserRowActions: ViewModifier {
    @Environment(GrimoraAppModel.self) private var model

    var list: CardCollectionRecord
    var onRenameList: (CardCollectionRecord) -> Void

    func body(content: Content) -> some View {
        let isProtected = model.isProtectedFavouritesList(list)

        content
            .swipeActions {
                if !isProtected {
                    Button {
                        model.setCardCollectionPinned(id: list.id, isPinned: !list.isPinned)
                    } label: {
                        Text(list.isPinned ? "Unpin" : "Pin")
                    }
                    .tint(.orange)

                    Button {
                        onRenameList(list)
                    } label: {
                        Text("Rename")
                    }
                    .tint(.blue)

                    Button(role: .destructive) {
                        model.deleteCardCollection(id: list.id)
                    } label: {
                        Text("Delete")
                    }
                }
            }
            .contextMenu {
                if !isProtected {
                    Button {
                        model.setCardCollectionPinned(id: list.id, isPinned: !list.isPinned)
                    } label: {
                        Text(list.isPinned ? "Unpin" : "Pin")
                    }

                    Button {
                        onRenameList(list)
                    } label: {
                        Text("Rename")
                    }

                    Button(role: .destructive) {
                        model.deleteCardCollection(id: list.id)
                    } label: {
                        Text("Delete")
                    }
                }
            }
            #if os(macOS) || os(iOS) || os(visionOS)
            .cardDropTarget { cardIDs in
                model.addCards(cardIDs, toListID: list.id)
            }
            #endif
    }
}

private extension View {
    func cardCollectionBrowserRowActions(
        for list: CardCollectionRecord,
        onRenameList: @escaping (CardCollectionRecord) -> Void
    ) -> some View {
        modifier(CardCollectionBrowserRowActions(list: list, onRenameList: onRenameList))
    }
}

private func entryCountText(for list: CardCollectionRecord) -> String {
    let noun = list.entryCount == 1 ? "card" : "cards"
    return "\(list.entryCount.formatted()) \(noun)"
}

private extension View {
    @ViewBuilder
    func cardCollectionBrowserDetailNavigationTitle(_ title: String) -> some View {
        #if os(iOS)
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        #else
        self.navigationTitle(title)
        #endif
    }
}
