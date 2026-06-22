import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

extension CardListDetailView {
    func header(snapshot: CardListDetailSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            #if os(iOS)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedList?.name ?? "List")
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
                Text(selectedListEntryCountText)
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
            model.selectedListSearchText
        } set: { newValue in
            if !GrimoraSearchHistoryStore.normalizedQuery(newValue).isEmpty {
                isReorderingCategories = false
            }
            model.setSelectedListSearchDraft(newValue)
        }
    }

    #if os(macOS)
    @ToolbarContentBuilder
    func macListToolbar(snapshot: CardListDetailSnapshot) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let selectedList = model.selectedList {
                listViewModePicker(for: selectedList)
                rulesetMenu(for: selectedList)
                listSortMenu(for: selectedList)

                Button {
                    model.setCardListDashboardVisibility(
                        id: selectedList.id,
                        showsDashboard: !selectedList.showsDashboard
                    )
                } label: {
                    Label(
                        selectedList.showsDashboard ? "Hide Stats" : "Show Stats",
                        systemImage: "chart.bar.xaxis"
                    )
                    .labelStyle(.iconOnly)
                }
                .help(selectedList.showsDashboard ? "Hide Stats" : "Show Stats")
                .accessibilityIdentifier("toggle-list-dashboard-button")
                .accessibilityValue(selectedList.showsDashboard ? "Shown" : "Hidden")

                Button {
                    toggleDescription(for: selectedList)
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
                    onCreateCategory(selectedList)
                } label: {
                    Label("New Category", systemImage: "folder.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .help("New Category")
                .accessibilityIdentifier("create-list-category-button")

                macListMoreMenu(for: selectedList, snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    func macListMoreMenu(
        for selectedList: CardListRecord,
        snapshot: CardListDetailSnapshot
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
                if model.selectedListCategories.count > 1 {
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
                    importMode = .append(selectedList.id)
                } label: {
                    Text("Import...")
                }
                .accessibilityIdentifier("import-list-detail-button")

                Button {
                    isShowingExportSheet = true
                } label: {
                    Text("Export List...")
                }
                .accessibilityIdentifier("export-list-button")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .help("More List Actions")
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
    func touchListToolbar(snapshot: CardListDetailSnapshot) -> some ToolbarContent {
        if let selectedList = model.selectedList {
            ToolbarItem(placement: .topBarTrailing) {
                listViewModePicker(for: selectedList)
                    #if os(iOS)
                    .fixedSize(horizontal: true, vertical: false)
                    #endif
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            touchListActionsMenu(snapshot: snapshot)
        }
    }

    @ViewBuilder
    func touchListActionsMenu(snapshot: CardListDetailSnapshot) -> some View {
        if let selectedList = model.selectedList {
            Menu {
                #if os(visionOS)
                visionListMenuContent(for: selectedList, snapshot: snapshot)
                #else
                touchListMenuContent(for: selectedList, snapshot: snapshot)
                #endif
            } label: {
                listActionsMenuLabel
                    .accessibilityIdentifier("list-detail-actions-menu")
            }
            .help("List Actions")
            .accessibilityLabel("List Actions")
        }
    }

    // Standard system-styled menu button: the previous capsule/material chrome
    // only wrapped the ellipsis (not the adjacent picker), which read as
    // inconsistent and cluttered. Letting the toolbar style the button keeps the
    // trailing cluster clean and on platform.
    @ViewBuilder
    private var listActionsMenuLabel: some View {
        Label("List Actions", systemImage: "ellipsis")
            .labelStyle(.iconOnly)
            .imageScale(.large)
    }

    #if os(visionOS)
    @ViewBuilder
    func visionListMenuContent(
        for selectedList: CardListRecord,
        snapshot: CardListDetailSnapshot
    ) -> some View {
        Button {
            onRenameList(selectedList)
        } label: {
            Text("Rename List")
        }
        .accessibilityIdentifier("rename-list-\(selectedList.name)")

        Button {
            model.undoLastListAction()
        } label: {
            Text("Undo")
        }
        .disabled(!model.canUndoListAction)
        .accessibilityIdentifier("undo-list-action-button")

        Menu {
            listSortButtons(for: selectedList)
        } label: {
            Text("Sort")
        }
        .accessibilityIdentifier("list-sort-menu")

        Menu {
            rulesetButtons(for: selectedList)
        } label: {
            Text("Ruleset")
        }
        .accessibilityIdentifier("list-ruleset-menu")

        Button {
            model.setCardListDashboardVisibility(
                id: selectedList.id,
                showsDashboard: !selectedList.showsDashboard
            )
        } label: {
            Text(selectedList.showsDashboard ? "Hide Stats" : "Show Stats")
        }
        .accessibilityIdentifier("toggle-list-dashboard-button")
        .accessibilityValue(selectedList.showsDashboard ? "Shown" : "Hidden")

        Button {
            toggleDescription(for: selectedList)
        } label: {
            Text("Description")
        }
        .accessibilityIdentifier("toggle-list-description-button")

        Button {
            importMode = .append(selectedList.id)
        } label: {
            Text("Import")
        }
        .accessibilityIdentifier("import-list-detail-button")

        Button {
            isShowingExportSheet = true
        } label: {
            Text("Export List")
        }
        .accessibilityIdentifier("export-list-button")

        Button {
            onCreateCategory(selectedList)
        } label: {
            Text("New Category")
        }
        .accessibilityIdentifier("create-list-category-button")

        if model.selectedListCategories.count > 1 {
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

        if !model.selectedListEntries.isEmpty {
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
        for selectedList: CardListRecord,
        snapshot: CardListDetailSnapshot
    ) -> some View {
        Section("List") {
            Button {
                onRenameList(selectedList)
            } label: {
                Text("Rename List")
            }
            .accessibilityIdentifier("rename-list-\(selectedList.name)")

            Button {
                model.undoLastListAction()
            } label: {
                Text("Undo")
            }
            .disabled(!model.canUndoListAction)
            .accessibilityIdentifier("undo-list-action-button")
        }

        listSortButtons(for: selectedList)

        Section("View") {
            Button {
                model.setCardListDashboardVisibility(
                    id: selectedList.id,
                    showsDashboard: !selectedList.showsDashboard
                )
            } label: {
                Text(selectedList.showsDashboard ? "Hide Stats" : "Show Stats")
            }
            .accessibilityIdentifier("toggle-list-dashboard-button")
            .accessibilityValue(selectedList.showsDashboard ? "Shown" : "Hidden")

            Button {
                toggleDescription(for: selectedList)
            } label: {
                Text("Description")
            }
            .accessibilityIdentifier("toggle-list-description-button")
        }

        Section("Transfer") {
            Button {
                importMode = .append(selectedList.id)
            } label: {
                Text("Import")
            }
            .accessibilityIdentifier("import-list-detail-button")

            Button {
                isShowingExportSheet = true
            } label: {
                Text("Export List")
            }
            .accessibilityIdentifier("export-list-button")
        }

        Section("Organize") {
            Button {
                onCreateCategory(selectedList)
            } label: {
                Text("New Category")
            }
            .accessibilityIdentifier("create-list-category-button")

            if model.selectedListCategories.count > 1 {
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

            if !model.selectedListEntries.isEmpty {
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
                Text(selectedListEntryCountText)
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
            rulesetButtons(for: selectedList)
        }
    }
    #endif

    @ViewBuilder
    func listViewModePicker(for selectedList: CardListRecord) -> some View {
        Picker("View", selection: listViewModeBinding(for: selectedList)) {
            ForEach(CardListViewMode.allCases) { mode in
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
        .accessibilityValue(selectedList.viewMode.toolbarTitle)
        .accessibilityIdentifier("card-list-view-mode-picker")
    }

    func listViewModeBinding(for selectedList: CardListRecord) -> Binding<CardListViewMode> {
        Binding {
            model.selectedList?.viewMode ?? selectedList.viewMode
        } set: { mode in
            guard mode != model.selectedList?.viewMode else {
                return
            }
            model.setCardListViewMode(id: selectedList.id, mode: mode)
        }
    }

    @ViewBuilder
    func rulesetMenu(for selectedList: CardListRecord) -> some View {
        Menu {
            rulesetButtons(for: selectedList)
        } label: {
            Text(selectedList.ruleset.title)
        }
        .help("Ruleset")
        .accessibilityIdentifier("list-ruleset-menu")
        .accessibilityValue(selectedList.ruleset.title)
    }

    @ViewBuilder
    func listSortMenu(for selectedList: CardListRecord) -> some View {
        Menu {
            listSortButtons(for: selectedList)
        } label: {
            Label("Sort List", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .help("Sort List: \(listSortDescription(for: selectedList))")
        .accessibilityIdentifier("list-sort-menu")
        .accessibilityLabel("Sort List")
        .accessibilityValue(listSortDescription(for: selectedList))
    }

    @ViewBuilder
    func listSortButtons(for selectedList: CardListRecord) -> some View {
        Section("Sort") {
            listSortModeButtons(for: selectedList)
        }

        if let mode = selectedList.displaySortMode {
            Section("Order") {
                listSortDirectionButtons(for: selectedList, mode: mode)
            }
        }
    }

    @ViewBuilder
    func listSortModeButtons(for selectedList: CardListRecord) -> some View {
        Button {
            model.setCardListDisplaySort(
                id: selectedList.id,
                mode: nil,
                direction: selectedList.displaySortDirection
            )
        } label: {
            GrimoraMenuSelectionLabel(
                title: "List Order",
                isSelected: selectedList.displaySortMode == nil
            )
        }
        .accessibilityIdentifier("list-sort-option-list-order")

        ForEach(SortMode.allCases) { mode in
            Button {
                model.setCardListDisplaySort(
                    id: selectedList.id,
                    mode: mode,
                    direction: selectedList.displaySortDirection
                )
            } label: {
                GrimoraMenuSelectionLabel(
                    title: mode.title,
                    isSelected: selectedList.displaySortMode == mode
                )
            }
            .accessibilityIdentifier("list-sort-option-\(mode.rawValue)")
        }
    }

    @ViewBuilder
    func listSortDirectionButtons(for selectedList: CardListRecord) -> some View {
        if let mode = selectedList.displaySortMode {
            listSortDirectionButtons(for: selectedList, mode: mode)
        }
    }

    @ViewBuilder
    func listSortDirectionButtons(for selectedList: CardListRecord, mode: SortMode) -> some View {
        ForEach(listSortDirections, id: \.self) { direction in
            Button {
                model.setCardListDisplaySort(
                    id: selectedList.id,
                    mode: mode,
                    direction: direction
                )
            } label: {
                GrimoraMenuSelectionLabel(
                    title: GrimoraSearchPreferences.directionTitle(direction, for: mode),
                    isSelected: selectedList.displaySortDirection == direction
                )
            }
            .accessibilityIdentifier("list-sort-direction-option-\(direction.rawValue)")
        }
    }

    @ViewBuilder
    func rulesetButtons(for selectedList: CardListRecord) -> some View {
        ForEach(CardListRuleset.allCases) { ruleset in
            Button {
                model.setCardListRuleset(id: selectedList.id, ruleset: ruleset)
            } label: {
                HStack {
                    Text(ruleset.title)
                    if selectedList.ruleset == ruleset {
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

    func listSortTitle(for selectedList: CardListRecord) -> String {
        selectedList.displaySortMode?.title ?? "List Order"
    }

    func listSortDescription(for selectedList: CardListRecord) -> String {
        guard let mode = selectedList.displaySortMode else {
            return "List Order"
        }
        return GrimoraSearchPreferences.sortDescription(
            sortMode: mode,
            sortDirection: selectedList.displaySortDirection
        )
    }
}

extension CardListViewMode {
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
