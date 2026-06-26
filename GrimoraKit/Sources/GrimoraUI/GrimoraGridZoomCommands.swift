import GrimoraCore
import SwiftUI

public struct GrimoraGridZoomCommands: Commands {
    @FocusedValue(\.gridZoomController) private var gridZoom: GridZoomController?

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Zoom In") {
                commandGridZoom?.zoomIn()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(commandGridZoom?.canZoomIn == false)

            Button("Zoom Out") {
                commandGridZoom?.zoomOut()
            }
            .keyboardShortcut(",", modifiers: [.command, .shift])
            .disabled(commandGridZoom?.canZoomOut == false)

            Button("Actual Size") {
                commandGridZoom?.reset()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(commandGridZoom?.canReset == false)
        }
    }

    private var commandGridZoom: GridZoomController? {
        gridZoom ?? GridZoomController.activeForCommands
    }
}

#if os(macOS)
@Observable
@MainActor
public final class GrimoraCollectionCommandController {
    var renameRequest: CardCollectionRecord?

    public init() {}

    public func requestRename(_ list: CardCollectionRecord) {
        renameRequest = list
    }

    func consumeRenameRequest() -> CardCollectionRecord? {
        defer {
            renameRequest = nil
        }
        return renameRequest
    }
}

public struct GrimoraSearchCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(before: .textEditing) {
            Button("Search Cards") {
                GrimoraSearchFocusController.shared.focusSearch()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Advanced Search…") {
                GrimoraSearchFocusController.shared.presentAdvancedSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}

public struct GrimoraListCommands: Commands {
    @FocusedValue(\.appModel) private var model: GrimoraAppModel?
    @FocusedValue(\.listCommandController) private var listCommandController: GrimoraCollectionCommandController?

    public init() {}

    public var body: some Commands {
        CommandMenu("Collection") {
            Button("Undo Collection Action") {
                model?.undoLastListAction()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(model?.canUndoListAction != true)

            Divider()

            Button("Rename Collection...") {
                requestSelectedListRename()
            }
            .disabled(selectedCollection == nil || listCommandController == nil)

            Button(selectedCollection?.isPinned == true ? "Unpin Collection" : "Pin Collection") {
                toggleSelectedListPinned()
            }
            .disabled(selectedCollection == nil)

            Divider()

            Button("Move Collection to Top") {
                moveSelectedListToTop()
            }
            .disabled(!canMoveSelectedListUp)

            Button("Move Collection Up") {
                moveSelectedList(by: -1)
            }
            .disabled(!canMoveSelectedListUp)

            Button("Move Collection Down") {
                moveSelectedList(by: 1)
            }
            .disabled(!canMoveSelectedListDown)

            Button("Move Collection to Bottom") {
                moveSelectedListToBottom()
            }
            .disabled(!canMoveSelectedListDown)

            Divider()

            Button(role: .destructive) {
                deleteSelectedList()
            } label: {
                Text("Delete Collection")
            }
            .disabled(selectedCollection == nil)
        }
    }

    private var selectedCollection: CardCollectionRecord? {
        model?.selectedCollection
    }

    private var selectedCollectionSection: [CardCollectionRecord] {
        guard let selectedCollection else {
            return []
        }
        return selectedCollection.isPinned ? model?.pinnedCardCollections ?? [] : model?.unpinnedCardCollections ?? []
    }

    private var selectedCollectionIndex: Int? {
        guard let selectedCollection else {
            return nil
        }
        return selectedCollectionSection.firstIndex { $0.id == selectedCollection.id }
    }

    private var canMoveSelectedListUp: Bool {
        guard let selectedCollectionIndex else {
            return false
        }
        return selectedCollectionIndex > 0
    }

    private var canMoveSelectedListDown: Bool {
        guard let selectedCollectionIndex else {
            return false
        }
        return selectedCollectionIndex < selectedCollectionSection.count - 1
    }

    private func requestSelectedListRename() {
        guard let selectedCollection else {
            return
        }
        listCommandController?.requestRename(selectedCollection)
    }

    private func toggleSelectedListPinned() {
        guard let selectedCollection else {
            return
        }
        model?.setCardCollectionPinned(id: selectedCollection.id, isPinned: !selectedCollection.isPinned)
    }

    private func moveSelectedListToTop() {
        guard let selectedCollection else {
            return
        }
        model?.moveCardCollection(id: selectedCollection.id, toPosition: 0, isPinned: selectedCollection.isPinned)
    }

    private func moveSelectedList(by offset: Int) {
        guard let selectedCollection else {
            return
        }
        model?.moveCardCollection(id: selectedCollection.id, by: offset)
    }

    private func moveSelectedListToBottom() {
        guard let selectedCollection else {
            return
        }
        model?.moveCardCollection(
            id: selectedCollection.id,
            toPosition: selectedCollectionSection.count - 1,
            isPinned: selectedCollection.isPinned
        )
    }

    private func deleteSelectedList() {
        guard let selectedCollection else {
            return
        }
        model?.deleteCardCollection(id: selectedCollection.id)
    }
}
#endif
