import GrimoraUI
import SwiftUI

@main
struct GrimoraApp: App {
    @State private var model: GrimoraAppModel

    init() {
        do {
            let environment = try GrimoraEnvironment.live()
            _model = State(
                wrappedValue: GrimoraAppModel.configuredForCurrentPreferences(
                    environment: environment
                )
            )
        } catch {
            fatalError("Unable to start Grimora: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            GrimoraRootView(model: model)
        }
        #if os(visionOS)
        .defaultSize(width: 1280, height: 900)
        #endif
        .commands {
            GrimoraGridZoomCommands()
            GrimoraLibraryCommands()
            #if os(macOS)
            GrimoraSyncCommands()
            GrimoraSearchCommands()
            GrimoraListCommands()
            InspectorCommands()
            GrimoraHelpCommands()
            #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        #endif

        #if os(macOS)
        Settings {
            GrimoraSettingsView()
                .environment(model)
        }
        #endif
    }
}
