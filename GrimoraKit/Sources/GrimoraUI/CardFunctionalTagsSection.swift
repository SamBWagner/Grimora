import GrimoraCore
import SwiftUI

enum CardFunctionalTagsPresentation: Equatable {
    case hidden
    case loading
    case unavailable
    case empty
    case failure(String)
    case tags([SemanticCardFunctionalTag])

    init(state: CardFunctionalTagsState) {
        switch state {
        case .idle:
            self = .hidden
        case .empty:
            self = .empty
        case .loading:
            self = .loading
        case .unavailable:
            self = .unavailable
        case .failed(let message):
            self = .failure(message)
        case .loaded(let tags):
            self = tags.isEmpty ? .hidden : .tags(tags)
        }
    }
}

struct CardFunctionalTagsSection: View {
    @Environment(\.colorScheme) private var colorScheme

    var state: CardFunctionalTagsState
    var onSearch: (SemanticCardFunctionalTag) -> Void

    var body: some View {
        switch CardFunctionalTagsPresentation(state: state) {
        case .hidden, .empty:
            EmptyView()
        case .loading:
            section {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading functions…")
                        .font(.callout)
                        .foregroundStyle(palette.secondaryText.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("card-functions-loading")
            }
        case .unavailable:
            section {
                Label(
                    "Functions require a catalog with Scryfall Oracle Tags.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(palette.secondaryText.color)
                .accessibilityIdentifier("card-functions-unavailable")
            }
        case .failure(let message):
            section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText.color)
                    .accessibilityIdentifier("card-functions-error")
            }
        case .tags(let tags):
            section {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 116), alignment: .leading)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(tags) { tag in
                            tagButton(tag)
                        }
                    }

                    Label(Self.provenanceText(for: tags), systemImage: "person.3")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .accessibilityIdentifier("card-functions-provenance")
                }
            }
        }
    }

    static func accessibilityLabel(for tag: SemanticCardFunctionalTag) -> String {
        "Search cards tagged \(tag.label)"
    }

    static func provenanceText(for tags: [SemanticCardFunctionalTag]) -> String {
        let labels = Set(tags.flatMap(\.sources).compactMap { rawSource -> String? in
            let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else {
                return nil
            }
            return source.range(of: "scryfall", options: .caseInsensitive) == nil
                ? source
                : "Scryfall"
        }).sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        switch labels.count {
        case 0:
            return "Community functional tags"
        case 1 where labels[0] == "Scryfall":
            return "Community tags from Scryfall"
        case 1:
            return "Source: \(labels[0])"
        default:
            return "Sources: \(labels.joined(separator: ", "))"
        }
    }

    private func section<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            content()
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Functions")
                .accessibilityIdentifier("card-functions-section")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.primaryText.color)
    }

    private func tagButton(_ tag: SemanticCardFunctionalTag) -> some View {
        Button {
            onSearch(tag)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tag.label)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.leading)
                    if let annotation = tag.annotation?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !annotation.isEmpty {
                        Text(annotation)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText.color)
                            .lineLimit(1)
                    }
                }
                Image(systemName: "magnifyingglass")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.accent.color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.placeholderFill.color.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(palette.hairline.color, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(tag.description ?? Self.accessibilityLabel(for: tag))
        .accessibilityLabel(Self.accessibilityLabel(for: tag))
        .accessibilityHint("Runs an offline Oracle tag search.")
        .accessibilityIdentifier("card-function-tag-\(tag.slug)")
    }

    private var palette: GrimoraPalette {
        GrimoraPalette.cached(for: colorScheme)
    }
}
