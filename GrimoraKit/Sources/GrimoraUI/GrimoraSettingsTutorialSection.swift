import SwiftUI

/// "Tutorial" settings section: a button to replay the first-run walkthrough.
struct GrimoraSettingsTutorialSection: View {
    var onReplay: () -> Void

    var body: some View {
        Section("Tutorial") {
            Button("Replay Tutorial", action: onReplay)
                .accessibilityIdentifier("replay-tutorial-button")

            Text("Replays the first-run walkthrough with the sample cards.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
