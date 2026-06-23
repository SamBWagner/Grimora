import GrimoraCore
import SwiftUI

/// "Format Legality" group of the advanced-search form: a format picker, plus a
/// legal/banned/restricted status picker revealed once a format is chosen.
struct AdvancedSearchFormatSection: View {
    @Binding var format: AdvancedSearchFormat?
    @Binding var formatStatus: AdvancedSearchFormatStatus

    var body: some View {
        Section("Format Legality") {
            Picker("Format", selection: $format) {
                Text("Any").tag(AdvancedSearchFormat?.none)
                ForEach(AdvancedSearchFormat.allCases) { format in
                    Text(format.displayName).tag(AdvancedSearchFormat?.some(format))
                }
            }
            .accessibilityIdentifier("advanced-search-format-picker")

            if format != nil {
                Picker("Status", selection: $formatStatus) {
                    ForEach(AdvancedSearchFormatStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("advanced-search-format-status-picker")
            }
        }
    }
}
