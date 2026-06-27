# Grimora App Store Listing Copy

Use this copy for version 1.3 (build 2026062601). All public screenshots use
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
Search smarter — tap cards to refine your results, build advanced queries with live colour-coded syntax, and search across every collection at once.
```

## Keywords

```text
cards,library,collection,deck,lists,trading,tcg,offline,search,prices,organizer,tracker
```

## Description

```text
Grimora is a local-first card library and collection manager for players who want fast, precise search and structured organisation across a large personal collection.

Search offline with live syntax highlighting, refine results by tapping cards, build advanced queries, and search across every collection at once. Group cards into collections and categories, track value over time, and keep devices aligned with optional iCloud sync. Images and library data are cached locally so browsing stays quick after setup.

Features:
- Fast local card search with live, colour-coded query syntax
- Tap-to-refine search and a visual advanced-search builder
- Search across all of your collections at once
- Collections with categories, on-card actions, and reordering
- Detail views for card versions, notes, artist art, and price history
- Import and export tools for your collections
- Optional iCloud sync across your Apple devices

Grimora is independently developed and is not affiliated with or endorsed by any card publisher, data provider, or marketplace.
```

## What's New

```text
Version 1.3 makes finding and organising cards faster across all your devices.

- Refine searches by tapping cards or selecting oracle text to include or exclude what you want — and hide terms you never want to see again
- Build precise queries with a new advanced search form and live, colour-coded Scryfall syntax right in the search field
- Search across every collection at once and see matching cards highlighted on the dashboard
- Lists are now Collections, with add, create and move-category actions on the card itself plus quick category reordering
- Pinch to zoom the card grid and resize the collections dashboard on iPad
- Star favourites from search results, scrub through price history, and jump from any card to all of an artist's art
- A guided walkthrough helps new players get started, replayable any time from Settings
- iCloud is now the single source of truth, ending the repeated sync prompt and keeping card counts accurate across devices
```

## App Review Notes

```text
Version 1.3 (2026062601) requires no account or reviewer credentials. iCloud sync is optional.

Grimora's card catalogue is a managed, prebuilt database. For an existing installation, the current library stays fully usable while any catalogue update stages on an allowed network and activates atomically on the next cold launch. A failed download, validation, or activation leaves the existing library untouched. A manual refresh may use any network.

iCloud sync is now deterministic: changes from all signed-in devices merge automatically with no prompts and no manual conflict resolution. The interactive "Review iCloud Data" screen from earlier versions has been removed.

Card menus include a "Buy" link that opens the third-party MTG Mate marketplace in the device browser. Grimora has no in-app purchases and is not affiliated with or endorsed by MTG Mate or any marketplace.

All App Store screenshots contain fictional card names, fictional set data, and original placeholder artwork. Grimora is independently developed and is not affiliated with or endorsed by any card publisher, data provider, or marketplace.
```

## Local Screenshot Regeneration

```sh
python3 Tools/generate_app_store_screenshots.py
```

The screenshot generator overwrites the ignored PNG release artifacts under
`AppStoreScreenshots/` while preserving every existing filename and dimension.
