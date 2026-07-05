import GrimoraCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

public enum CardDetailPresentationStyle: Equatable {
    case automatic
    case sheet
    case inspector
}

public struct CardDetailView: View {
    @Environment(GrimoraAppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var isShowingAllPrintings = false
    @State private var previewedPrintingID: CardRecord.ID?
    @State private var gallerySelectionID: CardRecord.ID?
    @State private var fullScreenPrintingID: CardRecord.ID?
    @State private var retainedDetailImageOracleID: String?
    @State private var retainedDetailImagePath: String?
    @State private var hasOverflowingDetailArtwork = false
    @State private var hasOverflowingExpandedPreviewArtwork = false
    @State private var raisedPrintingArtworkID: CardRecord.ID?
    @State private var detailFeedbackTrigger = 0
    @State private var shareFeedbackTrigger = 0
    @State private var buyFeedbackTrigger = 0
    @State private var isValueDetailsExpanded = false
    @State private var artistPendingArtSearch: String?
    // Printings whose artwork is currently turned to a landscape (quarter-turn) variant, e.g. a
    // rotated split or aftermath card. The compact gallery reserves a landscape box for these so the
    // rotated card fills the width instead of shrinking inside a portrait frame.
    @State private var landscapeGalleryPrintingIDs: Set<CardRecord.ID> = []
    @AppStorage(GrimoraValuePreferences.displayCurrencyKey)
    private var displayCurrencyRawValue = CardValueDisplayCurrency.usd.rawValue

    public var card: CardRecord
    public var printings: [CardRecord]
    public var valueGuide: CardValueGuide?
    public var valueHistoryBackgroundActivity: ValueHistoryBackgroundActivity?
    public var valueExchangeRate: CurrencyExchangeRate?
    public var presentationStyle: CardDetailPresentationStyle
    public var onSelectPrinting: (CardRecord) -> Void
    public var selectedFinish: (CardRecord) -> CardValueFinish
    public var onSetFinish: (CardRecord, CardValueFinish) -> Void
    public var onLoadPrintingThumbnailImage: (CardRecord) async -> Void
    public var onLoadPrintingPreviewImage: (CardRecord) async -> Void
    public var onLoadAvailablePrintingPreviewImages: ([CardRecord]) async -> Void
    public var onLoadValueExchangeRate: (CardValueDisplayCurrency) async -> Void
    public var onCreateListForCard: (CardRecord) -> Void
    public var onSearchArtist: (String) -> Void
    public var onClose: (() -> Void)?

    public init(
        card: CardRecord,
        printings: [CardRecord] = [],
        valueGuide: CardValueGuide? = nil,
        valueHistoryBackgroundActivity: ValueHistoryBackgroundActivity? = nil,
        valueExchangeRate: CurrencyExchangeRate? = nil,
        presentationStyle: CardDetailPresentationStyle = .automatic,
        onSelectPrinting: @escaping (CardRecord) -> Void = { _ in },
        selectedFinish: @escaping (CardRecord) -> CardValueFinish = { _ in .normal },
        onSetFinish: @escaping (CardRecord, CardValueFinish) -> Void = { _, _ in },
        onLoadPrintingThumbnailImage: @escaping (CardRecord) async -> Void = { _ in },
        onLoadPrintingPreviewImage: @escaping (CardRecord) async -> Void = { _ in },
        onLoadAvailablePrintingPreviewImages: @escaping ([CardRecord]) async -> Void = { _ in },
        onLoadValueExchangeRate: @escaping (CardValueDisplayCurrency) async -> Void = { _ in },
        onCreateListForCard: @escaping (CardRecord) -> Void = { _ in },
        onSearchArtist: @escaping (String) -> Void = { _ in },
        onClose: (() -> Void)? = nil
    ) {
        self.card = card
        self.printings = printings
        self.valueGuide = valueGuide
        self.valueHistoryBackgroundActivity = valueHistoryBackgroundActivity
        self.valueExchangeRate = valueExchangeRate
        self.presentationStyle = presentationStyle
        self.onSelectPrinting = onSelectPrinting
        self.selectedFinish = selectedFinish
        self.onSetFinish = onSetFinish
        self.onLoadPrintingThumbnailImage = onLoadPrintingThumbnailImage
        self.onLoadPrintingPreviewImage = onLoadPrintingPreviewImage
        self.onLoadAvailablePrintingPreviewImages = onLoadAvailablePrintingPreviewImages
        self.onLoadValueExchangeRate = onLoadValueExchangeRate
        self.onCreateListForCard = onCreateListForCard
        self.onSearchArtist = onSearchArtist
        self.onClose = onClose
    }

    public var body: some View {
        content
            .background {
                GrimoraAppBackground(palette: palette)
            }
            .grimoraSelectionFeedback(trigger: detailFeedbackTrigger)
            .navigationTitle(card.name)
            .onAppear {
                resetPreviewedPrintingIfNeeded()
                syncGallerySelectionToCurrentCard()
                rememberDetailImagePath()
            }
            .onChange(of: card.id) { _, newValue in
                previewedPrintingID = newValue
                gallerySelectionID = newValue
                hasOverflowingDetailArtwork = false
                rememberDetailImagePath()
            }
            .onChange(of: card.detailImagePath) { _, _ in
                rememberDetailImagePath()
            }
            .onChange(of: previewedPrintingID) { _, _ in
                hasOverflowingExpandedPreviewArtwork = false
            }
            .onChange(of: displayPrintingIDs) { _, _ in
                resetPreviewedPrintingIfNeeded()
                syncGallerySelectionToCurrentCard()
                hasOverflowingExpandedPreviewArtwork = false
            }
            .task(id: displayPrintingIDs) {
                await onLoadAvailablePrintingPreviewImages(displayPrintings)
            }
            .task(id: displayCurrency) {
                await onLoadValueExchangeRate(displayCurrency)
            }
            #if os(iOS)
            .sheet(isPresented: fullScreenImagePresented) {
                fullScreenImageViewer
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.black)
                    .presentationCornerRadius(28)
            }
            #elseif os(visionOS)
            .fullScreenCover(isPresented: fullScreenImagePresented) {
                fullScreenImageViewer
            }
            #endif
            #if os(iOS) || os(visionOS)
            .toolbar {
                if usesToolbarActions {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        addToListMenu
                        buyMenu
                        shareMenu
                        closeButton
                    }
                }
            }
            #endif
            #if os(macOS)
            .frame(minWidth: usesExpandedPrintingsBrowser ? Self.expandedDetailMinimumWidth : nil)
            // Tell the resizable detail column how wide the content needs to be so
            // the pane can grow for the wide "Show All" expanded printings browser.
            .preference(
                key: CardDetailContentMinWidthKey.self,
                value: usesExpandedPrintingsBrowser ? Self.expandedDetailMinimumWidth : nil
            )
            .overlay(alignment: .topTrailing) {
                closeButton
            }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        if usesExpandedPrintingsBrowser {
            expandedPrintingsBrowser
        } else {
            scrollingDetailLayout
        }
        #else
        scrollingDetailLayout
        #endif
    }

    private var scrollingDetailLayout: some View {
        ScrollView {
            detailLayout
                .padding()
        }
        .cardArtworkViewport()
        .accessibilityIdentifier("card-detail")
    }

    @ViewBuilder
    private var detailLayout: some View {
        if usesInspectorPresentation {
            inspectorDetailLayout
        } else {
        #if os(macOS)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    detailArtworkLayout(for: card)
                    detailText
                        .frame(width: Self.collapsedDetailTextWidth, alignment: .leading)
                        .accessibilityIdentifier("card-detail-text")
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 20) {
                    cardImage(
                        for: card,
                        onVisualOverflowChange: updateDetailArtworkOverflow
                    )
                        .frame(maxWidth: 420)
                        .frame(maxWidth: .infinity, alignment: .center)
                    detailText
                        .accessibilityIdentifier("card-detail-text")
                }
            }
        #else
            VStack(alignment: .leading, spacing: 20) {
                if usesCompactPrintingGallery {
                    compactPrintingGallery
                } else {
                    cardImage(for: card)
                        .frame(maxWidth: 420)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                detailText
            }
        #endif
        }
    }

    private var inspectorDetailLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            #if os(iOS) || os(visionOS)
            inspectorActionCluster
            #endif

            cardImage(
                for: card,
                onVisualOverflowChange: updateDetailArtworkOverflow
            )
                .frame(maxWidth: Self.inspectorArtworkMaximumWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("card-detail-artwork-layout")

            detailText
        }
    }

    #if os(macOS)
    private func detailArtworkLayout(for card: CardRecord) -> some View {
        ZStack {
            cardImage(
                for: card,
                onVisualOverflowChange: updateDetailArtworkOverflow
            )
            .frame(width: Self.collapsedDetailArtworkWidth)
        }
        .frame(width: collapsedDetailArtworkLayoutWidth, alignment: .center)
        .accessibilityIdentifier("card-detail-artwork-layout")
    }
    #endif

    private func cardImage(
        for card: CardRecord,
        onVisualOverflowChange: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        CardArtworkView(
            card: card,
            cornerRadius: 12,
            preferredQuality: .large,
            fallbackImagePath: primaryDetailImagePath(for: card),
            accessibilityHidden: false,
            foilTreatment: card.foilTreatment(for: selectedFinish(card)),
            onVisualOverflowChange: onVisualOverflowChange
        )
            .shadow(color: palette.shadow.color, radius: 10, x: 0, y: 6)
            .cardArtworkContextMenu(
                card: card,
                onCreateListForCard: onCreateListForCard
            )
    }

    private var detailText: some View {
        VStack(alignment: .leading, spacing: Self.detailSectionSpacing) {
            oracleSection
            if showsInlinePrintingsSection {
                printingsSection
            }
            valueSection
            metadataSection(for: card)
        }
    }

    private var oracleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if usesInspectorPresentation {
                inspectorHeader
            } else {
            #if os(iOS) || os(visionOS)
                cardTitle
            #else
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        cardTitle
                        Spacer(minLength: 12)
                        headerActions(includesClose: false)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        cardTitle
                        headerActions(includesClose: false)
                    }
                }
            #endif
                cardTypeLine
            }

            let refinementGroups = model.candidateRefinements(for: card)
            HStack(alignment: .center, spacing: 12) {
                if !refinementGroups.isEmpty {
                    CardRefinementButton(groups: refinementGroups)
                }
                Spacer(minLength: 12)
                finishControl
            }

            if !card.oracleText.isEmpty {
                selectableOracleText(card.oracleText)
            }

            if !card.faces.isEmpty {
                ForEach(card.faces) { face in
                    Divider()
                        .overlay(palette.hairline.color)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(face.name)
                            .font(.headline)
                            .foregroundStyle(palette.primaryText.color)
                        if !face.typeLine.isEmpty {
                            Text(face.typeLine)
                                .font(.subheadline)
                                .foregroundStyle(palette.secondaryText.color)
                        }
                        if !face.oracleText.isEmpty {
                            selectableOracleText(face.oracleText)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    /// Lets the user choose which finish of the displayed printing they're looking at. A printing
    /// that offers more than one finish (e.g. MH2 #271 Wonder = Normal / Foil / Etched) shows a
    /// segmented picker; a single-finish printing shows a static treatment badge instead (so a
    /// halo-foil or etched-only printing still reads as such without an inert one-option control).
    @ViewBuilder
    private var finishControl: some View {
        if card.availableFinishes.count > 1 {
            finishPicker
        } else {
            FoilTreatmentBadge(treatment: card.foilTreatment(for: card.defaultFinish))
        }
    }

    private var finishPicker: some View {
        Picker("Finish", selection: finishBinding) {
            ForEach(card.availableFinishes, id: \.self) { finish in
                Text(finish.title).tag(finish)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("card-detail-finish-picker")
    }

    private var finishBinding: Binding<CardValueFinish> {
        Binding {
            selectedFinish(card)
        } set: { newValue in
            detailFeedbackTrigger += 1
            onSetFinish(card, newValue)
        }
    }

    private var cardTitle: some View {
        Text(card.name)
            .font(cardTitleFont)
            .foregroundStyle(palette.primaryText.color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .layoutPriority(1)
    }

    private var inspectorHeader: some View {
        #if os(macOS)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    cardTitle
                    cardTypeLine
                }
                Spacer(minLength: 12)
                headerActions(includesClose: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                cardTitle
                cardTypeLine
                headerActions(includesClose: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        VStack(alignment: .leading, spacing: 8) {
            cardTitle
            cardTypeLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    #if os(iOS) || os(visionOS)
    private var inspectorActionCluster: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            floatingInspectorActions {
                HStack(spacing: 10) {
                    addToListMenu
                    buyMenu
                    shareMenu
                    closeButton
                }
            }
        }
    }

    @ViewBuilder
    private func floatingInspectorActions<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
    #endif

    private func headerActions(includesClose: Bool) -> some View {
        HStack(spacing: 8) {
            addToListMenu
            buyMenu
            shareMenu
            if includesClose {
                closeButton
            }
        }
    }

    private var cardTitleFont: Font {
        usesInspectorPresentation ? .title2.weight(.semibold) : .largeTitle.weight(.semibold)
    }

    private var cardTypeLine: some View {
        Text(card.typeLine)
            .font(usesInspectorPresentation ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(palette.secondaryText.color)
            .textSelection(.enabled)
    }

    private func selectableOracleText(_ text: String) -> some View {
        CardOracleText(
            text: text,
            color: palette.primaryText,
            onIncludeSelection: { selectedText in
                model.refineCurrentSearch(
                    with: .forSelectedOracleText(selectedText, intent: .include)
                )
            },
            onExcludeSelection: { selectedText in
                model.refineCurrentSearch(
                    with: .forSelectedOracleText(selectedText, intent: .exclude)
                )
            }
        )
    }

    private var shareMenu: some View {
        #if os(iOS) || os(visionOS)
        Group {
            if usesInspectorPresentation {
                Menu {
                    shareMenuItems
                } label: {
                    GrimoraFloatingActionIcon(
                        title: "Share",
                        systemName: "square.and.arrow.up",
                        palette: palette,
                        foregroundColor: palette.accent.color,
                        feedbackTrigger: shareFeedbackTrigger
                    )
                }
                .buttonStyle(GrimoraIconButtonStyle())
            } else {
                Menu {
                    shareMenuItems
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                        .imageScale(.large)
                        .accessibilityLabel("Share")
                        .accessibilityIdentifier("card-share-button")
                }
            }
        }
        .controlSize(.small)
        .help("Share")
        .accessibilityLabel("Share")
        .accessibilityIdentifier("card-share-button")
        .simultaneousGesture(
            TapGesture().onEnded {
                shareFeedbackTrigger += 1
            }
        )
        .grimoraSelectionFeedback(trigger: shareFeedbackTrigger)
        #else
        Menu {
            shareMenuItems
        } label: {
            CardGridControlIcon(
                systemName: "square.and.arrow.up",
                feedbackTrigger: shareFeedbackTrigger
            )
        }
        .buttonStyle(GrimoraIconButtonStyle())
        .controlSize(.small)
        .help("Share")
        .accessibilityLabel("Share")
        .accessibilityIdentifier("card-share-button")
        .simultaneousGesture(
            TapGesture().onEnded {
                shareFeedbackTrigger += 1
            }
        )
        .grimoraSelectionFeedback(trigger: shareFeedbackTrigger)
        #endif
    }

    private var buyMenu: some View {
        #if os(iOS) || os(visionOS)
        Group {
            if usesInspectorPresentation {
                Menu {
                    CardBuyMenuItems(card: card)
                } label: {
                    GrimoraFloatingActionIcon(
                        title: "Buy",
                        systemName: "cart",
                        palette: palette,
                        foregroundColor: palette.accent.color,
                        feedbackTrigger: buyFeedbackTrigger
                    )
                }
                .buttonStyle(GrimoraIconButtonStyle())
            } else {
                Menu {
                    CardBuyMenuItems(card: card)
                } label: {
                    Label("Buy", systemImage: "cart")
                        .labelStyle(.iconOnly)
                        .imageScale(.large)
                        .accessibilityLabel("Buy")
                        .accessibilityIdentifier("card-buy-button")
                }
            }
        }
        .controlSize(.small)
        .help("Buy")
        .accessibilityLabel("Buy")
        .accessibilityIdentifier("card-buy-button")
        .simultaneousGesture(
            TapGesture().onEnded {
                buyFeedbackTrigger += 1
            }
        )
        .grimoraSelectionFeedback(trigger: buyFeedbackTrigger)
        #else
        Menu {
            CardBuyMenuItems(card: card)
        } label: {
            CardGridControlIcon(
                systemName: "cart",
                feedbackTrigger: buyFeedbackTrigger
            )
        }
        .buttonStyle(GrimoraIconButtonStyle())
        .controlSize(.small)
        .help("Buy")
        .accessibilityLabel("Buy")
        .accessibilityIdentifier("card-buy-button")
        .simultaneousGesture(
            TapGesture().onEnded {
                buyFeedbackTrigger += 1
            }
        )
        .grimoraSelectionFeedback(trigger: buyFeedbackTrigger)
        #endif
    }

    @ViewBuilder
    private var shareMenuItems: some View {
        #if os(macOS)
        Button {
            shareWithMacServices([shareContent.scryfallURL])
        } label: {
            Label("Link", systemImage: "link")
        }
        .accessibilityIdentifier("card-share-link")

        if let image = macImageShareItem {
            Button {
                shareWithMacServices([image])
            } label: {
                Label("Image", systemImage: "photo")
            }
            .accessibilityIdentifier("card-share-image")
        } else {
            Label("Image", systemImage: "photo")
                .accessibilityIdentifier("card-share-image-unavailable")
                .disabled(true)
        }

        Button {
            shareWithMacServices([shareContent.detailsMarkdown])
        } label: {
            Label("Details", systemImage: "doc.text")
        }
        .accessibilityIdentifier("card-share-details")
        #else
        ShareLink(item: shareContent.scryfallURL) {
            Text("Link")
        }
        .accessibilityIdentifier("card-share-link")

        if let imageShareItem = shareContent.imageShareItem {
            ShareLink(item: imageShareItem, preview: SharePreview(imageShareItem.filename)) {
                Text("Image")
            }
            .accessibilityIdentifier("card-share-image")
        } else {
            Text("Image")
                .accessibilityIdentifier("card-share-image-unavailable")
                .disabled(true)
        }

        ShareLink(item: shareContent.detailsMarkdown) {
            Text("Details")
        }
        .accessibilityIdentifier("card-share-details")
        #endif
    }

    private var addToListMenu: some View {
        #if os(iOS) || os(visionOS)
        let presentation: CardCollectionAddMenuPresentation = usesInspectorPresentation ? .floatingAction : .toolbar
        #else
        let presentation: CardCollectionAddMenuPresentation = .toolbar
        #endif

        return CardCollectionAddMenu(
            card: card,
            presentation: presentation,
            accessibilityIdentifier: "card-detail-add-to-list-button",
            onCreateListForCard: onCreateListForCard
        )
            .controlSize(.small)
    }

    private var printingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Printings")
                    .font(.headline)
                    .foregroundStyle(palette.primaryText.color)
                    .accessibilityIdentifier("card-printings")

                Spacer()

                if canToggleAllPrintings {
                    showAllPrintingsButton
                }
            }

            if isShowingAllPrintings {
                printingsGrid
            } else {
                compactPrintingsList
            }
        }
    }

    private var showAllPrintingsButton: some View {
        Button {
            detailFeedbackTrigger += 1
            withAnimation(.easeInOut(duration: 0.16)) {
                if !isShowingAllPrintings {
                    resetPreviewedPrintingIfNeeded()
                }
                isShowingAllPrintings.toggle()
            }
        } label: {
            Text(isShowingAllPrintings ? "Show Less" : "Show All")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityIdentifier("card-printings-show-all-button")
        .accessibilityValue(isShowingAllPrintings ? "Expanded" : "Collapsed")
    }

    #if os(iOS) || os(visionOS) || os(macOS)
    @ViewBuilder
    private var closeButton: some View {
        if let onClose {
            #if os(iOS) || os(visionOS)
            Group {
                if usesInspectorPresentation {
                    Button(action: onClose) {
                        GrimoraFloatingActionIcon(
                            title: "Close",
                            systemName: "xmark",
                            palette: palette,
                            foregroundColor: palette.secondaryText.color
                        )
                    }
                    .buttonStyle(GrimoraIconButtonStyle())
                } else {
                    Button(action: onClose) {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Close")
                            .accessibilityIdentifier("card-detail-close-button")
                    }
                }
            }
            .help("Close")
            .accessibilityLabel("Close")
            .accessibilityIdentifier("card-detail-close-button")
            #elseif os(macOS)
            Button(action: onClose) {
                Label("Close", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .font(.title3)
            .foregroundStyle(palette.secondaryText.color)
            .padding(10)
            .help("Close")
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("card-detail-close-button")
            #endif
        }
    }
    #endif

    #if os(macOS)
    private var expandedPrintingsBrowser: some View {
        HStack(alignment: .top, spacing: 24) {
            expandedPreviewColumn

            Divider()
                .overlay(palette.hairline.color)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    oracleSection
                    expandedPrintingsGrid
                    valueSection
                }
                .padding(.vertical, 24)
                .padding(.trailing, 24)
            }
        }
        .padding(.leading, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardArtworkViewport()
    }

    private var expandedPreviewColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                CardArtworkView(
                    card: previewedPrinting,
                    cornerRadius: 12,
                    preferredQuality: .large,
                    fallbackImagePath: previewedPrinting.detailImagePath,
                    accessibilityHidden: false,
                    foilTreatment: previewedPrinting.foilTreatment(for: selectedFinish(previewedPrinting)),
                    onVisualOverflowChange: updateExpandedPreviewArtworkOverflow
                )
                .aspectRatio(0.716, contentMode: .fit)
                .shadow(color: palette.shadow.color, radius: 10, x: 0, y: 6)
                .frame(width: Self.expandedPreviewWidth)
                .cardArtworkContextMenu(
                    card: previewedPrinting,
                    onCreateListForCard: onCreateListForCard
                )
                .task(id: PrintingPreviewImageCacheTaskID(card: previewedPrinting)) {
                    await onLoadPrintingPreviewImage(previewedPrinting)
                }
            }
            .accessibilityLabel("\(previewedPrinting.name) preview")
            .accessibilityIdentifier("card-printings-expanded-preview")
            .frame(width: expandedPreviewArtworkLayoutWidth, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(previewedPrinting.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.primaryText.color)
                    .lineLimit(2)

                Text("\(previewedPrinting.setCode.uppercased()) #\(previewedPrinting.collectorNumber)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                metadataSection(
                    for: previewedPrinting,
                    accessibilityIdentifier: "card-printings-expanded-metadata"
                )
            }
        }
        .frame(width: expandedPreviewColumnLayoutWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 24)
    }

    private var expandedPrintingsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Printings")
                    .font(.headline)
                    .foregroundStyle(palette.primaryText.color)
                    .accessibilityIdentifier("card-printings")

                Spacer()

                showAllPrintingsButton
            }

            LazyVGrid(columns: expandedPrintingGridColumns, alignment: .leading, spacing: 10) {
                ForEach(displayPrintings) { printing in
                    printingThumbnailButton(printing)
                        .task(id: PrintingThumbnailImageCacheTaskID(card: printing)) {
                            await onLoadPrintingThumbnailImage(printing)
                        }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardSurface.color)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.hairline.color, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityIdentifier("card-printings-grid")
        }
    }
    #endif

    #if os(iOS) || os(visionOS)
    private var compactPrintingGallery: some View {
        Group {
            if isShowingAllPrintings {
                compactPrintingGrid
            } else {
                VStack(spacing: 12) {
                    compactPrintingPager
                    if canToggleCompactPrintingsGrid {
                        CardPrintingPageIndicator(
                            ids: displayPrintingIDs,
                            currentID: currentCompactPrintingID,
                            palette: palette
                        )
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isShowingAllPrintings)
        .overlay(alignment: .topTrailing) {
            if canToggleCompactPrintingsGrid {
                CardCompactPrintingGalleryToggle(
                    isShowingAllPrintings: $isShowingAllPrintings,
                    detailFeedbackTrigger: $detailFeedbackTrigger,
                    palette: palette
                )
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactPrintingPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(displayPrintings) { printing in
                    CardArtworkView(
                        card: printing,
                        cornerRadius: 12,
                        preferredQuality: .large,
                        fallbackImagePath: galleryImagePath(for: printing),
                        accessibilityHidden: false,
                        foilTreatment: printing.foilTreatment(for: selectedFinish(printing)),
                        onLandscapeLayoutChange: { isLandscape in
                            setGalleryPrinting(printing.id, showsLandscapeArtwork: isLandscape)
                        }
                    )
                    .aspectRatio(galleryArtworkAspectRatio, contentMode: .fit)
                    .shadow(color: palette.shadow.color, radius: 10, x: 0, y: 6)
                    .cardGridPointerActivation(
                        onClick: { _ in fullScreenPrintingID = printing.id },
                        onDoubleClick: { fullScreenPrintingID = printing.id },
                        onTouch: { fullScreenPrintingID = printing.id },
                        ignoredBottomTrailingSize: CardArtworkView.controlHitSize
                    )
                    .cardArtworkContextMenu(
                        card: printing,
                        onCreateListForCard: onCreateListForCard,
                        openAction: CardArtworkContextMenuAction(
                            title: "View Full Image",
                            systemImage: "arrow.up.left.and.arrow.down.right",
                            accessibilityIdentifier: "card-artwork-view-full-image-\(printing.id)",
                            handler: { fullScreenPrintingID = printing.id }
                        )
                    )
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.horizontal)
                    .tag(printing.id)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        fullScreenPrintingID = printing.id
                    }
                    .accessibilityIdentifier("card-printing-\(printing.id)-page")
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: compactGalleryScrollSelection)
        // Derive the gallery's reserved height from the *capped* card width, not
        // the full container width. The aspect ratio must sit inside the maxWidth
        // cap — otherwise a wide host (e.g. the iPad fly-up sheet) reserves a box
        // sized to the whole panel width while the card is only 420pt, leaving a
        // tall empty band above and below the artwork. When the visible card is
        // turned sideways the box flips to landscape so the rotated art fills it.
        .aspectRatio(galleryArtworkAspectRatio, contentMode: .fit)
        .frame(maxWidth: Self.compactGalleryMaximumWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.18), value: galleryArtworkAspectRatio)
        .accessibilityIdentifier("card-printings-gallery")
        .simultaneousGesture(compactGalleryMagnifyGesture)
    }

    private var currentCompactPrintingID: CardRecord.ID {
        gallerySelectionID ?? card.id
    }

    // Portrait by default; flips to landscape once the on-screen printing is turned sideways so the
    // rotated card gets a wide box to fill rather than being letterboxed inside a portrait frame.
    private var galleryArtworkAspectRatio: CGFloat {
        landscapeGalleryPrintingIDs.contains(currentCompactPrintingID)
            ? 1 / Self.cardAspectRatio
            : Self.cardAspectRatio
    }

    private func setGalleryPrinting(_ id: CardRecord.ID, showsLandscapeArtwork: Bool) {
        if showsLandscapeArtwork {
            landscapeGalleryPrintingIDs.insert(id)
        } else {
            landscapeGalleryPrintingIDs.remove(id)
        }
    }

    private var compactPrintingGrid: some View {
            LazyVGrid(columns: compactPrintingGridColumns, alignment: .leading, spacing: 10) {
                ForEach(displayPrintings) { printing in
                    compactPrintingGridCell(printing)
                        .task(id: PrintingThumbnailImageCacheTaskID(card: printing)) {
                            await onLoadPrintingThumbnailImage(printing)
                        }
                        .zIndex(raisedPrintingArtworkID == printing.id ? 100 : 0)
                }
            }
        .padding(10)
        .padding(.top, 42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.cardSurface.color)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .accessibilityIdentifier("card-printings-grid")
        .simultaneousGesture(compactGalleryMagnifyGesture)
    }

    #endif

    private var compactPrintingsList: some View {
        VStack(spacing: 0) {
            ForEach(compactPrintings) { printing in
                printingRow(printing)
                if printing.id != compactPrintings.last?.id {
                    Divider()
                        .overlay(palette.hairline.color)
                }
            }
        }
        .padding(10)
        .background(palette.cardSurface.color)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var printingsGrid: some View {
        LazyVGrid(columns: printingGridColumns, alignment: .leading, spacing: 10) {
            ForEach(displayPrintings) { printing in
                printingGridCell(printing)
                    .task(id: PrintingThumbnailImageCacheTaskID(card: printing)) {
                        await onLoadPrintingThumbnailImage(printing)
                    }
                    .zIndex(raisedPrintingArtworkID == printing.id ? 100 : 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.cardSurface.color)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
    }

    private func printingRow(_ printing: CardRecord) -> some View {
        let isCurrent = printing.id == card.id

        return Button {
            detailFeedbackTrigger += 1
            onSelectPrinting(printing)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "arrow.right.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? palette.accent.color : palette.secondaryText.color.opacity(0.7))
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(printing.setName)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(palette.primaryText.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("card-printing-\(printing.id)")

                        if isCurrent {
                            Label("Current", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.accent.color)
                                .accessibilityIdentifier("card-printing-\(printing.id)-current")
                        }
                    }

                    Text(printingSummary(for: printing))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("card-printing-\(printing.id)-summary")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isCurrent ? palette.accent.color.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityIdentifier("card-printing-\(printing.id)-button")
        .accessibilityLabel(printingAccessibilityLabel(for: printing, isCurrent: isCurrent))
        .accessibilityValue(isCurrent ? "Current Printing" : "Select Printing")
    }

    private func printingGridCell(_ printing: CardRecord) -> some View {
        let isCurrent = printing.id == card.id

        return Button {
            detailFeedbackTrigger += 1
            onSelectPrinting(printing)
        } label: {
            ZStack(alignment: .topTrailing) {
                CardCellView(
                    card: printing,
                    onArtworkOverflowChange: { isOverflowing in
                        updateRaisedPrintingArtwork(printingID: printing.id, isOverflowing: isOverflowing)
                    }
                )
                    .cardArtworkContextMenu(
                        card: printing,
                        onCreateListForCard: onCreateListForCard,
                        openAction: CardArtworkContextMenuAction(
                            title: "Select Printing",
                            systemImage: "checkmark.circle",
                            accessibilityIdentifier: "card-artwork-select-printing-\(printing.id)",
                            handler: { onSelectPrinting(printing) }
                        )
                    )

                if isCurrent {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent.color)
                        .padding(7)
                        .background(palette.cardSurface.color.opacity(0.92))
                        .clipShape(Circle())
                        .shadow(color: palette.shadow.color.opacity(0.35), radius: 3, x: 0, y: 2)
                        .padding(9)
                        .accessibilityIdentifier("card-printing-\(printing.id)-current")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isCurrent ? palette.accent.color.opacity(0.5) : palette.hairline.color, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityIdentifier("card-printing-\(printing.id)-button")
        .accessibilityLabel(printingAccessibilityLabel(for: printing, isCurrent: isCurrent))
        .accessibilityValue(isCurrent ? "Current Printing" : "Select Printing")
    }

    #if os(iOS) || os(visionOS)
    private func compactPrintingGridCell(_ printing: CardRecord) -> some View {
        let isCurrent = printing.id == card.id

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                CardArtworkView(
                    card: printing,
                    maximumVisualWidthExpansion: Self.rotatedArtworkGridOverflowAllowance,
                    onVisualOverflowChange: { isOverflowing in
                        updateRaisedPrintingArtwork(printingID: printing.id, isOverflowing: isOverflowing)
                    }
                )
                    .shadow(
                        color: palette.shadow.color.opacity(0.75),
                        radius: 5,
                        x: 0,
                        y: 3
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .cardGridPointerActivation(
                        onClick: { _ in selectPrintingFromCompactGallery(printing, closesGrid: false) },
                        onDoubleClick: { selectPrintingFromCompactGallery(printing, closesGrid: false) },
                        onTouch: { selectPrintingFromCompactGallery(printing, closesGrid: false) },
                        ignoredBottomTrailingSize: CardArtworkView.controlHitSize
                    )
                    .cardArtworkContextMenu(
                        card: printing,
                        onCreateListForCard: onCreateListForCard,
                        openAction: CardArtworkContextMenuAction(
                            title: "Select Printing",
                            systemImage: "checkmark.circle",
                            accessibilityIdentifier: "card-artwork-select-printing-\(printing.id)",
                            handler: { selectPrintingFromCompactGallery(printing, closesGrid: false) }
                        )
                    )

                CardIdentityLabel(card: printing)
                    .contentShape(Rectangle())
                    .cardGridPointerActivation(
                        onClick: { _ in selectPrintingFromCompactGallery(printing, closesGrid: false) },
                        onDoubleClick: { selectPrintingFromCompactGallery(printing, closesGrid: false) },
                        onTouch: { selectPrintingFromCompactGallery(printing, closesGrid: false) }
                    )
            }
            .padding(7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.cardSurface.color.opacity(0.88))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.hairline.color, lineWidth: 1)
            }

            if isCurrent {
                Label("Current", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent.color)
                    .padding(7)
                    .background(palette.cardSurface.color.opacity(0.92))
                    .clipShape(Circle())
                    .shadow(color: palette.shadow.color.opacity(0.35), radius: 3, x: 0, y: 2)
                    .padding(9)
                    .accessibilityIdentifier("card-printing-\(printing.id)-current")
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isCurrent ? palette.accent.color.opacity(0.5) : palette.hairline.color, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            selectPrintingFromCompactGallery(printing, closesGrid: false)
        }
        .accessibilityIdentifier("card-printing-\(printing.id)-button")
        .accessibilityLabel(printingAccessibilityLabel(for: printing, isCurrent: isCurrent))
        .accessibilityValue(isCurrent ? "Current Printing" : "Select Printing")
    }
    #endif

    private func updateRaisedPrintingArtwork(printingID: CardRecord.ID, isOverflowing: Bool) {
        if isOverflowing {
            raisedPrintingArtworkID = printingID
        } else if raisedPrintingArtworkID == printingID {
            raisedPrintingArtworkID = nil
        }
    }

    private func updateDetailArtworkOverflow(_ isOverflowing: Bool) {
        if hasOverflowingDetailArtwork != isOverflowing {
            hasOverflowingDetailArtwork = isOverflowing
        }
    }

    private func updateExpandedPreviewArtworkOverflow(_ isOverflowing: Bool) {
        if hasOverflowingExpandedPreviewArtwork != isOverflowing {
            hasOverflowingExpandedPreviewArtwork = isOverflowing
        }
    }

    private func printingThumbnailButton(_ printing: CardRecord) -> some View {
        let isCurrent = printing.id == card.id
        let isPreviewing = printing.id == previewedPrinting.id

        return Button {
            detailFeedbackTrigger += 1
            previewedPrintingID = printing.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    CardArtworkView(
                        card: printing,
                        cornerRadius: 8,
                        preferredQuality: .small,
                        fallbackImagePath: thumbnailImagePath(for: printing),
                        showsControls: false
                    )
                        .aspectRatio(0.716, contentMode: .fit)
                        .cardArtworkContextMenu(
                            card: printing,
                            onCreateListForCard: onCreateListForCard,
                            openAction: CardArtworkContextMenuAction(
                                title: "Preview Printing",
                                systemImage: "eye",
                                accessibilityIdentifier: "card-artwork-preview-printing-\(printing.id)",
                                handler: { previewedPrintingID = printing.id }
                            )
                        )

                    HStack(spacing: 5) {
                        if isPreviewing {
                            Image(systemName: "eye.circle.fill")
                                .foregroundStyle(palette.accent.color)
                                .accessibilityHidden(true)
                        }

                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(palette.accent.color)
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(7)
                    .background(palette.cardSurface.color.opacity(0.92))
                    .clipShape(Capsule())
                    .shadow(color: palette.shadow.color.opacity(0.35), radius: 3, x: 0, y: 2)
                    .padding(8)
                    .opacity(isPreviewing || isCurrent ? 1 : 0)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(printing.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(palette.primaryText.color)

                    Text("\(printing.setCode.uppercased()) #\(printing.collectorNumber)")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(7)
            .background(
                isPreviewing ? palette.accent.color.opacity(0.08) : palette.cardSurface.color.opacity(0.88)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isPreviewing
                            ? palette.accent.color.opacity(0.72)
                            : isCurrent ? palette.accent.color.opacity(0.42) : palette.hairline.color,
                        lineWidth: isPreviewing ? 2 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card-printing-\(printing.id)-button")
        .accessibilityLabel(printingAccessibilityLabel(for: printing, isCurrent: isCurrent))
        .accessibilityValue(printingThumbnailAccessibilityValue(isCurrent: isCurrent, isPreviewing: isPreviewing))
    }

    private var valueSection: some View {
        GroupBox {
            valueSectionContent
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Value")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.primaryText.color)
        .accessibilityIdentifier("card-value-section")
    }

    @ViewBuilder
    private var valueSectionContent: some View {
        if let valueGuide {
            if let entry = primaryValueEntry(in: valueGuide) {
                valueSummary(for: entry, sourceName: valueGuide.sourceName)
            } else {
                Text("No TCGplayer history is available for this printing.")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("card-value-unavailable")
            }
        } else {
            Text("Loading value guide")
                .font(.callout)
                .foregroundStyle(palette.secondaryText.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("card-value-loading")
        }
    }

    private func valueSummary(for entry: CardValueGuideEntry, sourceName: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if entry.finish != .normal {
                Text("\(entry.finish.title) pricing")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .accessibilityIdentifier("card-value-finish")
            }

            HStack(alignment: .top, spacing: 16) {
                CardValueMetric(
                    title: "Current",
                    valueText: formattedPrice(convertedPrice(entry.currentPrice)),
                    identifier: "card-value-current",
                    palette: palette
                )

                Divider()
                    .overlay(palette.hairline.color)

                CardValueMetric(
                    title: "90-Day High",
                    valueText: formattedPrice(convertedPrice(entry.highestPrice)),
                    identifier: "card-value-high",
                    palette: palette
                )
            }

            if displayCurrency != .usd && valueExchangeRate == nil {
                Label("\(displayCurrency.code) rate unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .accessibilityIdentifier("card-value-rate-unavailable")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isValueDetailsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isValueDetailsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                    Text("Details")
                        .font(.callout)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card-value-details-disclosure")
            .accessibilityLabel("Details")
            .accessibilityValue(isValueDetailsExpanded ? "Expanded" : "Collapsed")

            if isValueDetailsExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    CardValueHistoryBackgroundStatus(
                        activity: valueHistoryBackgroundActivity,
                        palette: palette
                    )
                    CardValueHistoryChart(
                        points: chartPoints(for: entry),
                        palette: palette,
                        detailFeedbackTrigger: $detailFeedbackTrigger,
                        shareFeedbackTrigger: $shareFeedbackTrigger,
                        priceText: formattedPrice,
                        compactPriceText: compactFormattedPrice,
                        dateText: { Self.chartDateAccessibilityFormatter.string(from: $0) },
                        snapshotText: priceHistorySnapshotText
                    )
                    valueMovementSummary(for: entry)
                    Text(valueSourceText(for: entry, sourceName: sourceName))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("card-value-source")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Card value")
        .accessibilityValue(valueAccessibilitySummary(for: entry, sourceName: sourceName))
    }

    private func priceHistorySnapshotText(for point: CardValueChartPoint) -> String {
        let date = Self.chartDateAccessibilityFormatter.string(from: point.date)
        return "\(card.name) — \(formattedPrice(point.price)) on \(date)"
    }

    private func valueMovementSummary(for entry: CardValueGuideEntry) -> some View {
        let movement = entry.ninetyDay ?? entry.thirtyDay
        let label = entry.ninetyDay == nil && entry.thirtyDay != nil ? "30-Day Change" : "90-Day Change"
        return LabeledContent(label) {
            Text(movement.map(valueMovementText) ?? "Unavailable")
                .font(.callout.monospacedDigit())
                .foregroundStyle(valueMovementColor(movement))
                .textSelection(.enabled)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("card-value-change")
    }

    private func metadataSection(
        for card: CardRecord,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        GroupBox {
            VStack(spacing: 8) {
                detailRow("Set", "\(card.setName) (\(card.setCode.uppercased()) #\(card.collectorNumber))")
                detailRow("Rarity", card.rarity.capitalized)
                artistDetailRow(card.artist)
                detailRow("Mana Value", manaValueText(for: card))
                if let power = card.power, let toughness = card.toughness {
                    detailRow("Power/Toughness", "\(power)/\(toughness)")
                }
                detailRow("USD", price(card.priceUSD))
                detailRow("EUR", price(card.priceEUR))
                detailRow("TIX", price(card.priceTIX))
                detailRow("EDHREC", card.edhrecRank.map(String.init) ?? "Unranked")
            }
            .font(.callout)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            if let accessibilityIdentifier {
                Text("Details")
                    .accessibilityIdentifier(accessibilityIdentifier)
            } else {
                Text("Details")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.primaryText.color)
        .confirmationDialog(
            artistPendingArtSearch.map { "See all of \($0)’s art?" } ?? "See all of this artist’s art?",
            isPresented: artistArtSearchConfirmationPresented,
            titleVisibility: .visible,
            presenting: artistPendingArtSearch
        ) { artist in
            Button("See Artworks") {
                artistPendingArtSearch = nil
                onSearchArtist(artist)
            }
            Button("Cancel", role: .cancel) {
                artistPendingArtSearch = nil
            }
        } message: { artist in
            Text("Clears the current search and shows every distinct artwork \(artist) has illustrated.")
        }
    }

    private var artistArtSearchConfirmationPresented: Binding<Bool> {
        Binding {
            artistPendingArtSearch != nil
        } set: { isPresented in
            if !isPresented {
                artistPendingArtSearch = nil
            }
        }
    }

    @ViewBuilder
    private func artistDetailRow(_ artist: String?) -> some View {
        if let artist, !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            detailRow("Artist") {
                Button {
                    detailFeedbackTrigger += 1
                    artistPendingArtSearch = artist
                } label: {
                    HStack(spacing: 4) {
                        Text(artist)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent.color)
                .accessibilityLabel(artist)
                .accessibilityHint("Searches for all of this artist’s artwork")
                .accessibilityIdentifier("card-detail-artist-button")
            }
        } else {
            detailRow("Artist", "Unknown")
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        detailRow(label) {
            Text(value)
                .foregroundStyle(palette.primaryText.color)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func detailRow<Value: View>(
        _ label: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .fontWeight(.semibold)
                .foregroundStyle(palette.secondaryText.color)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: Self.detailLabelColumnWidth, alignment: .trailing)

            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private var shareContent: CardShareContent {
        CardShareContent(card: card)
    }

    #if os(macOS)
    private var macImageShareItem: NSImage? {
        guard let imageShareItem = shareContent.imageShareItem else {
            return nil
        }

        return NSImage(data: imageShareItem.data)
    }

    private func shareWithMacServices(_ items: [Any]) {
        guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
            copyShareItemsToPasteboard(items)
            return
        }

        NSSharingServicePicker(items: items).show(
            relativeTo: view.bounds,
            of: view,
            preferredEdge: .minY
        )
    }

    private func copyShareItemsToPasteboard(_ items: [Any]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for item in items {
            if let url = item as? URL {
                pasteboard.writeObjects([url as NSURL])
                return
            }

            if let string = item as? String {
                pasteboard.setString(string, forType: .string)
                return
            }

            if let image = item as? NSImage {
                pasteboard.writeObjects([image])
                return
            }
        }
    }
    #endif

    private var displayPrintings: [CardRecord] {
        printings.isEmpty ? [card] : printings
    }

    private var displayPrintingIDs: [CardRecord.ID] {
        displayPrintings.map(\.id)
    }

    private var effectivePresentationStyle: CardDetailPresentationStyle {
        switch presentationStyle {
        case .automatic:
            #if os(macOS) || os(visionOS)
            return .inspector
            #elseif os(iOS)
            return horizontalSizeClass == .compact ? .sheet : .inspector
            #else
            return .sheet
            #endif
        case .sheet:
            return .sheet
        case .inspector:
            return .inspector
        }
    }

    private var usesInspectorPresentation: Bool {
        effectivePresentationStyle == .inspector
    }

    private var usesToolbarActions: Bool {
        #if os(iOS) || os(visionOS)
        effectivePresentationStyle == .sheet
        #else
        false
        #endif
    }

    private var usesExpandedPrintingsBrowser: Bool {
        #if os(macOS)
        isShowingAllPrintings
        #else
        false
        #endif
    }

    private var showsInlinePrintingsSection: Bool {
        #if os(macOS)
        true
        #else
        !usesCompactPrintingGallery
        #endif
    }

    private var usesCompactPrintingGallery: Bool {
        #if os(macOS)
        false
        #else
        !usesInspectorPresentation && horizontalSizeClass == .compact
        #endif
    }

    private var canToggleCompactPrintingsGrid: Bool {
        displayPrintings.count > 1
    }

    private var previewedPrinting: CardRecord {
        let previewID = previewedPrintingID ?? card.id
        return displayPrintings.first { $0.id == previewID }
            ?? displayPrintings.first { $0.id == card.id }
            ?? card
    }

    #if os(macOS)
    private var collapsedDetailArtworkLayoutWidth: CGFloat {
        cardArtworkReservedLayoutWidth(
            baseWidth: Self.collapsedDetailArtworkWidth,
            aspectRatio: Self.cardAspectRatio,
            hasVisualOverflow: reservesDetailArtworkOverflow
        )
    }

    private var expandedPreviewArtworkLayoutWidth: CGFloat {
        cardArtworkReservedLayoutWidth(
            baseWidth: Self.expandedPreviewWidth,
            aspectRatio: Self.cardAspectRatio,
            hasVisualOverflow: reservesExpandedPreviewArtworkOverflow
        )
    }

    private var expandedPreviewColumnLayoutWidth: CGFloat {
        max(Self.expandedPreviewColumnWidth, expandedPreviewArtworkLayoutWidth)
    }

    private var reservesDetailArtworkOverflow: Bool {
        hasOverflowingDetailArtwork
    }

    private var reservesExpandedPreviewArtworkOverflow: Bool {
        hasOverflowingExpandedPreviewArtwork
    }
    #endif

    private var compactPrintings: [CardRecord] {
        guard displayPrintings.count > Self.compactPrintingLimit else {
            return displayPrintings
        }

        var compact = Array(displayPrintings.prefix(Self.compactPrintingLimit))
        if !compact.contains(where: { $0.id == card.id }),
           let current = displayPrintings.first(where: { $0.id == card.id }) {
            compact[compact.index(before: compact.endIndex)] = current
        }
        return compact
    }

    private var canToggleAllPrintings: Bool {
        displayPrintings.count > Self.compactPrintingLimit
    }

    private var printingGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 148, maximum: 178), spacing: 10, alignment: .top)
        ]
    }

    private var expandedPrintingGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: Self.thumbnailWidth, maximum: 178), spacing: 10, alignment: .top)
        ]
    }

    #if os(iOS) || os(visionOS)
    private var compactPrintingGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: Self.compactThumbnailMinimumWidth), spacing: 10, alignment: .top),
            GridItem(.flexible(minimum: Self.compactThumbnailMinimumWidth), spacing: 10, alignment: .top)
        ]
    }

    private var compactGallerySelection: Binding<CardRecord.ID> {
        Binding {
            gallerySelectionID ?? card.id
        } set: { newValue in
            gallerySelectionID = newValue
            guard let printing = displayPrintings.first(where: { $0.id == newValue }) else {
                return
            }
            selectPrintingFromCompactGallery(printing, closesGrid: false)
        }
    }

    private var compactGalleryScrollSelection: Binding<CardRecord.ID?> {
        Binding {
            gallerySelectionID ?? card.id
        } set: { newValue in
            guard let newValue else {
                return
            }
            compactGallerySelection.wrappedValue = newValue
        }
    }

    #if os(iOS) || os(visionOS)
    private var fullScreenImagePresented: Binding<Bool> {
        Binding {
            fullScreenPrintingID != nil
        } set: { isPresented in
            if !isPresented {
                fullScreenPrintingID = nil
            }
        }
    }

    private var fullScreenImageViewer: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let printing = fullScreenPrinting {
                CardArtworkView(
                    card: printing,
                    cornerRadius: 12,
                    preferredQuality: .large,
                    fallbackImagePath: galleryImagePath(for: printing),
                    accessibilityHidden: false,
                    foilTreatment: printing.foilTreatment(for: selectedFinish(printing))
                )
                    .aspectRatio(Self.cardAspectRatio, contentMode: .fit)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .cardArtworkContextMenu(
                        card: printing,
                        onCreateListForCard: onCreateListForCard
                    )
                    .accessibilityIdentifier("card-printing-full-screen-image")
            }

            #if os(visionOS)
            Button {
                fullScreenPrintingID = nil
            } label: {
                Label("Close", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding(16)
            }
            .accessibilityIdentifier("card-printing-full-screen-close-button")
            #endif
        }
    }

    private var fullScreenPrinting: CardRecord? {
        guard let fullScreenPrintingID else {
            return nil
        }
        return displayPrintings.first { $0.id == fullScreenPrintingID }
    }
    #endif

    private var compactGalleryMagnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard canToggleCompactPrintingsGrid else {
                    return
                }

                if !isShowingAllPrintings && value.magnification < Self.compactGalleryExpandMagnification {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isShowingAllPrintings = true
                    }
                } else if isShowingAllPrintings && value.magnification > Self.compactGalleryCollapseMagnification {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isShowingAllPrintings = false
                    }
                }
            }
    }
    #endif

    private func printingSummary(for printing: CardRecord) -> String {
        [
            "\(printing.setCode.uppercased()) #\(printing.collectorNumber)",
            printing.releasedAt ?? "Unknown date",
            printing.rarity.capitalized,
            printing.language?.uppercased() ?? "Unknown language",
            "USD \(price(printing.priceUSD))"
        ].joined(separator: " | ")
    }

    private func printingAccessibilityLabel(for printing: CardRecord, isCurrent: Bool) -> String {
        let label = "\(printing.setName), \(printingSummary(for: printing))"
        return isCurrent ? "\(label), Current" : label
    }

    private func printingThumbnailAccessibilityValue(isCurrent: Bool, isPreviewing: Bool) -> String {
        switch (isCurrent, isPreviewing) {
        case (true, true):
            return "Previewing Current Printing"
        case (true, false):
            return "Current Printing"
        case (false, true):
            return "Previewing Printing"
        case (false, false):
            return "Select Preview"
        }
    }

    private func thumbnailImagePath(for printing: CardRecord) -> String? {
        printing.smallImagePath
            ?? printing.faces.first?.smallImagePath
            ?? printing.normalImagePath
            ?? printing.faces.first?.normalImagePath
    }

    private func galleryImagePath(for printing: CardRecord) -> String? {
        printing.detailImagePath
            ?? thumbnailImagePath(for: printing)
    }

    private func primaryDetailImagePath(for card: CardRecord) -> String? {
        card.detailImagePath
            ?? (retainedDetailImageOracleID == card.oracleID ? retainedDetailImagePath : nil)
    }

    private func rememberDetailImagePath() {
        if retainedDetailImageOracleID != card.oracleID {
            retainedDetailImageOracleID = card.oracleID
            retainedDetailImagePath = card.detailImagePath
            return
        }

        if let detailImagePath = card.detailImagePath {
            retainedDetailImagePath = detailImagePath
        }
    }

    private func resetPreviewedPrintingIfNeeded() {
        guard let previewedPrintingID,
              displayPrintings.contains(where: { $0.id == previewedPrintingID })
        else {
            self.previewedPrintingID = card.id
            return
        }
    }

    private func syncGallerySelectionToCurrentCard() {
        if displayPrintings.contains(where: { $0.id == card.id }) {
            gallerySelectionID = card.id
        } else if let gallerySelectionID,
                  displayPrintings.contains(where: { $0.id == gallerySelectionID }) {
            return
        } else {
            gallerySelectionID = displayPrintings.first?.id ?? card.id
        }
    }

    #if os(iOS) || os(visionOS)
    private func selectPrintingFromCompactGallery(_ printing: CardRecord, closesGrid: Bool) {
        detailFeedbackTrigger += 1
        gallerySelectionID = printing.id

        if closesGrid {
            withAnimation(.easeInOut(duration: 0.18)) {
                isShowingAllPrintings = false
            }
        }

        guard printing.id != card.id else {
            return
        }

        onSelectPrinting(printing)
    }
    #endif

    private var displayCurrency: CardValueDisplayCurrency {
        GrimoraValuePreferences.displayCurrency(from: displayCurrencyRawValue)
    }

    private func primaryValueEntry(in guide: CardValueGuide) -> CardValueGuideEntry? {
        // Prefer the pricing for the finish the user has the card set to (foil, etched, …).
        // Otherwise (and as a fallback when that finish has no pricing) use the normal
        // finish ordering.
        if let selectedEntry = guide.entries.first(where: { $0.finish == selectedFinish(card) }) {
            return selectedEntry
        }
        for finish in CardValueFinish.allCases {
            if let entry = guide.entries.first(where: { $0.finish == finish }) {
                return entry
            }
        }
        return guide.entries.first
    }

    private func convertedPrice(_ usdPrice: Double) -> Double? {
        guard displayCurrency != .usd else {
            return usdPrice
        }
        guard let valueExchangeRate,
              valueExchangeRate.baseCurrency == .usd,
              valueExchangeRate.quoteCurrency == displayCurrency
        else {
            return nil
        }
        return usdPrice * valueExchangeRate.rate
    }

    private func formattedPrice(_ value: Double?) -> String {
        guard let value else {
            return "Unavailable"
        }
        return "\(displayCurrency.rawValue) \(price(value))"
    }

    private func compactFormattedPrice(_ value: Double) -> String {
        "\(displayCurrency.rawValue) \(Self.compactPriceFormatter.string(from: NSNumber(value: value)) ?? price(value))"
    }

    private func chartPoints(for entry: CardValueGuideEntry) -> [CardValueChartPoint] {
        entry.history.compactMap { point in
            guard let date = Self.valueHistoryDateFormatter.date(from: point.date),
                  let price = convertedPrice(point.price)
            else {
                return nil
            }
            return CardValueChartPoint(date: date, price: price)
        }
    }

    private func valueMovementText(_ movement: CardValueMovement) -> String {
        let deltaText: String
        if let convertedDelta = convertedPrice(abs(movement.delta)) {
            deltaText = "\(movement.delta >= 0 ? "+" : "-")\(formattedPrice(convertedDelta))"
        } else {
            deltaText = "Unavailable"
        }

        let direction: String
        if movement.delta > 0 {
            direction = "up"
        } else if movement.delta < 0 {
            direction = "down"
        } else {
            direction = "flat"
        }

        if let percent = movement.percent {
            return "\(direction) \(deltaText) (\(Self.percentFormatter.string(from: NSNumber(value: percent)) ?? "0%"))"
        }
        return "\(direction) \(deltaText)"
    }

    private func valueMovementColor(_ movement: CardValueMovement?) -> Color {
        guard let movement else {
            return palette.secondaryText.color
        }
        if movement.delta > 0 {
            return .green
        }
        if movement.delta < 0 {
            return .red
        }
        return palette.secondaryText.color
    }

    private func valueSourceText(for entry: CardValueGuideEntry, sourceName: String) -> String {
        var parts = ["\(sourceName). Updated \(entry.currentDate)."]
        if displayCurrency != .usd, let valueExchangeRate {
            parts.append(
                "Converted with \(valueExchangeRate.providerName) rate from \(valueExchangeRate.date): 1 USD = \(price(valueExchangeRate.rate)) \(displayCurrency.code)."
            )
        }
        return parts.joined(separator: " ")
    }

    private func valueAccessibilitySummary(
        for entry: CardValueGuideEntry,
        sourceName: String
    ) -> String {
        [
            "Current \(formattedPrice(convertedPrice(entry.currentPrice)))",
            "90-day high \(formattedPrice(convertedPrice(entry.highestPrice)))",
            "\(entry.finish.title) finish",
            valueSourceText(for: entry, sourceName: sourceName),
        ].joined(separator: ", ")
    }

    private func price(_ value: Double?) -> String {
        guard let value else {
            return "Unknown"
        }
        return Self.priceFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func signedPrice(_ value: Double) -> String {
        let formatted = price(abs(value))
        if value > 0 {
            return "+\(formatted)"
        }
        if value < 0 {
            return "-\(formatted)"
        }
        return formatted
    }

    private func manaValueText(for card: CardRecord) -> String {
        guard let manaValue = card.manaValue else {
            return "Unknown"
        }
        return Self.numberFormatter.string(from: NSNumber(value: manaValue)) ?? "\(manaValue)"
    }

    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let compactPriceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let valueHistoryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let chartDateAccessibilityFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let compactPrintingLimit = 4
    private static let cardAspectRatio: CGFloat = 0.716
    private static let detailSectionSpacing: CGFloat = 28
    private static let detailLabelColumnWidth: CGFloat = 120
    private static let collapsedDetailArtworkWidth: CGFloat = 340
    private static let rotatedArtworkGridOverflowAllowance: CGFloat = 12
    private static let compactGalleryMaximumWidth: CGFloat = 420
    // The card art fills the detail pane's width; the pane itself is clamped so
    // this never exceeds the source resolution (~672pt at Scryfall "large"), so
    // this cap is just a guard against upscaling/blur.
    private static let inspectorArtworkMaximumWidth: CGFloat = 672
    private static let compactThumbnailMinimumWidth: CGFloat = 118
    private static let compactGalleryExpandMagnification = 0.82
    private static let compactGalleryCollapseMagnification = 1.12
    private static let collapsedDetailTextWidth: CGFloat = 460
    private static let expandedDetailMinimumWidth: CGFloat = 1180
    private static let expandedPreviewColumnWidth: CGFloat = 330
    private static let expandedPreviewWidth: CGFloat = 300
    private static let thumbnailWidth: CGFloat = 150
}

/// Index range of printing dots the compact page indicator renders. Small print
/// counts show every dot; larger counts slide a fixed-width window centred on
/// the current page so the strip never overflows. Factored out as a pure
/// function so the windowing policy can be unit-tested without rendering a view.
func compactPrintingDotWindow(count: Int, current: Int, maxVisible: Int) -> Range<Int> {
    let clampedCount = max(count, 0)
    guard maxVisible > 0, clampedCount > maxVisible else { return 0..<clampedCount }
    let clampedCurrent = min(max(current, 0), clampedCount - 1)
    let half = maxVisible / 2
    let start = min(max(clampedCurrent - half, 0), clampedCount - maxVisible)
    return start..<(start + maxVisible)
}

/// Diameter for the dot at `index`. The current page reads largest; the
/// outermost dot on a side that still hides printings shrinks to hint that more
/// art exists beyond the window.
func compactPrintingDotDiameter(
    index: Int, current: Int, count: Int, window: Range<Int>
) -> CGFloat {
    if index == current { return 8 }
    if window.lowerBound > 0, index == window.lowerBound { return 4 }
    if window.upperBound < count, index == window.upperBound - 1 { return 4 }
    return 6
}

struct CardValueChartPoint: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var price: Double
}

/// Returns the charted point whose day is closest to `date`, used to snap the
/// price-history scrub readout to a real reading. Factored out as a pure
/// function so the nearest-point policy can be unit-tested without a chart.
func nearestChartPoint(to date: Date, in points: [CardValueChartPoint]) -> CardValueChartPoint? {
    points.min {
        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
    }
}

private struct PrintingThumbnailImageCacheTaskID: Equatable {
    var cardID: String
    var thumbnailImagePath: String?

    init(card: CardRecord) {
        cardID = card.id
        thumbnailImagePath = card.smallImagePath
            ?? card.faces.first?.smallImagePath
            ?? card.normalImagePath
            ?? card.faces.first?.normalImagePath
    }
}

private struct PrintingPreviewImageCacheTaskID: Equatable {
    var cardID: String
    var detailImagePath: String?

    init(card: CardRecord) {
        cardID = card.id
        detailImagePath = card.detailImagePath
    }
}
