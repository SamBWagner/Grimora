import GrimoraCore

/// Data-loading state for future read-only list insights; no recommendation or mutation actions.
public enum CollectionSemanticProfileState: Equatable, Sendable {
  case idle
  case loading(String)
  case unavailable
  case loaded(CardCollectionSemanticProfile)
  case failed(String)
}
