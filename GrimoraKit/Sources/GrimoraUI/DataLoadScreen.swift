import SwiftUI

struct DataLoadScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    var activity: GrimoraLibraryActivity
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            GrimoraAppBackground(palette: palette)

            VStack(spacing: 18) {
                headerMark
                statusPanel
            }
            .padding(24)
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(activity.title)
        .accessibilityValue(activity.message)
        .accessibilityIdentifier("data-load-screen")
    }

    private var headerMark: some View {
        ZStack(alignment: .bottomTrailing) {
            GrimoraLogoView(size: 88)
                .shadow(color: palette.shadow.color, radius: 16, x: 0, y: 9)

            statusBadge
                .offset(x: 8, y: 8)
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(activity.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.primaryText.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(activity.message)
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText.color)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .overlay(palette.hairline.color)

            statusContent
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairline.color, lineWidth: 1)
        }
        .shadow(color: palette.shadow.color, radius: 26, x: 0, y: 16)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch activity.state {
        case .running:
            if activity.steps.isEmpty {
                fallbackProgressContent
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(activity.steps) { step in
                        DataLoadStepRow(step: step, palette: palette, statusTint: statusTint)
                    }
                }
            }
        case .succeeded:
            completionRow(
                symbol: "checkmark.circle.fill",
                text: "Ready",
                tint: .green
            )
        case .failed:
            VStack(spacing: 16) {
                completionRow(
                    symbol: "exclamationmark.triangle.fill",
                    text: "Needs attention",
                    tint: .orange
                )

                Button {
                    onDismiss()
                } label: {
                    Label("Done", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(palette.accent.color)
                .accessibilityIdentifier("data-load-done-button")
            }
        }
    }

    private var fallbackProgressContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(statusTint)
                    .accessibilityHidden(true)

                Text("Working on your local library")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1)
            }

            ProgressView(value: 0, total: 1)
                .progressViewStyle(.linear)
                .tint(statusTint)
                .accessibilityIdentifier("data-load-progress")
        }
    }

    private var statusBadge: some View {
        Image(systemName: badgeSymbol)
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(statusTint)
            .frame(width: 38, height: 38)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.hairline.color, lineWidth: 1)
            }
            .shadow(color: palette.shadow.color, radius: 10, x: 0, y: 6)
            .accessibilityHidden(true)
    }

    private func completionRow(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.primaryText.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(statusFill(for: tint), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(statusStroke(for: tint), lineWidth: 1)
        }
    }

    private var badgeSymbol: String {
        switch activity.state {
        case .succeeded:
            "checkmark"
        case .failed:
            "exclamationmark"
        case .running:
            switch activity.operation {
            case .setupLibrary, .importCardDatabase, .updateSyncedDatabase:
                "tray.and.arrow.down"
            case .refreshCardDatabase:
                "arrow.triangle.2.circlepath"
            case .deleteAndRefreshDatabase:
                "trash"
            case .refreshCardValues:
                "chart.line.uptrend.xyaxis"
            }
        }
    }

    private var statusTint: Color {
        switch activity.state {
        case .running:
            activity.operation == .deleteAndRefreshDatabase ? .orange : palette.accent.color
        case .succeeded:
            .green
        case .failed:
            .orange
        }
    }

    private func statusFill(for color: Color) -> Color {
        color.opacity(colorScheme == .dark ? 0.16 : 0.10)
    }

    private func statusStroke(for color: Color) -> Color {
        color.opacity(colorScheme == .dark ? 0.34 : 0.22)
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}

#Preview("Running") {
    DataLoadScreen(
        activity: GrimoraLibraryActivity(
            operation: .deleteAndRefreshDatabase,
            title: "Deleting and Refreshing Database",
            message: "Deleted cached images and refreshed 114,177 cards. Images load as you browse.",
            state: .running,
            steps: [
                GrimoraLibraryActivityStep(
                    id: "download-card-data",
                    title: "Download card data",
                    detail: "61 MB of 149 MB",
                    progress: 0.41,
                    state: .running
                ),
                GrimoraLibraryActivityStep(
                    id: "build-card-library",
                    title: "Build local library"
                ),
                GrimoraLibraryActivityStep(
                    id: "download-price-history",
                    title: "Download price history"
                ),
            ]
        ),
        onDismiss: {}
    )
    .frame(width: 700, height: 500)
}

#Preview("Failed") {
    DataLoadScreen(
        activity: GrimoraLibraryActivity(
            operation: .deleteAndRefreshDatabase,
            title: "Deleting and Refreshing Database",
            message: "Deleted cached images and refreshed 114,177 cards. Value history could not be updated; card search is ready.",
            state: .failed
        ),
        onDismiss: {}
    )
    .frame(width: 700, height: 500)
}
