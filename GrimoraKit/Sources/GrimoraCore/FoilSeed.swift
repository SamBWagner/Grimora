import Foundation

/// Deterministic per-card foil parameters derived from a stable string id.
///
/// A grid of foil cards must not shimmer in lockstep — that reads as tacky. Each card
/// gets its own phase offset, animation speed, and a small sweep-angle nudge so neighbours
/// catch the light differently. The derivation is a plain FNV-1a hash of the id's UTF-8
/// bytes, **not** Swift's `Hasher`/`hashValue` (which is seeded randomly per process), so a
/// given card always catches the light the same way across launches and across devices.
public struct FoilSeed: Equatable, Sendable {
    /// Where this card sits in the shimmer cycle, `0..<1`.
    public let phaseOffset: Double
    /// Animation-rate multiplier, roughly `0.7...1.3` of the base rate.
    public let speed: Double
    /// Sweep-angle nudge in radians, small (±π/12 ≈ ±15°) so every card still reads as a
    /// diagonal sheen rather than a random scatter.
    public let angle: Double

    public init(id: String) {
        // FNV-1a (64-bit). Stable across launches/processes.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // offset basis
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3 // FNV prime
        }

        // Three independent 16-bit streams pulled from the hash.
        let a = Double(hash & 0xFFFF) / Double(0xFFFF)
        let b = Double((hash >> 16) & 0xFFFF) / Double(0xFFFF)
        let c = Double((hash >> 32) & 0xFFFF) / Double(0xFFFF)

        phaseOffset = a
        speed = 0.7 + 0.6 * b
        angle = (c - 0.5) * (.pi / 6) // ±π/12
    }
}

extension CardRecord {
    /// The stable foil shimmer parameters for this printing.
    public var foilSeed: FoilSeed { FoilSeed(id: id) }
}
