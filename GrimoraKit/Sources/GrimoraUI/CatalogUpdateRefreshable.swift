import GrimoraCore
import SwiftUI

/// The result a search pull-to-refresh reaches after checking the card catalog for newer data.
///
/// Extracted from the view modifier (which is iOS/visionOS-only) so the branching is unit-testable
/// on every platform, mirroring how other search UI logic is split out for testing
/// (e.g. `MacSearchHeaderScrollTrigger`).
enum CatalogUpdateRefreshOutcome: Equatable {
  /// Another library operation was already running, so the check was a no-op — surface nothing.
  case skipped
  /// Newer card data is available; offer to download it.
  case updateAvailable(BulkDataManifest)
  /// The local catalog is already current; flash a brief confirmation.
  case upToDate
}

/// Maps the post-check model state onto the outcome the refresh gesture should present.
///
/// - Parameters:
///   - wasWorking: whether a library operation was already running when the pull began. The update
///     check short-circuits in that case, so any result would be misleading.
///   - updateManifest: `model.updateManifest` after `checkForUpdates` returned — non-nil when there
///     is data available to import (a newer catalog, or an initial library).
func catalogUpdateRefreshOutcome(
  wasWorking: Bool,
  updateManifest: BulkDataManifest?
) -> CatalogUpdateRefreshOutcome {
  guard !wasWorking else {
    return .skipped
  }
  if let updateManifest {
    return .updateAvailable(updateManifest)
  }
  return .upToDate
}

extension View {
  /// Pull-to-refresh on the search results that checks the card catalog for newer data.
  ///
  /// Touch platforms only — on macOS this is a no-op (the Mac surfaces the same actions through the
  /// Library menu, toolbar button, and sidebar callout). Mirrors `cloudSyncRefreshable`, but drives
  /// the catalog-update flow (`checkForUpdates` → optional `importAvailableUpdate`) instead of an
  /// iCloud sync: a downward pull checks whether newer card data is available and, if so, offers to
  /// download it; otherwise it flashes a brief "up to date" confirmation.
  ///
  /// Pass `active: false` to suppress the gesture.
  @ViewBuilder
  func catalogUpdateRefreshable(active: Bool = true) -> some View {
    #if os(iOS) || os(visionOS)
    if active {
      modifier(CatalogUpdateRefreshable())
    } else {
      self
    }
    #else
    self
    #endif
  }
}

#if os(iOS) || os(visionOS)
private struct CatalogUpdateRefreshable: ViewModifier {
  @Environment(GrimoraAppModel.self) private var model

  @State private var pendingManifest: BulkDataManifest?
  @State private var showsUpToDate = false
  @State private var upToDateDismissTask: Task<Void, Never>?

  func body(content: Content) -> some View {
    content
      .refreshable {
        await runCatalogUpdateCheck()
      }
      .alert(
        "New Card Data Available",
        isPresented: alertPresented,
        presenting: pendingManifest
      ) { _ in
        Button("Download") {
          Task { await model.importAvailableUpdate() }
        }
        .accessibilityIdentifier("search-download-update-button")
        Button("Not Now", role: .cancel) {}
      } message: { manifest in
        Text(updateMessage(for: manifest))
      }
      .overlay(alignment: .top) {
        if showsUpToDate {
          upToDateBanner
            .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      .animation(.easeInOut(duration: 0.2), value: showsUpToDate)
  }

  private func runCatalogUpdateCheck() async {
    // Capture before the check, which flips `isWorking` itself: a result is only meaningful when
    // nothing else was already running.
    let wasWorking = await model.isWorking

    // Floor the spinner so an instant "up to date" result doesn't flicker.
    async let floor: Void = floorRefreshSpinner()
    await model.checkForUpdates(manual: true)
    await floor

    await MainActor.run {
      switch catalogUpdateRefreshOutcome(wasWorking: wasWorking, updateManifest: model.updateManifest) {
      case .skipped:
        break
      case .updateAvailable(let manifest):
        pendingManifest = manifest
      case .upToDate:
        presentUpToDateBanner()
      }
    }
  }

  private func presentUpToDateBanner() {
    upToDateDismissTask?.cancel()
    showsUpToDate = true
    upToDateDismissTask = Task {
      try? await Task.sleep(for: .milliseconds(1800))
      guard !Task.isCancelled else { return }
      showsUpToDate = false
    }
  }

  private var alertPresented: Binding<Bool> {
    Binding {
      pendingManifest != nil
    } set: { isPresented in
      if !isPresented {
        pendingManifest = nil
      }
    }
  }

  private func updateMessage(for manifest: BulkDataManifest) -> String {
    let size = ByteCountFormatter.string(fromByteCount: Int64(manifest.size), countStyle: .file)
    return "\(manifest.name) · \(size). Download now?"
  }

  private var upToDateBanner: some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.secondary)
      Text("Card data is up to date")
        .font(.subheadline.weight(.medium))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.separator))
    .shadow(radius: 10, y: 4)
    .padding(.top, 12)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("search-catalog-up-to-date")
  }
}

private func floorRefreshSpinner() async {
  try? await Task.sleep(for: .milliseconds(600))
}
#endif
