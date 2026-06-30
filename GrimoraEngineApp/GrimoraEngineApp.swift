import SwiftUI

@main
struct GrimoraEngineApp: App {
  @State private var model = EngineDashboardModel(controller: EngineController())
  @State private var loginItem = LoginItemController()

  var body: some Scene {
    Window("Grimora Engine", id: "dashboard") {
      EngineRootView(model: model)
        .frame(minWidth: 720, minHeight: 480)
    }
    .windowStyle(.titleBar)
    .defaultSize(width: 900, height: 600)
    .commands {
      CommandGroup(after: .newItem) {
        Button("Start (Build)") {
          Task { await model.build(force: false) }
        }
        .keyboardShortcut("b", modifiers: .command)
        .disabled(model.isBusy)

        Button("Publish") {
          Task { await model.publish() }
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(!model.canPublish)

        Button("Build & Publish") {
          Task { await model.buildAndPublish(force: false) }
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(model.isBusy)

        Divider()

        Button("Check for Updates") {
          Task { await model.checkForUpdates() }
        }
        .keyboardShortcut("u", modifiers: .command)
        .disabled(model.isChecking)
      }
    }

    MenuBarExtra {
      MenuBarStatusView(model: model, loginItem: loginItem)
    } label: {
      MenuBarLabel(model: model, loginItem: loginItem)
    }
    .menuBarExtraStyle(.menu)
  }
}
