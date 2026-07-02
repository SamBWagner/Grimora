import SwiftUI

/// Dev-only corpus-capture harness: scans cards with the real Scry engine and
/// saves verdict-labeled captures for `Tools/scry_import_captures.py`.
/// Never shipped — lives outside the App Store release pipeline.
@main
struct GrimoraScryApp: App {
  @State private var model = ScryHarnessModel()

  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
        .preferredColorScheme(.dark)
    }
  }
}
