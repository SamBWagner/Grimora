import SwiftUI

/// One step of the data-load screen's progress checklist: a state indicator, the
/// step title/detail, a percentage readout, and a progress bar. Rendered once per
/// step and refreshed as download/build progress changes.
struct DataLoadStepRow: View {
    let step: GrimoraLibraryActivityStep
    var palette: GrimoraPalette
    var statusTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                stepStateIndicator(for: step.state)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.primaryText.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    if let detail = step.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                    }
                }

                Spacer(minLength: 12)

                Text(progressText(for: step))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }

            progressIndicator(for: step)
                .accessibilityIdentifier("data-load-progress-\(step.id)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(step.title)
        .accessibilityValue(progressText(for: step))
        .accessibilityIdentifier("data-load-step-\(step.id)")
    }

    @ViewBuilder
    private func stepStateIndicator(for state: GrimoraLibraryActivityStepState) -> some View {
        switch state {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(tint(for: state))
                .frame(width: 16)
                .accessibilityHidden(true)
        case .pending, .succeeded, .failed:
            Image(systemName: symbol(for: state))
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint(for: state))
                .frame(width: 16)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func progressIndicator(for step: GrimoraLibraryActivityStep) -> some View {
        if let value = progressValue(for: step) {
            ProgressView(value: value, total: 1)
                .progressViewStyle(.linear)
                .tint(tint(for: step.state))
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(tint(for: step.state))
        }
    }

    private func symbol(for state: GrimoraLibraryActivityStepState) -> String {
        switch state {
        case .pending:
            "circle"
        case .running:
            "arrow.triangle.2.circlepath"
        case .succeeded:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func tint(for state: GrimoraLibraryActivityStepState) -> Color {
        switch state {
        case .pending:
            palette.secondaryText.color.opacity(0.7)
        case .running:
            statusTint
        case .succeeded:
            .green
        case .failed:
            .orange
        }
    }

    private func progressValue(for step: GrimoraLibraryActivityStep) -> Double? {
        switch step.state {
        case .succeeded:
            1
        case .failed:
            step.progress ?? 0
        case .pending, .running:
            step.progress
        }
    }

    private func progressText(for step: GrimoraLibraryActivityStep) -> String {
        switch step.state {
        case .pending:
            "Queued"
        case .running:
            if let progress = progressValue(for: step) {
                "\(Int((progress * 100).rounded()))%"
            } else {
                "Working"
            }
        case .succeeded:
            "Done"
        case .failed:
            "Failed"
        }
    }
}
