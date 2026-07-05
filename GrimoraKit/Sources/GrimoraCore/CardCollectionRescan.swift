import Foundation

/// One scanned printing and how many copies were seen during a Commander re-scan.
public struct CommanderRescanScannedCard: Equatable, Sendable {
    public let card: CardRecord
    public let count: Int

    public init(card: CardRecord, count: Int) {
        self.card = card
        self.count = count
    }
}

/// Accumulates the cards seen while re-scanning a Commander deck, keyed by exact
/// printing (`cardID`).
///
/// Commander is singleton, so a second scan of a card already captured this session
/// (matched by oracle identity, the same rule the deck validator uses) is *voided*
/// rather than counted. Only basic lands and other "any number" cards accumulate
/// copies. This is a pure value type so the behavior is unit-testable; the iOS view
/// layer wraps it purely for sound/haptic/HUD feedback.
public struct CommanderRescanTally: Equatable, Sendable {
    public enum RecordOutcome: Equatable, Sendable {
        /// The scan was added to the tally.
        case counted
        /// A singleton already captured this session — the scan was ignored.
        case voidedDuplicate
    }

    private var counts: [String: Int] = [:]
    private var cards: [String: CardRecord] = [:]
    private var singletonIdentities: Set<String> = []

    public init() {}

    /// Total copies counted so far (voided duplicates don't contribute).
    public var total: Int { counts.values.reduce(0, +) }

    /// The distinct printings captured, ready to diff against a deck.
    public var scannedCards: [CommanderRescanScannedCard] {
        counts.compactMap { id, count in
            cards[id].map { CommanderRescanScannedCard(card: $0, count: count) }
        }
    }

    @discardableResult
    public mutating func record(_ card: CardRecord) -> RecordOutcome {
        if !CardCollectionRulesetValidator.isCopyLimitExempt(card) {
            let identity = CardCollectionRulesetValidator.identityKey(for: card)
            guard singletonIdentities.insert(identity).inserted else {
                return .voidedDuplicate
            }
        }
        counts[card.id, default: 0] += 1
        cards[card.id] = card
        return .counted
    }
}

/// A single proposed change to a deck from a re-scan.
///
/// `delta > 0` adds copies of `card`; `delta < 0` removes copies of an existing
/// mainboard entry. Identity is the *exact printing* (`cardID`), so a different
/// printing of a card already in the deck shows up as a removal of the old
/// printing plus an addition of the new one.
public struct CommanderRescanChange: Equatable, Sendable, Identifiable {
    public let cardID: String
    public let card: CardRecord
    public let delta: Int
    /// The existing deck entry to mutate, when one exists. Removals always carry
    /// one; additions carry it only when the printing is already in the mainboard.
    public let entryID: String?
    public let zone: CardCollectionZone

    public var id: String { cardID }

    public init(
        cardID: String,
        card: CardRecord,
        delta: Int,
        entryID: String?,
        zone: CardCollectionZone
    ) {
        self.cardID = cardID
        self.card = card
        self.delta = delta
        self.entryID = entryID
        self.zone = zone
    }
}

/// The reconciliation between a stored deck and a fresh physical scan of it.
public struct CommanderRescanDiff: Equatable, Sendable {
    public var additions: [CommanderRescanChange]
    public var removals: [CommanderRescanChange]
    /// Distinct printings already in the deck that matched the scan exactly.
    public var unchangedCount: Int

    public init(
        additions: [CommanderRescanChange],
        removals: [CommanderRescanChange],
        unchangedCount: Int
    ) {
        self.additions = additions
        self.removals = removals
        self.unchangedCount = unchangedCount
    }

    public var isEmpty: Bool { additions.isEmpty && removals.isEmpty }

    /// Total copies added across all additions.
    public var addedCopies: Int { additions.reduce(0) { $0 + $1.delta } }

    /// Total copies removed across all removals, as a positive count.
    public var removedCopies: Int { removals.reduce(0) { $0 - $1.delta } }
}

public enum CommanderRescan {
    /// The zones that make up "the deck" for matching. Maybeboard is a wishlist and
    /// is never matched or mutated by a re-scan.
    public static let matchZones: Set<CardCollectionZone> = [.commander, .mainboard]

    /// Reconciles a stored deck against a physical scan, keyed by exact printing.
    ///
    /// - New printings (or extra copies) become additions to the mainboard.
    /// - Printings scanned fewer times than the deck holds become removals — but
    ///   only from the mainboard. A shortfall that exists solely in the commander
    ///   zone is ignored, so the commander is never auto-removed even if unscanned.
    public static func diff(
        deckEntries: [CardCollectionEntryRecord],
        scanned: [CommanderRescanScannedCard]
    ) -> CommanderRescanDiff {
        let deckEntries = deckEntries.filter { matchZones.contains($0.zone) }

        // Deck side: total copies per printing, plus a mainboard entry to mutate
        // and any hydrated card for display.
        var deckCount: [String: Int] = [:]
        var deckCard: [String: CardRecord] = [:]
        var mainboardEntry: [String: CardCollectionEntryRecord] = [:]
        for entry in deckEntries {
            deckCount[entry.cardID, default: 0] += max(1, entry.quantity)
            if let card = entry.card { deckCard[entry.cardID] = card }
            if entry.zone == .mainboard, mainboardEntry[entry.cardID] == nil {
                mainboardEntry[entry.cardID] = entry
            }
        }

        // Scanned side: total copies per printing (defensive against duplicates in
        // the input), plus the scanned card for display.
        var scanCount: [String: Int] = [:]
        var scanCard: [String: CardRecord] = [:]
        for scan in scanned {
            scanCount[scan.card.id, default: 0] += max(0, scan.count)
            scanCard[scan.card.id] = scan.card
        }

        var additions: [CommanderRescanChange] = []
        var removals: [CommanderRescanChange] = []
        var unchangedCount = 0

        for cardID in Set(deckCount.keys).union(scanCount.keys) {
            let deckN = deckCount[cardID] ?? 0
            let scanN = scanCount[cardID] ?? 0

            if scanN == deckN {
                if deckN > 0 { unchangedCount += 1 }
                continue
            }

            if scanN > deckN {
                guard let card = scanCard[cardID] ?? deckCard[cardID] else { continue }
                additions.append(CommanderRescanChange(
                    cardID: cardID,
                    card: card,
                    delta: scanN - deckN,
                    entryID: mainboardEntry[cardID]?.id,
                    zone: .mainboard
                ))
            } else {
                // Fewer scanned than stored → remove copies, but only from the
                // mainboard; never from the commander zone.
                guard let entry = mainboardEntry[cardID] else { continue }
                let removable = min(deckN - scanN, max(1, entry.quantity))
                guard removable > 0 else { continue }
                guard let card = entry.card ?? deckCard[cardID] ?? scanCard[cardID] else { continue }
                removals.append(CommanderRescanChange(
                    cardID: cardID,
                    card: card,
                    delta: -removable,
                    entryID: entry.id,
                    zone: .mainboard
                ))
            }
        }

        additions.sort { sortKey($0.card) < sortKey($1.card) }
        removals.sort { sortKey($0.card) < sortKey($1.card) }
        return CommanderRescanDiff(
            additions: additions,
            removals: removals,
            unchangedCount: unchangedCount
        )
    }

    /// Stable ordering for display and deterministic tests.
    private static func sortKey(_ card: CardRecord) -> String {
        "\(card.name.lowercased())|\(card.setCode)|\(card.collectorNumber)"
    }
}
