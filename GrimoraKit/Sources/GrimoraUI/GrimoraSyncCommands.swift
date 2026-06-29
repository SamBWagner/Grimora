#if os(macOS)
import SwiftUI

/// macOS menu command for a user-triggered iCloud sync. iCloud sync is global (one
/// shared zone), so a single command covers every context — the dashboard, search, and
/// any open collection. Reaches the app model via `@FocusedValue(\.appModel)`, which
/// `SplitRootView` publishes through `.focusedSceneValue(\.appModel, model)`.
public struct GrimoraSyncCommands: Commands {
  @FocusedValue(\.appModel) private var model: GrimoraAppModel?

  public init() {}

  public var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Sync with iCloud") {
        Task { await model?.syncWithCloudNow() }
      }
      .keyboardShortcut("r", modifiers: .command)
      .disabled(model?.canSyncWithCloudNow != true)

      Divider()
    }
  }
}
#endif
