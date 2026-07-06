import GrimoraCore
import SwiftUI

/// iCloud settings sections: the sync toggle, live status, and (when available)
/// list recovery from local pre-sync snapshots.
struct GrimoraSettingsSyncSections: View {
    @Environment(GrimoraAppModel.self) private var model

    @AppStorage(GrimoraCloudSyncPreferences.modeKey)
    private var cloudSyncModeRawValue = GrimoraCloudSyncMode.undecided.rawValue

    @State private var pendingRecoverySnapshotID: CloudSyncRecoverySnapshot.ID?

    var body: some View {
        Group {
            Section("iCloud") {
                Toggle("Sync collections and search settings", isOn: cloudSyncEnabled)
                    .accessibilityIdentifier("cloud-sync-toggle")

                Text("Card data stays local. Collections, favourites, search settings, and search history sync through your private iCloud database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            CloudSyncStatusSection()

            if !model.cloudSyncRecoverySnapshots.isEmpty {
                Section("Sync Recovery") {
                    Text("Grimora keeps local recovery copies before iCloud changes your collections. Restoring also preserves your current collections as another recovery copy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Menu {
                        ForEach(model.cloudSyncRecoverySnapshots) { snapshot in
                            Button(recoveryLabel(for: snapshot)) {
                                pendingRecoverySnapshotID = snapshot.id
                            }
                        }
                    } label: {
                        Label("Restore Previous Collections", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("restore-cloud-sync-lists-menu")
                }
                .confirmationDialog(
                    "Restore Previous Collections?",
                    isPresented: recoveryConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button("Restore Collections", role: .destructive) {
                        guard let pendingRecoverySnapshotID else {
                            return
                        }
                        model.restoreCloudSyncRecoverySnapshot(id: pendingRecoverySnapshotID)
                        self.pendingRecoverySnapshotID = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingRecoverySnapshotID = nil
                    }
                } message: {
                    Text("This replaces the current collections with the selected recovery copy. The current collections are backed up first.")
                }
            }
        }
        .onAppear {
            model.reloadCloudSyncRecoverySnapshots()
            model.reloadCloudSyncDiagnostics()
        }
    }

    private var cloudSyncEnabled: Binding<Bool> {
        Binding {
            GrimoraCloudSyncMode(rawValue: cloudSyncModeRawValue) == .enabled
        } set: { isEnabled in
            cloudSyncModeRawValue = isEnabled
                ? GrimoraCloudSyncMode.enabled.rawValue
                : GrimoraCloudSyncMode.disabled.rawValue
        }
    }

    private var recoveryConfirmationPresented: Binding<Bool> {
        Binding {
            pendingRecoverySnapshotID != nil
        } set: { isPresented in
            if !isPresented {
                pendingRecoverySnapshotID = nil
            }
        }
    }

    private func recoveryLabel(for snapshot: CloudSyncRecoverySnapshot) -> String {
        let listCount = snapshot.listSnapshot.lists.count
        let listNoun = listCount == 1 ? "collection" : "collections"
        let date = snapshot.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(date) - \(listCount) \(listNoun)"
    }
}
