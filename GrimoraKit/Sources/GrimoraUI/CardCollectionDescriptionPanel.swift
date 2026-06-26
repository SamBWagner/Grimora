import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

struct CardCollectionDescriptionPanel: View {
    @Binding var rtfdData: Data?
    @Binding var plainText: String

    var palette: GrimoraPalette

    @State private var command: RichTextEditorCommand?
    @State private var isImportingImage = false
    @State private var isShowingLinkPrompt = false
    @State private var linkDraft = "https://"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()
                .overlay(palette.hairline.color)

            toolbar

            NativeRichTextEditor(
                rtfdData: $rtfdData,
                plainText: $plainText,
                command: $command,
                onRequestLink: {
                    isShowingLinkPrompt = true
                },
                onRequestAttachment: {
                    isImportingImage = true
                }
            )
            .frame(minHeight: 260)
            .accessibilityIdentifier("card-list-description-editor")
        }
        .padding(12)
        .background(palette.cardSurface.color.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .fileImporter(
            isPresented: $isImportingImage,
            allowedContentTypes: [.image]
        ) { result in
            importImage(from: result)
        }
        .alert("Add Link", isPresented: $isShowingLinkPrompt) {
            TextField("URL", text: $linkDraft)
            Button("Add") {
                addLink()
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-list-description-panel")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "text.alignleft")
                .accessibilityHidden(true)

            Text("Description")
        }
        .font(.headline.weight(.semibold))
        .foregroundStyle(palette.primaryText.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Description")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("card-list-description-heading")
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Title") {
                    send(.title)
                }
                Button("Heading") {
                    send(.heading)
                }
                Button("Subheading") {
                    send(.subheading)
                }
                Button("Body") {
                    send(.body)
                }
                Button("Monostyled") {
                    send(.monostyled)
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            .help("Text Style")

            Divider()
                .frame(height: 22)

            toolbarButton(systemImage: "bold", help: "Bold") {
                send(.bold)
            }
            toolbarButton(systemImage: "italic", help: "Italic") {
                send(.italic)
            }
            toolbarButton(systemImage: "underline", help: "Underline") {
                send(.underline)
            }
            toolbarButton(systemImage: "strikethrough", help: "Strikethrough") {
                send(.strikethrough)
            }
            toolbarButton(systemImage: "highlighter", help: "Highlight") {
                send(.highlight)
            }

            Divider()
                .frame(height: 22)

            toolbarButton(systemImage: "list.bullet", help: "Bulleted List") {
                send(.bulletedList)
            }
            toolbarButton(systemImage: "minus", help: "Dashed List") {
                send(.dashedList)
            }
            toolbarButton(systemImage: "list.number", help: "Numbered List") {
                send(.numberedList)
            }
            toolbarButton(systemImage: "checklist", help: "Checklist") {
                send(.checklist)
            }
            toolbarButton(systemImage: "quote.opening", help: "Quote") {
                send(.quote)
            }

            Divider()
                .frame(height: 22)

            toolbarButton(systemImage: "link", help: "Link") {
                isShowingLinkPrompt = true
            }
            toolbarButton(systemImage: "photo.badge.plus", help: "Insert Image") {
                isImportingImage = true
            }

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private func toolbarButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 22)
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private func send(_ action: RichTextEditorAction) {
        command = RichTextEditorCommand(action: action)
    }

    private func addLink() {
        let trimmed = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            return
        }
        send(.link(url))
        linkDraft = "https://"
    }

    private func importImage(from result: Result<URL, Error>) {
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
            return
        }
        let typeIdentifier = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.image.identifier
        send(.image(data: data, filename: url.lastPathComponent, typeIdentifier: typeIdentifier))
    }
}
