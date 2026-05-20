import Foundation
import GrimoraCore
import SwiftUI
import UniformTypeIdentifiers

extension View {
    func cardDropTarget(onDropCards: @escaping ([CardRecord.ID]) -> Void) -> some View {
        modifier(CardDropTargetModifier(onDropCards: onDropCards))
    }
}

private struct CardDropTargetModifier: ViewModifier {
    @State private var dropFeedbackTrigger = 0

    var onDropCards: ([CardRecord.ID]) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS) || os(iOS) || os(visionOS)
        content
            .dropDestination(for: String.self) { values, _ in
                let cardIDs = CardDragToken.cardIDs(from: values)
                guard !cardIDs.isEmpty else {
                    return false
                }
                onDropCards(cardIDs)
                dropFeedbackTrigger += 1
                return true
            }
            .onDrop(of: CardDropTokenLoader.supportedContentTypes, isTargeted: nil) { providers in
                CardDropTokenLoader.loadCardIDs(from: providers) { cardIDs in
                    onDropCards(cardIDs)
                    dropFeedbackTrigger += 1
                }
            }
            .grimoraDropSuccessFeedback(trigger: dropFeedbackTrigger)
        #else
        content
        #endif
    }
}

enum CardDropTokenLoader {
    static let supportedContentTypes: [UTType] = [.utf8PlainText, .plainText, .text]

    static func loadCardIDs(
        from providers: [NSItemProvider],
        onDropCards: @escaping ([CardRecord.ID]) -> Void
    ) -> Bool {
        let stringProviders = providers.filter { provider in
            provider.canLoadObject(ofClass: NSString.self)
                || provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
        }
        guard !stringProviders.isEmpty else {
            return false
        }

        let group = DispatchGroup()
        let collector = CardDropStringCollector()
        for provider in stringProviders {
            group.enter()
            loadString(from: provider) { value in
                if let value {
                    collector.append(value)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let cardIDs = CardDragToken.cardIDs(from: collector.values)
            guard !cardIDs.isEmpty else {
                return
            }
            onDropCards(cardIDs)
        }
        return true
    }

    private static func loadString(
        from provider: NSItemProvider,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                completion((object as? NSString).map { $0 as String })
            }
            return
        }

        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
            typeIdentifier = UTType.utf8PlainText.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            typeIdentifier = UTType.plainText.identifier
        } else {
            typeIdentifier = UTType.text.identifier
        }

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            switch item {
            case let value as String:
                completion(value)
            case let value as NSString:
                completion(value as String)
            case let data as Data:
                completion(String(data: data, encoding: .utf8))
            default:
                completion(nil)
            }
        }
    }
}

private final class CardDropStringCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collectedValues: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return collectedValues
    }

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        collectedValues.append(value)
    }
}
