import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

extension CardCollectionDetailView {
    @ViewBuilder
    func content(snapshot: CardCollectionDetailSnapshot) -> some View {
        if isListViewMode {
            listModeContent(snapshot: snapshot)
        } else {
            gridModeContent(snapshot: snapshot)
        }
    }

    var isListViewMode: Bool {
        model.selectedCollection?.viewMode == .list
    }

    var isGridViewMode: Bool {
        !isListViewMode
    }

    private func gridModeContent(snapshot: CardCollectionDetailSnapshot) -> some View {
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

                            if isLoadingSelectedList {
                                listDetailSkeleton
                            } else if isShowingEmptyListState {
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
                    .cloudSyncRefreshable(model, active: !isSelectingListEntries)
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

    private func listModeContent(snapshot: CardCollectionDetailSnapshot) -> some View {
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

                        if isLoadingSelectedList {
                            listDetailSkeleton
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else if isShowingEmptyListState {
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
                    .cloudSyncRefreshable(model, active: !isSelectingListEntries)
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
        model.selectedCollectionEntries.isEmpty
            && model.selectedCollectionCategories.isEmpty
            && model.selectedCollectionRulesetWarnings.isEmpty
            && !isShowingDescription
    }

    /// True while the selected collection's detail state is still loading off the main thread.
    /// Gated on the selected ID so a stale `.loading` for a different list never shows here.
    var isLoadingSelectedList: Bool {
        if case .loading(let id) = model.listLoadPhase, id == model.selectedCollectionID {
            return true
        }
        return false
    }

    /// Card-shaped placeholders shown the instant a list is tapped, before its cards have
    /// been read. Keeps the layout stable (fixed card aspect ratio) so content streams in
    /// without reflow, per the HIG "show content as soon as possible" guidance.
    var listDetailSkeleton: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: gridZoom.minimumColumnWidth,
                        maximum: gridZoom.maximumColumnWidth
                    ),
                    spacing: 18,
                    alignment: .top
                )
            ],
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(spacing: 0) {
                    // Artwork well, sized by the same fixed card aspect ratio the real tile
                    // reserves, so the row height matches once cards stream in.
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.hairline.color.opacity(0.35))
                        .aspectRatio(cardArtworkAspectRatio, contentMode: .fit)
                    // Approximates the tile's bottom control bar so the skeleton footprint
                    // matches a loaded tile and the loading -> ready swap doesn't jump.
                    Color.clear.frame(height: Self.skeletonBottomBarHeight)
                }
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.cardSurface.color.opacity(0.5))
                }
            }
        }
        .padding(24)
        .accessibilityIdentifier("card-list-detail-skeleton")
    }

    /// Matches `CardGridItemView`'s minimum bottom-bar height so skeleton tiles reserve the
    /// same total footprint as loaded tiles.
    private static let skeletonBottomBarHeight: CGFloat = 60

    private func gridDetailSections(snapshot: CardCollectionDetailSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            if !model.selectedCollectionRulesetWarnings.isEmpty {
                CardCollectionRulesetWarningPanel(
                    warnings: model.selectedCollectionRulesetWarnings,
                    palette: palette
                )
            }

            if let selectedCollection = model.selectedCollection,
               selectedCollection.showsDashboard,
               !snapshot.visibleEntries.isEmpty
            {
                CardCollectionDashboardView(
                    stats: CardCollectionDashboardStats.make(
                        entries: snapshot.visibleEntries,
                        includeLandsInTypes: selectedCollection.dashboardIncludesLands
                    ),
                    includesLands: selectedCollection.dashboardIncludesLands,
                    palette: palette
                ) { includesLands in
                    model.setCardCollectionDashboardIncludesLands(
                        id: selectedCollection.id,
                        includesLands: includesLands
                    )
                }
            }

            if isShowingDescription {
                CardCollectionDescriptionPanel(
                    rtfdData: descriptionRTFDDataBinding,
                    plainText: descriptionPlainTextBinding,
                    palette: palette
                )
            }

            if model.selectedCollectionEntries.isEmpty && model.selectedCollectionCategories.isEmpty {
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
                    Text("No cards in this collection match \(GrimoraSearchHistoryStore.normalizedQuery(model.selectedCollectionSearchText)).")
                }
                .tint(palette.accent.color)
                .frame(maxWidth: .infinity, minHeight: 220)
                .accessibilityIdentifier("empty-list-search-results")
            } else if isReorderingCategories {
                CardCollectionCategoryReorderView(
                    categories: model.selectedCollectionCategories,
                    palette: palette,
                    onRenameCategory: onRenameCategory
                )
            } else {
                ForEach(snapshot.sections) { section in
                    VStack(alignment: .leading, spacing: 28) {
                        CardCollectionCategorySectionView(
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
                                CardCollectionEmptyCategoryView(
                                    palette: palette,
                                    onMoveEntriesToCategory: { entryIDs in
                                        moveEntryIDs(entryIDs, toZone: section.zone, categoryID: section.category?.id)
                                    }
                                )
                            } else {
                                AdaptiveCardGrid(
                                    items: section.entries,
                                    id: { $0.id },
                                    landscapeItemIDs: defaultLandscapeArtworkEntryIDs(for: section.entries),
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
                                    let entryIDs = CardCollectionEntryDragToken.entryIDs(from: tokens)
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
    private func listDetailSections(snapshot: CardCollectionDetailSnapshot) -> some View {
        if !model.selectedCollectionRulesetWarnings.isEmpty {
            CardCollectionRulesetWarningPanel(
                warnings: model.selectedCollectionRulesetWarnings,
                palette: palette
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }

        if let selectedCollection = model.selectedCollection,
           selectedCollection.showsDashboard,
           !snapshot.visibleEntries.isEmpty
        {
            CardCollectionDashboardView(
                stats: CardCollectionDashboardStats.make(
                    entries: snapshot.visibleEntries,
                    includeLandsInTypes: selectedCollection.dashboardIncludesLands
                ),
                includesLands: selectedCollection.dashboardIncludesLands,
                palette: palette
            ) { includesLands in
                model.setCardCollectionDashboardIncludesLands(
                    id: selectedCollection.id,
                    includesLands: includesLands
                )
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }

        if isShowingDescription {
            CardCollectionDescriptionPanel(
                rtfdData: descriptionRTFDDataBinding,
                plainText: descriptionPlainTextBinding,
                palette: palette
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }

        if model.selectedCollectionEntries.isEmpty && model.selectedCollectionCategories.isEmpty {
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
                Text("No cards in this collection match \(GrimoraSearchHistoryStore.normalizedQuery(model.selectedCollectionSearchText)).")
            }
            .tint(palette.accent.color)
            .frame(maxWidth: .infinity, minHeight: 220)
            .accessibilityIdentifier("empty-list-search-results")
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if isReorderingCategories {
            CardCollectionCategoryReorderView(
                categories: model.selectedCollectionCategories,
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
                            CardCollectionTextEmptyCategoryRow(palette: palette)
                                .listRowBackground(listRowBackground)
                                .dropDestination(for: String.self) { tokens, _ in
                                    let entryIDs = CardCollectionEntryDragToken.entryIDs(from: tokens)
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
                                        let entryIDs = CardCollectionEntryDragToken.entryIDs(from: tokens)
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
                    CardCollectionCategorySectionView(
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
        .leading
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
            .onPreferenceChange(CardCollectionEntryFramePreferenceKey.self) { frames in
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
        for entries: [CardCollectionEntryRecord]
    ) -> Set<CardCollectionEntryRecord.ID> {
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

private struct CardCollectionRulesetWarningPanel: View {
    @Environment(GrimoraAppModel.self) private var model

    var warnings: [CardCollectionRulesetWarning]
    var palette: GrimoraPalette

    private var hasCommanderMissing: Bool {
        warnings.contains { $0.id == "commander-missing" }
    }

    private var hasSingletonDuplicates: Bool {
        warnings.contains { $0.id.hasPrefix("commander-singleton") }
    }

    /// Mainboard cards eligible to be promoted to the commander zone.
    private var commanderCandidates: [CardCollectionEntryRecord] {
        model.selectedCollectionEntries.filter { $0.zone == .mainboard }
    }

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

            if hasCommanderMissing || hasSingletonDuplicates {
                HStack(spacing: 10) {
                    if hasCommanderMissing {
                        chooseCommanderMenu
                    }
                    if hasSingletonDuplicates {
                        removeDuplicatesButton
                    }
                }
                .font(.caption.weight(.semibold))
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

    @ViewBuilder
    private var chooseCommanderMenu: some View {
        Menu {
            if commanderCandidates.isEmpty {
                Text("Add a card to the deck first")
            } else {
                ForEach(commanderCandidates) { entry in
                    Button(entry.card?.name ?? "Card") {
                        model.moveCardCollectionEntry(id: entry.id, toZone: .commander)
                    }
                }
            }
        } label: {
            Label("Choose Commander", systemImage: "crown")
        }
        .accessibilityIdentifier("list-fix-commander-missing")
    }

    private var removeDuplicatesButton: some View {
        Button {
            if let listID = model.selectedCollectionID {
                model.deduplicateCommander(listID: listID)
            }
        } label: {
            Label("Remove Duplicate Copies", systemImage: "rectangle.stack.badge.minus")
        }
        .accessibilityIdentifier("list-fix-commander-duplicates")
    }
}
