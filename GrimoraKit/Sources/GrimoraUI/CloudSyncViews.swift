import GrimoraCore
import SwiftUI

struct CloudSyncSetupView: View {
  @Environment(\.colorScheme) private var colorScheme
  @EnvironmentObject private var model: GrimoraAppModel

  var body: some View {
    ContentUnavailableView {
      Label {
        Text("Set Up Grimora")
      } icon: {
        GrimoraLogoView(size: 72)
      }
    } description: {
      Text("Download the card database, then choose whether lists and search settings sync with iCloud on your devices.")
    } actions: {
      VStack(spacing: 10) {
        Button {
          model.chooseCloudSync()
        } label: {
          Label("Sync with iCloud", systemImage: "icloud")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("enable-cloud-sync-button")

        Button {
          model.keepDeviceSeparate()
        } label: {
          Text("Keep This Device Separate")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("disable-cloud-sync-button")

        cloudSyncStatusText
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .tint(palette.accent.color)
    .background {
      GrimoraAppBackground(palette: palette)
    }
    .accessibilityIdentifier("cloud-sync-setup")
  }

  private var cloudSyncStatusText: some View {
    Group {
      switch model.cloudSyncStatus {
      case .preparing, .syncing:
        HStack(spacing: 8) {
          ProgressView()
          Text("Checking iCloud...")
        }
      case .unavailable(let message), .failed(let message):
        Text(message)
      case .waitingForDatabaseUpdate:
        Text("The card database will be matched to your synced library.")
      case .needsAppUpdate:
        Text("Update Grimora to continue syncing.")
      case .resolving:
        Text("Choose the data to sync.")
      case .disabled, .ready, .appliedRemoteSnapshot:
        EmptyView()
      }
    }
    .font(.caption)
    .foregroundStyle(palette.secondaryText.color)
    .multilineTextAlignment(.center)
  }

  private var palette: GrimoraPalette {
    GrimoraPalette(colorScheme: colorScheme)
  }
}

struct CloudSyncResolutionView: View {
  @Environment(\.colorScheme) private var colorScheme
  @EnvironmentObject private var model: GrimoraAppModel
  @State private var sourceSnapshotID: DeviceSyncSnapshot.ID?
  @State private var importedListIDsBySnapshotID: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if !model.hasLibrary {
        Button {
          model.reconsiderCloudSyncChoice()
        } label: {
          Label("Back", systemImage: "chevron.left")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("back-to-cloud-sync-choice-button")
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Choose Sync Source")
          .font(.title2.weight(.semibold))
          .foregroundStyle(palette.primaryText.color)
        Text("Pick the device that should become the starting point. You can also import individual lists from the other devices.")
          .font(.callout)
          .foregroundStyle(palette.secondaryText.color)
      }

      List {
        ForEach(model.cloudSyncResolutionSnapshots) { snapshot in
          Section {
            Button {
              sourceSnapshotID = snapshot.id
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(snapshot.deviceName)
                    .font(.headline)
                  Text("\(snapshot.listCount) lists, \(snapshot.entryCount) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedSourceID == snapshot.id {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.accent.color)
                }
              }
            }
            .accessibilityIdentifier("sync-source-\(snapshot.id)")

            ForEach(snapshot.listSnapshot.lists) { list in
              Toggle(isOn: importBinding(snapshotID: snapshot.id, listID: list.id)) {
                Text(list.name)
              }
              .disabled(selectedSourceID == snapshot.id)
            }
          } header: {
            Text(snapshot.deviceName)
          }
        }
      }
      .listStyle(.inset)

      HStack {
        Spacer()
        Button {
          Task {
            await model.resolveCloudSync(
              sourceSnapshotID: selectedSourceID,
              importedListIDsBySnapshotID: importedListIDsBySnapshotID
            )
          }
        } label: {
          Text("Use Selected Data")
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.cloudSyncResolutionSnapshots.isEmpty)
        .accessibilityIdentifier("confirm-sync-resolution-button")
      }
    }
    .padding(24)
    .frame(maxWidth: 820, maxHeight: .infinity)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      GrimoraAppBackground(palette: palette)
        .ignoresSafeArea()
    }
    .onAppear {
      sourceSnapshotID = selectedSourceID
    }
    .accessibilityIdentifier("cloud-sync-resolution")
  }

  private var selectedSourceID: DeviceSyncSnapshot.ID {
    sourceSnapshotID ?? model.cloudSyncResolutionSnapshots.first?.id ?? ""
  }

  private func importBinding(
    snapshotID: DeviceSyncSnapshot.ID,
    listID: CardListRecord.ID
  ) -> Binding<Bool> {
    Binding {
      importedListIDsBySnapshotID[snapshotID, default: []].contains(listID)
    } set: { isImported in
      var ids = importedListIDsBySnapshotID[snapshotID, default: []]
      if isImported {
        ids.insert(listID)
      } else {
        ids.remove(listID)
      }
      importedListIDsBySnapshotID[snapshotID] = ids
    }
  }

  private var palette: GrimoraPalette {
    GrimoraPalette(colorScheme: colorScheme)
  }
}

struct CloudSyncStatusSection: View {
  @EnvironmentObject private var model: GrimoraAppModel

  var body: some View {
    Section("iCloud Sync") {
      switch model.cloudSyncStatus {
      case .waitingForDatabaseUpdate(let identity):
        VStack(alignment: .leading, spacing: 8) {
          Text("A newer synced card database is required before lists can sync.")
          if let manifest = identity.manifest {
            Text(manifest.name)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Button {
            Task { await model.importRequiredCloudDatabaseUpdate() }
          } label: {
            Text("Update Card Database")
          }
          .disabled(model.isWorking)
        }
      case .needsAppUpdate:
        Label("Update Grimora to continue syncing.", systemImage: "exclamationmark.triangle")
      case .resolving:
        Label("Choose which device data to sync.", systemImage: "icloud.and.arrow.up")
      case .unavailable(let message), .failed(let message):
        Label(message, systemImage: "icloud.slash")
      case .ready, .appliedRemoteSnapshot:
        Label("Sync is ready.", systemImage: "icloud")
      case .preparing, .syncing:
        HStack {
          ProgressView()
          Text("Syncing...")
        }
      case .disabled:
        Text("Sync is off.")
      }
    }
  }
}
