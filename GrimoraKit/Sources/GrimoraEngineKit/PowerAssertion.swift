import Foundation

#if canImport(IOKit)
import IOKit.pwr_mgt
#endif

/// Keeps a scheduled engine run alive against macOS power management.
///
/// launchd's `StartCalendarInterval` does not wake a sleeping Mac. On a laptop the job therefore
/// tends to start during an opportunistic dark wake and the system suspends again seconds later,
/// killing whatever request was in flight — which is exactly how the Aug 2026 outage presented
/// (`-1001` timeouts on a 2 KB endpoint that normally answers in under a second).
///
/// `NetworkClientActive` is the assertion macOS honours for background network work during dark
/// wake; `PreventUserIdleSystemSleep` covers the awake-but-unattended case.
///
/// **Neither defeats lid-close sleep on battery.** Closing the lid forces sleep regardless of any
/// user-space assertion, so this narrows the window rather than closing it. Reliable unattended runs
/// still need the machine on AC, or a scheduled wake (`pmset repeat`), or both.
public enum PowerManagement {
  /// Runs `body` while holding the assertions, releasing them however it exits.
  public static func withRunAssertions<T>(
    reason: String = "Grimora catalog build",
    _ body: () async throws -> T
  ) async rethrows -> T {
    let tokens = acquire(reason: reason)
    defer { release(tokens) }
    return try await body()
  }

  #if canImport(IOKit)
  private static func acquire(reason: String) -> [UInt32] {
    let types = [kIOPMAssertNetworkClientActive, kIOPMAssertPreventUserIdleSystemSleep]
    return types.compactMap { type in
      var id = IOPMAssertionID(0)
      let status = IOPMAssertionCreateWithName(
        type as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        reason as CFString,
        &id
      )
      // Best-effort: a refused assertion must never stop a run from happening at all.
      return status == kIOReturnSuccess ? UInt32(id) : nil
    }
  }

  private static func release(_ tokens: [UInt32]) {
    for token in tokens {
      IOPMAssertionRelease(IOPMAssertionID(token))
    }
  }
  #else
  private static func acquire(reason: String) -> [UInt32] { [] }

  private static func release(_ tokens: [UInt32]) {}
  #endif
}
