import Foundation

public enum CardArtworkSourceReference: Hashable, Sendable {
  case card
  case face(Int)
}

public enum CardArtworkRotation: Int, Equatable, Sendable {
  case none = 0
  case clockwise90 = 90
  case upsideDown180 = 180

  public var degrees: Double {
    Double(rawValue)
  }
}

public struct CardArtworkImageSource: Equatable, Hashable, Sendable {
  public var reference: CardArtworkSourceReference
  public var title: String
  public var typeLine: String
  public var smallImagePath: String?
  public var normalImagePath: String?
  public var largeImagePath: String?
  public var artCropImagePath: String?
  public var smallImageURL: String?
  public var normalImageURL: String?
  public var largeImageURL: String?
  public var artCropImageURL: String?

  public var faceIndex: Int? {
    if case .face(let index) = reference {
      return index
    }
    return nil
  }

  public var remoteImageURLs: ImageURLPair {
    ImageURLPair(
      small: smallImageURL.flatMap(URL.init(string:)),
      normal: normalImageURL.flatMap(URL.init(string:)),
      large: largeImageURL.flatMap(URL.init(string:)),
      artCrop: artCropImageURL.flatMap(URL.init(string:))
    )
  }

  public func localPath(for quality: CardImageQuality) -> String? {
    firstPath(localPathCandidates(for: quality))
  }

  public func hasCachedImage(for quality: CardImageQuality) -> Bool {
    switch quality {
    case .small:
      if firstPath([normalImagePath, smallImagePath]) != nil {
        return true
      }
      return !hasRemoteImage(for: .small) && localPath(for: .small) != nil
    case .normal:
      if normalImagePath != nil {
        return true
      }
      guard !hasRemoteImage(for: .normal) else {
        return false
      }
      if firstPath([normalImagePath, smallImagePath]) != nil {
        return true
      }
      return !hasRemoteImage(for: .small) && localPath(for: .normal) != nil
    case .large:
      if largeImagePath != nil {
        return true
      }
      guard !hasRemoteImage(for: .large) else {
        return false
      }
      if hasRemoteImage(for: .normal) {
        return normalImagePath != nil
      }
      return localPath(for: .large) != nil
    case .artCrop:
      if artCropImagePath != nil {
        return true
      }
      guard !hasRemoteImage(for: .artCrop) else {
        return false
      }
      return localPath(for: .artCrop) != nil
    }
  }

  public func cachedImagePaths(for quality: CardImageQuality) -> [String] {
    switch quality {
    case .small:
      let previewPaths = compactPaths([normalImagePath, smallImagePath])
      guard previewPaths.isEmpty else {
        return previewPaths
      }
      return hasRemoteImage(for: .small) ? [] : compactPaths(localPathCandidates(for: .small))
    case .normal:
      let normalPaths = compactPaths([normalImagePath])
      guard normalPaths.isEmpty else {
        return normalPaths
      }
      return hasRemoteImage(for: .normal) ? [] : cachedImagePaths(for: .small)
    case .large:
      let largePaths = compactPaths([largeImagePath])
      guard largePaths.isEmpty else {
        return largePaths
      }
      guard !hasRemoteImage(for: .large) else {
        return []
      }
      if hasRemoteImage(for: .normal) {
        return compactPaths([normalImagePath])
      }
      return compactPaths(localPathCandidates(for: .large))
    case .artCrop:
      let artCropPaths = compactPaths([artCropImagePath])
      guard artCropPaths.isEmpty else {
        return artCropPaths
      }
      return hasRemoteImage(for: .artCrop) ? [] : compactPaths(localPathCandidates(for: .artCrop))
    }
  }

  public func hasUnavailableCachedImageFile(
    for quality: CardImageQuality,
    fileManager: FileManager = .default
  ) -> Bool {
    let paths = cachedImagePaths(for: quality)
    guard !paths.isEmpty else {
      return false
    }

    return paths.allSatisfy {
      !LocalImageFileValidator.isUsableCachedImageFile(atPath: $0, fileManager: fileManager)
    }
  }

  public func hasRemoteImage(for quality: CardImageQuality) -> Bool {
    switch quality {
    case .small:
      smallImageURL != nil
    case .normal:
      normalImageURL != nil
    case .large:
      largeImageURL != nil
    case .artCrop:
      remoteImageURLs.artCrop != nil
    }
  }

  public var hasAnyImageReference: Bool {
    firstPath([
      smallImagePath,
      normalImagePath,
      largeImagePath,
      artCropImagePath,
      smallImageURL,
      normalImageURL,
      largeImageURL,
      artCropImageURL
    ]) != nil
  }

  private func localPathCandidates(for quality: CardImageQuality) -> [String?] {
    switch quality {
    case .small:
      [normalImagePath, smallImagePath, largeImagePath]
    case .normal:
      [normalImagePath, largeImagePath, smallImagePath]
    case .large:
      [largeImagePath, normalImagePath, smallImagePath]
    case .artCrop:
      [artCropImagePath, normalImagePath, largeImagePath, smallImagePath]
    }
  }
}

public struct CardArtworkVariant: Identifiable, Equatable, Sendable {
  public var id: String
  public var source: CardArtworkSourceReference
  public var title: String
  public var typeLine: String
  public var imagePath: String?
  public var hasRemoteImage: Bool
  public var rotation: CardArtworkRotation

  public var isRotated: Bool {
    rotation != .none
  }

  public init(
    id: String,
    source: CardArtworkSourceReference,
    title: String,
    typeLine: String,
    imagePath: String?,
    hasRemoteImage: Bool,
    rotation: CardArtworkRotation
  ) {
    self.id = id
    self.source = source
    self.title = title
    self.typeLine = typeLine
    self.imagePath = imagePath
    self.hasRemoteImage = hasRemoteImage
    self.rotation = rotation
  }
}

public enum CardArtworkMotionKind: Equatable, Sendable {
  case none
  case rotate
  case flip
}

public struct CardArtworkMotionPlan: Equatable, Sendable {
  public var kind: CardArtworkMotionKind
  public var rotationDeltaDegrees: Double
  public var targetRotationDegrees: Double

  public init(
    kind: CardArtworkMotionKind,
    rotationDeltaDegrees: Double,
    targetRotationDegrees: Double
  ) {
    self.kind = kind
    self.rotationDeltaDegrees = rotationDeltaDegrees
    self.targetRotationDegrees = targetRotationDegrees
  }

  public static func transition(
    from current: CardArtworkVariant,
    to target: CardArtworkVariant
  ) -> CardArtworkMotionPlan {
    let currentDegrees = current.rotation.degrees
    let targetDegrees = target.rotation.degrees
    let delta = shortestRotationDelta(from: currentDegrees, to: targetDegrees)

    guard current != target else {
      return CardArtworkMotionPlan(
        kind: .none,
        rotationDeltaDegrees: 0,
        targetRotationDegrees: targetDegrees
      )
    }

    guard usesSameArtworkSurface(current, target) else {
      return CardArtworkMotionPlan(
        kind: .flip,
        rotationDeltaDegrees: delta,
        targetRotationDegrees: targetDegrees
      )
    }

    return CardArtworkMotionPlan(
      kind: delta == 0 ? .none : .rotate,
      rotationDeltaDegrees: delta,
      targetRotationDegrees: targetDegrees
    )
  }

  public static func shortestRotationDelta(from currentDegrees: Double, to targetDegrees: Double) -> Double {
    let rawDelta = targetDegrees - currentDegrees
    let normalizedDelta = rawDelta.truncatingRemainder(dividingBy: 360)
    let positiveDelta = (normalizedDelta + 540).truncatingRemainder(dividingBy: 360) - 180
    return positiveDelta == -180 ? 180 : positiveDelta
  }

  private static func usesSameArtworkSurface(
    _ current: CardArtworkVariant,
    _ target: CardArtworkVariant
  ) -> Bool {
    current.source == target.source
      && current.imagePath == target.imagePath
      && current.hasRemoteImage == target.hasRemoteImage
  }
}

public enum CardArtworkPresentationResolver {
  // The variant list is a pure function of the card's image sources, its normalised layout, the
  // requested quality, and the landscape flag — `imageSources(for:)` already extracts every image
  // field that matters (including the paths that get backfilled at runtime), so a key built from it
  // is complete and never goes stale: once `patchImageUpdate` swaps in new paths, the sources change,
  // the key changes, and the entry is recomputed. CardArtworkView resolves variants several times per
  // render (selected variant, next variant, ids, layout), so this memo turns the per-cell string
  // folding/normalisation into a dictionary lookup.
  private struct VariantsCacheKey: Hashable {
    let sources: [CardArtworkImageSource]
    let normalizedLayout: String
    let quality: CardImageQuality
    let includesLandscapeRotation: Bool
  }

  private static let variantsCacheLock = NSLock()
  // Safe: every access is serialised through `variantsCacheLock`.
  private nonisolated(unsafe) static var variantsCache: [VariantsCacheKey: [CardArtworkVariant]] = [:]
  private static let variantsCacheLimit = 1_024

  public static func variants(
    for card: CardRecord,
    preferredQuality: CardImageQuality = .normal,
    includesLandscapeRotation: Bool = false
  ) -> [CardArtworkVariant] {
    let sources = imageSources(for: card)
    let key = VariantsCacheKey(
      sources: sources,
      normalizedLayout: card.layout.normalizedArtworkKey,
      quality: preferredQuality,
      includesLandscapeRotation: includesLandscapeRotation
    )

    variantsCacheLock.lock()
    if let cached = variantsCache[key] {
      variantsCacheLock.unlock()
      return cached
    }
    variantsCacheLock.unlock()

    let computed = sources.flatMap { source in
      variants(
        for: source,
        card: card,
        preferredQuality: preferredQuality,
        includesLandscapeRotation: includesLandscapeRotation
      )
    }

    variantsCacheLock.lock()
    if variantsCache.count >= variantsCacheLimit {
      variantsCache.removeAll(keepingCapacity: true)
    }
    variantsCache[key] = computed
    variantsCacheLock.unlock()
    return computed
  }

  public static func imageSources(for card: CardRecord) -> [CardArtworkImageSource] {
    let topLevelSource = CardArtworkImageSource(
      reference: .card,
      title: card.name,
      typeLine: card.typeLine,
      smallImagePath: card.smallImagePath,
      normalImagePath: card.normalImagePath,
      largeImagePath: card.largeImagePath,
      artCropImagePath: card.artCropImagePath,
      smallImageURL: card.smallImageURL,
      normalImageURL: card.normalImageURL,
      largeImageURL: card.largeImageURL,
      artCropImageURL: card.artCropImageURL
    )

    if topLevelSource.hasAnyImageReference {
      return [topLevelSource]
    }

    return card.faces
      .map { face in
        CardArtworkImageSource(
          reference: .face(face.faceIndex),
          title: face.name.isEmpty ? card.name : face.name,
          typeLine: face.typeLine,
          smallImagePath: face.smallImagePath,
          normalImagePath: face.normalImagePath,
          largeImagePath: face.largeImagePath,
          artCropImagePath: face.artCropImagePath,
          smallImageURL: face.smallImageURL,
          normalImageURL: face.normalImageURL,
          largeImageURL: face.largeImageURL,
          artCropImageURL: face.artCropImageURL
        )
      }
      .filter(\.hasAnyImageReference)
  }

  public static func hasAlternatePresentation(for card: CardRecord) -> Bool {
    variants(for: card).count > 1
  }

  private static func variants(
    for source: CardArtworkImageSource,
    card: CardRecord,
    preferredQuality: CardImageQuality,
    includesLandscapeRotation: Bool
  ) -> [CardArtworkVariant] {
    let baseVariant = variant(
      for: source,
      preferredQuality: preferredQuality,
      rotation: .none
    )
    let normalizedLayout = card.layout.normalizedArtworkKey
    let rotations = rotations(
      for: source,
      card: card,
      normalizedLayout: normalizedLayout,
      includesLandscapeRotation: includesLandscapeRotation
    )
    let rotatedVariants = rotations.map { rotation in
      variant(
        for: source,
        preferredQuality: preferredQuality,
        rotation: rotation
      )
    }

    if shouldDefaultToClockwise90(source: source, card: card, normalizedLayout: normalizedLayout),
       let defaultRotatedVariant = rotatedVariants.first(where: { $0.rotation == .clockwise90 }) {
      return [defaultRotatedVariant] + rotatedVariants.filter { $0.rotation != .clockwise90 }
    }

    return [baseVariant] + rotatedVariants
  }

  private static func variant(
    for source: CardArtworkImageSource,
    preferredQuality: CardImageQuality,
    rotation: CardArtworkRotation
  ) -> CardArtworkVariant {
    CardArtworkVariant(
      id: variantID(source: source.reference, rotation: rotation),
      source: source.reference,
      title: source.title,
      typeLine: source.typeLine,
      imagePath: source.localPath(for: preferredQuality),
      hasRemoteImage: source.remoteImageURLs.small != nil
        || source.remoteImageURLs.normal != nil
        || source.remoteImageURLs.large != nil
        || source.remoteImageURLs.artCrop != nil,
      rotation: rotation
    )
  }

  private static func rotations(
    for source: CardArtworkImageSource,
    card: CardRecord,
    normalizedLayout: String,
    includesLandscapeRotation: Bool
  ) -> [CardArtworkRotation] {
    var rotations: [CardArtworkRotation] = []

    if normalizedLayout == "flip" {
      rotations.append(.upsideDown180)
    }

    if shouldRotateClockwise90(source: source, card: card, normalizedLayout: normalizedLayout) {
      rotations.append(.clockwise90)
    }

    if includesLandscapeRotation,
       !rotations.contains(.clockwise90),
       !rotations.contains(.upsideDown180) {
      rotations.append(.clockwise90)
    }

    return rotations
  }

  private static func shouldRotateClockwise90(
    source: CardArtworkImageSource,
    card: CardRecord,
    normalizedLayout: String
  ) -> Bool {
    if ["split", "planar", "scheme", "vanguard"].contains(normalizedLayout) {
      return true
    }

    if normalizedLayout == "room" {
      return true
    }

    if source.typeLine.containsBattleType {
      return true
    }

    if source.typeLine.containsRoomType {
      return true
    }

    if source.reference == .card, card.typeLine.containsBattleType {
      return true
    }

    if source.reference == .card, card.typeLine.containsRoomType {
      return true
    }

    return false
  }

  private static func shouldDefaultToClockwise90(
    source: CardArtworkImageSource,
    card: CardRecord,
    normalizedLayout: String
  ) -> Bool {
    if source.typeLine.containsBattleType || source.typeLine.containsRoomType {
      return true
    }

    if source.reference == .card,
       card.typeLine.containsBattleType || card.typeLine.containsRoomType {
      return true
    }

    return normalizedLayout == "room"
  }

  private static func variantID(
    source: CardArtworkSourceReference,
    rotation: CardArtworkRotation
  ) -> String {
    let sourceID: String
    switch source {
    case .card:
      sourceID = "card"
    case .face(let index):
      sourceID = "face-\(index)"
    }

    return "\(sourceID)-rotation-\(rotation.rawValue)"
  }
}

public extension CardRecord {
  func artworkImagePathsForPreload(preferredQuality: CardImageQuality = .normal) -> [String] {
    CardArtworkPresentationResolver.imageSources(for: self)
      .compactMap { $0.localPath(for: preferredQuality) }
  }

  func hasCachedArtworkPresentationImages(for quality: CardImageQuality) -> Bool {
    let sources = CardArtworkPresentationResolver.imageSources(for: self)
    guard !sources.isEmpty else {
      return hasCachedDisplayImage(for: quality)
    }

    return sources.allSatisfy { $0.hasCachedImage(for: quality) }
  }

  func hasUnavailableCachedArtworkPresentationImageFile(
    for quality: CardImageQuality,
    fileManager: FileManager = .default
  ) -> Bool {
    CardArtworkPresentationResolver.imageSources(for: self).contains { source in
      source.hasUnavailableCachedImageFile(for: quality, fileManager: fileManager)
    }
  }
}

private extension String {
  var normalizedArtworkKey: String {
    folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
  }

  var containsBattleType: Bool {
    normalizedArtworkKey
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .contains("battle")
  }

  var containsRoomType: Bool {
    normalizedArtworkKey
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .contains("room")
  }
}

private func firstPath(_ values: [String?]) -> String? {
  values.first { value in
    guard let value else {
      return false
    }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  } ?? nil
}

private func compactPaths(_ values: [String?]) -> [String] {
  values.compactMap { value in
    guard let value,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }
    return value
  }
}
