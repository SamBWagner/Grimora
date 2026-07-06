import Foundation

extension CardDatabase {
  func migrate() throws {
    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS cards (
          id TEXT PRIMARY KEY,
          oracle_id TEXT,
          name TEXT NOT NULL,
          name_key TEXT NOT NULL,
          display_name_key TEXT NOT NULL,
          lang TEXT,
          released_at TEXT,
          set_code TEXT NOT NULL,
          set_name TEXT NOT NULL,
          set_type TEXT NOT NULL,
          collector_number TEXT NOT NULL,
          collector_number_number INTEGER,
          rarity TEXT NOT NULL,
          rarity_rank INTEGER,
          artist TEXT,
          artist_key TEXT,
          artist_count INTEGER NOT NULL DEFAULT 0,
          illustration_count INTEGER NOT NULL DEFAULT 0,
          edhrec_rank INTEGER,
          penny_rank INTEGER,
          mtgo_id INTEGER,
          mana_cost TEXT NOT NULL DEFAULT '',
          mana_value REAL,
          power TEXT,
          power_value REAL,
          toughness TEXT,
          toughness_value REAL,
          loyalty TEXT,
          loyalty_value REAL,
          price_usd REAL,
          price_tix REAL,
          price_eur REAL,
          color_sort_key INTEGER NOT NULL,
          colors_key TEXT NOT NULL DEFAULT '',
          color_identity_key TEXT NOT NULL DEFAULT '',
          produced_mana_key TEXT NOT NULL DEFAULT '',
          color_indicator_key TEXT NOT NULL DEFAULT '',
          color_count INTEGER NOT NULL DEFAULT 0,
          color_identity_count INTEGER NOT NULL DEFAULT 0,
          produced_mana_count INTEGER NOT NULL DEFAULT 0,
          layout TEXT NOT NULL,
          layout_key TEXT NOT NULL DEFAULT '',
          type_line TEXT NOT NULL,
          type_line_key TEXT NOT NULL DEFAULT '',
          oracle_text TEXT NOT NULL,
          oracle_text_key TEXT NOT NULL DEFAULT '',
          keywords_key TEXT NOT NULL DEFAULT '',
          flavor_text TEXT,
          flavor_text_key TEXT NOT NULL DEFAULT '',
          watermark TEXT,
          legalities_key TEXT NOT NULL DEFAULT '',
          games_key TEXT NOT NULL DEFAULT '',
          finishes_key TEXT NOT NULL DEFAULT '',
          promo_types_key TEXT NOT NULL DEFAULT '',
          frame_effects_key TEXT NOT NULL DEFAULT '',
          artist_ids_key TEXT NOT NULL DEFAULT '',
          illustration_id TEXT,
          border_color TEXT,
          frame TEXT,
          security_stamp TEXT,
          is_digital INTEGER NOT NULL DEFAULT 0,
          is_oversized INTEGER NOT NULL DEFAULT 0,
          is_universes_beyond INTEGER NOT NULL,
          is_alchemy INTEGER NOT NULL,
          is_real_card INTEGER NOT NULL,
          is_promo INTEGER NOT NULL DEFAULT 0,
          is_variation INTEGER NOT NULL DEFAULT 0,
          is_booster_fun INTEGER NOT NULL DEFAULT 0,
          is_base_printing INTEGER NOT NULL DEFAULT 0,
          is_reserved INTEGER NOT NULL DEFAULT 0,
          is_game_changer INTEGER NOT NULL DEFAULT 0,
          is_reprint INTEGER NOT NULL DEFAULT 0,
          is_booster INTEGER NOT NULL DEFAULT 0,
          is_story_spotlight INTEGER NOT NULL DEFAULT 0,
          is_full_art INTEGER NOT NULL DEFAULT 0,
          is_textless INTEGER NOT NULL DEFAULT 0,
          is_foil INTEGER NOT NULL DEFAULT 0,
          is_nonfoil INTEGER NOT NULL DEFAULT 0,
          is_high_resolution INTEGER NOT NULL DEFAULT 0,
          print_count INTEGER NOT NULL DEFAULT 1,
          set_count INTEGER NOT NULL DEFAULT 1,
          paper_print_count INTEGER NOT NULL DEFAULT 0,
          paper_set_count INTEGER NOT NULL DEFAULT 0,
          is_new_art INTEGER NOT NULL DEFAULT 0,
          is_new_artist INTEGER NOT NULL DEFAULT 0,
          is_new_flavor INTEGER NOT NULL DEFAULT 0,
          is_new_rarity INTEGER NOT NULL DEFAULT 0,
          is_new_frame INTEGER NOT NULL DEFAULT 0,
          is_new_language INTEGER NOT NULL DEFAULT 0,
          small_image_path TEXT,
          normal_image_path TEXT,
          large_image_path TEXT,
          art_crop_image_path TEXT,
          small_image_url TEXT,
          normal_image_url TEXT,
          large_image_url TEXT,
          art_crop_image_url TEXT
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS card_faces (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
          face_index INTEGER NOT NULL,
          name TEXT NOT NULL,
          type_line TEXT NOT NULL,
          oracle_text TEXT NOT NULL,
          small_image_path TEXT,
          normal_image_path TEXT,
          large_image_path TEXT,
          art_crop_image_path TEXT,
          small_image_url TEXT,
          normal_image_url TEXT,
          large_image_url TEXT,
          art_crop_image_url TEXT
      )
      """)

    try database.execute(
      """
      CREATE VIRTUAL TABLE IF NOT EXISTS cards_fts
      USING fts5(card_id UNINDEXED, search_text, tokenize = 'unicode61 remove_diacritics 2')
      """)

    try database.execute(
      """
      CREATE VIRTUAL TABLE IF NOT EXISTS cards_name_fts
      USING fts5(card_id UNINDEXED, name_text, tokenize = 'unicode61 remove_diacritics 2')
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS card_value_mappings (
          card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
          mtgjson_uuid TEXT PRIMARY KEY
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS card_price_points (
          card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
          provider TEXT NOT NULL,
          finish TEXT NOT NULL,
          date TEXT NOT NULL,
          price REAL NOT NULL,
          PRIMARY KEY (card_id, provider, finish, date)
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS card_value_summaries (
          card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
          provider TEXT NOT NULL,
          finish TEXT NOT NULL,
          current_price REAL NOT NULL,
          current_date TEXT NOT NULL,
          price_1d REAL,
          price_7d REAL,
          price_30d REAL,
          price_90d REAL,
          PRIMARY KEY (card_id, provider, finish)
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS card_value_series (
          card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
          provider TEXT NOT NULL,
          finish TEXT NOT NULL,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL,
          day_count INTEGER NOT NULL,
          prices_cents BLOB NOT NULL,
          PRIMARY KEY (card_id, provider, finish)
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS value_history_background_jobs (
          id TEXT PRIMARY KEY,
          mtgjson_date TEXT NOT NULL,
          mtgjson_version TEXT NOT NULL,
          card_database_identity TEXT NOT NULL,
          stage TEXT NOT NULL,
          status TEXT NOT NULL,
          downloaded_bytes INTEGER NOT NULL DEFAULT 0,
          total_download_bytes INTEGER,
          scanned_bytes INTEGER NOT NULL DEFAULT 0,
          total_scan_bytes INTEGER,
          imported_price_points INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          completed_at TEXT,
          last_error TEXT
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS staging_card_value_mappings (
          job_id TEXT NOT NULL REFERENCES value_history_background_jobs(id) ON DELETE CASCADE,
          card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
          mtgjson_uuid TEXT NOT NULL,
          PRIMARY KEY (job_id, mtgjson_uuid)
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS staging_card_price_points (
          job_id TEXT NOT NULL REFERENCES value_history_background_jobs(id) ON DELETE CASCADE,
          card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
          provider TEXT NOT NULL,
          finish TEXT NOT NULL,
          date TEXT NOT NULL,
          price REAL NOT NULL,
          PRIMARY KEY (job_id, card_id, provider, finish, date)
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS sync_metadata (
          key TEXT PRIMARY KEY,
          value_text TEXT,
          value_data BLOB
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS sync_outbox (
          id TEXT PRIMARY KEY,
          entity_type TEXT NOT NULL,
          record_id TEXT NOT NULL,
          operation TEXT NOT NULL,
          payload BLOB,
          created_at TEXT NOT NULL
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS sync_tombstones (
          id TEXT PRIMARY KEY,
          entity_type TEXT NOT NULL,
          record_id TEXT NOT NULL,
          deleted_at TEXT NOT NULL
      )
      """)

    // Append-only, immutable log of every user action ("git-style changelog"). Each row has a
    // globally-unique id, so it syncs as a pure union across devices with no conflict logic — it
    // is history/observability only and is NOT the sync merge authority (that's the logical clock
    // on updated_at). Rows are stamped at the point of interaction and never re-stamped on pull.
    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS change_log (
          id TEXT PRIMARY KEY,
          recorded_at TEXT NOT NULL,
          device_id TEXT NOT NULL,
          action TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          list_id TEXT,
          summary TEXT
      )
      """)
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_change_log_recorded ON change_log(recorded_at)"
    )

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS cloud_sync_recovery_snapshots (
          id TEXT PRIMARY KEY,
          created_at TEXT NOT NULL,
          reason TEXT NOT NULL,
          payload BLOB NOT NULL
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS cloud_sync_records (
          record_type TEXT NOT NULL,
          record_id TEXT NOT NULL,
          system_fields BLOB NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (record_type, record_id)
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS sync_list_revision (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          revision INTEGER NOT NULL
      )
      """)
    try database.execute(
      "INSERT OR IGNORE INTO sync_list_revision (singleton, revision) VALUES (1, 0)"
    )

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS card_lists (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          ruleset TEXT NOT NULL DEFAULT 'none',
          description_rtfd BLOB,
          description_plain_text TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_pinned INTEGER NOT NULL DEFAULT 0,
          pinned_at TEXT,
          position INTEGER NOT NULL DEFAULT 0,
          shows_dashboard INTEGER NOT NULL DEFAULT 0,
          dashboard_includes_lands INTEGER NOT NULL DEFAULT 0,
          display_sort_mode TEXT,
          display_sort_direction TEXT NOT NULL DEFAULT 'ascending',
          view_mode TEXT NOT NULL DEFAULT 'grid'
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS card_list_categories (
          id TEXT PRIMARY KEY,
          list_id TEXT NOT NULL REFERENCES card_lists(id) ON DELETE CASCADE,
          zone TEXT NOT NULL DEFAULT 'mainboard',
          name TEXT NOT NULL,
          position INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
      )
      """)

    try database.execute(
      """
      CREATE TABLE IF NOT EXISTS card_list_entries (
          id TEXT PRIMARY KEY,
          list_id TEXT NOT NULL REFERENCES card_lists(id) ON DELETE CASCADE,
          zone TEXT NOT NULL DEFAULT 'mainboard',
          category_id TEXT REFERENCES card_list_categories(id) ON DELETE SET NULL,
          card_id TEXT NOT NULL,
          position INTEGER NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
      )
      """)

    try addColumnIfNeeded("cards", column: "lang", definition: "lang TEXT")
    try addColumnIfNeeded(
      "cards", column: "display_name_key", definition: "display_name_key TEXT NOT NULL DEFAULT ''")
    try addColumnIfNeeded(
      "cards", column: "is_promo", definition: "is_promo INTEGER NOT NULL DEFAULT 0")
    try addColumnIfNeeded(
      "cards", column: "is_variation", definition: "is_variation INTEGER NOT NULL DEFAULT 0")
    try addColumnIfNeeded(
      "cards", column: "is_booster_fun", definition: "is_booster_fun INTEGER NOT NULL DEFAULT 0")
    try addColumnIfNeeded(
      "cards", column: "is_base_printing", definition: "is_base_printing INTEGER NOT NULL DEFAULT 0")
    try addColumnIfNeeded("cards", column: "small_image_path", definition: "small_image_path TEXT")
    try addColumnIfNeeded("cards", column: "small_image_url", definition: "small_image_url TEXT")
    try addColumnIfNeeded("cards", column: "normal_image_url", definition: "normal_image_url TEXT")
    try addColumnIfNeeded("cards", column: "large_image_url", definition: "large_image_url TEXT")
    try addColumnIfNeeded("cards", column: "art_crop_image_path", definition: "art_crop_image_path TEXT")
    try addColumnIfNeeded("cards", column: "art_crop_image_url", definition: "art_crop_image_url TEXT")
    for column in Self.additionalCardColumnDefinitions {
      try addColumnIfNeeded("cards", column: column.name, definition: column.definition)
    }
    try addColumnIfNeeded(
      "card_lists",
      column: "ruleset",
      definition: "ruleset TEXT NOT NULL DEFAULT 'none'"
    )
    try addColumnIfNeeded("card_lists", column: "description_rtfd", definition: "description_rtfd BLOB")
    try addColumnIfNeeded(
      "card_lists",
      column: "description_plain_text",
      definition: "description_plain_text TEXT NOT NULL DEFAULT ''"
    )
    try addColumnIfNeeded(
      "card_lists",
      column: "is_pinned",
      definition: "is_pinned INTEGER NOT NULL DEFAULT 0"
    )
    try addColumnIfNeeded(
      "card_lists",
      column: "pinned_at",
      definition: "pinned_at TEXT"
    )
    let addedCardCollectionPositionColumn = try addColumnIfNeeded(
      "card_lists",
      column: "position",
      definition: "position INTEGER NOT NULL DEFAULT 0"
    )
    try addColumnIfNeeded(
      "card_lists",
      column: "shows_dashboard",
      definition: "shows_dashboard INTEGER NOT NULL DEFAULT 0"
    )
    try addColumnIfNeeded(
      "card_lists",
      column: "dashboard_includes_lands",
      definition: "dashboard_includes_lands INTEGER NOT NULL DEFAULT 0"
    )
    try addColumnIfNeeded(
      "card_lists",
      column: "display_sort_mode",
      definition: "display_sort_mode TEXT"
    )
    try addColumnIfNeeded(
      "card_lists",
      column: "display_sort_direction",
      definition: "display_sort_direction TEXT NOT NULL DEFAULT 'ascending'"
    )
    try addColumnIfNeeded(
      "card_lists",
      column: "view_mode",
      definition: "view_mode TEXT NOT NULL DEFAULT 'grid'"
    )
    try addColumnIfNeeded(
      "card_faces", column: "small_image_path", definition: "small_image_path TEXT")
    try addColumnIfNeeded(
      "card_faces", column: "small_image_url", definition: "small_image_url TEXT")
    try addColumnIfNeeded(
      "card_faces", column: "normal_image_url", definition: "normal_image_url TEXT")
    try addColumnIfNeeded(
      "card_faces", column: "large_image_url", definition: "large_image_url TEXT")
    try addColumnIfNeeded(
      "card_faces", column: "art_crop_image_path", definition: "art_crop_image_path TEXT")
    try addColumnIfNeeded(
      "card_faces", column: "art_crop_image_url", definition: "art_crop_image_url TEXT")
    try addColumnIfNeeded(
      "card_list_categories",
      column: "zone",
      definition: "zone TEXT NOT NULL DEFAULT 'mainboard'"
    )
    try addColumnIfNeeded(
      "card_list_entries",
      column: "zone",
      definition: "zone TEXT NOT NULL DEFAULT 'mainboard'"
    )
    try addColumnIfNeeded(
      "card_list_entries",
      column: "category_id",
      definition: "category_id TEXT REFERENCES card_list_categories(id) ON DELETE SET NULL"
    )
    try addColumnIfNeeded(
      "card_list_entries",
      column: "quantity",
      definition: "quantity INTEGER NOT NULL DEFAULT 1"
    )
    try addColumnIfNeeded(
      "card_lists",
      column: "sync_updated_at",
      definition: "sync_updated_at TEXT"
    )
    try addColumnIfNeeded(
      "card_list_categories",
      column: "sync_updated_at",
      definition: "sync_updated_at TEXT"
    )
    try addColumnIfNeeded(
      "card_list_entries",
      column: "updated_at",
      definition: "updated_at TEXT"
    )
    try addColumnIfNeeded(
      "card_list_entries",
      column: "sync_updated_at",
      definition: "sync_updated_at TEXT"
    )
    try addColumnIfNeeded(
      "card_list_entries",
      column: "selected_finish",
      definition: "selected_finish TEXT"
    )
    try addColumnIfNeeded(
      "card_list_entries",
      column: "secondary_category_ids",
      definition: "secondary_category_ids TEXT"
    )
    try migrateCardValueMappingTablesIfNeeded()

    try database.execute(
      """
      CREATE INDEX IF NOT EXISTS idx_card_value_mappings_card
      ON card_value_mappings(card_id)
      """)
    try database.execute(
      """
      CREATE INDEX IF NOT EXISTS idx_staging_card_value_mappings_job_card
      ON staging_card_value_mappings(job_id, card_id)
      """)
    try database.execute(
      """
      CREATE INDEX IF NOT EXISTS idx_card_price_points_card_finish_date
      ON card_price_points(card_id, provider, finish, date)
      """)

    try database.execute(
      """
      CREATE INDEX IF NOT EXISTS idx_card_value_summaries_current_price
      ON card_value_summaries(provider, finish, current_price)
      """)
    try database.execute(
      """
      CREATE INDEX IF NOT EXISTS idx_card_value_series_card_finish
      ON card_value_series(card_id, provider, finish)
      """)
    try database.execute(
      """
      CREATE INDEX IF NOT EXISTS idx_value_history_background_jobs_status
      ON value_history_background_jobs(status, updated_at)
      """)
    try database.execute(
      """
      CREATE INDEX IF NOT EXISTS idx_staging_card_price_points_job_card_finish_date
      ON staging_card_price_points(job_id, card_id, provider, finish, date)
      """)
    try database.execute("UPDATE card_lists SET sync_updated_at = updated_at WHERE sync_updated_at IS NULL")
    try database.execute(
      "UPDATE card_list_categories SET sync_updated_at = updated_at WHERE sync_updated_at IS NULL")
    try database.execute("UPDATE card_list_entries SET updated_at = created_at WHERE updated_at IS NULL")
    try database.execute(
      "UPDATE card_list_entries SET sync_updated_at = updated_at WHERE sync_updated_at IS NULL")
    // Collections are now either a plain Collection (`none`) or a Commander deck.
    // Coerce any list still tagged with a retired constructed format down to
    // `none`; the zone normalization below then rehomes stranded sideboard cards
    // into the mainboard. Idempotent — a no-op once every list is `none`/`commander`.
    try database.execute("UPDATE card_lists SET ruleset = 'none' WHERE ruleset NOT IN ('none', 'commander')")
    try normalizeCardCollectionZonesForRulesetsUnlocked()
    try consolidateDuplicateCardCollectionEntriesUnlocked()
    try normalizeCardCollectionPositionsUnlocked(
      ordering: addedCardCollectionPositionColumn ? .legacySidebarOrder : .storedPosition
    )

    try database.execute("CREATE INDEX IF NOT EXISTS idx_cards_name_key ON cards(name_key)")
    try database.execute("CREATE INDEX IF NOT EXISTS idx_cards_display_name_key ON cards(display_name_key)")
    try database.execute("CREATE INDEX IF NOT EXISTS idx_cards_release ON cards(released_at)")
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_cards_set_number ON cards(set_code, collector_number_number, collector_number)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_cards_flags ON cards(is_universes_beyond, is_alchemy, is_real_card)"
    )
    try database.execute("CREATE INDEX IF NOT EXISTS idx_cards_oracle ON cards(oracle_id, name_key)")
    try database.execute("CREATE INDEX IF NOT EXISTS idx_cards_layout ON cards(layout_key)")
    try database.execute("CREATE INDEX IF NOT EXISTS idx_cards_dates ON cards(released_at)")
    try database.execute("CREATE INDEX IF NOT EXISTS idx_cards_display_art ON cards(illustration_id)")
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_card_faces_card_id_face_index ON card_faces(card_id, face_index)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_card_list_entries_list_position ON card_list_entries(list_id, position)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_card_list_entries_list_zone_position ON card_list_entries(list_id, zone, position)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_card_list_entries_category ON card_list_entries(category_id)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_card_list_entries_list_category_card ON card_list_entries(list_id, zone, category_id, card_id)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_card_list_categories_list_position ON card_list_categories(list_id, position)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_card_list_categories_list_zone_position ON card_list_categories(list_id, zone, position)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_card_lists_pinned_position ON card_lists(is_pinned, position)"
    )
    try database.execute("DROP INDEX IF EXISTS idx_card_list_categories_list_name")
    try database.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_card_list_categories_list_zone_name ON card_list_categories(list_id, zone, name COLLATE NOCASE)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_card_list_entries_card ON card_list_entries(card_id)"
    )
    try database.execute("CREATE INDEX IF NOT EXISTS idx_sync_outbox_created ON sync_outbox(created_at)")
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_sync_tombstones_record ON sync_tombstones(entity_type, record_id)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_cloud_sync_recovery_created ON cloud_sync_recovery_snapshots(created_at)"
    )
    try database.execute(
      "CREATE INDEX IF NOT EXISTS idx_cloud_sync_records_updated ON cloud_sync_records(updated_at)"
    )
    try database.execute("DROP TRIGGER IF EXISTS trg_card_lists_sync_updated_at")
    try database.execute(
      """
      CREATE TRIGGER trg_card_lists_sync_updated_at
      AFTER UPDATE OF updated_at ON card_lists
      WHEN NEW.sync_updated_at IS OLD.sync_updated_at
      BEGIN
          UPDATE card_lists
          SET sync_updated_at = CASE
              WHEN OLD.sync_updated_at IS NULL OR NEW.updated_at > OLD.sync_updated_at
              THEN NEW.updated_at
              ELSE strftime(
                  '%Y-%m-%dT%H:%M:%fZ',
                  julianday(OLD.sync_updated_at) + (0.001 / 86400.0)
              )
          END
          WHERE id = NEW.id;
      END
      """)
    try database.execute("DROP TRIGGER IF EXISTS trg_card_list_categories_sync_updated_at")
    try database.execute(
      """
      CREATE TRIGGER trg_card_list_categories_sync_updated_at
      AFTER UPDATE OF updated_at ON card_list_categories
      WHEN NEW.sync_updated_at IS OLD.sync_updated_at
      BEGIN
          UPDATE card_list_categories
          SET sync_updated_at = CASE
              WHEN OLD.sync_updated_at IS NULL OR NEW.updated_at > OLD.sync_updated_at
              THEN NEW.updated_at
              ELSE strftime(
                  '%Y-%m-%dT%H:%M:%fZ',
                  julianday(OLD.sync_updated_at) + (0.001 / 86400.0)
              )
          END
          WHERE id = NEW.id;
      END
      """)
    // Entries need the same "advance the sync clock whenever updated_at changes" trigger that
    // card_lists / card_list_categories already have. Without it, `sync_updated_at` was only ever
    // set at INSERT and stayed frozen: every entry edit (quantity, finish, printing swap, zone /
    // category move) bumps `updated_at` but the sync-visible timestamp — read via
    // COALESCE(sync_updated_at, updated_at) — never moved, so the upload diff saw "no change" and
    // the edit silently stopped syncing. This mirror keeps sync_updated_at in step, monotonically.
    try database.execute("DROP TRIGGER IF EXISTS trg_card_list_entries_sync_updated_at")
    try database.execute(
      """
      CREATE TRIGGER trg_card_list_entries_sync_updated_at
      AFTER UPDATE OF updated_at ON card_list_entries
      WHEN NEW.sync_updated_at IS OLD.sync_updated_at
      BEGIN
          UPDATE card_list_entries
          SET sync_updated_at = CASE
              WHEN OLD.sync_updated_at IS NULL OR NEW.updated_at > OLD.sync_updated_at
              THEN NEW.updated_at
              ELSE strftime(
                  '%Y-%m-%dT%H:%M:%fZ',
                  julianday(OLD.sync_updated_at) + (0.001 / 86400.0)
              )
          END
          WHERE id = NEW.id;
      END
      """)
    try database.execute("DROP TRIGGER IF EXISTS trg_card_list_entries_updated_at")
    try database.execute(
      """
      CREATE TRIGGER trg_card_list_entries_updated_at
      AFTER UPDATE ON card_list_entries
      WHEN NEW.updated_at IS OLD.updated_at OR NEW.updated_at IS NULL
      BEGIN
          UPDATE card_list_entries
          SET updated_at = CASE
                  WHEN OLD.sync_updated_at IS NULL
                    OR COALESCE(NEW.updated_at, '') > OLD.sync_updated_at
                  THEN COALESCE(
                      NEW.updated_at,
                      strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
                  )
                  ELSE strftime(
                      '%Y-%m-%dT%H:%M:%fZ',
                      julianday(OLD.sync_updated_at) + (0.001 / 86400.0)
                  )
              END,
              sync_updated_at = CASE
                  WHEN OLD.sync_updated_at IS NULL
                    OR COALESCE(NEW.updated_at, '') > OLD.sync_updated_at
                  THEN COALESCE(
                      NEW.updated_at,
                      strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
                  )
                  ELSE strftime(
                      '%Y-%m-%dT%H:%M:%fZ',
                      julianday(OLD.sync_updated_at) + (0.001 / 86400.0)
                  )
              END
          WHERE id = NEW.id;
      END
      """)
    try database.execute(
      """
      CREATE TRIGGER IF NOT EXISTS trg_card_lists_sync_timestamp_insert
      AFTER INSERT ON card_lists
      WHEN NEW.sync_updated_at IS NULL
      BEGIN
          UPDATE card_lists SET sync_updated_at = NEW.updated_at WHERE id = NEW.id;
      END
      """)
    try database.execute(
      """
      CREATE TRIGGER IF NOT EXISTS trg_card_list_categories_sync_timestamp_insert
      AFTER INSERT ON card_list_categories
      WHEN NEW.sync_updated_at IS NULL
      BEGIN
          UPDATE card_list_categories SET sync_updated_at = NEW.updated_at WHERE id = NEW.id;
      END
      """)
    try database.execute(
      """
      CREATE TRIGGER IF NOT EXISTS trg_card_list_entries_sync_timestamp_insert
      AFTER INSERT ON card_list_entries
      WHEN NEW.sync_updated_at IS NULL
      BEGIN
          UPDATE card_list_entries
          SET sync_updated_at = COALESCE(NEW.updated_at, NEW.created_at)
          WHERE id = NEW.id;
      END
      """)
    for table in ["card_lists", "card_list_categories", "card_list_entries"] {
      for operation in ["INSERT", "UPDATE", "DELETE"] {
        try database.execute(
          """
          CREATE TRIGGER IF NOT EXISTS trg_\(table)_sync_revision_\(operation.lowercased())
          AFTER \(operation) ON \(table)
          BEGIN
              UPDATE sync_list_revision
              SET revision = revision + 1
              WHERE singleton = 1;
          END
          """)
      }
    }
    try rebuildNameSearchIndexIfNeeded()
  }

  enum CardCollectionPositionOrdering {
    case storedPosition
    case legacySidebarOrder
  }

  @discardableResult
  func addColumnIfNeeded(_ table: String, column: String, definition: String) throws -> Bool {
    let statement = try database.prepare("PRAGMA table_info(\(table))")
    while try statement.step() {
      if statement.string(at: 1) == column {
        return false
      }
    }

    try database.execute("ALTER TABLE \(table) ADD COLUMN \(definition)")
    return true
  }

  private func migrateCardValueMappingTablesIfNeeded() throws {
    let mappingPrimaryKey = try primaryKeyColumns(in: "card_value_mappings")
    if mappingPrimaryKey != ["mtgjson_uuid"] {
      try database.transaction {
        try database.execute(
          """
          CREATE TABLE card_value_mappings_v2 (
              card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
              mtgjson_uuid TEXT PRIMARY KEY
          )
          """)
        try database.execute(
          """
          INSERT OR IGNORE INTO card_value_mappings_v2 (card_id, mtgjson_uuid)
          SELECT card_id, mtgjson_uuid
          FROM card_value_mappings
          """)
        try database.execute("DROP TABLE card_value_mappings")
        try database.execute("ALTER TABLE card_value_mappings_v2 RENAME TO card_value_mappings")
      }
    }

    let stagingPrimaryKey = try primaryKeyColumns(in: "staging_card_value_mappings")
    if stagingPrimaryKey != ["job_id", "mtgjson_uuid"] {
      try database.transaction {
        try database.execute(
          """
          CREATE TABLE staging_card_value_mappings_v2 (
              job_id TEXT NOT NULL REFERENCES value_history_background_jobs(id) ON DELETE CASCADE,
              card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
              mtgjson_uuid TEXT NOT NULL,
              PRIMARY KEY (job_id, mtgjson_uuid)
          )
          """)
        try database.execute(
          """
          INSERT OR IGNORE INTO staging_card_value_mappings_v2 (job_id, card_id, mtgjson_uuid)
          SELECT job_id, card_id, mtgjson_uuid
          FROM staging_card_value_mappings
          """)
        try database.execute("DROP TABLE staging_card_value_mappings")
        try database.execute(
          "ALTER TABLE staging_card_value_mappings_v2 RENAME TO staging_card_value_mappings")
      }
    }
  }

  private func primaryKeyColumns(in table: String) throws -> [String] {
    let statement = try database.prepare("PRAGMA table_info(\(table))")
    var columns: [(position: Int, name: String)] = []
    while try statement.step() {
      guard let name = statement.string(at: 1),
        let position = statement.int(at: 5),
        position > 0
      else {
        continue
      }
      columns.append((position, name))
    }
    return columns.sorted { $0.position < $1.position }.map(\.name)
  }

  func rebuildNameSearchIndexIfNeeded() throws {
    let cardCount = try self.cardCount()
    guard cardCount > 0 else {
      return
    }

    let nameIndexCount = try nameSearchIndexCount()
    let schemaVersion = try metadataValue(forKey: MetadataKey.searchSchemaVersion.rawValue)
    guard schemaVersion != Self.currentSearchSchemaVersion || nameIndexCount != cardCount else {
      return
    }

    try database.transaction {
      try database.execute("DELETE FROM cards_name_fts")
      try database.execute(
        """
        INSERT INTO cards_name_fts (card_id, name_text)
        SELECT id, name
        FROM cards
        """)
    }

    if schemaVersion != nil {
      try saveMetadataValue(Self.currentSearchSchemaVersion, forKey: MetadataKey.searchSchemaVersion.rawValue)
    }
  }

  func nameSearchIndexCount() throws -> Int {
    let statement = try database.prepare("SELECT COUNT(*) FROM cards_name_fts")
    _ = try statement.step()
    return statement.int(at: 0) ?? 0
  }

  func consolidateDuplicateCardCollectionEntriesUnlocked(listID: String? = nil) throws {
    let duplicateGroups: SQLiteStatement
    if let listID {
      duplicateGroups = try database.prepare(
        """
        SELECT list_id, zone, category_id, card_id
        FROM card_list_entries
        WHERE list_id = ?
        GROUP BY list_id, zone, category_id, card_id
        HAVING COUNT(*) > 1
        """)
      try duplicateGroups.bind(listID, at: 1)
    } else {
      duplicateGroups = try database.prepare(
        """
        SELECT list_id, zone, category_id, card_id
        FROM card_list_entries
        GROUP BY list_id, zone, category_id, card_id
        HAVING COUNT(*) > 1
        """)
    }

    var groups: [(listID: String, zone: String, categoryID: String?, cardID: String)] = []
    while try duplicateGroups.step() {
      groups.append((
        listID: duplicateGroups.string(at: 0) ?? "",
        zone: duplicateGroups.string(at: 1) ?? CardCollectionZone.mainboard.rawValue,
        categoryID: duplicateGroups.string(at: 2),
        cardID: duplicateGroups.string(at: 3) ?? ""
      ))
    }

    guard !groups.isEmpty else {
      return
    }

    let entries = try database.prepare(
      """
      SELECT id, quantity
      FROM card_list_entries
      WHERE list_id = ? AND zone = ? AND category_id IS ? AND card_id = ?
      ORDER BY position ASC, created_at ASC, id ASC
      """)
    let update = try database.prepare(
      """
      UPDATE card_list_entries
      SET quantity = ?
      WHERE id = ?
      """)
    let delete = try database.prepare("DELETE FROM card_list_entries WHERE id = ?")

    for group in groups {
      try entries.bind(group.listID, at: 1)
      try entries.bind(group.zone, at: 2)
      try entries.bind(group.categoryID, at: 3)
      try entries.bind(group.cardID, at: 4)

      var survivorID: String?
      var duplicateIDs: [String] = []
      var totalQuantity = 0
      while try entries.step() {
        let entryID = entries.string(at: 0) ?? ""
        totalQuantity += max(1, entries.int(at: 1) ?? 1)
        if survivorID == nil {
          survivorID = entryID
        } else {
          duplicateIDs.append(entryID)
        }
      }
      try entries.reset()

      guard let survivorID else {
        continue
      }

      try update.bind(max(1, totalQuantity), at: 1)
      try update.bind(survivorID, at: 2)
      try update.step()
      try update.reset()

      for duplicateID in duplicateIDs {
        try delete.bind(duplicateID, at: 1)
        try delete.step()
        try delete.reset()
      }
    }
  }
}
