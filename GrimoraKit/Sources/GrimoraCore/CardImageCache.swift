import Foundation

public final class CardImageCache: Sendable {
  private let database: CardDatabase
  private let imageResolver: ImageResolving

  public init(database: CardDatabase, imageResolver: ImageResolving) {
    self.database = database
    self.imageResolver = imageResolver
  }

  @discardableResult
  public func cacheImages(
    for card: CardRecord,
    qualities: Set<CardImageQuality>
  ) async throws -> Bool {
    var updated = card
    var didChange = false

    let topLevelResult = await imageResolver.resolve(
      card.remoteImageURLs,
      cardID: card.id,
      faceIndex: nil,
      qualities: qualities
    )
    didChange = updated.applyLocalImagePaths(topLevelResult.paths) || didChange

    for index in updated.faces.indices {
      let faceResult = await imageResolver.resolve(
        updated.faces[index].remoteImageURLs,
        cardID: updated.id,
        faceIndex: updated.faces[index].faceIndex,
        qualities: qualities
      )
      didChange = updated.faces[index].applyLocalImagePaths(faceResult.paths) || didChange
    }

    guard didChange else {
      return false
    }

    _ = try database.mergeImagePaths(for: updated)
    return true
  }

  @discardableResult
  public func cacheDisplayedImage(
    for card: CardRecord,
    quality: CardImageQuality
  ) async throws -> Bool {
    try await cacheDisplayedImageRecord(for: card, quality: quality) != nil
  }

  public func cacheDisplayedImageRecord(
    for card: CardRecord,
    quality: CardImageQuality
  ) async throws -> CardRecord? {
    var updated = card
    var didChange = false

    let sources = CardArtworkPresentationResolver.imageSources(for: updated)
    guard !sources.isEmpty else {
      return nil
    }

    for source in sources
    where !source.hasCachedImage(for: quality) || source.hasUnavailableCachedImageFile(for: quality) {
      guard let downloadQuality = availableDisplayQuality(for: quality, in: source.remoteImageURLs) else {
        continue
      }
      let result = await imageResolver.resolve(
        source.remoteImageURLs,
        cardID: updated.id,
        faceIndex: source.faceIndex,
        qualities: [downloadQuality]
      )

      switch source.reference {
      case .card:
        didChange = updated.applyLocalImagePaths(result.paths) || didChange
      case .face(let faceIndex):
        guard let index = updated.faces.firstIndex(where: { $0.faceIndex == faceIndex }) else {
          continue
        }
        didChange = updated.faces[index].applyLocalImagePaths(result.paths) || didChange
      }
    }

    guard didChange else {
      return nil
    }

    return try database.mergeImagePaths(for: updated)
  }

  private func availableDisplayQuality(
    for preferredQuality: CardImageQuality,
    in remoteURLs: ImageURLPair
  ) -> CardImageQuality? {
    fallbackQualities(for: preferredQuality).first { quality in
      remoteURL(for: quality, in: remoteURLs) != nil
    }
  }

  private func fallbackQualities(for preferredQuality: CardImageQuality) -> [CardImageQuality] {
    switch preferredQuality {
    case .small:
      [.small, .normal]
    case .normal:
      [.normal, .small]
    case .large:
      [.large, .normal, .small]
    case .artCrop:
      [.artCrop, .normal, .small]
    }
  }

  private func remoteURL(for quality: CardImageQuality, in remoteURLs: ImageURLPair) -> URL? {
    switch quality {
    case .small:
      remoteURLs.small
    case .normal:
      remoteURLs.normal
    case .large:
      remoteURLs.large
    case .artCrop:
      remoteURLs.artCrop
    }
  }
}
