import AppKit
import GrimoraEngineKit
import SwiftUI

/// The tray-icon label shown in the menu bar. Lives for the whole app session, so it owns the
/// polling loop — that keeps the icon and the menu in sync with the engine even when the
/// dashboard window is closed. The glyph fills and pulses while a run is in progress (including
/// launchd-driven runs, which `EngineDashboardModel` reflects via its on-disk snapshot).
struct MenuBarLabel: View {
  let model: EngineDashboardModel
  let loginItem: LoginItemController

  var body: some View {
    Image(systemName: model.isBusy ? "cylinder.split.1x2.fill" : "cylinder.split.1x2")
      .symbolEffect(.pulse, isActive: model.isBusy)
      .task {
        loginItem.enableByDefaultIfNeeded()
        await model.startPolling()
      }
  }
}

/// The contents of the menu-bar (tray) menu: a live status header plus the same build/publish
/// actions as the main window, a launch-at-login toggle, and shortcuts to open or quit the app.
/// Reuses `EngineDashboardModel` and `EngineFormat`; it adds no engine logic of its own.
struct MenuBarStatusView: View {
  let model: EngineDashboardModel
  let loginItem: LoginItemController
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    statusHeader

    if let next = model.nextScheduledRun {
      Text("Next run \(EngineFormat.relative(next))")
    }

    Divider()

    Button("Check for Updates") { Task { await model.checkForUpdates() } }
      .disabled(model.isChecking)
    Button("Download & Build") { Task { await model.build(force: false) } }
      .disabled(model.isBusy)
    Button("Publish") { Task { await model.publish() } }
      .disabled(!model.canPublish)
    Button("Build & Publish") { Task { await model.buildAndPublish(force: false) } }
      .disabled(model.isBusy)

    Divider()

    Toggle("Launch at Login", isOn: Binding(
      get: { loginItem.isEnabled },
      set: { loginItem.setEnabled($0) }
    ))

    Button("Open Dashboard…") {
      NSApp.activate(ignoringOtherApps: true)
      openWindow(id: "dashboard")
    }

    Divider()

    Button("Quit Grimora Engine") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
  }

  /// Non-actionable status line(s): the current activity, and the last recorded run when idle.
  @ViewBuilder
  private var statusHeader: some View {
    switch model.activity {
    case .running(let progress):
      Text("Running — \(progress.phase.title)")
    case .idle:
      if let last = model.history.first {
        Text("Idle · last run \(last.outcome.label.lowercased()) \(EngineFormat.relative(last.startedAt))")
      } else {
        Text("Idle · no runs recorded yet")
      }
    }
  }
}
