import GrimoraCore
import SwiftUI

enum MacSearchHeaderScrollTrigger: Equatable {
    case expand
    case hold
    case collapse

    static let expandThreshold: CGFloat = 8
    static let collapseThreshold: CGFloat = 48

    init(contentOffsetY: CGFloat) {
        let offsetY = max(0, contentOffsetY)
        if offsetY <= Self.expandThreshold {
            self = .expand
        } else if offsetY >= Self.collapseThreshold {
            self = .collapse
        } else {
            self = .hold
        }
    }

    init(legacyContentMinY: CGFloat) {
        self.init(contentOffsetY: -legacyContentMinY)
    }
}

struct SearchHistorySuggestions: View {
    var searchText: String
    var history: [String]
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        ForEach(filteredHistory, id: \.self) { query in
            Button {
                onSelect(query)
            } label: {
                Label(query, systemImage: "clock.arrow.circlepath")
            }
            .searchCompletion(query)
            .accessibilityIdentifier("search-history-suggestion-\(query)")
        }
    }

    private var filteredHistory: [String] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return history
        }

        return history.filter {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

struct SearchInputModeToggle: View {
    @EnvironmentObject private var model: GrimoraAppModel

    var body: some View {
        Button {
            model.togglePlainTextSearchMode()
        } label: {
            Label(accessibilityLabel, systemImage: searchAISymbolName)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityIdentifier("plain-text-search-mode-toggle")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .disabled(!model.isPlainTextSearchAvailable && !model.isPlainTextSearchModeActive)
        .help(helpText)
    }

    private var accessibilityLabel: String {
        model.isPlainTextSearchModeActive ? "Disable Plain Text Search" : "Enable Plain Text Search"
    }

    private var accessibilityValue: String {
        if model.isPlainTextSearchModeActive {
            return "On"
        }
        if let unavailableMessage = model.plainTextSearchUnavailableMessage {
            return unavailableMessage
        }
        return "Off"
    }

    private var helpText: String {
        if let unavailableMessage = model.plainTextSearchUnavailableMessage,
           !model.isPlainTextSearchModeActive {
            return unavailableMessage
        }
        return model.isPlainTextSearchModeActive ? "Using plain-text search" : "Use plain-text search"
    }
}

struct PlainTextSearchStatusView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: GrimoraAppModel

    var body: some View {
        if model.isPlainTextSearchModeActive {
            statusContent
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if model.isTranslatingSearch {
            statusLabel("Translating", systemImage: searchAISymbolName)
                .accessibilityIdentifier("plain-text-search-translating")
        } else if let message = model.plainTextSearchErrorMessage {
            statusLabel(message, systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("plain-text-search-error")
        } else if let query = model.generatedSearchQuery {
            statusLabel(query, systemImage: "curlybraces")
                .accessibilityIdentifier("plain-text-generated-query")
        }
    }

    private func statusLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.secondaryText.color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(palette.hairline.color, lineWidth: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}

var searchAISymbolName: String {
    #if os(macOS)
    if #available(macOS 26.0, *) {
        return "apple.intelligence"
    }
    return "atom"
    #elseif os(iOS)
    if #available(iOS 26.0, *) {
        return "apple.intelligence"
    }
    return "sparkles"
    #elseif os(visionOS)
    if #available(visionOS 26.0, *) {
        return "apple.intelligence"
    }
    return "sparkles"
    #else
    return "sparkles"
    #endif
}
