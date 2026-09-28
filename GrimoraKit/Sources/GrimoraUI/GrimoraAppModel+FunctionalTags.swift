import GrimoraCore

extension GrimoraAppModel {
  func updateCardFunctionalTagsSelection(from oldCard: CardRecord?, to newCard: CardRecord?) {
    let oldKey = oldCard.map(cardFunctionalTagKey(for:))
    let newKey = newCard.map(cardFunctionalTagKey(for:))
    guard oldKey != newKey else {
      return
    }

    cardFunctionalTagsGeneration &+= 1
    let generation = cardFunctionalTagsGeneration
    cardFunctionalTagsTask?.cancel()

    guard let newKey else {
      cardFunctionalTagsState = .idle
      cardFunctionalTagsTask = nil
      return
    }

    cardFunctionalTagsState = .loading(newKey)
    let loader = cardFunctionalTagLoader
    cardFunctionalTagsTask = Task { [weak self] in
      do {
        let lookup = try await loader(newKey)
        guard !Task.isCancelled,
          let self,
          self.cardFunctionalTagsGeneration == generation,
          self.selectedCard.map(self.cardFunctionalTagKey(for:)) == newKey
        else {
          return
        }

        switch lookup {
        case .unavailable:
          self.cardFunctionalTagsState = .unavailable
        case .available(let tags) where tags.isEmpty:
          self.cardFunctionalTagsState = .empty
        case .available(let tags):
          self.cardFunctionalTagsState = .loaded(tags)
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled,
          let self,
          self.cardFunctionalTagsGeneration == generation,
          self.selectedCard.map(self.cardFunctionalTagKey(for:)) == newKey
        else {
          return
        }
        self.cardFunctionalTagsState = .failed("Functional tags could not be loaded.")
      }
    }
  }

  func cardFunctionalTagKey(for card: CardRecord) -> SemanticCardKey {
    let oracleID = card.oracleID.flatMap {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
    }
    return SemanticCardKey(oracleID: oracleID, printingID: card.id)
  }

  public func searchCards(taggedWith tag: SemanticCardFunctionalTag) async {
    let slug = tag.slug.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !slug.isEmpty else {
      return
    }

    let refinement = SearchRefinement(
      field: "otag",
      value: slug,
      intent: .include,
      displayLabel: tag.label
    )
    selectSearch()
    setSearchDraft(refinement.queryFragment)
    await submitSearch()
  }

  public func drainCardFunctionalTagsForTesting() async {
    await cardFunctionalTagsTask?.value
  }
}
