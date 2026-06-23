import SwiftUI

/// Row of progress dots for the first-run walkthrough, one per step with the
/// current step highlighted. Exposes a single accessibility element reporting
/// the position in the sequence.
struct OnboardingProgressDots: View {
  let steps: [GrimoraOnboardingWalkthroughStep]
  let current: GrimoraOnboardingWalkthroughStep
  var palette: GrimoraPalette

  var body: some View {
    HStack(spacing: 6) {
      ForEach(steps) { item in
        Circle()
          .fill(item == current ? palette.accent.color : palette.secondaryText.color.opacity(0.3))
          .frame(width: 7, height: 7)
      }
    }
    .accessibilityElement()
    .accessibilityLabel("Step \(current.index + 1) of \(steps.count)")
    .accessibilityIdentifier("onboarding-progress")
  }
}
