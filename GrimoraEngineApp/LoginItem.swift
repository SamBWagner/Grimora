import Foundation
import Observation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the dashboard and the menu-bar item can show and toggle
/// whether "Grimora Engine" launches automatically at login.
///
/// The registration only sticks once the app is installed in a stable location (e.g.
/// `/Applications`) and code-signed — see `Tools/install_grimora_engine_app.sh`. Running the
/// app straight out of DerivedData will register, but macOS may drop the item when that build
/// path changes.
@MainActor
@Observable
final class LoginItemController {
  /// Whether the app is currently registered to launch at login.
  private(set) var isEnabled: Bool
  /// Last error encountered while toggling, surfaced to the UI (nil when the last action succeeded).
  private(set) var lastError: String?

  init() {
    isEnabled = SMAppService.mainApp.status == .enabled
  }

  /// Re-reads the live registration status. Cheap; call when a menu opens to stay in sync with
  /// changes the user made in System Settings → General → Login Items.
  func refresh() {
    isEnabled = SMAppService.mainApp.status == .enabled
  }

  /// Turns launch-at-login on the first time the *installed* app runs, so it's enabled by
  /// default without the user having to find the toggle. Guarded by a one-shot flag so a later
  /// manual "off" sticks, and restricted to `/Applications` builds so transient Xcode/DerivedData
  /// runs don't register a stale path.
  func enableByDefaultIfNeeded() {
    let key = "didConfigureLoginItem"
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
    setEnabled(true)
    UserDefaults.standard.set(true, forKey: key)
  }

  /// Registers or unregisters the app as a login item.
  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      lastError = nil
    } catch {
      lastError = String(describing: error)
    }
    refresh()
  }
}
