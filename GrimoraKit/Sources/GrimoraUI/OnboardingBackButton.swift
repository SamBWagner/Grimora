import SwiftUI

/// Back affordance for the first-run walkthrough. Rendered in the header on
/// touch platforms (leading, nav-bar style) and in the footer button row on
/// macOS (bottom-leading). The caller gates visibility — it isn't shown on the
/// first step. Tint is inherited from the enclosing walkthrough.
struct OnboardingBackButton: View {
  var action: () -> Void

  var body: some View {
    #if os(macOS)
    Button("Back", action: action)
      .buttonStyle(.bordered)
      .controlSize(.large)
      .accessibilityIdentifier("onboarding-back-button")
    #else
    Button(action: action) {
      Label("Back", systemImage: "chevron.backward")
        .font(.callout.weight(.medium))
    }
    .buttonStyle(.borderless)
    .accessibilityIdentifier("onboarding-back-button")
    #endif
  }
}
