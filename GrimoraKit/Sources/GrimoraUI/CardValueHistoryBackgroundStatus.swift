import SwiftUI

/// Inline status row shown inside the value section while price history is being
/// fetched or refreshed in the background (a spinner/progress plus title and
/// message), or surfacing a failure. Renders nothing when no activity is present.
struct CardValueHistoryBackgroundStatus: View {
    var activity: ValueHistoryBackgroundActivity?
    var palette: GrimoraPalette

    @ViewBuilder
    var body: some View {
        if let activity {
            HStack(alignment: .center, spacing: 8) {
                if activity.state == .running {
                    if let progress = activity.progress {
                        ProgressView(value: progress)
                            .controlSize(.small)
                            .frame(width: 42)
                            .accessibilityHidden(true)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 42)
                            .accessibilityHidden(true)
                    }
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title)
                            .font(.caption.weight(.semibold))
                        Text(activity.message)
                            .font(.caption2)
                    }
                } icon: {
                    Image(systemName: activity.state == .running ? "clock.arrow.circlepath" : "exclamationmark.triangle")
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(palette.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardSurface.color.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("card-value-history-background-status")
        }
    }
}
