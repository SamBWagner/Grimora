import GrimoraCore
import SwiftUI

/// A live, colour-coded echo of the current Scryfall draft query shown beneath the
/// search field on touch platforms (which cannot colour the `.searchable` text in
/// place the way macOS colours its `NSSearchField`). Each top-level clause is tinted
/// by validity to teach the syntax over time, and a light haptic fires when a clause
/// turns red.
struct SearchSyntaxHighlightBar: View {
    @Environment(\.colorScheme) private var colorScheme
    var query: String
    @State private var invalidFeedbackTrigger = 0

    var body: some View {
        let segments = ScryfallSyntaxHighlighter.segments(for: query)
        let invalidCount = invalidClauseCount(in: segments)

        if !segments.isEmpty {
            ScrollView(.horizontal) {
                Text(attributedQuery(segments: segments))
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(palette.cardSurface.color.opacity(0.6))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.hairline.color)
                    .frame(height: 1)
            }
            .grimoraSelectionFeedback(trigger: invalidFeedbackTrigger)
            .onChange(of: invalidCount) { oldCount, newCount in
                if newCount > oldCount {
                    invalidFeedbackTrigger += 1
                }
            }
            .accessibilityElement()
            .accessibilityIdentifier("search-syntax-highlight-bar")
            .accessibilityLabel("Search syntax")
            .accessibilityValue(query)
        }
    }

    private func invalidClauseCount(in segments: [ScryfallHighlightSegment]) -> Int {
        segments.reduce(into: 0) { count, segment in
            if segment.highlight == .invalid {
                count += 1
            }
        }
    }

    private func attributedQuery(segments: [ScryfallHighlightSegment]) -> AttributedString {
        var attributed = AttributedString(query)
        attributed.foregroundColor = palette.primaryText.color
        for segment in segments {
            guard
                let lower = AttributedString.Index(segment.range.lowerBound, within: attributed),
                let upper = AttributedString.Index(segment.range.upperBound, within: attributed)
            else {
                continue
            }
            attributed[lower..<upper].foregroundColor = Self.color(for: segment.highlight, palette: palette)
        }
        return attributed
    }

    /// Maps a clause classification to its display colour. Mirrors the `NSColor`
    /// mapping used by `NativeMacSearchField` so clauses look identical on every
    /// platform.
    static func color(for highlight: ScryfallClauseHighlight, palette: GrimoraPalette) -> Color {
        switch highlight {
        case .pending:
            palette.primaryText.color
        case .valid:
            Color.green.opacity(0.85)
        case .invalid:
            Color.red
        case .incomplete:
            Color.yellow
        }
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}
