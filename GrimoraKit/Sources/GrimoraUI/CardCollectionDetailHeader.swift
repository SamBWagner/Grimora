import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

extension CardCollectionDetailView {
    func header(snapshot: CardCollectionDetailSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            #if os(iOS)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedCollection?.name ?? "Collection")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(palette.primaryText.color)
                    .lineLimit(2)
                    .accessibilityIdentifier("card-list-detail-title")

                Text(snapshot.entryCountText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.secondaryText.color)
                    .accessibilityIdentifier("card-list-entry-count")
            }
            #else
            Text(snapshot.entryCountText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.secondaryText.color)
                .accessibilityIdentifier("card-list-entry-count")
            #endif

            #if os(macOS)
            if isSelectingListEntries || !listEntrySelection.isEmpty {
                Text(selectedCollectionEntryCountText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
                    .accessibilityIdentifier("selected-list-entry-count")
            }
            #endif

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, headerVerticalPadding)
    }

    var headerVerticalPadding: CGFloat {
        #if os(macOS)
        10
        #else
        16
        #endif
    }

    var listSearchTextBinding: Binding<String> {
        Binding {
            model.selectedCollectionSearchText
        } set: { newValue in
            if !GrimoraSearchHistoryStore.normalizedQuery(newValue).isEmpty {
                isReorderingCategories = false
            }
            model.setSelectedListSearchDraft(newValue)
        }
    }

    /// Primary action for the Scanned list: **move** every scanned card into one of
    /// the user's other collections, emptying Scanned. Scanned is non-permanent
    /// storage — you scan a batch, then file it somewhere.
    @ViewBuilder
    func scannedAddToCollectionMenu(from list: CardCollectionRecord) -> some View {
        Menu {
            let targets = model.cardCollections.filter { $0.id != list.id }
            if targets.isEmpty {
                Text("No other collections yet")
            } else {
                ForEach(targets) { target in
                    Button(target.name) {
                        let entries = model.selectedCollectionEntries
                        let cardIDs = entries.flatMap {
                            Array(repeating: $0.cardID, count: max(1, $0.quantity))
                        }
                        model.addCards(cardIDs, toListID: target.id)
                        model.removeCardCollectionEntriesCompletely(ids: entries.map(\.id))
                    }
                }
            }
        } label: {
            Label("Add to Collection", systemImage: "plus")
        }
        .help("Move all scanned cards into another collection")
        .accessibilityIdentifier("scanned-add-to-collection-menu")
    }

    /// Clears the Scanned list (deletes it; it returns on the next scan), with a
    /// confirmation handled by the detail view.
    @ViewBuilder
    func scannedClearButton(for list: CardCollectionRecord) -> some View {
        Button(role: .destructive) {
            isConfirmingClearScanned = true
        } label: {
            Label("Clear Scanned", systemImage: "minus")
                .labelStyle(.iconOnly)
        }
        .help("Clear Scanned")
        .accessibilityIdentifier("scanned-clear-button")
    }

    #if os(macOS)
    @ToolbarContentBuilder
    func macListToolbar(snapshot: CardCollectionDetailSnapshot) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let selectedCollection = model.selectedCollection {
                if model.isScannedList(selectedCollection) {
                    scannedAddToCollectionMenu(from: selectedCollection)
                    scannedClearButton(for: selectedCollection)
                    listSortMenu(for: selectedCollection)
                    Button {
                        model.setCardCollectionDashboardVisibility(
                            id: selectedCollection.id,
                            showsDashboard: !selectedCollection.showsDashboard
                        )
                    } label: {
                        Label(
                            selectedCollection.showsDashboard ? "Hide Stats" : "Show Stats",
                            systemImage: "chart.bar.xaxis"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .help(selectedCollection.showsDashboard ? "Hide Stats" : "Show Stats")
                    Menu {
                        Button {
                            importMode = .append(selectedCollection.id)
                        } label: {
                            Text("Import")
                        }
                        Button {
                            isShowingExportSheet = true
                        } label: {
                            Text("Export Collection")
                        }
                    } label: {
                        Label("Transfer", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                } else {
                listViewModePicker(for: selectedCollection)
                rulesetMenu(for: selectedCollection)
                listSortMenu(for: selectedCollection)

                Button {
                    model.setCardCollectionDashboardVisibility(
                        id: selectedCollection.id,
                        showsDashboard: !selectedCollection.showsDashboard
                    )
                } label: {
                    Label(
                        selectedCollection.showsDashboard ? "Hide Stats" : "Show Stats",
                        systemImage: "chart.bar.xaxis"
                    )
                    .labelStyle(.iconOnly)
                }
                .help(selectedCollection.showsDashboard ? "Hide Stats" : "Show Stats")
                .accessibilityIdentifier("toggle-list-dashboard-button")
                .accessibilityValue(selectedCollection.showsDashboard ? "Shown" : "Hidden")

                Button {
                    toggleDescription(for: selectedCollection)
                } label: {
                    Label(
                        isShowingDescription ? "Hide Description" : "Show Description",
                        systemImage: "text.alignleft"
                    )
                    .labelStyle(.iconOnly)
                }
                .help(isShowingDescription ? "Hide Description" : "Show Description")
                .accessibilityIdentifier("toggle-list-description-button")
                .accessibilityValue(isShowingDescription ? "Shown" : "Hidden")

                Button {
                    onCreateCategory(selectedCollection)
                } label: {
                    Label("New Category", systemImage: "folder.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .help("New Category")
                .accessibilityIdentifier("create-list-category-button")

                macListMoreMenu(for: selectedCollection, snapshot: snapshot)
                }
            }
        }
    }

    @ViewBuilder
    func macListMoreMenu(
        for selectedCollection: CardCollectionRecord,
        snapshot: CardCollectionDetailSnapshot
    ) -> some View {
        Menu {
            if isSelectingListEntries || !listEntrySelection.isEmpty {
                Section("Selection") {
                    Button {
                        clearListEntrySelection()
                    } label: {
                        Text("Clear Selection")
                    }
                    .disabled(listEntrySelection.isEmpty)
                    .accessibilityIdentifier("clear-list-entry-selection-button")
                }
            }

            Section("Organize") {
                if model.selectedCollectionCategories.count > 1 {
                    Button {
                        if !isReorderingCategories {
                            clearListEntrySelection()
                            endListEntrySelectionMode()
                        }
                        isReorderingCategories.toggle()
                    } label: {
                        Text(isReorderingCategories ? "Finish Reordering" : "Reorder Categories")
                    }
                    .accessibilityIdentifier(
                        isReorderingCategories
                            ? "finish-reorder-list-categories-button"
                            : "reorder-list-categories-button"
                    )
                }

                if !snapshot.sections.isEmpty && !isReorderingCategories {
                    Button {
                        collapseAllSections(snapshot)
                    } label: {
                        Text("Collapse All")
                    }
                    .accessibilityIdentifier("collapse-all-list-categories-button")

                    Button {
                        unfoldAllSections()
                    } label: {
                        Text("Expand All")
                    }
                    .accessibilityIdentifier("unfold-all-list-categories-button")
                }
            }

            Section("Transfer") {
                Button {
                    importMode = .append(selectedCollection.id)
                } label: {
                    Text("Import...")
                }
                .accessibilityIdentifier("import-list-detail-button")

                Button {
                    isShowingExportSheet = true
                } label: {
                    Text("Export Collection...")
                }
                .accessibilityIdentifier("export-list-button")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .help("More Collection Actions")
        .accessibilityIdentifier("list-detail-more-menu")
    }
    #endif

    #if os(iOS) || os(visionOS)
    // Each control gets its own ToolbarItem rather than sharing a
    // ToolbarItemGroup: a group renders its children in one container, and when
    // the actions menu presents, SwiftUI hides the sibling view-mode picker but
    // leaves the group's container behind — the "empty box" the brief flags.
    // Separate items keep the picker visible (and its own container) while the
    // menu is open.
    @ToolbarContentBuilder
    func touchListToolbar(snapshot: CardCollectionDetailSnapshot) -> some ToolbarContent {
        if let selectedCollection = model.selectedCollection, model.isScannedList(selectedCollection) {
            // Scanned is a scanning inbox: two primary actions only — add the whole
            // list to another collection, and a slim more-menu (Sort, Export).
            ToolbarItem(placement: .topBarTrailing) {
                scannedAddToCollectionMenu(from: selectedCollection)
            }
            ToolbarItem(placement: .topBarTrailing) {
                scannedClearButton(for: selectedCollection)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    scannedMoreMenuContent(for: selectedCollection)
                } label: {
                    listActionsMenuLabel
                }
                .accessibilityIdentifier("list-detail-actions-menu")
            }
        } else {
            if let selectedCollection = model.selectedCollection {
                ToolbarItem(placement: .topBarTrailing) {
                    listViewModePicker(for: selectedCollection)
                        #if os(iOS)
                        .fixedSize(horizontal: true, vertical: false)
                        #endif
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                touchListActionsMenu(snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    func touchListActionsMenu(snapshot: CardCollectionDetailSnapshot) -> some View {
        if let selectedCollection = model.selectedCollection {
            Menu {
                #if os(visionOS)
                visionListMenuContent(for: selectedCollection, snapshot: snapshot)
                #else
                touchListMenuContent(for: selectedCollection, snapshot: snapshot)
                #endif
            } label: {
                listActionsMenuLabel
                    .accessibilityIdentifier("list-detail-actions-menu")
            }
            .help("Collection Actions")
            .accessibilityLabel("Collection Actions")
        }
    }

    // Standard system-styled menu button: the previous capsule/material chrome
    // only wrapped the ellipsis (not the adjacent picker), which read as
    // inconsistent and cluttered. Letting the toolbar style the button keeps the
    // trailing cluster clean and on platform.
    @ViewBuilder
    private var listActionsMenuLabel: some View {
        Label("Collection Actions", systemImage: "ellipsis")
            .labelStyle(.iconOnly)
            .imageScale(.large)
    }

    // MARK: - Scanned (special list) — stripped-down chrome

    /// The slim "more" menu for the Scanned list — Sort, Show Stats, and Transfer
    /// (Import + Export). No rename/undo/description/organize/ruleset.
    @ViewBuilder
    func scannedMoreMenuContent(for list: CardCollectionRecord) -> some View {
        Menu {
            listSortButtons(for: list)
        } label: {
            Text("Sort")
        }
        .accessibilityIdentifier("list-sort-menu")

        Button {
            model.setCardCollectionDashboardVisibility(
                id: list.id,
                showsDashboard: !list.showsDashboard
            )
        } label: {
            Text(list.showsDashboard ? "Hide Stats" : "Show Stats")
        }
        .accessibilityIdentifier("toggle-list-dashboard-button")

        Section("Transfer") {
            Button {
                importMode = .append(list.id)
            } label: {
                Text("Import")
            }
            .accessibilityIdentifier("import-list-detail-button")

            Button {
                isShowingExportSheet = true
            } label: {
                Text("Export Collection")
            }
            .accessibilityIdentifier("export-list-button")
        }
    }

    #if os(visionOS)
    @ViewBuilder
    func visionListMenuContent(
        for selectedCollection: CardCollectionRecord,
        snapshot: CardCollectionDetailSnapshot
    ) -> some View {
        Button {
            onRenameList(selectedCollection)
        } label: {
            Text("Rename Collection")
        }
        .accessibilityIdentifier("rename-list-\(selectedCollection.name)")

        Button {
            model.undoLastListAction()
        } label: {
            Text("Undo")
        }
        .disabled(!model.canUndoListAction)
        .accessibilityIdentifier("undo-list-action-button")

        Menu {
            listSortButtons(for: selectedCollection)
        } label: {
            Text("Sort")
        }
        .accessibilityIdentifier("list-sort-menu")

        Menu {
            rulesetButtons(for: selectedCollection)
        } label: {
            Text("Ruleset")
        }
        .accessibilityIdentifier("list-ruleset-menu")

        Button {
            model.setCardCollectionDashboardVisibility(
                id: selectedCollection.id,
                showsDashboard: !selectedCollection.showsDashboard
            )
        } label: {
            Text(selectedCollection.showsDashboard ? "Hide Stats" : "Show Stats")
        }
        .accessibilityIdentifier("toggle-list-dashboard-button")
        .accessibilityValue(selectedCollection.showsDashboard ? "Shown" : "Hidden")

        Button {
            toggleDescription(for: selectedCollection)
        } label: {
            Text("Description")
        }
        .accessibilityIdentifier("toggle-list-description-button")

        Button {
            importMode = .append(selectedCollection.id)
        } label: {
            Text("Import")
        }
        .accessibilityIdentifier("import-list-detail-button")

        Button {
            isShowingExportSheet = true
        } label: {
            Text("Export Collection")
        }
        .accessibilityIdentifier("export-list-button")

        Button {
            onCreateCategory(selectedCollection)
        } label: {
            Text("New Category")
        }
        .accessibilityIdentifier("create-list-category-button")

        if model.selectedCollectionCategories.count > 1 {
            Button {
                if !isReorderingCategories {
                    clearListEntrySelection()
                    endListEntrySelectionMode()
                }
                isReorderingCategories.toggle()
            } label: {
                Text(isReorderingCategories ? "Finish Reordering" : "Reorder Categories")
            }
            .accessibilityIdentifier(
                isReorderingCategories
                    ? "finish-reorder-list-categories-button"
                    : "reorder-list-categories-button"
            )
        }

        if !snapshot.sections.isEmpty {
            Button {
                collapseAllSections(snapshot)
            } label: {
                Text("Collapse All")
            }
            .accessibilityIdentifier("collapse-all-list-categories-button")

            Button {
                unfoldAllSections()
            } label: {
                Text("Expand All")
            }
            .accessibilityIdentifier("unfold-all-list-categories-button")
        }

        if !model.selectedCollectionEntries.isEmpty {
            Button {
                if isSelectingListEntries {
                    finishListEntrySelection()
                } else {
                    beginListEntrySelection()
                }
            } label: {
                Text(isSelectingListEntries ? "Finish Selection" : "Select Entries")
            }
            .accessibilityIdentifier(
                isSelectingListEntries
                    ? "finish-list-entry-selection-button"
                    : "select-list-entries-button"
            )
        }

        if isSelectingListEntries || !listEntrySelection.isEmpty {
            Button {
                clearListEntrySelection()
            } label: {
                Text("Clear Selection")
            }
            .disabled(listEntrySelection.isEmpty)
            .accessibilityIdentifier("clear-list-entry-selection-button")
        }
    }
    #endif

    @ViewBuilder
    func touchListMenuContent(
        for selectedCollection: CardCollectionRecord,
        snapshot: CardCollectionDetailSnapshot
    ) -> some View {
        Section("Collection") {
            Button {
                onRenameList(selectedCollection)
            } label: {
                Text("Rename Collection")
            }
            .accessibilityIdentifier("rename-list-\(selectedCollection.name)")

            Button {
                model.undoLastListAction()
            } label: {
                Text("Undo")
            }
            .disabled(!model.canUndoListAction)
            .accessibilityIdentifier("undo-list-action-button")
        }

        listSortButtons(for: selectedCollection)

        Section("View") {
            Button {
                model.setCardCollectionDashboardVisibility(
                    id: selectedCollection.id,
                    showsDashboard: !selectedCollection.showsDashboard
                )
            } label: {
                Text(selectedCollection.showsDashboard ? "Hide Stats" : "Show Stats")
            }
            .accessibilityIdentifier("toggle-list-dashboard-button")
            .accessibilityValue(selectedCollection.showsDashboard ? "Shown" : "Hidden")

            Button {
                toggleDescription(for: selectedCollection)
            } label: {
                Text("Description")
            }
            .accessibilityIdentifier("toggle-list-description-button")
        }

        Section("Transfer") {
            Button {
                importMode = .append(selectedCollection.id)
            } label: {
                Text("Import")
            }
            .accessibilityIdentifier("import-list-detail-button")

            Button {
                isShowingExportSheet = true
            } label: {
                Text("Export Collection")
            }
            .accessibilityIdentifier("export-list-button")
        }

        Section("Organize") {
            Button {
                onCreateCategory(selectedCollection)
            } label: {
                Text("New Category")
            }
            .accessibilityIdentifier("create-list-category-button")

            if model.selectedCollectionCategories.count > 1 {
                Button {
                    if !isReorderingCategories {
                        clearListEntrySelection()
                        endListEntrySelectionMode()
                    }
                    isReorderingCategories.toggle()
                } label: {
                    Text(isReorderingCategories ? "Finish Reordering" : "Reorder Categories")
                }
                .accessibilityIdentifier(
                    isReorderingCategories
                        ? "finish-reorder-list-categories-button"
                        : "reorder-list-categories-button"
                )
            }

            if !snapshot.sections.isEmpty {
                Button {
                    collapseAllSections(snapshot)
                } label: {
                    Text("Collapse All")
                }
                .accessibilityIdentifier("collapse-all-list-categories-button")

                Button {
                    unfoldAllSections()
                } label: {
                    Text("Expand All")
                }
                .accessibilityIdentifier("unfold-all-list-categories-button")
            }

            if !model.selectedCollectionEntries.isEmpty {
                Button {
                    if isSelectingListEntries {
                        finishListEntrySelection()
                    } else {
                        beginListEntrySelection()
                    }
                } label: {
                    Text(isSelectingListEntries ? "Finish Selection" : "Select Entries")
                }
                .accessibilityIdentifier(
                    isSelectingListEntries
                        ? "finish-list-entry-selection-button"
                        : "select-list-entries-button"
                )
            }

        }

        if isSelectingListEntries || !listEntrySelection.isEmpty {
            Section("Selection") {
                Text(selectedCollectionEntryCountText)
                    .accessibilityIdentifier("selected-list-entry-count")

                Button {
                    clearListEntrySelection()
                } label: {
                    Text("Clear Selection")
                }
                .disabled(listEntrySelection.isEmpty)
                .accessibilityIdentifier("clear-list-entry-selection-button")

                Button {
                    if isSelectingListEntries {
                        finishListEntrySelection()
                    } else {
                        beginListEntrySelection()
                    }
                } label: {
                    Text(isSelectingListEntries ? "Finish Selection" : "Select Entries")
                }
                .accessibilityIdentifier(
                    isSelectingListEntries
                        ? "finish-list-entry-selection-button"
                        : "select-list-entries-button"
                )
            }
        }

        Section("Ruleset") {
            rulesetButtons(for: selectedCollection)
        }
    }
    #endif

    @ViewBuilder
    func listViewModePicker(for selectedCollection: CardCollectionRecord) -> some View {
        Picker("View", selection: listViewModeBinding(for: selectedCollection)) {
            ForEach(CardCollectionViewMode.allCases) { mode in
                Image(systemName: mode.systemImage)
                    .imageScale(.medium)
                    .frame(maxWidth: .infinity)
                    .tag(mode)
                    .help(mode.toolbarTitle)
                    .accessibilityLabel(mode.toolbarTitle)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 116)
        .help("List View")
        .accessibilityLabel("List View")
        .accessibilityValue(selectedCollection.viewMode.toolbarTitle)
        .accessibilityIdentifier("card-list-view-mode-picker")
    }

    func listViewModeBinding(for selectedCollection: CardCollectionRecord) -> Binding<CardCollectionViewMode> {
        Binding {
            model.selectedCollection?.viewMode ?? selectedCollection.viewMode
        } set: { mode in
            guard mode != model.selectedCollection?.viewMode else {
                return
            }
            model.setCardCollectionViewMode(id: selectedCollection.id, mode: mode)
        }
    }

    @ViewBuilder
    func rulesetMenu(for selectedCollection: CardCollectionRecord) -> some View {
        Menu {
            rulesetButtons(for: selectedCollection)
        } label: {
            Text(selectedCollection.ruleset.title)
        }
        .help("Ruleset")
        .accessibilityIdentifier("list-ruleset-menu")
        .accessibilityValue(selectedCollection.ruleset.title)
    }

    @ViewBuilder
    func listSortMenu(for selectedCollection: CardCollectionRecord) -> some View {
        Menu {
            listSortButtons(for: selectedCollection)
        } label: {
            Label("Sort Collection", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .help("Sort Collection: \(listSortDescription(for: selectedCollection))")
        .accessibilityIdentifier("list-sort-menu")
        .accessibilityLabel("Sort Collection")
        .accessibilityValue(listSortDescription(for: selectedCollection))
    }

    @ViewBuilder
    func listSortButtons(for selectedCollection: CardCollectionRecord) -> some View {
        Section("Sort") {
            listSortModeButtons(for: selectedCollection)
        }

        if let mode = selectedCollection.displaySortMode {
            Section("Order") {
                listSortDirectionButtons(for: selectedCollection, mode: mode)
            }
        }
    }

    @ViewBuilder
    func listSortModeButtons(for selectedCollection: CardCollectionRecord) -> some View {
        Button {
            model.setCardCollectionDisplaySort(
                id: selectedCollection.id,
                mode: nil,
                direction: selectedCollection.displaySortDirection
            )
        } label: {
            GrimoraMenuSelectionLabel(
                title: "List Order",
                isSelected: selectedCollection.displaySortMode == nil
            )
        }
        .accessibilityIdentifier("list-sort-option-list-order")

        ForEach(SortMode.allCases) { mode in
            Button {
                model.setCardCollectionDisplaySort(
                    id: selectedCollection.id,
                    mode: mode,
                    direction: selectedCollection.displaySortDirection
                )
            } label: {
                GrimoraMenuSelectionLabel(
                    title: mode.title,
                    isSelected: selectedCollection.displaySortMode == mode
                )
            }
            .accessibilityIdentifier("list-sort-option-\(mode.rawValue)")
        }
    }

    @ViewBuilder
    func listSortDirectionButtons(for selectedCollection: CardCollectionRecord) -> some View {
        if let mode = selectedCollection.displaySortMode {
            listSortDirectionButtons(for: selectedCollection, mode: mode)
        }
    }

    @ViewBuilder
    func listSortDirectionButtons(for selectedCollection: CardCollectionRecord, mode: SortMode) -> some View {
        ForEach(listSortDirections, id: \.self) { direction in
            Button {
                model.setCardCollectionDisplaySort(
                    id: selectedCollection.id,
                    mode: mode,
                    direction: direction
                )
            } label: {
                GrimoraMenuSelectionLabel(
                    title: GrimoraSearchPreferences.directionTitle(direction, for: mode),
                    isSelected: selectedCollection.displaySortDirection == direction
                )
            }
            .accessibilityIdentifier("list-sort-direction-option-\(direction.rawValue)")
        }
    }

    @ViewBuilder
    func rulesetButtons(for selectedCollection: CardCollectionRecord) -> some View {
        ForEach(CardCollectionRuleset.allCases) { ruleset in
            Button {
                model.setCardCollectionRuleset(id: selectedCollection.id, ruleset: ruleset)
            } label: {
                HStack {
                    Text(ruleset.title)
                    if selectedCollection.ruleset == ruleset {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .accessibilityIdentifier("list-ruleset-\(ruleset.rawValue)")
        }
    }

    var listSortDirections: [SearchSortDirection] {
        [.ascending, .descending]
    }

    func listSortTitle(for selectedCollection: CardCollectionRecord) -> String {
        selectedCollection.displaySortMode?.title ?? "List Order"
    }

    func listSortDescription(for selectedCollection: CardCollectionRecord) -> String {
        guard let mode = selectedCollection.displaySortMode else {
            return "List Order"
        }
        return GrimoraSearchPreferences.sortDescription(
            sortMode: mode,
            sortDirection: selectedCollection.displaySortDirection
        )
    }
}

extension CardCollectionViewMode {
    var toolbarTitle: String {
        switch self {
        case .grid:
            "Gallery"
        case .list:
            "List"
        }
    }

    var systemImage: String {
        switch self {
        case .grid:
            "square.grid.2x2"
        case .list:
            "list.bullet"
        }
    }
}
