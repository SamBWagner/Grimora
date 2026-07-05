import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

enum CardCollectionImportMode: Identifiable, Equatable {
    case create
    case append(CardCollectionRecord.ID)

    var id: String {
        switch self {
        case .create:
            "create"
        case .append(let listID):
            "append-\(listID)"
        }
    }

    var isCreate: Bool {
        if case .create = self {
            return true
        }
        return false
    }
}

struct CardCollectionImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    var mode: CardCollectionImportMode

    var body: some View {
        #if os(iOS)
        NavigationStack {
            CardCollectionImportForm(
                mode: mode,
                presentation: .touchSheet,
                onCancel: {
                    dismiss()
                },
                onComplete: {
                    dismiss()
                }
            )
            .navigationBarTitleDisplayMode(.inline)
        }
        #else
        CardCollectionImportForm(
            mode: mode,
            presentation: .modalSheet,
            onCancel: {
                dismiss()
            },
            onComplete: {
                dismiss()
            }
        )
        .padding(24)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 430)
        #endif
    }
}

struct CardCollectionCreateDestinationView: View {
    @Environment(\.colorScheme) private var colorScheme

    var onCancel: () -> Void
    var onComplete: () -> Void

    var body: some View {
        #if os(iOS)
        CardCollectionImportForm(
            mode: .create,
            presentation: .touchDestination,
            onCancel: onCancel,
            onComplete: onComplete,
            titleAccessibilityIdentifier: "create-list-destination"
        )
        #else
        ScrollView {
            CardCollectionImportForm(
                mode: .create,
                presentation: .inlineDestination,
                onCancel: onCancel,
                onComplete: onComplete,
                titleAccessibilityIdentifier: "create-list-destination"
            )
            .frame(maxWidth: 680, alignment: .top)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            GrimoraAppBackground(palette: palette)
        }
        #endif
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private var horizontalPadding: CGFloat {
        #if os(visionOS)
        44
        #else
        32
        #endif
    }

    private var topPadding: CGFloat {
        #if os(visionOS)
        42
        #else
        34
        #endif
    }
}

private enum CardCollectionImportPresentation: Equatable {
    case modalSheet
    case inlineDestination
    case touchDestination
    case touchSheet

    var usesTouchForm: Bool {
        self == .touchDestination || self == .touchSheet
    }
}

private struct CardCollectionImportForm: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(GrimoraAppModel.self) private var model

    var mode: CardCollectionImportMode
    var presentation: CardCollectionImportPresentation
    var onCancel: () -> Void
    var onComplete: () -> Void
    var titleAccessibilityIdentifier: String?

    @State private var listName = ""
    @State private var sourceMode: ImportSourceMode
    @State private var sourceText = ""
    @State private var isShowingFileImporter = false
    @State private var isImporting = false
    @State private var localMessage: String?
    @FocusState private var focusedField: FocusedField?

    init(
        mode: CardCollectionImportMode,
        presentation: CardCollectionImportPresentation = .modalSheet,
        onCancel: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        titleAccessibilityIdentifier: String? = nil
    ) {
        self.mode = mode
        self.presentation = presentation
        self.onCancel = onCancel
        self.onComplete = onComplete
        self.titleAccessibilityIdentifier = titleAccessibilityIdentifier
        _sourceMode = State(initialValue: mode.isCreate ? .blank : .pasteOrLink)
    }

    var body: some View {
        content
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: allowedContentTypes
            ) { result in
                handleFileImport(result)
            }
            .onAppear {
                focusInitialField()
            }
            .onChange(of: sourceMode) { _, newValue in
                focusField(for: newValue)
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if presentation.usesTouchForm {
            touchForm
        } else {
            panelForm
        }
        #else
        panelForm
        #endif
    }

    private var panelForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            CardCollectionImportHeader(
                title: title,
                subtitle: subtitle,
                headerFont: headerFont,
                titleAccessibilityIdentifier: titleAccessibilityIdentifier,
                palette: palette
            )

            VStack(alignment: .leading, spacing: 18) {
                if mode.isCreate {
                    listNameSection
                }

                sourceSection
                sourceInputContent

                if let localMessage {
                    messageText(localMessage)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.hairline.color, lineWidth: 1)
            }

            actionRow
        }
    }

    #if os(iOS)
    private var touchForm: some View {
        Form {
            if mode.isCreate {
                Section("Details") {
                    listNameField
                }
            }

            Section("Source") {
                sourcePicker
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            }

            if sourceMode != .blank {
                Section(sourceMode.title) {
                    sourceInputContent
                }
            }

            if let localMessage {
                Section {
                    messageText(localMessage)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background {
            GrimoraAppBackground(palette: palette)
        }
        .navigationTitle(title)
        .accessibilityIdentifier(titleAccessibilityIdentifier ?? "list-import-form")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                submitButton
            }
        }
    }
    #endif

    private var listNameSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Collection name")
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)

            listNameField
        }
    }

    @ViewBuilder
    private var listNameField: some View {
        #if os(iOS) || os(visionOS)
        TextField("Collection name", text: $listName)
            .textInputAutocapitalization(.words)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .focused($focusedField, equals: .listName)
            .onSubmit {
                submit()
            }
            .accessibilityIdentifier("list-import-name-field")
        #else
        TextField("Collection name", text: $listName)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .focused($focusedField, equals: .listName)
            .onSubmit {
                submit()
            }
            .accessibilityIdentifier("list-import-name-field")
        #endif
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source")
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)

            sourcePicker
        }
    }

    private var sourcePicker: some View {
        ImportSourcePicker(
            sources: sourceOptions,
            selection: $sourceMode,
            palette: palette
        )
        .accessibilityIdentifier("list-import-source-picker")
    }

    @ViewBuilder
    private var sourceInputContent: some View {
        switch sourceMode {
        case .blank:
            EmptyView()
        case .pasteOrLink:
            pasteOrLinkInput
        case .file:
            CardCollectionImportFileInput(
                fileTitle: fileTitle,
                fileSubtitle: fileSubtitle,
                palette: palette,
                onChooseFile: { isShowingFileImporter = true }
            )
        }
    }

    private var pasteOrLinkInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deck text or link")
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)

            TextEditor(text: $sourceText)
                .font(.system(.body, design: .monospaced))
                .focused($focusedField, equals: .sourceText)
                .frame(minHeight: editorMinimumHeight)
                .scrollContentBackground(.hidden)
                .padding(7)
                .background(palette.placeholderFill.color.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.hairline.color, lineWidth: 1)
                }
                .accessibilityIdentifier("list-import-source-text")
        }
    }

    private func messageText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(palette.secondaryText.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button("Cancel", role: .cancel) {
                onCancel()
            }

            submitButton
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            submitButtonLabel
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSubmit || isImporting)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("list-import-submit-button")
    }

    @ViewBuilder
    private var submitButtonLabel: some View {
        if isImporting {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("Importing")
            }
        } else {
            Text(actionTitle)
        }
    }

    private var title: String {
        switch mode {
        case .create:
            "New List"
        case .append:
            "Import"
        }
    }

    private var subtitle: String {
        switch mode {
        case .create:
            "Start empty or bring in cards from text, a link, or a file."
        case .append:
            "Add cards from deck text or a file."
        }
    }

    private var actionTitle: String {
        switch (mode, sourceMode) {
        case (.create, .blank):
            "Create"
        case (.create, _):
            "Create & Import"
        case (.append, _):
            "Import"
        }
    }

    private var sourceOptions: [ImportSourceMode] {
        mode.isCreate ? ImportSourceMode.allCases : [.pasteOrLink, .file]
    }

    private var allowedContentTypes: [UTType] {
        mode.isCreate ? [.plainText, .text, .grimoraList, .json] : [.plainText, .text]
    }

    private var canSubmit: Bool {
        switch (mode, sourceMode) {
        case (.create, .blank):
            !normalizedListName.isEmpty
        case (.create, .pasteOrLink), (.append, .pasteOrLink):
            !normalizedSourceText.isEmpty
        case (.append, .blank):
            false
        case (_, .file):
            false
        }
    }

    private var normalizedListName: String {
        listName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSourceText: String {
        sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private var headerFont: Font {
        presentation == .inlineDestination ? .title.weight(.semibold) : .title3.weight(.semibold)
    }

    private var editorMinimumHeight: CGFloat {
        presentation.usesTouchForm ? 170 : 220
    }

    private var fileTitle: String {
        mode.isCreate ? "Import a list file" : "Import cards from a file"
    }

    private var fileSubtitle: String {
        mode.isCreate ? "Text, JSON, and Grimora list files are supported." : "Text files are supported."
    }

    private func submit() {
        guard canSubmit, !isImporting else {
            return
        }

        switch mode {
        case .create where sourceMode == .blank:
            if model.createCardCollection(named: normalizedListName, selectAfterCreate: true) != nil {
                onComplete()
            }
        case .create:
            let requestedName = normalizedListName.isEmpty ? nil : normalizedListName
            let source = normalizedSourceText
            isImporting = true
            Task {
                let summary = await model.createCardCollectionFromArchidektSource(
                    source,
                    named: requestedName
                )
                isImporting = false
                if summary != nil {
                    onComplete()
                }
            }
        case .append(let listID):
            let source = normalizedSourceText
            isImporting = true
            Task {
                let summary = await model.importArchidektCards(
                    from: source,
                    intoListID: listID
                )
                isImporting = false
                if summary != nil {
                    onComplete()
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            return
        }

        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            localMessage = "File could not be read."
            return
        }

        if mode.isCreate, isGrimoraArchive(url) {
            if model.importCardCollectionArchive(data: data) != nil {
                onComplete()
            } else {
                localMessage = "File could not be imported."
            }
            return
        }

        guard let text = String(data: data, encoding: .utf8) else {
            localMessage = "File is not valid UTF-8 text."
            return
        }

        sourceText = text
        sourceMode = .pasteOrLink
        localMessage = "Loaded \(url.lastPathComponent)."
    }

    private func isGrimoraArchive(_ url: URL) -> Bool {
        ["grimoralist", "json"].contains(url.pathExtension.lowercased())
    }

    private func focusInitialField() {
        guard mode.isCreate else {
            return
        }

        Task { @MainActor in
            focusedField = .listName
        }
    }

    private func focusField(for sourceMode: ImportSourceMode) {
        Task { @MainActor in
            switch sourceMode {
            case .blank, .file:
                focusedField = mode.isCreate ? .listName : nil
            case .pasteOrLink:
                focusedField = .sourceText
            }
        }
    }

    private enum FocusedField: Hashable {
        case listName
        case sourceText
    }
}

private struct ImportSourcePicker: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var sources: [ImportSourceMode]
    @Binding var selection: ImportSourceMode
    var palette: GrimoraPalette

    var body: some View {
        if useVerticalRows {
            // Compact widths (iPhone, down to the SE/Mini): a single column of
            // full-width rows never clips its card borders and stays balanced.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sources) { source in
                    optionButton(source, axis: .horizontal)
                }
            }
        } else {
            // Regular widths (iPad, macOS/visionOS panel): keep the card grid.
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(sources) { source in
                    optionButton(source, axis: .vertical)
                }
            }
        }
    }

    @ViewBuilder
    private func optionButton(_ source: ImportSourceMode, axis: Axis) -> some View {
        Button {
            selection = source
        } label: {
            ImportSourceOptionLabel(
                source: source,
                isSelected: selection == source,
                axis: axis,
                palette: palette
            )
        }
        .buttonStyle(
            ImportSourceOptionButtonStyle(
                isSelected: selection == source,
                palette: palette
            )
        )
        .accessibilityIdentifier("list-import-source-option-\(source.id)")
        .accessibilityValue(selection == source ? "Selected" : "Not selected")
        #if os(macOS)
        .help(source.title)
        #endif
    }

    private var useVerticalRows: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 152, maximum: 220),
                spacing: 10,
                alignment: .topLeading
            )
        ]
    }
}

private struct ImportSourceOptionLabel: View {
    var source: ImportSourceMode
    var isSelected: Bool
    var axis: Axis
    var palette: GrimoraPalette

    var body: some View {
        switch axis {
        case .vertical:
            verticalLayout
        case .horizontal:
            horizontalLayout
        }
    }

    // Card layout for the grid (iPad / macOS / visionOS): icon top-leading,
    // selection indicator top-trailing, title + subtitle beneath.
    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                icon
                Spacer(minLength: 0)
                selectionIndicator
            }

            titleBlock
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(12)
    }

    // Full-width row layout for compact widths (iPhone): icon leading,
    // title + subtitle, selection indicator trailing.
    private var horizontalLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            icon
            titleBlock
            Spacer(minLength: 12)
            selectionIndicator
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var icon: some View {
        Image(systemName: source.systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(isSelected ? palette.primaryText.color : palette.accent.color)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(source.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)
                .lineLimit(1)

            Text(source.subtitle)
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? palette.accent.color : palette.secondaryText.color.opacity(0.6))
            .accessibilityHidden(true)
    }
}

private struct ImportSourceOptionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var isSelected: Bool
    var palette: GrimoraPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(strokeColor(isPressed: configuration.isPressed), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(
                reduceMotion ? GrimoraInteraction.focusAnimation : GrimoraInteraction.pressSpring,
                value: configuration.isPressed
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return palette.selectedAccent.color.opacity(isPressed ? 0.78 : 0.58)
        }
        return palette.cardSurface.color.opacity(isPressed ? 0.82 : 0.58)
    }

    private func strokeColor(isPressed: Bool) -> Color {
        if isSelected {
            return palette.accent.color.opacity(isPressed ? 0.62 : 0.48)
        }
        return isPressed ? palette.accent.color.opacity(0.35) : palette.hairline.color
    }
}

private enum ImportSourceMode: String, CaseIterable, Identifiable {
    case blank
    case pasteOrLink
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank:
            "Blank"
        case .pasteOrLink:
            "Paste or Link"
        case .file:
            "File"
        }
    }

    var subtitle: String {
        switch self {
        case .blank:
            "Start empty"
        case .pasteOrLink:
            "Deck text or URL"
        case .file:
            "Text or archive"
        }
    }

    var systemImage: String {
        switch self {
        case .blank:
            "plus"
        case .pasteOrLink:
            "text.insert"
        case .file:
            "doc"
        }
    }
}
