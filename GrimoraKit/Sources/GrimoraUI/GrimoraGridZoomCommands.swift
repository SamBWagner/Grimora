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
public final class GrimoraListCommandController {
    var renameRequest: CardListRecord?

    public init() {}

    public func requestRename(_ list: CardListRecord) {
        renameRequest = list
    }

    func consumeRenameRequest() -> CardListRecord? {
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
        }
    }
}

public struct GrimoraListCommands: Commands {
    @FocusedObject private var model: GrimoraAppModel?
    @FocusedValue(\.listCommandController) private var listCommandController: GrimoraListCommandController?

    public init() {}

    public var body: some Commands {
        CommandMenu("List") {
            Button("Undo List Action") {
                model?.undoLastListAction()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(model?.canUndoListAction != true)

            Divider()

            Button("Rename List...") {
                requestSelectedListRename()
            }
            .disabled(selectedList == nil || listCommandController == nil)

            Button(selectedList?.isPinned == true ? "Unpin List" : "Pin List") {
                toggleSelectedListPinned()
            }
            .disabled(selectedList == nil)

            Divider()

            Button("Move List to Top") {
                moveSelectedListToTop()
            }
            .disabled(!canMoveSelectedListUp)

            Button("Move List Up") {
                moveSelectedList(by: -1)
            }
            .disabled(!canMoveSelectedListUp)

            Button("Move List Down") {
                moveSelectedList(by: 1)
            }
            .disabled(!canMoveSelectedListDown)

            Button("Move List to Bottom") {
                moveSelectedListToBottom()
            }
            .disabled(!canMoveSelectedListDown)

            Divider()

            Button(role: .destructive) {
                deleteSelectedList()
            } label: {
                Text("Delete List")
            }
            .disabled(selectedList == nil)
        }
    }

    private var selectedList: CardListRecord? {
        model?.selectedList
    }

    private var selectedListSection: [CardListRecord] {
        guard let selectedList else {
            return []
        }
        return selectedList.isPinned ? model?.pinnedCardLists ?? [] : model?.unpinnedCardLists ?? []
    }

    private var selectedListIndex: Int? {
        guard let selectedList else {
            return nil
        }
        return selectedListSection.firstIndex { $0.id == selectedList.id }
    }

    private var canMoveSelectedListUp: Bool {
        guard let selectedListIndex else {
            return false
        }
        return selectedListIndex > 0
    }

    private var canMoveSelectedListDown: Bool {
        guard let selectedListIndex else {
            return false
        }
        return selectedListIndex < selectedListSection.count - 1
    }

    private func requestSelectedListRename() {
        guard let selectedList else {
            return
        }
        listCommandController?.requestRename(selectedList)
    }

    private func toggleSelectedListPinned() {
        guard let selectedList else {
            return
        }
        model?.setCardListPinned(id: selectedList.id, isPinned: !selectedList.isPinned)
    }

    private func moveSelectedListToTop() {
        guard let selectedList else {
            return
        }
        model?.moveCardList(id: selectedList.id, toPosition: 0, isPinned: selectedList.isPinned)
    }

    private func moveSelectedList(by offset: Int) {
        guard let selectedList else {
            return
        }
        model?.moveCardList(id: selectedList.id, by: offset)
    }

    private func moveSelectedListToBottom() {
        guard let selectedList else {
            return
        }
        model?.moveCardList(
            id: selectedList.id,
            toPosition: selectedListSection.count - 1,
            isPinned: selectedList.isPinned
        )
    }

    private func deleteSelectedList() {
        guard let selectedList else {
            return
        }
        model?.deleteCardList(id: selectedList.id)
    }
}
#endif
