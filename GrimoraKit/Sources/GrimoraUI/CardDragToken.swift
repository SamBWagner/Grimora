import Foundation
import GrimoraCore

enum CardDragToken {
    private static let prefix = "grimora-card:"

    static func token(for cardIDs: [CardRecord.ID]) -> String {
        prefix + unique(cardIDs).joined(separator: ",")
    }

    static func cardIDs(from values: [String]) -> [CardRecord.ID] {
        unique(values.flatMap(cardIDs(from:)))
    }

    static func cardIDs(from value: String) -> [CardRecord.ID] {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              !CardListDragToken.isListDragToken(trimmedValue),
              !CardListEntryDragToken.isEntryDragToken(trimmedValue)
        else {
            return []
        }

        if trimmedValue.hasPrefix(prefix) {
            return unique(
                trimmedValue
                    .dropFirst(prefix.count)
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }

        guard !trimmedValue.contains(",") else {
            return []
        }
        return [trimmedValue]
    }

    private static func unique(_ ids: [CardRecord.ID]) -> [CardRecord.ID] {
        var seenIDs: Set<CardRecord.ID> = []
        return ids.filter { seenIDs.insert($0).inserted }
    }
}

enum CardListDragToken {
    static let prefix = "grimora-list:"

    static func token(for listID: CardListRecord.ID) -> String {
        prefix + listID
    }

    static func isListDragToken(_ value: String) -> Bool {
        value.hasPrefix(prefix)
    }

    static func listID(from value: String) -> CardListRecord.ID? {
        guard isListDragToken(value) else {
            return nil
        }

        let id = value.dropFirst(prefix.count)
        return id.isEmpty ? nil : String(id)
    }
}

enum CardListEntryDragToken {
    static let prefix = "grimora-list-entry:"

    static func token(for entryIDs: [CardListEntryRecord.ID]) -> String {
        prefix + unique(entryIDs).joined(separator: ",")
    }

    static func isEntryDragToken(_ value: String) -> Bool {
        value.hasPrefix(prefix)
    }

    static func entryIDs(from values: [String]) -> [CardListEntryRecord.ID] {
        unique(values.flatMap(entryIDs(from:)))
    }

    static func entryIDs(from value: String) -> [CardListEntryRecord.ID] {
        guard isEntryDragToken(value) else {
            return []
        }

        return unique(
            value
                .dropFirst(prefix.count)
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private static func unique(_ ids: [CardListEntryRecord.ID]) -> [CardListEntryRecord.ID] {
        var seenIDs: Set<CardListEntryRecord.ID> = []
        return ids.filter { seenIDs.insert($0).inserted }
    }
}
