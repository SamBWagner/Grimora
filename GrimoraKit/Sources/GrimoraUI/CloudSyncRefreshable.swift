import SwiftUI

extension View {
  /// Pull-to-refresh that triggers a manual iCloud sync ("Sync with iCloud").
  ///
  /// Touch platforms only, and only while sync is enabled — on macOS this is a no-op
  /// (the Mac surfaces the action through the menu command + toolbar button instead),
  /// and when sync is off there is nothing to fetch so the control is omitted entirely.
  ///
  /// Pass `active: false` to suppress the gesture (e.g. while a multi-select drag is in
  /// progress, so the downward pull doesn't fight the selection drag).
  @ViewBuilder
  func cloudSyncRefreshable(_ model: GrimoraAppModel, active: Bool = true) -> some View {
    #if os(iOS) || os(visionOS)
    if active, model.isCloudSyncEnabled {
      refreshable {
        // Floor the spinner so an instant no-op sync (no remote changes) doesn't flicker.
        async let floor: Void = floorRefreshSpinner()
        await model.syncWithCloudNow()
        await floor
      }
    } else {
      self
    }
    #else
    self
    #endif
  }
}

#if os(iOS) || os(visionOS)
private func floorRefreshSpinner() async {
  try? await Task.sleep(for: .milliseconds(600))
}
#endif
