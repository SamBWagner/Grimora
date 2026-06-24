#if os(macOS)
import SwiftUI

/// Help-menu commands.
///
/// Surfaces a discoverable, conventional macOS entry point for replaying the
/// first-run walkthrough — the same action offered in Settings → Tutorial →
/// "Replay Tutorial". The Help menu is the standard home for tutorial /
/// getting-started items on macOS, and it covers the case where a first-time
/// user skips the tour by accident and wants it back.
///
/// Reads the app model through the same `\.appModel` focused scene value the
/// other macOS command groups use (published by ``GrimoraSplitRootView``), and
/// triggers replay via ``GrimoraAppModel/requestOnboardingReplay()``.
public struct GrimoraHelpCommands: Commands {
  @FocusedValue(\.appModel) private var model: GrimoraAppModel?

  public init() {}

  public var body: some Commands {
    CommandGroup(replacing: .help) {
      Button("Replay Tutorial") {
        model?.requestOnboardingReplay()
      }
      .disabled(model == nil)
    }
  }
}
#endif
