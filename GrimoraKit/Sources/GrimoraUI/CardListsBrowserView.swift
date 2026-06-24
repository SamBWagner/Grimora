import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

enum CardListsBrowserRoute: Hashable {
    case overview
    case newList
    case list(CardListRecord.ID)
}

struct CardListsBrowserView: View {
    @Environment(GrimoraAppModel.self) private var model
    var gridZoom: GridZoomController

    var onCreateList: () -> Void
    var onCancelCreateList: () -> Void = {}
    var onCompleteCreateList: () -> Void = {}
    var onRenameList: (CardListRecord) -> Void
    var onSelectCard: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: ([CardRecord.ID]) -> Void = { _ in }
    var onCreateCategory: (CardListRecord) -> Void = { _ in }
    var onRenameCategory: (CardListCategoryRecord) -> Void = { _ in }

    var body: some View {
        CardListsOverviewView(
            onCreateList: onCreateList,
            onSelectList: { _ in },
            onRenameList: onRenameList
        )
        .navigationDestination(for: CardListsBrowserRoute.self) { route in
            switch route {
            case .overview:
                CardListsOverviewView(
                    onCreateList: onCreateList,
                    onSelectList: { _ in },
                    onRenameList: onRenameList
                )
            case .newList:
                CardListCreateDestinationView(
                    onCancel: onCancelCreateList,
                    onComplete: onCompleteCreateList
                )
                .navigationTitle("New List")
            case .list(let listID):
                CardListDetailView(
                    gridZoom: gridZoom,
                    onSelect: onSelectCard,
                    onCreateListForCard: onCreateListForCard,
                    onCreateListForCards: onCreateListForCards,
                    onRenameList: onRenameList,
                    onCreateCategory: onCreateCategory,
                    onRenameCategory: onRenameCategory
                )
                .cardListBrowserDetailNavigationTitle(model.cardLists.first { $0.id == listID }?.name ?? "List")
                .onAppear {
                    model.selectCardList(id: listID)
                }
                .onDisappear {
                    // Popping back to the dashboard leaves `selectedListID` set, so
                    // re-tapping the tile we just left wouldn't change it and the
                    // navigation-driving `onChange(of: selectedListID)` never fires —
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

struct CardListsBrowserSidebarView: View {
    @Environment(GrimoraAppModel.self) private var model

    var onCreateList: () -> Void
    var onRenameList: (CardListRecord) -> Void

    var body: some View {
        List(selection: sidebarRouteSelection) {
            Section {
                NavigationLink(value: CardListsBrowserRoute.overview) {
                    Label("Lists", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("card-lists-overview-sidebar-button")

                NavigationLink(value: CardListsBrowserRoute.newList) {
                    Label("New List", systemImage: "plus")
                }
                .accessibilityIdentifier("create-list-button")
            }

            Section("Lists") {
                if model.cardLists.isEmpty {
                    ContentUnavailableView("No Lists", systemImage: "list.bullet.rectangle")
                        .accessibilityIdentifier("empty-lists-browser")
                } else {
                    ForEach(model.cardLists) { list in
                        NavigationLink(value: CardListsBrowserRoute.list(list.id)) {
                            CardListBrowserRowLabel(list: list)
                        }
                        .accessibilityIdentifier("card-list-row-\(list.name)")
                        .accessibilityValue(entryCountText(for: list))
                        .cardListBrowserRowActions(for: list, onRenameList: onRenameList)
                    }
                }
            }
        }
        .accessibilityIdentifier("card-lists-split-sidebar")
    }

    private var sidebarRouteSelection: Binding<CardListsBrowserRoute?> {
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
                model.selectCardList(id: id)
            case nil:
                model.selectListsOverview()
            }
        }
    }
}

private struct CardListBrowserRowLabel: View {
    @Environment(GrimoraAppModel.self) private var model

    var list: CardListRecord

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

private struct CardListBrowserRowActions: ViewModifier {
    @Environment(GrimoraAppModel.self) private var model

    var list: CardListRecord
    var onRenameList: (CardListRecord) -> Void

    func body(content: Content) -> some View {
        let isProtected = model.isProtectedFavouritesList(list)

        content
            .swipeActions {
                if !isProtected {
                    Button {
                        model.setCardListPinned(id: list.id, isPinned: !list.isPinned)
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
                        model.deleteCardList(id: list.id)
                    } label: {
                        Text("Delete")
                    }
                }
            }
            .contextMenu {
                if !isProtected {
                    Button {
                        model.setCardListPinned(id: list.id, isPinned: !list.isPinned)
                    } label: {
                        Text(list.isPinned ? "Unpin" : "Pin")
                    }

                    Button {
                        onRenameList(list)
                    } label: {
                        Text("Rename")
                    }

                    Button(role: .destructive) {
                        model.deleteCardList(id: list.id)
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
    func cardListBrowserRowActions(
        for list: CardListRecord,
        onRenameList: @escaping (CardListRecord) -> Void
    ) -> some View {
        modifier(CardListBrowserRowActions(list: list, onRenameList: onRenameList))
    }
}

private func entryCountText(for list: CardListRecord) -> String {
    let noun = list.entryCount == 1 ? "card" : "cards"
    return "\(list.entryCount.formatted()) \(noun)"
}

private extension View {
    @ViewBuilder
    func cardListBrowserDetailNavigationTitle(_ title: String) -> some View {
        #if os(iOS)
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        #else
        self.navigationTitle(title)
        #endif
    }
}
