import GrimoraCore

extension GrimoraAppModel {
  func updateRelatedCardsSelection(from oldCard: CardRecord?, to newCard: CardRecord?) {
    let oldKey = oldCard.map(cardFunctionalTagKey(for:))
    let newKey = newCard.map(cardFunctionalTagKey(for:))
    guard oldKey != newKey else {
      return
    }

    relatedCardsGeneration &+= 1
    let generation = relatedCardsGeneration
    relatedCardsTask?.cancel()

    guard let newCard, let newKey else {
      relatedCardsState = .idle
      relatedCardsTask = nil
      return
    }

    relatedCardsState = .loading(newKey)
    let loader = relatedCardLoader
    let filters = SemanticRelatedCardFilters(limit: 6)
    relatedCardsTask = Task { [weak self] in
      do {
        let lookup = try await loader(newCard, filters)
        guard !Task.isCancelled,
          let self,
          self.relatedCardsGeneration == generation,
          self.selectedCard.map(self.cardFunctionalTagKey(for:)) == newKey
        else {
          return
        }

        switch lookup {
        case .unavailable:
          self.relatedCardsState = .unavailable
        case .available(let cards) where cards.isEmpty:
          self.relatedCardsState = .empty
        case .available(let cards):
          self.relatedCardsState = .loaded(cards)
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled,
          let self,
          self.relatedCardsGeneration == generation,
          self.selectedCard.map(self.cardFunctionalTagKey(for:)) == newKey
        else {
          return
        }
        self.relatedCardsState = .failed("Related cards could not be loaded.")
      }
    }
  }

  public func selectRelatedCard(_ relatedCard: SemanticRelatedCard) {
    selectCard(relatedCard.card)
  }

  public func drainRelatedCardsForTesting() async {
    await relatedCardsTask?.value
  }
}
