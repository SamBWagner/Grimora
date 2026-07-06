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
      Text("Download the card database, then choose whether collections, favourites, and search settings sync with iCloud on your devices.")
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
      statusContent
      if showsDiagnostics {
        diagnosticsContent
      }
    }
  }

  @ViewBuilder
  private var statusContent: some View {
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
      VStack(alignment: .leading, spacing: 8) {
        Label(message, systemImage: "icloud.slash")
        Button {
          Task { await model.syncWithCloudNow() }
        } label: {
          Label("Try Again", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.bordered)
        .disabled(!model.canSyncWithCloudNow || model.isPerformingCloudSync)
        .accessibilityIdentifier("retry-cloud-sync-button")
      }
    case .ready, .appliedRemoteSnapshot:
      Label("Sync is ready.", systemImage: "icloud")
    case .preparing, .syncing:
      HStack {
        ProgressView()
        Text("Syncing…")
      }
    case .disabled:
      Text("Sync is off.")
    }
  }

  /// Show the diagnostics block whenever sync is engaged (ready, in-flight, or in a retryable
  /// failure) — including failures, so a "Last download: Never" or stale timestamp is visible.
  private var showsDiagnostics: Bool {
    switch model.cloudSyncStatus {
    case .disabled, .needsAppUpdate, .accountChangeRequiresResolution:
      return false
    case .ready, .appliedRemoteSnapshot, .unavailable, .failed, .preparing, .syncing:
      return true
    }
  }

  @ViewBuilder
  private var diagnosticsContent: some View {
    VStack(alignment: .leading, spacing: 4) {
      diagnosticRow("iCloud environment", value: syncEnvironmentDescription)
      if model.cloudSyncPendingChangeCount > 0 {
        diagnosticRow("Waiting to upload", value: "\(model.cloudSyncPendingChangeCount)")
      }
      diagnosticRow(
        "Last upload",
        value: model.cloudSyncLastUploadAt.map(Self.formatted) ?? "Never"
      )
      diagnosticRow(
        "Last download",
        value: model.cloudSyncLastDownloadAt.map(Self.formatted) ?? "Never"
      )

      Text("Debug builds use iCloud's Development database; TestFlight and App Store builds use Production. Those are separate stores and don't sync with each other.")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private func diagnosticRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(value).monospacedDigit()
    }
  }

  private static func formatted(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }

  /// Build-channel heuristic for the CloudKit environment: Debug/Xcode builds talk to the
  /// Development database, while Release (TestFlight/App Store) builds talk to Production.
  private var syncEnvironmentDescription: String {
    #if DEBUG
      return "Development"
    #else
      return "Production"
    #endif
  }
}
