import GrimoraCore

extension GrimoraAppModel {
  func invalidateCollectionSemanticProfile() {
    collectionSemanticProfileGeneration &+= 1
    collectionSemanticProfileTask?.cancel()
    collectionSemanticProfileTask = nil
    collectionSemanticProfileState = .idle
  }

  /// Explicit data-layer integration for later Insights work. Nothing is loaded or mutated
  /// automatically when a list is opened. Selection, entries and ruleset changes cancel it.
  public func loadSelectedCollectionSemanticProfile(policy: CardCollectionSemanticPolicy = .init())
  {
    invalidateCollectionSemanticProfile()
    guard let list = selectedCollection else { return }
    let entries = selectedCollectionEntries
    let generation = collectionSemanticProfileGeneration
    let loader = collectionSemanticProfileLoader
    collectionSemanticProfileState = .loading(list.id)
    collectionSemanticProfileTask = Task { [weak self] in
      do {
        let fingerprint = try CardCollectionSemanticProfiler.fingerprint(
          for: list, entries: entries, policy: policy)
        let lookup = try await loader(list, entries, policy)
        guard !Task.isCancelled, let self,
          self.collectionSemanticProfileGeneration == generation,
          let currentList = self.selectedCollection, currentList.id == list.id,
          try CardCollectionSemanticProfiler.fingerprint(
            for: currentList, entries: self.selectedCollectionEntries, policy: policy)
            == fingerprint
        else { return }
        switch lookup {
        case .unavailable: self.collectionSemanticProfileState = .unavailable
        case .available(let profile): self.collectionSemanticProfileState = .loaded(profile)
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, let self,
          self.collectionSemanticProfileGeneration == generation,
          self.selectedCollectionID == list.id
        else { return }
        self.collectionSemanticProfileState = .failed("List semantics could not be loaded.")
      }
    }
  }

  public func drainCollectionSemanticProfileForTesting() async {
    await collectionSemanticProfileTask?.value
  }
}
