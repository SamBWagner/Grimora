import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct CardCollectionDetailView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) var colorScheme
    @Environment(GrimoraAppModel.self) var model
    var gridZoom: GridZoomController
    @State var isShowingExportSheet = false
    @State var importMode: CardCollectionImportMode?
    @State var isShowingDescription = false
    @State var descriptionRTFDData: Data?
    @State var descriptionPlainText = ""
    @State var descriptionListID: CardCollectionRecord.ID?
    @State var descriptionIsDirty = false
    @State var descriptionSaveTask: Task<Void, Never>?
    @State var isReorderingCategories = false
    @State var isSelectingListEntries = false
    @State var listEntrySelection = CardGridSelectionState<CardCollectionEntryRecord.ID>()
    @State var raisedArtworkEntryID: CardCollectionEntryRecord.ID?
    @State var collapsedListCategoryIDs: Set<String> = []
    @State var quantityEditEntry: CardCollectionEntryRecord?
    @State var quantityDraft = ""
    @State var entrySelectionFrames: [CardCollectionEntryRecord.ID: CGRect] = [:]
    @State var selectionDragStart: CGPoint?
    @State var selectionDragLocation: CGPoint?
    @State var pendingListEntryOpenTask: Task<Void, Never>?
    @State var listMoveFeedbackTrigger = 0
    @State var landscapeArtworkEntryIDs: Set<CardCollectionEntryRecord.ID> = []
    @State var listJumpToTopState = JumpToTopScrollState.top
    @State var renderedListEntryIDs: [CardCollectionEntryRecord.ID] = []

    var onSelect: (CardRecord) -> Void
    var onCreateListForCard: (CardRecord) -> Void
    var onCreateListForCards: ([CardRecord.ID]) -> Void = { _ in }
    var onRenameList: (CardCollectionRecord) -> Void = { _ in }
    var onCreateCategory: (CardCollectionRecord) -> Void = { _ in }
    var onRenameCategory: (CardCollectionCategoryRecord) -> Void = { _ in }

    static let entrySelectionCoordinateSpace = "card-list-entry-selection-space"
    static let listDetailTopAnchorID = "card-list-detail-top-anchor"
    static let listEntryOpenDelayNanoseconds: UInt64 = 1_000_000_000

    var body: some View {
        let snapshot = makeListDetailSnapshot()

        content(snapshot: snapshot)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                GrimoraAppBackground(palette: palette)
            }
            .grimoraSuccessFeedback(trigger: listMoveFeedbackTrigger)
        #if os(macOS)
        .toolbar {
            macListToolbar(snapshot: snapshot)
        }
        .searchable(
            text: listSearchTextBinding,
            placement: .toolbar,
            prompt: Text("Search collection")
        )
        #elseif os(iOS)
        .toolbar {
            touchListToolbar(snapshot: snapshot)
        }
        .searchable(
            text: listSearchTextBinding,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search collection")
        )
        #elseif os(visionOS)
        .toolbar {
            touchListToolbar(snapshot: snapshot)
        }
        .searchable(
            text: listSearchTextBinding,
            prompt: Text("Search collection")
        )
        #endif
        .onSubmit(of: .search) {
            model.reloadSelectedListSearch()
        }
        .sheet(isPresented: $isShowingExportSheet) {
            if let list = model.selectedCollection {
                CardCollectionExportSheet(
                    list: list,
                    entries: model.selectedCollectionEntries,
                    categories: model.selectedCollectionCategories
                )
            }
        }
        .sheet(item: $importMode) { mode in
            CardCollectionImportSheet(mode: mode)
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
            renderedListEntryIDs = snapshot.expandedEntryIDs
            syncListEntrySelectionVisibleIDs(snapshot.expandedEntryIDs)
        }
        .task(id: visibleListImageRefreshTaskID(snapshot: snapshot)) {
            let imageQuality = gridZoom.visibleImageQuality
            guard isGridViewMode else {
                await model.refreshVisibleListEntryImages(
                    displayedEntries: [],
                    around: nil,
                    quality: imageQuality
                )
                return
            }
            guard let entryID = snapshot.expandedEntryIDs.first,
                  await VisibleImageCacheTaskDeferral.waitBeforeStarting()
            else {
                return
            }
            await model.refreshVisibleListEntryImages(
                displayedEntries: snapshot.expandedEntries,
                around: entryID,
                quality: imageQuality
            )
        }
        .onChange(of: model.selectedCollectionID) { oldValue, _ in
            flushDescriptionSave(forListID: oldValue)
            syncDescriptionDraft(for: model.selectedCollection)
            isReorderingCategories = false
            listJumpToTopState = .top
            endListEntrySelectionMode()
            collapsedListCategoryIDs = []
            clearListEntrySelection()
            cancelPendingListEntryOpen()
        }
        .onChange(of: model.selectedCollection?.viewMode) { _, _ in
            listJumpToTopState = .top
        }
        .onChange(of: model.selectedCollectionCategories.count) { _, count in
            if count < 2 {
                isReorderingCategories = false
            }
        }
        .onChange(of: model.selectedCollectionEntries.map(\.id)) { _, _ in
            pruneSelectedListEntryIDs()
        }
        .onChange(of: snapshot.expandedEntryIDs) { _, entryIDs in
            renderedListEntryIDs = entryIDs
            syncListEntrySelectionVisibleIDs(entryIDs)
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

    private func visibleListImageRefreshTaskID(
        snapshot: CardCollectionDetailSnapshot
    ) -> VisibleListImageRefreshTaskID {
        VisibleListImageRefreshTaskID(
            listID: model.selectedCollectionID,
            viewMode: model.selectedCollection?.viewMode ?? .grid,
            entryIDs: snapshot.expandedEntryIDs,
            quality: gridZoom.visibleImageQuality
        )
    }
}

private struct VisibleListImageRefreshTaskID: Equatable {
    var listID: CardCollectionRecord.ID?
    var viewMode: CardCollectionViewMode
    var entryIDs: [CardCollectionEntryRecord.ID]
    var quality: CardImageQuality
}
