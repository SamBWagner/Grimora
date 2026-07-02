#if canImport(Vision)
import CoreGraphics
import Foundation
import Vision

/// LRU cache of reference-side feature prints for `ScrySymbolMatcher`.
///
/// Reference images are deterministic (a candidate's Scryfall scan cropped at a
/// metadata-chosen band), so their feature prints never change — but bulk
/// scanning a stack of same-name reprints would otherwise recompute them on
/// every uncertain card. Keyed by (card id, band), lock-guarded like the other
/// camera-adjacent shared state.
public final class ScryFeaturePrintCache: @unchecked Sendable {
  struct Key: Hashable {
    var cardID: String
    /// The band quantized to a stable key (bands are derived constants; exact
    /// float equality is fine, but quantizing keeps the key robust to
    /// recomputation noise).
    var band: [Int]

    init(cardID: String, band: CGRect) {
      self.cardID = cardID
      self.band = [band.origin.x, band.origin.y, band.width, band.height].map { Int(($0 * 10000).rounded()) }
    }
  }

  private let lock = NSLock()
  private var storage: [Key: VNFeaturePrintObservation] = [:]
  private var order: [Key] = []
  public let capacity: Int

  public init(capacity: Int = 128) {
    self.capacity = max(1, capacity)
  }

  func observation(for cardID: String, band: CGRect) -> VNFeaturePrintObservation? {
    let key = Key(cardID: cardID, band: band)
    lock.lock()
    defer { lock.unlock() }
    guard let observation = storage[key] else { return nil }
    order.removeAll { $0 == key }
    order.append(key)
    return observation
  }

  func store(_ observation: VNFeaturePrintObservation, cardID: String, band: CGRect) {
    let key = Key(cardID: cardID, band: band)
    lock.lock()
    defer { lock.unlock() }
    if storage[key] == nil {
      order.append(key)
    } else {
      order.removeAll { $0 == key }
      order.append(key)
    }
    storage[key] = observation
    while order.count > capacity, let evicted = order.first {
      order.removeFirst()
      storage.removeValue(forKey: evicted)
    }
  }

  /// Whether a reference print is already cached — lets callers skip fetching
  /// that candidate's reference image entirely.
  public func hasObservation(for cardID: String, band: CGRect) -> Bool {
    let key = Key(cardID: cardID, band: band)
    lock.lock()
    defer { lock.unlock() }
    return storage[key] != nil
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return storage.count
  }
}
#endif
