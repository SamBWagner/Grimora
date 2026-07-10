import SwiftUI

/// Tracks whether a card is currently being dragged over the open collection, so the shadowed
/// (card-less) categories can surface as drop targets for as long as the drag needs them.
///
/// SwiftUI has no cross-platform "a drag began / ended" callback — `onDragSessionUpdated` is
/// macOS-only, and a cancelled drag reports nothing anywhere. What every platform *does* deliver
/// is `isTargeted` on each drop destination. So every drop destination in the collection reports
/// here: a card entering one is a drag in progress, and the last one to report an exit without a
/// successor ends it. The destinations are laid out as siblings (a section heading above its card
/// grid, one section above the next), so the pointer travelling between them dips through dead
/// space; the grace period rides over those gaps rather than collapsing the revealed categories
/// out from under a drag that is still looking for a home. Depth counting covers the case of two
/// destinations claiming the pointer at once.
///
/// Overshooting the grace period is the safe direction: a landed drop calls `endDrag()` and
/// retires the reveal at once, so the only thing the delay can prolong is a few empty headings
/// after a drag is abandoned mid-air.
@MainActor
@Observable
final class CardCollectionDragRevealState {
    private static let gracePeriod = Duration.milliseconds(400)

    private(set) var isRevealing = false

    @ObservationIgnored private var targetedDepth = 0
    @ObservationIgnored private var retireTask: Task<Void, Never>?

    func setTargeted(_ isTargeted: Bool) {
        if isTargeted {
            targetedDepth += 1
            retireTask?.cancel()
            retireTask = nil
            isRevealing = true
        } else {
            targetedDepth = max(0, targetedDepth - 1)
            guard targetedDepth == 0 else {
                return
            }
            scheduleRetire()
        }
    }

    /// Drops finish the drag outright — no need to wait out the grace period.
    func endDrag() {
        targetedDepth = 0
        retireTask?.cancel()
        retireTask = nil
        isRevealing = false
    }

    private func scheduleRetire() {
        retireTask?.cancel()
        retireTask = Task { [weak self] in
            try? await Task.sleep(for: Self.gracePeriod)
            guard !Task.isCancelled, let self, targetedDepth == 0 else {
                return
            }
            isRevealing = false
        }
    }
}

private struct CardCollectionDragRevealEnvironmentKey: EnvironmentKey {
    static let defaultValue: CardCollectionDragRevealState? = nil
}

extension EnvironmentValues {
    var cardCollectionDragReveal: CardCollectionDragRevealState? {
        get { self[CardCollectionDragRevealEnvironmentKey.self] }
        set { self[CardCollectionDragRevealEnvironmentKey.self] = newValue }
    }
}
