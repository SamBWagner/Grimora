import SwiftUI

/// Title block for a walkthrough step: the logo mark on the welcome step,
/// followed by the step's title and summary copy.
struct OnboardingStepHeader: View {
  let step: GrimoraOnboardingWalkthroughStep
  var palette: GrimoraPalette

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if step == .welcome {
        GrimoraLogoView(size: 64)
          .shadow(color: palette.shadow.color, radius: 14, x: 0, y: 8)
          .padding(.bottom, 4)
      }

      Text(step.title)
        .font(.title2.weight(.semibold))
        .foregroundStyle(palette.primaryText.color)

      Text(step.summary)
        .font(.callout)
        .foregroundStyle(palette.secondaryText.color)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
