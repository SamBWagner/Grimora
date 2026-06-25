#if os(macOS)
import AppKit
import GrimoraCore
import SwiftUI

struct MacSearchFloatingHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(GrimoraAppModel.self) private var model
    @State private var showsSearchLoadingIndicator = false
    @State private var searchActivationFeedbackTrigger = 0
    @State private var createListFeedbackTrigger = 0
    var isExpanded: Bool
    @Binding var isSearchFocused: Bool
    var focusRequestID: Int
    var onCreateListFromSearch: () -> Void
    var onOpenAdvancedSearch: () -> Void
    var onMouseDown: () -> Void = {}
    var onSearchActivated: () -> Void = {}

    static let expandedContentInset: CGFloat = 148
    static let minimumExpandedSurfaceWidth: CGFloat = expandedSearchAreaMinimumWidth + (expandedContentPadding * 2)

    private static let searchLoadingIndicatorDelayNanoseconds: UInt64 = 200_000_000
    private static let searchFieldHeight: CGFloat = 34
    private static let expandedContentPadding: CGFloat = 14
    private static let collapsedContentPadding: CGFloat = 10
    private static let expandedSearchAreaMinimumWidth: CGFloat = 200

    var body: some View {
        floatingSurface {
            VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
                searchArea(isExpanded: isExpanded)

                if isExpanded {
                    ViewThatFits(in: .horizontal) {
                        searchControlRow
                        compactSearchControlRow
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(isExpanded ? Self.expandedContentPadding : Self.collapsedContentPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: isExpanded ? 1180 : 520)
        .clipShape(RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
        .background {
            ZStack {
                SearchFocusDismissalBridge(isFocused: $isSearchFocused)
                SearchHeaderMouseDownBridge {
                    onMouseDown()
                    if !isExpanded {
                        onSearchActivated()
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.smooth(duration: 0.24), value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isExpanded ? "mac-search-expanded-header" : "mac-search-collapsed-header")
        .task(id: searchIsBusy) {
            let searchIsBusy = searchIsBusy
            guard searchIsBusy else {
                showsSearchLoadingIndicator = false
                return
            }

            try? await Task.sleep(nanoseconds: Self.searchLoadingIndicatorDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            showsSearchLoadingIndicator = true
        }
        .animation(.easeInOut(duration: 0.14), value: showsSearchLoadingIndicator)
    }

    private var searchIsBusy: Bool {
        model.isSearchingCards
    }

    private func searchArea(isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isExpanded {
                    searchFieldWithLoadingIndicator(height: Self.searchFieldHeight)
                        .layoutPriority(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.searchFieldHeight)
                        .accessibilityIdentifier("mac-expanded-search-bar")
                    advancedSearchButton
                } else {
                    compactSearchButton
                        .layoutPriority(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.searchFieldHeight)
                }
            }
        }
        .frame(minWidth: isExpanded ? Self.expandedSearchAreaMinimumWidth : nil, maxWidth: .infinity)
    }

    private var compactSearchButton: some View {
        Button {
            searchActivationFeedbackTrigger += 1
            onSearchActivated()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .imageScale(.small)

                Text(model.searchText.isEmpty ? searchPlaceholder : model.searchText)
                    .lineLimit(1)
                    .foregroundStyle(model.searchText.isEmpty ? palette.secondaryText.color : palette.primaryText.color)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(GrimoraCapsuleSurfaceButtonStyle(palette: palette))
        .contentShape(searchFieldShape)
        .focusable(false)
        .accessibilityIdentifier("mac-compact-search-bar")
        .grimoraOpenFeedback(trigger: searchActivationFeedbackTrigger)
    }

    private var searchControlRow: some View {
        HStack(spacing: 8) {
            refinementRow
            Spacer(minLength: 12)
            createListButton
        }
        .controlSize(.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactSearchControlRow: some View {
        HStack(spacing: 8) {
            moreOptionsMenu
            Spacer(minLength: 12)
            createListButton
        }
        .controlSize(.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Permanent Advanced Search affordance pinned to the trailing edge of the
    /// search field — the discoverable, always-visible entry point that mirrors
    /// the ⇧⌘F menu command. Icon-only so it reads as a search accessory rather
    /// than competing with the Sort/Printings/Create List controls below.
    private var advancedSearchButton: some View {
        Button(action: onOpenAdvancedSearch) {
            Image(systemName: "slider.horizontal.3")
                .imageScale(.medium)
                .frame(width: Self.searchFieldHeight, height: Self.searchFieldHeight)
                .contentShape(.rect)
        }
        .buttonStyle(GrimoraCapsuleSurfaceButtonStyle(palette: palette))
        .clipShape(searchFieldShape)
        .focusable(false)
        .help("Advanced Search (⇧⌘F)")
        .accessibilityLabel("Advanced Search")
        .accessibilityIdentifier("advanced-search-launch-button")
    }

    private var createListButton: some View {
        Button {
            createListFeedbackTrigger += 1
            onCreateListFromSearch()
        } label: {
            Text("Create List")
        }
        .controlSize(.regular)
        .accessibilityIdentifier("create-list-from-search-button")
        .disabled(!model.canCreateListFromCurrentSearch)
        .grimoraSelectionFeedback(trigger: createListFeedbackTrigger)
    }

    private func nativeSearchField(
        height: CGFloat,
        allowsFocus: Bool = true
    ) -> some View {
        NativeMacSearchField(
            text: searchTextBinding,
            isFocused: allowsFocus ? $isSearchFocused : .constant(false),
            focusRequestID: allowsFocus ? focusRequestID : -1,
            placeholder: searchPlaceholder,
            recentSearches: model.visibleSearchHistory,
            onClearRecentSearches: model.clearSearchHistory,
            onSubmit: {
                Task {
                    await model.submitSearch()
                }
            }
        )
        .frame(height: height)
        .clipShape(searchFieldShape)
        .overlay {
            searchFieldShape
                .strokeBorder(
                    Color.accentColor.opacity(allowsFocus && isSearchFocused ? 0.95 : 0),
                    lineWidth: 2
                )
                .padding(1)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.12), value: isSearchFocused)
    }

    private func searchFieldWithLoadingIndicator(height: CGFloat) -> some View {
        nativeSearchField(height: height)
            .overlay(alignment: .trailing) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
                    .padding(.trailing, 10)
                    .opacity(showsSearchLoadingIndicator ? 1 : 0)
                    .accessibilityLabel(searchLoadingAccessibilityLabel)
                    .accessibilityHidden(!showsSearchLoadingIndicator)
                    .allowsHitTesting(false)
            }
    }

    private var searchTextBinding: Binding<String> {
        Binding {
            model.searchText
        } set: { newValue in
            model.setSearchDraft(newValue)
        }
    }

    private var searchLoadingAccessibilityLabel: String {
        "Searching cards"
    }

    private var refinementRow: some View {
        HStack(spacing: 8) {
            sortMenu
            orderMenu
            printingModeMenu
        }
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var sortMenu: some View {
        MacSearchRefinementMenu(
            title: "Sort: \(model.sortMode.title)",
            accessibilityIdentifier: "search-sort-menu",
            helpText: "Sort search results"
        ) {
            sortPicker
        }
    }

    private var orderMenu: some View {
        MacSearchRefinementMenu(
            title: orderTitle,
            accessibilityIdentifier: "search-order-menu",
            helpText: "Search result order"
        ) {
            orderPicker
        }
    }

    private var printingModeMenu: some View {
        MacSearchRefinementMenu(
            title: model.printingDisplayMode.title,
            accessibilityIdentifier: "printing-display-mode-picker",
            helpText: "Choose which printings to show",
            accessibilityValue: model.printingDisplayMode.title
        ) {
            printingModeButtons
        }
    }

    private var moreOptionsMenu: some View {
        MacSearchRefinementPopoverButton(
            title: "More Options",
            accessibilityIdentifier: "search-more-options-menu",
            helpText: "Search sorting and display options"
        ) { dismiss in
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("More Options")
                        .font(.headline)

                    Spacer(minLength: 12)

                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Close More Options")
                    .accessibilityIdentifier("search-more-options-panel-close-button")
                }

                SearchRefinementPanelSection(title: "Sort") {
                    sortPicker
                    orderPicker
                }

                SearchRefinementPanelSection(title: "Printings") {
                    printingModeButtons
                }
            }
            .padding(14)
            .frame(minWidth: 260, alignment: .leading)
            .accessibilityIdentifier("search-more-options-panel")
        }
    }

    private var sortPicker: some View {
        ForEach(SortMode.allCases) { mode in
            Button {
                model.sortMode = mode
            } label: {
                GrimoraMenuSelectionLabel(title: mode.title, isSelected: model.sortMode == mode)
            }
            .accessibilityIdentifier("search-sort-option-\(mode.rawValue)")
        }
    }

    private var orderPicker: some View {
        ForEach(searchSortDirections, id: \.self) { direction in
            Button {
                model.sortDirection = direction
            } label: {
                GrimoraMenuSelectionLabel(
                    title: GrimoraSearchPreferences.directionTitle(direction, for: model.sortMode),
                    isSelected: model.sortDirection == direction
                )
            }
            .accessibilityIdentifier("search-sort-direction-option-\(direction.rawValue)")
        }
    }

    private var printingModeButtons: some View {
        ForEach(PrintingDisplayMode.allCases) { mode in
            Button {
                model.printingDisplayMode = mode
            } label: {
                GrimoraMenuSelectionLabel(
                    title: mode.title,
                    isSelected: model.printingDisplayMode == mode
                )
            }
            .accessibilityIdentifier("printing-mode-\(mode.rawValue)")
        }
    }

    private var searchPlaceholder: String {
        "Search cards"
    }

    private var orderTitle: String {
        GrimoraSearchPreferences.directionTitle(model.sortDirection, for: model.sortMode)
    }

    private var searchSortDirections: [SearchSortDirection] {
        [.ascending, .descending]
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    @ViewBuilder
    private func floatingSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 14) {
                content()
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
            }
        } else {
            content()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                        .stroke(palette.hairline.color.opacity(0.75), lineWidth: 1)
                }
        }
    }

    private var surfaceCornerRadius: CGFloat {
        isExpanded ? 18 : Self.collapsedSurfaceCornerRadius
    }

    private static var collapsedSurfaceCornerRadius: CGFloat {
        (searchFieldHeight + collapsedContentPadding * 2) / 2
    }

    private var searchFieldShape: Capsule {
        Capsule(style: .continuous)
    }
}

private struct SearchRefinementPanelSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SearchHeaderMouseDownBridge: NSViewRepresentable {
    var onMouseDown: () -> Void

    func makeNSView(context: Context) -> SearchHeaderMouseDownView {
        let view = SearchHeaderMouseDownView()
        context.coordinator.hostView = view
        context.coordinator.startMonitoringIfNeeded()
        return view
    }

    func updateNSView(_ view: SearchHeaderMouseDownView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostView = view
        context.coordinator.startMonitoringIfNeeded()
    }

    static func dismantleNSView(_ nsView: SearchHeaderMouseDownView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: @unchecked Sendable {
        var parent: SearchHeaderMouseDownBridge
        weak var hostView: SearchHeaderMouseDownView?
        private var monitor: Any?

        init(parent: SearchHeaderMouseDownBridge) {
            self.parent = parent
        }

        func startMonitoringIfNeeded() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                let windowNumber = event.windowNumber
                let location = event.locationInWindow

                MainActor.assumeIsolated {
                    self?.handleMouseDown(windowNumber: windowNumber, location: location)
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        @MainActor
        private func handleMouseDown(windowNumber: Int, location: NSPoint) {
            guard let hostView,
                  let window = hostView.window,
                  window.windowNumber == windowNumber
            else {
                return
            }

            let point = hostView.convert(location, from: nil)
            guard hostView.bounds.contains(point) else {
                return
            }

            parent.onMouseDown()
        }
    }
}

private final class SearchHeaderMouseDownView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
#endif
