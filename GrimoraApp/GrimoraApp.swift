import GrimoraUI
import SwiftUI

@main
struct GrimoraApp: App {
    private let environment: GrimoraEnvironment

    init() {
        do {
            environment = try GrimoraEnvironment.live()
        } catch {
            fatalError("Unable to start Grimora: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            GrimoraRootView(environment: environment)
        }
        #if os(visionOS)
        .defaultSize(width: 1280, height: 900)
        #endif
        .commands {
            GrimoraGridZoomCommands()
            GrimoraLibraryCommands()
            #if os(macOS)
            GrimoraSearchCommands()
            GrimoraListCommands()
            InspectorCommands()
            #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        #endif

        #if os(macOS)
        Settings {
            GrimoraSettingsView()
        }
        #endif
    }
}
