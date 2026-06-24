import SwiftUI

/// Bottom navigation for the first-run walkthrough: the centered progress dots
/// above a prominent forward action. On touch platforms the forward action
/// spans the full width and Back lives in the header. On macOS the footer holds
/// a button row — Back bottom-leading and the prominent forward action
/// bottom-trailing (the default button), matching Mac conventions.
struct OnboardingNavigationBar: View {
  let steps: [GrimoraOnboardingWalkthroughStep]
  let step: GrimoraOnboardingWalkthroughStep
  var palette: GrimoraPalette
  var goBack: () -> Void
  var goNext: () -> Void

  private var forwardTitle: String {
    step.isLast ? "Start Exploring" : "Continue"
  }

  var body: some View {
    VStack(spacing: 14) {
      OnboardingProgressDots(steps: steps, current: step, palette: palette)

      #if os(macOS)
      HStack(spacing: 12) {
        if !step.isFirst {
          OnboardingBackButton(action: goBack)
        }
        Spacer()
        forwardButton
          .keyboardShortcut(.defaultAction)
      }
      #else
      forwardButton
        .frame(maxWidth: .infinity)
      #endif
    }
    .padding(.horizontal, 26)
    .padding(.top, 12)
    .padding(.bottom, 16)
    .frame(maxWidth: 600)
    .frame(maxWidth: .infinity)
  }

  private var forwardButton: some View {
    Button(forwardTitle, action: goNext)
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .accessibilityIdentifier("onboarding-next-button")
  }
}
