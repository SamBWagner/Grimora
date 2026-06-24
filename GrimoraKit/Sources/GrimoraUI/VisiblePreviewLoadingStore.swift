import GrimoraCore
import SwiftUI

@MainActor
final class VisiblePreviewLoadingStore {
  private var entries: [VisibleImageRequestKey: VisiblePreviewLoadingEntry] = [:]
  private var currentKeys: Set<VisibleImageRequestKey> = []

  func entry(for key: VisibleImageRequestKey) -> VisiblePreviewLoadingEntry {
    if let entry = entries[key] {
      return entry
    }

    let entry = VisiblePreviewLoadingEntry()
    entry.isCurrentWindow = currentKeys.contains(key)
    entries[key] = entry
    return entry
  }

  func setState(_ state: VisibleImageRequestState?, for key: VisibleImageRequestKey) {
    if let state {
      entry(for: key).state = state
    } else {
      entries[key]?.state = nil
    }
  }

  func updateCurrentKeys(_ keys: Set<VisibleImageRequestKey>) {
    let previousKeys = currentKeys
    currentKeys = keys

    for key in previousKeys.subtracting(keys) {
      entries[key]?.isCurrentWindow = false
    }
    for key in keys {
      entry(for: key).isCurrentWindow = true
    }
  }

  func remove(_ key: VisibleImageRequestKey) {
    entries[key]?.state = nil
    entries[key]?.isCurrentWindow = false
  }

  func removeAll() {
    for entry in entries.values {
      entry.state = nil
      entry.isCurrentWindow = false
    }
    entries.removeAll()
    currentKeys = []
  }
}

@Observable
@MainActor
final class VisiblePreviewLoadingEntry {
  fileprivate var state: VisibleImageRequestState?
  fileprivate var isCurrentWindow = false

  func isLoading(for card: CardRecord) -> Bool {
    guard !card.hasExistingDisplayImage, isCurrentWindow else {
      return false
    }

    switch state?.phase {
    case .queued, .inFlight, .retrying:
      return true
    case .failed, .none:
      return false
    }
  }

  func accessibilityValue(for card: CardRecord) -> String {
    if card.hasExistingDisplayImage {
      return "Image"
    }

    return isLoading(for: card) ? "Loading Image" : "Text Only"
  }
}

struct VisiblePreviewLoadingObserver<Content: View>: View {
  var entry: VisiblePreviewLoadingEntry
  var card: CardRecord
  var content: (String, Bool) -> Content

  var body: some View {
    content(
      entry.accessibilityValue(for: card),
      entry.isLoading(for: card)
    )
  }
}
