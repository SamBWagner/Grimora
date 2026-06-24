import SwiftUI

/// Header chrome of the first-run walkthrough: a leading Back affordance (touch
/// platforms only, hidden on the first step) and an always-available Skip
/// button. The progress dots, and on macOS the Back button, live in the footer
/// (``OnboardingNavigationBar``).
struct OnboardingTopBar: View {
  let step: GrimoraOnboardingWalkthroughStep
  var goBack: () -> Void
  var skip: () -> Void

  var body: some View {
    HStack {
      #if !os(macOS)
      if !step.isFirst {
        OnboardingBackButton(action: goBack)
      }
      #endif
      Spacer()
      Button("Skip", action: skip)
        .font(.callout.weight(.medium))
        .buttonStyle(.borderless)
        .accessibilityIdentifier("onboarding-skip-button")
    }
    .padding(.horizontal, 22)
    .padding(.top, 16)
    .padding(.bottom, 8)
  }
}
