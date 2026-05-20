import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct CardListDetailView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var model: GrimoraAppModel
    @ObservedObject var gridZoom: GridZoomController
    @State var isShowingExportSheet = false
    @State var importMode: CardListImportMode?
    @State var isShowingDescription = false
    @State var descriptionRTFDData: Data?
    @State var descriptionPlainText = ""
    @State var descriptionListID: CardListRecord.ID?
    @State var descriptionIsDirty = false
    @State var descriptionSaveTask: Task<Void, Never>?
    @State var isReorderingCategories = false
    @State var isSelectingListEntries = false
    @State var listEntrySelection = CardGridSelectionState<CardListEntryRecord.ID>()
    @State var raisedArtworkEntryID: CardListEntryRecord.ID?
    @State var collapsedListCategoryIDs: Set<String> = []
    @State var quantityEditEntry: CardListEntryRecord?
    @State var quantityDraft = ""
    @State var entrySelectionFrames: [CardListEntryRecord.ID: CGRect] = [:]
    @State var selectionDragStart: CGPoint?
    @State var selectionDragLocation: CGPoint?
    @State var pendingListEntryOpenTask: Task<Void, Never>?
    @State var listMoveFeedbackTrigger = 0
    @State var landscapeArtworkEntryIDs: Set<CardListEntryRecord.ID> = []
    @State var listJumpToTopState = JumpToTopScrollState.top

    var onSelect: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: ([CardRecord.ID]) -> Void = { _ in }
    var onRenameList: (CardListRecord) -> Void = { _ in }
    var onCreateCategory: (CardListRecord) -> Void = { _ in }
    var onRenameCategory: (CardListCategoryRecord) -> Void = { _ in }

    static let entrySelectionCoordinateSpace = "card-list-entry-selection-space"
    static let listDetailTopAnchorID = "card-list-detail-top-anchor"
    private static let initialVisibleImageCacheIdentityCount = 48
    static let listEntryOpenDelayNanoseconds: UInt64 = 1_000_000_000

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                GrimoraAppBackground(palette: palette)
            }
            .grimoraSuccessFeedback(trigger: listMoveFeedbackTrigger)
        #if os(macOS)
        .toolbar {
            macListToolbar
        }
        .searchable(
            text: listSearchTextBinding,
            placement: .toolbar,
            prompt: Text("Search list")
        )
        #elseif os(iOS)
        .toolbar {
            touchListToolbar
        }
        .searchable(
            text: listSearchTextBinding,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search list")
        )
        #elseif os(visionOS)
        .toolbar {
            touchListToolbar
        }
        .searchable(
            text: listSearchTextBinding,
            prompt: Text("Search list")
        )
        #endif
        .onSubmit(of: .search) {
            model.reloadSelectedListSearch()
        }
        .sheet(isPresented: $isShowingExportSheet) {
            if let list = model.selectedList {
                CardListExportSheet(
                    list: list,
                    entries: model.selectedListEntries,
                    categories: model.selectedListCategories
                )
            }
        }
        .sheet(item: $importMode) { mode in
            CardListImportSheet(mode: mode)
        }
        .alert("Set Quantity", isPresented: quantityEditBinding) {
            TextField("Quantity", text: $quantityDraft)
            Button("Set") {
                submitQuantityEdit()
            }
            .disabled(Int(quantityDraft.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
            Button("Cancel", role: .cancel) {
                quantityEditEntry = nil
                quantityDraft = ""
            }
        }
        .onAppear {
            syncDescriptionDraftIfNeeded()
            syncListEntrySelectionVisibleIDs()
        }
        .task(id: initialVisibleListImageCacheTaskID) {
            guard isGridViewMode else {
                return
            }
            guard let entryID = firstVisibleListEntryID,
                  await VisibleImageCacheTaskDeferral.waitBeforeStarting()
            else {
                return
            }
            await model.cacheVisibleListEntryImages(
                around: entryID,
                quality: gridZoom.visibleImageQuality,
                forceRefresh: true
            )
        }
        .onChange(of: model.selectedListID) { oldValue, _ in
            flushDescriptionSave(forListID: oldValue)
            syncDescriptionDraft(for: model.selectedList)
            isReorderingCategories = false
            listJumpToTopState = .top
            endListEntrySelectionMode()
            collapsedListCategoryIDs = []
            clearListEntrySelection()
            cancelPendingListEntryOpen()
        }
        .onChange(of: model.selectedList?.viewMode) { _, _ in
            listJumpToTopState = .top
        }
        .onChange(of: model.selectedListCategories.count) { _, count in
            if count < 2 {
                isReorderingCategories = false
            }
        }
        .onChange(of: model.selectedListEntries.map(\.id)) { _, _ in
            pruneSelectedListEntryIDs()
        }
        .onChange(of: visibleListEntryIDs) { _, _ in
            syncListEntrySelectionVisibleIDs()
            keepLandscapeArtworkEntriesVisible()
        }
        .onDisappear {
            cancelPendingListEntryOpen()
            flushDescriptionSave(forListID: descriptionListID)
        }
        #if os(macOS)
        .onExitCommand {
            if isSelectingListEntries || !listEntrySelection.isEmpty {
                finishListEntrySelection()
            }
        }
        #endif
    }

    var quantityEditBinding: Binding<Bool> {
        Binding {
            quantityEditEntry != nil
        } set: { isPresented in
            if !isPresented {
                quantityEditEntry = nil
                quantityDraft = ""
            }
        }
    }

    private var firstVisibleListEntryID: CardListEntryRecord.ID? {
        visibleListEntryIDs.first
    }

    private var initialVisibleListImageCacheTaskID: InitialVisibleListImageCacheTaskID {
        InitialVisibleListImageCacheTaskID(
            listID: model.selectedListID,
            viewMode: model.selectedList?.viewMode ?? .grid,
            entryIDs: Array(visibleListEntryIDs.prefix(Self.initialVisibleImageCacheIdentityCount)),
            quality: gridZoom.visibleImageQuality
        )
    }
}

private struct InitialVisibleListImageCacheTaskID: Equatable {
    var listID: CardListRecord.ID?
    var viewMode: CardListViewMode
    var entryIDs: [CardListEntryRecord.ID]
    var quality: CardImageQuality
}
