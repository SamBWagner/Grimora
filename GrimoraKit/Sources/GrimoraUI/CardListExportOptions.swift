import GrimoraCore
import SwiftUI

/// Per-format option controls for the card list export sheet. Bound directly to
/// the export configuration so toggling an option updates the live preview.
struct CardListExportOptions: View {
    @Binding var configuration: CardListExportConfiguration

    @ViewBuilder
    var body: some View {
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
}
