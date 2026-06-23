import SwiftUI

/// Interactive body for the current walkthrough step, dispatching to the
/// per-step views (operators, search playground, quiz, lists, favourites). The
/// finish step has no body of its own.
struct OnboardingStepContent: View {
  let step: GrimoraOnboardingWalkthroughStep
  let cards: [GrimoraOnboardingSampleCard]
  var palette: GrimoraPalette

  @ViewBuilder
  var body: some View {
    switch step {
    case .welcome:
      OnboardingWelcomeStepView(cards: cards, palette: palette)
    case .operators:
      OnboardingOperatorsStepView(
        operators: GrimoraOnboardingOperatorCatalog.cheatsheet,
        palette: palette
      )
    case .search:
      OnboardingOperatorPlaygroundView(
        cards: cards,
        operators: GrimoraOnboardingOperatorCatalog.playground,
        palette: palette
      )
    case .quiz:
      OnboardingQuizStepView(
        questions: GrimoraOnboardingQuizCatalog.questions,
        palette: palette
      )
    case .lists:
      OnboardingListsStepView(
        cards: Array(cards.prefix(4)),
        palette: palette
      )
    case .favourites:
      OnboardingFavouritesStepView(
        cards: Array(cards.prefix(4)),
        palette: palette
      )
    case .finish:
      EmptyView()
    }
  }
}
