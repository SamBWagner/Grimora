import GrimoraCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

struct CardListExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let list: CardListRecord
    let entries: [CardListEntryRecord]
    let categories: [CardListCategoryRecord]

    @State private var configuration: CardListExportConfiguration
    @State private var exportDate: Date
    @State private var isPresentingFileExporter = false
    @State private var exportedDocument = CardListExportDocument()
    @State private var exportContentType: UTType = .plainText
    @State private var exportFilename = "Card List.txt"
    @State private var statusMessage: String?

    init(
        list: CardListRecord,
        entries: [CardListEntryRecord],
        categories: [CardListCategoryRecord] = []
    ) {
        self.list = list
        self.entries = entries
        self.categories = categories

        let now = Date()
        var defaultConfiguration = CardListExportConfiguration.defaultConfiguration()
        defaultConfiguration.deckRegistrationFields.deckName = list.name
        defaultConfiguration.deckRegistrationFields.date = Self.formattedDate(now)
        _configuration = State(initialValue: defaultConfiguration)
        _exportDate = State(initialValue: now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cards") {
                    LabeledContent("Selected cards", value: result.selectedCardCount.formatted())
                    LabeledContent("Unique cards", value: result.uniqueCardCount.formatted())
                }

                Section("Export type") {
                    Picker("Export type", selection: $configuration.format) {
                        ForEach(CardListExportFormat.allCases) { format in
                            Text(format.displayTitle).tag(format)
                        }
                    }
                    .accessibilityIdentifier("card-list-export-format-picker")
                }

                exportOptions

                if !result.warnings.isEmpty {
                    Section("Warnings") {
                        ForEach(result.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Export preview") {
                    ScrollView {
                        Text(previewText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("card-list-export-preview")
                    }
                    .frame(minHeight: 160)
                }

                if let statusMessage {
                    Section {
                        Label(statusMessage, systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Spacer(minLength: 0)
                        actionButtons
                    }
                }
            }
            .navigationTitle("Export \(list.name)")
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 620)
        .fileExporter(
            isPresented: $isPresentingFileExporter,
            document: exportedDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { outcome in
            switch outcome {
            case .success:
                statusMessage = "Export saved."
            case .failure(let error):
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if result.isCopyable {
            Button {
                copyResult()
            } label: {
                Text("Copy")
            }
            .accessibilityIdentifier("card-list-export-copy-button")
        }

        if result.isDownloadable {
            Button {
                prepareFileExport()
            } label: {
                Text("Download")
            }
            .accessibilityIdentifier("card-list-export-download-button")
        }
    }

    @ViewBuilder
    private var exportOptions: some View {
        switch configuration.format {
        case .text:
            Section("Export options") {
                Toggle("Include x in quantity", isOn: $configuration.textIncludesXInQuantity)
                Toggle("Include set code", isOn: $configuration.textIncludesSetCode)
                Toggle("Include collector number", isOn: $configuration.textIncludesCollectorNumber)
                Toggle("Use front name only for MDFC cards", isOn: $configuration.textUsesFrontNameOnlyForMDFC)

                Picker("Section header", selection: $configuration.textSectionHeader) {
                    ForEach(CardListExportTextSectionHeader.allCases) { sectionHeader in
                        Text(sectionHeader.displayTitle).tag(sectionHeader)
                    }
                }
            }
        case .csv:
            Section("Export options") {
                Toggle("Header row", isOn: $configuration.csvIncludesHeaderRow)

                HStack {
                    Button("Check all") {
                        configuration.csvColumns = CardListExportCSVColumn.allCases
                    }

                    Button("Uncheck all") {
                        configuration.csvColumns = []
                    }
                }

                ForEach(CardListExportCSVColumn.allCases) { column in
                    Toggle(column.displayTitle, isOn: csvColumnBinding(column))
                }
            }
        case .arena:
            Section("Export options") {
                Text("Arena export uses Arena-available print names with set and collector numbers when available.")
                    .foregroundStyle(.secondary)
            }
        case .mtgoDek:
            Section("Export options") {
                Text("MTGO.dek export uses MTGO IDs when available and falls back to card names otherwise.")
                    .foregroundStyle(.secondary)
            }
        case .deckRegistrationPDF:
            Section("Deck registration") {
                TextField("Deck name", text: $configuration.deckRegistrationFields.deckName)
                TextField("Date", text: $configuration.deckRegistrationFields.date)
                TextField("First name", text: $configuration.deckRegistrationFields.firstName)
                TextField("Last name", text: $configuration.deckRegistrationFields.lastName)
                TextField("Designer", text: $configuration.deckRegistrationFields.designer)
                TextField("DCI #", text: $configuration.deckRegistrationFields.dciNumber)
                TextField("Location", text: $configuration.deckRegistrationFields.location)
                TextField("Event name", text: $configuration.deckRegistrationFields.eventName)

                Picker("Sort by", selection: $configuration.deckRegistrationSortMode) {
                    ForEach(CardListDeckRegistrationSortMode.allCases) { sortMode in
                        Text(sortMode.displayTitle).tag(sortMode)
                    }
                }
            }
        case .edhrecArticle:
            Section("Export options") {
                Text("EDHREC article export includes category headings when this list has categories.")
                    .foregroundStyle(.secondary)
            }
        case .grimoraArchive:
            Section("Export options") {
                Text("Grimora Archive preserves cards, categories, rich descriptions, and embedded images.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var result: CardListExportResult {
        CardListExporter.export(
            list: list,
            entries: entries,
            categories: categories,
            configuration: configuration,
            date: exportDate
        )
    }

    private var previewText: String {
        result.preview.isEmpty ? "No exportable output for the current configuration." : result.preview
    }

    private func csvColumnBinding(_ column: CardListExportCSVColumn) -> Binding<Bool> {
        Binding {
            configuration.csvColumns.contains(column)
        } set: { isSelected in
            if isSelected {
                configuration.csvColumns = CardListExportCSVColumn.allCases.filter { candidate in
                    candidate == column || configuration.csvColumns.contains(candidate)
                }
            } else {
                configuration.csvColumns.removeAll { $0 == column }
            }
        }
    }

    private func copyResult() {
        guard let content = result.content else {
            return
        }

        ClipboardWriter.copy(content)
        statusMessage = "Export copied."
    }

    private func prepareFileExport() {
        guard let data = result.fileData else {
            return
        }

        exportedDocument = CardListExportDocument(data: data)
        exportContentType = result.format.exportContentType
        exportFilename = result.filename
        isPresentingFileExporter = true
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct CardListExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.plainText, .pdf, .xml, .data, .csvFile, .mtgoDeck, .grimoraList]
    }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum ClipboardWriter {
    static func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #elseif os(iOS) || os(visionOS)
        UIPasteboard.general.string = value
        #endif
    }
}

private extension CardListExportFormat {
    var exportContentType: UTType {
        switch self {
        case .text, .arena, .edhrecArticle:
            .plainText
        case .csv:
            .csvFile
        case .mtgoDek:
            .mtgoDeck
        case .deckRegistrationPDF:
            .pdf
        case .grimoraArchive:
            .grimoraList
        }
    }
}

extension UTType {
    static var csvFile: UTType {
        UTType(filenameExtension: "csv") ?? .plainText
    }

    static var mtgoDeck: UTType {
        UTType(filenameExtension: "dek") ?? .xml
    }

    static var grimoraList: UTType {
        UTType(filenameExtension: "grimoralist") ?? .json
    }
}
