import Foundation

/// Shared names + DDL for the build-to-build patch database (`delta.sqlite`). Living in GrimoraCore
/// keeps the engine's ``CatalogDeltaBuilder`` and the client's ``CatalogDeltaApplier`` in lockstep
/// on the format — the one thing that must never drift between the two sides.
///
/// A patch database is a plain SQLite file (gzipped for transport) that transforms a catalog at
/// `base_version` into the catalog at `target_version`. It is applied with ordinary SQL — the iOS
/// system SQLite has no session/changeset extension, so nothing exotic is used.
///
/// The price columns on `cards` churn daily while the rest of the (large) row is stable, so a
/// changed card is expressed narrowly via ``cardsPriceUpdate`` when *only* prices moved, and as a
/// full-row ``cardsUpsert`` otherwise. Value series are a fixed-width, contiguous daily window that
/// *slides* each build (drop the oldest day, append the newest), so they ship as ``seriesSlide``
/// (a `drop_bytes` count + the appended byte-suffix) where the overlap is byte-identical, and as a
/// full ``seriesReplace`` blob otherwise. Value summaries are never shipped — the client recomputes
/// them from the patched series (`CardDatabase.recomputeValueSummary`).
public enum CatalogDeltaSchema {
  public static let meta = "delta_meta"
  public static let cardsPriceUpdate = "cards_price_update"
  public static let cardsUpsert = "cards_upsert"
  public static let cardsDelete = "cards_delete"
  public static let cardFacesReplace = "card_faces_replace"
  public static let cardFacesReplaceCards = "card_faces_replace_cards"
  public static let seriesReplace = "series_replace"
  public static let seriesSlide = "series_slide"
  public static let seriesDelete = "series_delete"
  public static let mappingsUpsert = "mappings_upsert"
  public static let mappingsDelete = "mappings_delete"
  public static let metadataSet = "metadata_set"

  /// The extra column carried in ``cardsUpsert`` beyond the `cards` columns: the FTS search string,
  /// which is a normalized derivation (`CardRecord.searchText`) the client can't recompute cheaply,
  /// so it travels in the delta. (`name_fts` is rebuilt from the plain `name` column, so no
  /// separate name column is needed.)
  public static let cardsUpsertSearchTextColumn = "search_text"

  /// Price columns on `cards` that change daily; used to classify a changed card row as
  /// price-only vs. a full-row change.
  public static let cardsPriceColumns = ["price_usd", "price_tix", "price_eur"]

  /// DDL for the fixed-shape patch tables. ``cardsUpsert`` and ``cardFacesReplace`` are created
  /// dynamically from the live catalog schema (they mirror `cards` / `card_faces` minus excluded
  /// columns), so they aren't listed here.
  public static let fixedTableDDL = """
    CREATE TABLE \(meta) (
        base_version TEXT NOT NULL,
        target_version TEXT NOT NULL,
        format_version INTEGER NOT NULL,
        created_at TEXT NOT NULL
    );
    CREATE TABLE \(cardsPriceUpdate) (
        id TEXT PRIMARY KEY,
        price_usd REAL,
        price_tix REAL,
        price_eur REAL
    );
    CREATE TABLE \(cardsDelete) (
        id TEXT PRIMARY KEY
    );
    CREATE TABLE \(cardFacesReplaceCards) (
        card_id TEXT PRIMARY KEY
    );
    CREATE TABLE \(seriesReplace) (
        card_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        finish TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        day_count INTEGER NOT NULL,
        prices_cents BLOB NOT NULL,
        PRIMARY KEY (card_id, provider, finish)
    );
    CREATE TABLE \(seriesSlide) (
        card_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        finish TEXT NOT NULL,
        drop_bytes INTEGER NOT NULL,
        new_start_date TEXT NOT NULL,
        new_end_date TEXT NOT NULL,
        new_day_count INTEGER NOT NULL,
        appended_cents BLOB NOT NULL,
        PRIMARY KEY (card_id, provider, finish)
    );
    CREATE TABLE \(seriesDelete) (
        card_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        finish TEXT NOT NULL,
        PRIMARY KEY (card_id, provider, finish)
    );
    CREATE TABLE \(mappingsUpsert) (
        card_id TEXT NOT NULL,
        mtgjson_uuid TEXT PRIMARY KEY
    );
    CREATE TABLE \(mappingsDelete) (
        mtgjson_uuid TEXT PRIMARY KEY
    );
    CREATE TABLE \(metadataSet) (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    """
}
