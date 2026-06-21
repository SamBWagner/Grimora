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
      case .resolving:
        Text("Choose the data to sync.")
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

struct CloudSyncResolutionView: View {
  @Environment(\.colorScheme) private var colorScheme
  @EnvironmentObject private var model: GrimoraAppModel
  @State private var sourceSnapshotID: DeviceSyncSnapshot.ID?
  @State private var importedListIDsBySnapshotID: [DeviceSyncSnapshot.ID: Set<CardListRecord.ID>] = [:]

  var body: some View {
    Group {
      if let context = model.cloudSyncResolutionContext {
        VStack(alignment: .leading, spacing: 20) {
          if !model.hasLibrary {
            Button("Back", systemImage: "chevron.left", action: model.reconsiderCloudSyncChoice)
              .buttonStyle(.bordered)
              .accessibilityIdentifier("back-to-cloud-sync-choice-button")
          }

          VStack(alignment: .leading, spacing: 7) {
            Text("Review iCloud Data")
              .font(.title2)
              .bold()
              .foregroundStyle(palette.primaryText.color)
            Text(
              "Grimora combined everything it could safely. Choose a starting point, then decide whether to keep any genuinely different versions."
            )
            .font(.callout)
            .foregroundStyle(palette.secondaryText.color)
          }

          ScrollView {
            LazyVStack(spacing: 14) {
              ForEach(context.snapshots) { snapshot in
                CloudSyncResolutionSourceCard(
                  snapshot: snapshot,
                  isSelected: selectedSourceID == snapshot.id,
                  isEligibleSource: context.eligibleSourceSnapshotIDs.contains(snapshot.id),
                  conflictingLists: conflictingLists(
                    in: snapshot,
                    context: context
                  ),
                  selectedConflictingListIDs:
                    importedListIDsBySnapshotID[snapshot.id, default: []],
                  accent: palette.accent.color,
                  selectSource: {
                    selectSource(snapshot.id, context: context)
                  },
                  toggleConflictingList: { listID in
                    toggleImportedList(snapshotID: snapshot.id, listID: listID)
                  }
                )
                .accessibilityIdentifier("sync-source-\(snapshot.id)")
              }
            }
            .padding(.vertical, 2)
          }

          VStack(alignment: .leading, spacing: 12) {
            Text(selectionSummary(context: context))
              .font(.subheadline)
              .foregroundStyle(palette.secondaryText.color)

            HStack {
              Spacer()
              Button("Combine and Continue") {
                resolveSelection()
              }
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(.defaultAction)
              .accessibilityIdentifier("confirm-sync-resolution-button")
            }
          }
        }
        .onAppear {
          prepareSelection(context)
        }
        .onChange(of: context) { _, updatedContext in
          prepareSelection(updatedContext)
        }
      } else {
        ProgressView("Preparing iCloud data…")
      }
    }
    .padding(24)
    .frame(maxWidth: 860, maxHeight: .infinity)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      GrimoraAppBackground(palette: palette)
        .ignoresSafeArea()
    }
    .accessibilityIdentifier("cloud-sync-resolution")
  }

  private var selectedSourceID: DeviceSyncSnapshot.ID {
    sourceSnapshotID ?? model.cloudSyncResolutionContext?.defaultSourceSnapshotID ?? ""
  }

  private func prepareSelection(_ context: CloudSyncResolutionContext) {
    let sourceID =
      context.eligibleSourceSnapshotIDs.contains(selectedSourceID)
      ? selectedSourceID
      : context.defaultSourceSnapshotID
    selectSource(sourceID, context: context)
  }

  private func selectSource(
    _ snapshotID: DeviceSyncSnapshot.ID,
    context: CloudSyncResolutionContext
  ) {
    guard context.eligibleSourceSnapshotIDs.contains(snapshotID) else {
      return
    }
    sourceSnapshotID = snapshotID
    importedListIDsBySnapshotID = context.safeImportedListIDs(for: snapshotID)
  }

  private func toggleImportedList(
    snapshotID: DeviceSyncSnapshot.ID,
    listID: CardListRecord.ID
  ) {
    if importedListIDsBySnapshotID[snapshotID, default: []].contains(listID) {
      importedListIDsBySnapshotID[snapshotID, default: []].remove(listID)
    } else {
      importedListIDsBySnapshotID[snapshotID, default: []].insert(listID)
    }
  }

  private func conflictingLists(
    in snapshot: DeviceSyncSnapshot,
    context: CloudSyncResolutionContext
  ) -> [CardListRecord] {
    let conflictIDs = context.conflictingListIDs(for: snapshot.id)
    return snapshot.listSnapshot.lists.filter { conflictIDs.contains($0.id) }
  }

  private func selectionSummary(context: CloudSyncResolutionContext) -> String {
    let source = context.snapshots.first { $0.id == selectedSourceID }
    let sourceListCount = source?.listCount ?? 0
    let sourceCardCount = source?.entryCount ?? 0
    var importedListCount = 0
    var importedCardCount = 0

    for snapshot in context.snapshots where snapshot.id != selectedSourceID {
      let selectedIDs = importedListIDsBySnapshotID[snapshot.id, default: []]
      importedListCount += selectedIDs.count
      importedCardCount += snapshot.listSnapshot.entries
        .filter { selectedIDs.contains($0.listID) }
        .reduce(0) { $0 + max(1, $1.quantity) }
    }

    let listCount = sourceListCount + importedListCount
    let cardCount = sourceCardCount + importedCardCount
    let listNoun = listCount == 1 ? "list" : "lists"
    let cardNoun = cardCount == 1 ? "card" : "cards"
    return "\(listCount) \(listNoun) and \(cardCount) \(cardNoun) will be combined. A recovery copy is created first."
  }

  private func resolveSelection() {
    Task {
      await model.resolveCloudSync(
        sourceSnapshotID: selectedSourceID,
        importedListIDsBySnapshotID: importedListIDsBySnapshotID
      )
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
      case .needsAppUpdate:
        Label("Update Grimora to continue syncing.", systemImage: "exclamationmark.triangle")
      case .resolving:
        Label("Choose which device data to sync.", systemImage: "icloud.and.arrow.up")
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
