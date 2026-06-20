# Agent Instructions

- After implementing runtime app changes, run the relevant tests, rebuild/relaunch or reload the locally testable app, and state the exact verification status in the final response.
- Every Grimora runtime app change must be implemented and verified across macOS, iOS, iPadOS, and visionOS before completion. Report each platform explicitly; iPadOS requires its own build and test status even when it shares the iOS target or a `#if os(iOS)` path.
- Do not mark a runtime task complete until the exact build, test, profiling when applicable, and relaunch status for all four platforms is recorded. State any blocker plainly.
- For Grimora Swift UI/model changes, prefer the macOS/Xcode workflow to relaunch the app after verification. If relaunch is blocked or skipped, say so plainly.
- Treat "reloaded" as the app process being rebuilt/relaunched for local testing, not merely that tests passed.
