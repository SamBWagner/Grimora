import GrimoraCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

struct CardCollectionExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let list: CardCollectionRecord
    let entries: [CardCollectionEntryRecord]
    let categories: [CardCollectionCategoryRecord]

    @State private var configuration: CardCollectionExportConfiguration
    @State private var exportDate: Date
    @State private var isPresentingFileExporter = false
    @State private var exportedDocument = CardCollectionExportDocument()
    @State private var exportContentType: UTType = .plainText
    @State private var exportFilename = "Card List.txt"
    @State private var statusMessage: String?

    init(
        list: CardCollectionRecord,
        entries: [CardCollectionEntryRecord],
        categories: [CardCollectionCategoryRecord] = []
    ) {
        self.list = list
        self.entries = entries
        self.categories = categories

        let now = Date()
        var defaultConfiguration = CardCollectionExportConfiguration.defaultConfiguration()
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
                        ForEach(CardCollectionExportFormat.allCases) { format in
                            Text(format.displayTitle).tag(format)
                        }
                    }
                    .accessibilityIdentifier("card-list-export-format-picker")
                }

                CardCollectionExportOptions(configuration: $configuration)

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
        #if os(macOS) || os(visionOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
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

    private var result: CardCollectionExportResult {
        CardCollectionExporter.export(
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

        exportedDocument = CardCollectionExportDocument(data: data)
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

private struct CardCollectionExportDocument: FileDocument {
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

private extension CardCollectionExportFormat {
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
