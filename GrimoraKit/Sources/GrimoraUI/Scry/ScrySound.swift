#if os(iOS)
import AudioToolbox

/// Short audio cues for scanning. Uses system ACK tones so there are no bundled
/// assets: a positive "ping" when a card is kept, a negative "buzz" on failure.
enum ScrySound {
  /// A card was successfully scanned and added to Scanned.
  static func scanned() {
    AudioServicesPlaySystemSound(1054)  // SIMToolkitPositiveACK — a short ping
  }

  /// A scan definitely failed (nothing identifiable).
  static func failed() {
    AudioServicesPlaySystemSound(1053)  // SIMToolkitNegativeACK — a short buzz
  }
}
#endif
