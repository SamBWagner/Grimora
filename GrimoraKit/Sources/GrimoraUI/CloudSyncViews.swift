import GrimoraCore
import SwiftUI

struct CloudSyncSetupView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(GrimoraAppModel.self) private var model

  var body: some View {
    ContentUnavailableView {
      Label {
        Text("Set Up Grimora")
      } icon: {
        GrimoraLogoView(size: 72)
      }
    } description: {
      Text("Download the card database, then choose whether lists, favourites, and search settings sync with iCloud on your devices.")
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
      case .needsAppUpdate:
        Text("Update Grimora to continue syncing.")
      case .accountChangeRequiresResolution:
        Text("The iCloud account changed. Choose how to protect the local library.")
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

struct CloudSyncStatusSection: View {
  @Environment(GrimoraAppModel.self) private var model

  var body: some View {
    Section("iCloud Sync") {
      switch model.cloudSyncStatus {
      case .needsAppUpdate:
        Label("Update Grimora to continue syncing.", systemImage: "exclamationmark.triangle")
      case .accountChangeRequiresResolution:
        VStack(alignment: .leading, spacing: 8) {
          Label(
            "The iCloud account changed. Grimora paused before uploading any local data.",
            systemImage: "person.crop.circle.badge.exclamationmark"
          )
          Button("Use This iCloud Account") {
            model.useCurrentICloudAccount()
          }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("accept-current-icloud-account-button")

          Button("Keep This Device Separate") {
            model.keepDeviceSeparate()
          }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("separate-current-icloud-account-button")

          Text("Sign back into the previous iCloud account in System Settings to continue without changing accounts.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      case .unavailable(let message), .failed(let message):
        Label(message, systemImage: "icloud.slash")
      case .ready, .appliedRemoteSnapshot:
        VStack(alignment: .leading, spacing: 6) {
          Label("Sync is ready.", systemImage: "icloud")
          if model.cloudSyncPendingChangeCount > 0 {
            Text("\(model.cloudSyncPendingChangeCount) local changes waiting to upload")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if let lastUpload = model.cloudSyncLastUploadAt {
            Text("Last upload: \(lastUpload.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if let lastDownload = model.cloudSyncLastDownloadAt {
            Text("Last download: \(lastDownload.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
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
