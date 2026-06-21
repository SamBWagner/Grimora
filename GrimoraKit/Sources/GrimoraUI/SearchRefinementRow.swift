import GrimoraCore
import SwiftUI

struct SearchRefinementRow: View {
    var refinement: SearchRefinement
    var state: SearchRefinementState
    var onCycle: () -> Void

    var body: some View {
        Button(action: onCycle) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                Text(refinement.displayLabel)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(stateTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(refinement.displayLabel)
        .accessibilityValue(stateTitle)
        .accessibilityHint("Cycles between neutral, include, and exclude")
        .accessibilityIdentifier("search-refinement-row-\(refinement.id)")
    }

    private var systemImage: String {
        switch state {
        case .neutral:
            "circle"
        case .include:
            "checkmark.circle.fill"
        case .exclude:
            "minus.circle.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .neutral:
            .secondary
        case .include:
            .green
        case .exclude:
            .red
        }
    }

    private var stateTitle: String {
        switch state {
        case .neutral:
            "Neutral"
        case .include:
            "Include"
        case .exclude:
            "Exclude"
        }
    }
}
