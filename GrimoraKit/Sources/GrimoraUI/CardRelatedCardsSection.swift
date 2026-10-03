import GrimoraCore
import SwiftUI

enum CardRelatedCardsPresentation: Equatable {
    case hidden
    case loading
    case unavailable
    case empty
    case failure(String)
    case cards([SemanticRelatedCard])

    init(state: CardRelatedCardsState) {
        switch state {
        case .idle:
            self = .hidden
        case .loading:
            self = .loading
        case .unavailable:
            self = .unavailable
        case .empty:
            self = .empty
        case .failed(let message):
            self = .failure(message)
        case .loaded(let cards):
            self = cards.isEmpty ? .empty : .cards(cards)
        }
    }
}

struct CardRelatedCardsSection: View {
    @Environment(\.colorScheme) private var colorScheme

    static let emptyMessage = "No functionally related cards were found."

    var state: CardRelatedCardsState
    var onSelect: (SemanticRelatedCard) -> Void

    var body: some View {
        switch CardRelatedCardsPresentation(state: state) {
        case .hidden:
            EmptyView()
        case .empty:
            section {
                Label(Self.emptyMessage, systemImage: "sparkles")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText.color)
                    .accessibilityIdentifier("card-related-empty")
            }
        case .loading:
            section {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finding related cards…")
                        .font(.callout)
                        .foregroundStyle(palette.secondaryText.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("card-related-loading")
            }
        case .unavailable:
            section {
                Label(
                    "Related cards require a catalog with functional tags.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(palette.secondaryText.color)
                .accessibilityIdentifier("card-related-unavailable")
            }
        case .failure(let message):
            section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText.color)
                    .accessibilityIdentifier("card-related-error")
            }
        case .cards(let cards):
            section {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cards) { relatedCard in
                        relatedCardButton(relatedCard)
                    }
                }
            }
        }
    }

    static func explanationText(for relatedCard: SemanticRelatedCard) -> String {
        let labels = relatedCard.sharedConcepts.prefix(3).map(\.label)
        guard !labels.isEmpty else {
            return "Shared functional tags"
        }
        return "Shared: \(labels.joined(separator: ", "))"
    }

    static func provenanceText(for relatedCard: SemanticRelatedCard) -> String {
        let labels = Set(relatedCard.sharedConcepts.flatMap(\.sources).compactMap { rawSource -> String? in
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
            return "Functional similarity"
        case 1 where labels[0] == "Scryfall":
            return "Community tags from Scryfall"
        case 1:
            return "Source: \(labels[0])"
        default:
            return "Sources: \(labels.joined(separator: ", "))"
        }
    }

    static func accessibilityLabel(for relatedCard: SemanticRelatedCard) -> String {
        let concepts = Array(relatedCard.sharedConcepts.prefix(3).map(\.label))
        let provenance = provenanceText(for: relatedCard)
        guard !concepts.isEmpty else {
            return "Open \(relatedCard.card.name), functionally related card. \(provenance)"
        }
        let relationship: String
        if concepts.count == 1 {
            relationship = concepts[0]
        } else {
            relationship = concepts.dropLast().joined(separator: ", ") + " and " + concepts.last!
        }
        return "Open \(relatedCard.card.name), related by \(relationship). \(provenance)"
    }

    private func section<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            content()
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Related Cards")
                .accessibilityIdentifier("card-related-section")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.primaryText.color)
    }

    private func relatedCardButton(_ relatedCard: SemanticRelatedCard) -> some View {
        Button {
            onSelect(relatedCard)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(relatedCard.card.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.primaryText.color)
                        .multilineTextAlignment(.leading)
                    Text(Self.explanationText(for: relatedCard))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .lineLimit(2)
                    Text(Self.provenanceText(for: relatedCard))
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent.color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
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
        .accessibilityLabel(Self.accessibilityLabel(for: relatedCard))
        .accessibilityHint("Opens this related card in card detail.")
        .accessibilityIdentifier("card-related-card-\(relatedCard.card.id)")
    }

    private var palette: GrimoraPalette {
        GrimoraPalette.cached(for: colorScheme)
    }
}
