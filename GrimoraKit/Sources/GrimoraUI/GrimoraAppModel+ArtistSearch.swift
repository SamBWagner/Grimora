import Foundation
import GrimoraCore

extension GrimoraAppModel {
    /// Replaces the current search with every distinct artwork credited to
    /// `artist`. Runs a Scryfall query (`artist:"…" unique:art`) through the
    /// normal submit path so identical art is de-duplicated by illustration.
    public func searchArtworks(byArtist artist: String) async {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        closeSelectedCard()
        setSearchDraft(Self.artistArtworksQuery(forArtist: trimmed))
        await submitSearch()
    }

    /// Scryfall query that surfaces all of an artist's distinct artworks. The
    /// `unique:art` operator collapses prints that reuse the same illustration.
    static func artistArtworksQuery(forArtist artist: String) -> String {
        let artistClause = SearchRefinement.forArtist(artist).queryFragment
        return "\(artistClause) unique:art"
    }
}
