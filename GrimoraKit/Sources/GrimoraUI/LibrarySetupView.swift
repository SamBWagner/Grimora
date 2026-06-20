import GrimoraCore
import SwiftUI

struct LibrarySetupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: GrimoraAppModel

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                GrimoraLogoView(size: 72)
            }
        } description: {
            Text(description)
        } actions: {
            if model.isWorking {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    if !model.statusMessage.isEmpty {
                        Text(model.statusMessage)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText.color)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("setup-status-message")
                    }
                }
                .accessibilityIdentifier("setup-progress")
            } else {
                VStack(spacing: 10) {
                    Button {
                        Task { await model.startInitialSetup() }
                    } label: {
                        Text("Start Download")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("start-setup-button")

                    if model.cloudSyncMode != .undecided {
                        Button {
                            model.reconsiderCloudSyncChoice()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("back-to-cloud-sync-choice-button")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(palette.accent.color)
        .background {
            GrimoraAppBackground(palette: palette)
        }
        .accessibilityIdentifier("library-setup")
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }

    private var title: String {
        switch model.libraryState {
        case .missing:
            "Set Up Library"
        case .initializing:
            "Downloading Library"
        case .ready:
            "Library Ready"
        case .failed:
            "Setup Failed"
        }
    }

    private var description: String {
        switch model.libraryState {
        case .missing:
            "Download the Grimora catalog for offline search. Images load as you browse."
        case .initializing:
            "Preparing the offline card library."
        case .ready:
            "The offline library is ready."
        case .failed(let message):
            message
        }
    }
}

struct EmptyListDestinationView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ContentUnavailableView("Select a List", systemImage: "list.bullet.rectangle")
            .tint(palette.accent.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GrimoraAppBackground(palette: palette)
            }
            .accessibilityIdentifier("empty-list-destination")
    }

    private var palette: GrimoraPalette {
        GrimoraPalette(colorScheme: colorScheme)
    }
}

struct SidebarNavigationButtonStyle: ButtonStyle {
    var isSelected: Bool
    var palette: GrimoraPalette

    func makeBody(configuration: Configuration) -> some View {
        GrimoraSidebarNavigationButtonStyle(isSelected: isSelected, palette: palette)
            .makeBody(configuration: configuration)
    }
}
