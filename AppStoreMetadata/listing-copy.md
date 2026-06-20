# Grimora App Store Listing Copy

Use this copy for version 1.2 (build 2026061402). All public screenshots use
the clean fictional-card screenshot set.

## App Name

```text
Grimora
```

## Subtitle

```text
Card Library & Lists
```

## Promotional Text

```text
Build searchable card libraries, organize lists, compare versions, and review collection value with a private, local-first workspace.
```

## Keywords

```text
cards,library,collection,deck,lists,trading,tcg,offline,search,prices,organizer,tracker
```

## Description

```text
Grimora is a local-first card library and list manager for players who want fast search, structured lists, and value context across a large personal collection.

Search offline, save reusable list views, compare card versions, group entries into categories, and keep devices aligned with optional iCloud sync. Images and library data are cached locally so browsing stays quick after setup.

Features:
- Fast local card search
- Flexible list and category organization
- Detail views for card versions, notes, and value history
- Import and export tools for personal lists
- Optional iCloud sync across your Apple devices

Grimora is independently developed and is not affiliated with or endorsed by any card publisher, data provider, or marketplace.
```

## What's New

```text
Version 1.2 moves Grimora's card catalog to a managed, prebuilt database.

- Existing libraries remain usable while the approximately 126 MB catalog stages
- Catalog updates no longer require rebuilding card and market indexes on device
- Downloads validate before activation and safely fall back to the previous catalog
- User lists and optional iCloud sync remain separate from managed card data
- Improved migration recovery, storage checks, and cross-device compatibility
```

## App Review Notes

```text
Version 1.2 (2026061402) requires no account or reviewer credentials. iCloud sync is optional.

For an existing installation, Grimora keeps the current library fully usable while an approximately 126 MB managed catalog stages on an allowed network. The app then displays "Restart to finish"; activation occurs atomically on the next cold launch. A failed download, validation, migration, or activation leaves the existing library untouched. A manual refresh may use any network.

All App Store screenshots contain fictional card names, fictional set data, and original placeholder artwork. Grimora is independently developed and is not affiliated with or endorsed by any card publisher, data provider, or marketplace.
```

## Local Screenshot Regeneration

```sh
python3 Tools/generate_app_store_screenshots.py
```

The screenshot generator overwrites the ignored PNG release artifacts under
`AppStoreScreenshots/` while preserving every existing filename and dimension.
