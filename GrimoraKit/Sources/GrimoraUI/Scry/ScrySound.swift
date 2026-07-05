#if os(iOS)
import AudioToolbox
import AVFoundation
import GrimoraCore

/// Short audio cues for scanning.
///
/// The base cues use system ACK tones (no assets): a positive "ping" when a card
/// is kept, a light "tink" when one is identified, a "buzz" on failure. The
/// price-tier cue layers on bundled "level-up" jingles that escalate with a
/// card's value.
enum ScrySound {
  /// A card was successfully scanned and added to Scanned.
  static func scanned() {
    AudioServicesPlaySystemSound(1054)  // SIMToolkitPositiveACK — a short ping
  }

  /// The passive scanner confidently identified a card (the confirm chip just
  /// appeared). Deliberately lighter than `scanned()` — it's an invitation, not
  /// a commit.
  static func identified() {
    AudioServicesPlaySystemSound(1057)  // Tink — a very light, short ding
  }

  /// A scan definitely failed (nothing identifiable).
  static func failed() {
    AudioServicesPlaySystemSound(1053)  // SIMToolkitNegativeACK — a short buzz
  }

  /// The cue for a scanned card's price tier: the light `identified()` click for
  /// sub-threshold cards, escalating "level-up" jingles as the value climbs.
  @MainActor
  static func tier(_ tier: ScryPriceTier) {
    switch tier {
    case .none: identified()
    case .green: ScrySoundPlayer.shared.play("Level-up-Common")
    case .blue: ScrySoundPlayer.shared.play("Level-up-Uncommon")
    case .purple: ScrySoundPlayer.shared.play("Level-up-Epic")
    case .gold: ScrySoundPlayer.shared.play("Level-up-Legendary")
    }
  }
}

/// Owns a single `AVAudioPlayer` for the bundled level-up jingles. Retaining the
/// player is required — a local one would deallocate before the sound finishes.
/// Uses the `.ambient` category (honors the silent switch, mixes with other
/// audio) to match the system-tone behavior of the other cues.
@MainActor
final class ScrySoundPlayer {
  static let shared = ScrySoundPlayer()

  private var player: AVAudioPlayer?
  private var didConfigureSession = false

  private init() {}

  func play(_ resource: String) {
    guard let url = Bundle.module.url(forResource: resource, withExtension: "mp3")
      ?? Bundle.module.url(forResource: resource, withExtension: "mp3", subdirectory: "Sounds")
    else { return }
    configureSessionIfNeeded()
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      self.player = player
      player.prepareToPlay()
      player.play()
    } catch {
      // A missing/undecodable asset shouldn't break scanning — just skip the cue.
    }
  }

  private func configureSessionIfNeeded() {
    guard !didConfigureSession else { return }
    didConfigureSession = true
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.ambient, options: [.mixWithOthers])
    try? session.setActive(true)
  }
}
#endif
