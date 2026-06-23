import SwiftUI

/// Bottom navigation for the first-run walkthrough: an optional Back button and
/// a primary Next / "Start Exploring" button on the final step.
struct OnboardingNavigationBar: View {
  let step: GrimoraOnboardingWalkthroughStep
  var goBack: () -> Void
  var goNext: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      if !step.isFirst {
        Button("Back", action: goBack)
          .buttonStyle(.bordered)
          .controlSize(.large)
          .accessibilityIdentifier("onboarding-back-button")
      }

      Button(step.isLast ? "Start Exploring" : "Next", action: goNext)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("onboarding-next-button")
    }
    .padding(.horizontal, 26)
    .padding(.vertical, 16)
    .frame(maxWidth: 600)
    .frame(maxWidth: .infinity)
  }
}
