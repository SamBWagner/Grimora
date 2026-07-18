import GrimoraCore
import SwiftUI

/// A small sheet for creating or editing a label: a name field plus the curated color palette.
/// Reused by the card context menu, the detail pane, and the Settings manager.
struct LabelEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let saveButtonTitle: String
    @State private var name: String
    @State private var color: LabelColor
    var onSave: (String, LabelColor) -> Void

    init(
        title: String,
        saveButtonTitle: String = "Save",
        initialName: String = "",
        initialColor: LabelColor = .blue,
        onSave: @escaping (String, LabelColor) -> Void
    ) {
        self.title = title
        self.saveButtonTitle = saveButtonTitle
        _name = State(initialValue: initialName)
        _color = State(initialValue: initialColor)
        self.onSave = onSave
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var palette: GrimoraPalette { .cached(for: colorScheme) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Label name", text: $name)
                        .accessibilityIdentifier("label-editor-name")
                }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 12)], spacing: 12) {
                        ForEach(LabelColor.allCases) { option in
                            Button {
                                color = option
                            } label: {
                                LabelSwatch(color: option, size: 28)
                                    .padding(5)
                                    .overlay {
                                        if option == color {
                                            Circle().strokeBorder(palette.accent.color, lineWidth: 3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.displayName)
                            .accessibilityAddTraits(option == color ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        onSave(trimmedName, color)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                    .accessibilityIdentifier("label-editor-save")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 380)
        #endif
    }
}

extension View {
    /// Presents the label create/edit sheet.
    func labelEditor(
        isPresented: Binding<Bool>,
        title: String,
        saveButtonTitle: String = "Save",
        initialName: String = "",
        initialColor: LabelColor = .blue,
        onSave: @escaping (String, LabelColor) -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            LabelEditorSheet(
                title: title,
                saveButtonTitle: saveButtonTitle,
                initialName: initialName,
                initialColor: initialColor,
                onSave: onSave
            )
        }
    }
}
