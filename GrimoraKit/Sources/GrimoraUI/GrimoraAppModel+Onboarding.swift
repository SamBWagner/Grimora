import Foundation

extension GrimoraAppModel {
  /// Ask the app to replay the first-run onboarding walkthrough.
  ///
  /// The onboarding state machine lives in a `GrimoraOnboardingModel` owned
  /// privately by `GrimoraRootView`, which isn't reachable from the (separate,
  /// macOS) Settings scene. Bumping this request id is the cross-platform signal
  /// the root view watches to call `restart()` on that model.
  public func requestOnboardingReplay() {
    onboardingReplayRequestID += 1
  }
}
