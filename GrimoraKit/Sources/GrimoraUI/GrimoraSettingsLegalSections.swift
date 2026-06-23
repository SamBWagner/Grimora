import SwiftUI

/// Static legal / attribution sections shown in settings (Fan Content notice and
/// data-source credits).
struct GrimoraSettingsLegalSections: View {
    var body: some View {
        Group {
            Section("Unofficial Fan Content") {
                Text("Grimora is unofficial Fan Content permitted under the Fan Content Policy. Not approved or endorsed by Wizards. Portions of the materials used are property of Wizards of the Coast. (C) Wizards of the Coast LLC.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Credits") {
                Text("Card data and imagery are provided by Scryfall. Grimora is not produced by or endorsed by Scryfall.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Value history uses data from MTGJSON. MTGJSON is copyright (C) 2018-Present Zach Halpern and is distributed under the MIT License.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
