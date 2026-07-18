import GrimoraCore
import SwiftUI

/// Settings section managing the instance-wide (global) label palette: list, edit, recolor, delete,
/// and add. Modeled on the "Always Hidden" section — an iCloud-synced, model-backed list. List-local
/// labels are managed from each collection; this is the global set plus the (editable/deletable)
/// built-in defaults.
struct GrimoraSettingsLabelsSection: View {
    @Environment(GrimoraAppModel.self) private var model
    @State private var editTarget: LabelEditTarget?

    private enum LabelEditTarget: Identifiable {
        case new
        case edit(CardLabelRecord)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let label): label.id
            }
        }
    }

    var body: some View {
        Section("Labels") {
            if model.globalLabels.isEmpty {
                Text("Add labels to mark cards in your collections (e.g. “On the way”, “Owned”).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Colored markers you attach to cards in a collection. Global labels sync through iCloud and are available in every collection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(model.globalLabels) { label in
                    HStack(spacing: 10) {
                        LabelSwatch(color: label.color, size: 14)
                        Text(label.name)
                        Spacer()
                        Button("Edit \(label.name)", systemImage: "pencil") {
                            editTarget = .edit(label)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("edit-label-\(label.id)")

                        Button("Remove \(label.name)", systemImage: "minus.circle", role: .destructive) {
                            model.deleteLabel(id: label.id)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("remove-label-\(label.id)")
                    }
                }
            }

            Button("New Label", systemImage: "plus") {
                editTarget = .new
            }
            .accessibilityIdentifier("new-global-label")
        }
        .sheet(item: $editTarget) { target in
            switch target {
            case .new:
                LabelEditorSheet(title: "New Label", saveButtonTitle: "Create") { name, color in
                    _ = model.createLabel(named: name, color: color, listID: nil)
                }
            case .edit(let label):
                LabelEditorSheet(
                    title: "Edit Label",
                    initialName: label.name,
                    initialColor: label.color
                ) { name, color in
                    model.updateLabel(id: label.id, name: name, color: color)
                }
            }
        }
    }
}
