import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

extension CardListDetailView {
    @ViewBuilder
    func content(snapshot: CardListDetailSnapshot) -> some View {
        if isListViewMode {
            listModeContent(snapshot: snapshot)
        } else {
            gridModeContent(snapshot: snapshot)
        }
    }

    var isListViewMode: Bool {
        model.selectedList?.viewMode == .list
    }

    var isGridViewMode: Bool {
        !isListViewMode
    }

    private func gridModeContent(snapshot: CardListDetailSnapshot) -> some View {
        ScrollViewReader { proxy in
            listSelectionContainer(
                ZStack {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            header(snapshot: snapshot)
                                .id(Self.listDetailTopAnchorID)
                                .jumpToTopLegacyOffsetReader(coordinateSpaceName: Self.entrySelectionCoordinateSpace)
                            Divider()
                                .overlay(palette.hairline.color)

                            if isShowingEmptyListState {
                                ContentUnavailableView("Empty List", systemImage: "list.bullet.rectangle")
                                    .tint(palette.accent.color)
                                    .frame(maxWidth: .infinity, minHeight: 360)
                                    .padding(24)
                                    .accessibilityIdentifier("empty-card-list")
                            } else {
                                gridDetailSections(snapshot: snapshot)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .cardArtworkViewport()
                    .coordinateSpace(name: Self.entrySelectionCoordinateSpace)
                    .accessibilityIdentifier("card-list-detail-scroll")
                    .simultaneousGesture(isSelectingListEntries ? selectionDragGesture : nil)
                    .overlay(alignment: .topLeading) {
                        if isSelectingListEntries {
                            selectionDragOverlay
                        }
                    }
                    .jumpToTopScrollTracking($listJumpToTopState)
                }
                .jumpToTopButtonInset(
                    isVisible: listJumpToTopState.showsButton,
                    accessibilityIdentifier: "card-list-detail-jump-to-top-button"
                ) {
                    scrollListDetailToTop(using: proxy)
                }
            )
        }
    }

    private func listModeContent(snapshot: CardListDetailSnapshot) -> some View {
        ScrollViewReader { proxy in
            listSelectionContainer(
                ZStack {
                    List {
                        header(snapshot: snapshot)
                            .id(Self.listDetailTopAnchorID)
                            .jumpToTopLegacyOffsetReader(coordinateSpaceName: Self.entrySelectionCoordinateSpace)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        if isShowingEmptyListState {
                            ContentUnavailableView("Empty List", systemImage: "list.bullet.rectangle")
                                .tint(palette.accent.color)
                                .frame(maxWidth: .infinity, minHeight: 360)
                                .padding(24)
                                .accessibilityIdentifier("empty-card-list")
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            listDetailSections(snapshot: snapshot)
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .coordinateSpace(name: Self.entrySelectionCoordinateSpace)
                    .accessibilityIdentifier("card-list-detail-scroll")
                    .simultaneousGesture(isSelectingListEntries ? selectionDragGesture : nil)
                    .overlay(alignment: .topLeading) {
                        if isSelectingListEntries {
                            selectionDragOverlay
                        }
                    }
                    .jumpToTopScrollTracking($listJumpToTopState)
                }
                .jumpToTopButtonInset(
                    isVisible: listJumpToTopState.showsButton,
                    accessibilityIdentifier: "card-list-detail-jump-to-top-button"
                ) {
                    scrollListDetailToTop(using: proxy)
                }
            )
        }
    }

    private func scrollListDetailToTop(using proxy: ScrollViewProxy) {
        let scroll = {
            proxy.scrollTo(Self.listDetailTopAnchorID, anchor: .top)
            listJumpToTopState = .top
        }

        if reduceMotion {
            scroll()
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                scroll()
            }
        }
    }

    private var isShowingEmptyListState: Bool {
        model.selectedListEntries.isEmpty
            && model.selectedListCategories.isEmpty
            && model.selectedListRulesetWarnings.isEmpty
            && !isShowingDescription
    }

    private func gridDetailSections(snapshot: CardListDetailSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            if !model.selectedListRulesetWarnings.isEmpty {
                CardListRulesetWarningPanel(
                    warnings: model.selectedListRulesetWarnings,
                    palette: palette
                )
            }

            if let selectedList = model.selectedList,
               selectedList.showsDashboard,
               !snapshot.visibleEntries.isEmpty
            {
                CardListDashboardView(
                    stats: CardListDashboardStats.make(
                        entries: snapshot.visibleEntries,
                        includeLandsInTypes: selectedList.dashboardIncludesLands
                    ),
                    includesLands: selectedList.dashboardIncludesLands,
                    palette: palette
                ) { includesLands in
                    model.setCardListDashboardIncludesLands(
                        id: selectedList.id,
                        includesLands: includesLands
                    )
                }
            }

            if isShowingDescription {
                CardListDescriptionPanel(
                    rtfdData: descriptionRTFDDataBinding,
                    plainText: descriptionPlainTextBinding,
                    palette: palette
                )
            }

            if model.selectedListEntries.isEmpty && model.selectedListCategories.isEmpty {
                ContentUnavailableView("Empty List", systemImage: "list.bullet.rectangle")
                    .tint(palette.accent.color)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .accessibilityIdentifier("empty-card-list")
            } else if let listSearchUnsupportedMessage {
                ContentUnavailableView {
                    Label("Unsupported Search", systemImage: "magnifyingglass")
                } description: {
                    Text(listSearchUnsupportedMessage)
                }
                .tint(palette.accent.color)
                .frame(maxWidth: .infinity, minHeight: 220)
                .accessibilityIdentifier("unsupported-list-search")
            } else if isListSearchActive && snapshot.visibleEntries.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Cards", systemImage: "magnifyingglass")
                } description: {
                    Text("No cards in this list match \(GrimoraSearchHistoryStore.normalizedQuery(model.selectedListSearchText)).")
                }
                .tint(palette.accent.color)
                .frame(maxWidth: .infinity, minHeight: 220)
                .accessibilityIdentifier("empty-list-search-results")
            } else if isReorderingCategories {
                CardListCategoryReorderView(
                    categories: model.selectedListCategories,
                    palette: palette,
                    onRenameCategory: onRenameCategory
                )
            } else {
                ForEach(snapshot.sections) { section in
                    VStack(alignment: .leading, spacing: 28) {
                        CardListCategorySectionView(
                            section: section,
                            palette: palette,
                            isCollapsed: isSectionCollapsed(section),
                            onToggleCollapsed: { toggleCollapsedSection(section) },
                            onMoveEntriesToCategory: { entryIDs in
                                moveEntryIDs(entryIDs, toZone: section.zone, categoryID: section.category?.id)
                            },
                            onRenameCategory: onRenameCategory
                        )

                        if !isSectionCollapsed(section) {
                            if section.entries.isEmpty {
                                CardListEmptyCategoryView(
                                    palette: palette,
                                    onMoveEntriesToCategory: { entryIDs in
                                        moveEntryIDs(entryIDs, toZone: section.zone, categoryID: section.category?.id)
                                    }
                                )
                            } else {
                                AdaptiveCardGrid(
                                    items: section.entries,
                                    id: { $0.id },
                                    landscapeItemIDs: defaultLandscapeArtworkEntryIDs(for: section.entries)
                                        .union(landscapeArtworkEntryIDs),
                                    minimumColumnWidth: gridZoom.minimumColumnWidth,
                                    maximumColumnWidth: gridZoom.maximumColumnWidth,
                                    horizontalAlignment: listGridHorizontalAlignment,
                                    fillsSingleColumn: listGridFillsSingleColumn
                                ) { entry in
                                    listEntryView(
                                        entry,
                                        displayedEntries: snapshot.expandedEntries
                                    )
                                }
                                #if os(macOS) || os(iOS) || os(visionOS)
                                .dropDestination(for: String.self) { tokens, _ in
                                    let entryIDs = CardListEntryDragToken.entryIDs(from: tokens)
                                    guard !entryIDs.isEmpty else {
                                        return false
                                    }
                                    moveEntryIDs(entryIDs, toZone: section.zone, categoryID: section.category?.id)
                                    return true
                                }
                                #endif
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("list-category-section-content-\(section.title)")
                }
            }
        }
        .padding(24)
        .background {
            listBlankSpaceTapTarget
        }
    }

    @ViewBuilder
    private func listDetailSections(snapshot: CardListDetailSnapshot) -> some View {
        if !model.selectedListRulesetWarnings.isEmpty {
            CardListRulesetWarningPanel(
                warnings: model.selectedListRulesetWarnings,
                palette: palette
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }

        if let selectedList = model.selectedList,
           selectedList.showsDashboard,
           !snapshot.visibleEntries.isEmpty
        {
            CardListDashboardView(
                stats: CardListDashboardStats.make(
                    entries: snapshot.visibleEntries,
                    includeLandsInTypes: selectedList.dashboardIncludesLands
                ),
                includesLands: selectedList.dashboardIncludesLands,
                palette: palette
            ) { includesLands in
                model.setCardListDashboardIncludesLands(
                    id: selectedList.id,
                    includesLands: includesLands
                )
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }

        if isShowingDescription {
            CardListDescriptionPanel(
                rtfdData: descriptionRTFDDataBinding,
                plainText: descriptionPlainTextBinding,
                palette: palette
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }

        if model.selectedListEntries.isEmpty && model.selectedListCategories.isEmpty {
            ContentUnavailableView("Empty List", systemImage: "list.bullet.rectangle")
                .tint(palette.accent.color)
                .frame(maxWidth: .infinity, minHeight: 220)
                .accessibilityIdentifier("empty-card-list")
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else if let listSearchUnsupportedMessage {
            ContentUnavailableView {
                Label("Unsupported Search", systemImage: "magnifyingglass")
            } description: {
                Text(listSearchUnsupportedMessage)
            }
            .tint(palette.accent.color)
            .frame(maxWidth: .infinity, minHeight: 220)
            .accessibilityIdentifier("unsupported-list-search")
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if isListSearchActive && snapshot.visibleEntries.isEmpty {
            ContentUnavailableView {
                Label("No Matching Cards", systemImage: "magnifyingglass")
            } description: {
                Text("No cards in this list match \(GrimoraSearchHistoryStore.normalizedQuery(model.selectedListSearchText)).")
            }
            .tint(palette.accent.color)
            .frame(maxWidth: .infinity, minHeight: 220)
            .accessibilityIdentifier("empty-list-search-results")
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if isReorderingCategories {
            CardListCategoryReorderView(
                categories: model.selectedListCategories,
                palette: palette,
                onRenameCategory: onRenameCategory
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(snapshot.sections) { section in
                Section {
                    if !isSectionCollapsed(section) {
                        if section.entries.isEmpty {
                            CardListTextEmptyCategoryRow(palette: palette)
                                .listRowBackground(listRowBackground)
                                .dropDestination(for: String.self) { tokens, _ in
                                    let entryIDs = CardListEntryDragToken.entryIDs(from: tokens)
                                    guard !entryIDs.isEmpty else {
                                        return false
                                    }
                                    moveEntryIDs(entryIDs, toZone: section.zone, categoryID: section.category?.id)
                                    return true
                                }
                        } else {
                            ForEach(section.entries) { entry in
                                listEntryTextRowView(entry)
                                    .listRowBackground(listRowBackground)
                                    .dropDestination(for: String.self) { tokens, _ in
                                        let entryIDs = CardListEntryDragToken.entryIDs(from: tokens)
                                        guard !entryIDs.isEmpty else {
                                            return false
                                        }
                                        moveEntryIDs(entryIDs, toZone: section.zone, categoryID: section.category?.id)
                                        return true
                                    }
                            }
                        }
                    }
                } header: {
                    CardListCategorySectionView(
                        section: section,
                        palette: palette,
                        isCollapsed: isSectionCollapsed(section),
                        onToggleCollapsed: { toggleCollapsedSection(section) },
                        onMoveEntriesToCategory: { entryIDs in
                            moveEntryIDs(entryIDs, toZone: section.zone, categoryID: section.category?.id)
                        },
                        onRenameCategory: onRenameCategory
                    )
                    .textCase(nil)
                    .padding(.vertical, 6)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("list-category-section-content-\(section.title)")
            }
        }
    }

    private var listRowBackground: Color {
        palette.cardSurface.color.opacity(0.36)
    }

    private var listGridHorizontalAlignment: AdaptiveCardGridHorizontalAlignment {
        #if os(iOS)
        .center
        #else
        .leading
        #endif
    }

    private var listGridFillsSingleColumn: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    @ViewBuilder
    func listSelectionContainer<Content: View>(_ content: Content) -> some View {
        content
            .onPreferenceChange(CardListEntryFramePreferenceKey.self) { frames in
                updateEntrySelectionFrames(frames)
            }
            .background {
                BlankSpaceTapTarget {
                    clearListEntrySelection()
                }
            }
        }

    private var listBlankSpaceTapTarget: some View {
        BlankSpaceTapTarget {
            clearListEntrySelection()
        }
    }

    private func defaultLandscapeArtworkEntryIDs(
        for entries: [CardListEntryRecord]
    ) -> Set<CardListEntryRecord.ID> {
        Set(entries.compactMap { entry in
            guard let card = entry.card else {
                return nil
            }

            return cardUsesDefaultLandscapeArtworkLayout(card) ? entry.id : nil
        })
    }

    var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.entrySelectionCoordinateSpace))
            .onChanged { value in
                updateSelectionDrag(value)
            }
            .onEnded { value in
                updateSelectionDrag(value)
                finishSelectionDrag()
            }
    }

    @ViewBuilder
    var selectionDragOverlay: some View {
        if let rect = currentSelectionDragRect {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.accent.color.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(palette.accent.color.opacity(0.55), lineWidth: 1)
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct CardListRulesetWarningPanel: View {
    var warnings: [CardListRulesetWarning]
    var palette: GrimoraPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ruleset Warnings", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(warnings) { warning in
                    Text(warning.message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 720, alignment: .leading)
        .background(palette.cardSurface.color.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.accent.color.opacity(0.34), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("list-ruleset-warning-panel")
    }
}
