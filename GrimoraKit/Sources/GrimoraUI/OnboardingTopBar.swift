import SwiftUI

/// Top chrome of the first-run walkthrough: the progress dots and an
/// always-available Skip button.
struct OnboardingTopBar: View {
  let steps: [GrimoraOnboardingWalkthroughStep]
  let current: GrimoraOnboardingWalkthroughStep
  var palette: GrimoraPalette
  var skip: () -> Void

  var body: some View {
    HStack {
      OnboardingProgressDots(steps: steps, current: current, palette: palette)
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
