import GrimoraCore
import SwiftUI

/// Context-menu actions for a dashboard list tile. Mirrors the sidebar row
/// actions (CardListBrowserRowActions): the protected Favourites list isn't
/// pinnable, renamable, or deletable.
struct CardListOverviewActions: View {
    var model: GrimoraAppModel
    var item: CardListOverviewItem
    var onRenameList: (CardListRecord) -> Void

    @ViewBuilder
    var body: some View {
        if !model.isProtectedFavouritesList(item.list) {
            Button {
                model.setCardListPinned(id: item.list.id, isPinned: !item.list.isPinned)
            } label: {
                Label(item.list.isPinned ? "Unpin" : "Pin",
                      systemImage: item.list.isPinned ? "pin.slash" : "pin")
            }

            Button {
                onRenameList(item.list)
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                model.deleteCardList(id: item.list.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
