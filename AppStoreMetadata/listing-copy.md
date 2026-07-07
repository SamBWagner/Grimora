# Grimora App Store Listing Copy

Use this copy for version 1.6 (build 2026070702). All public screenshots use
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
New in 1.6: build proper Commander decks — one copy of each card, one-tap organising by type — and iCloud sync now keeps every edit in step across all your devices.
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
Version 1.6 adds Commander decks and makes iCloud sync dependable.

- iCloud sync that sticks: an edit made on one device now holds everywhere instead of quietly reverting to an older copy — change a quantity or swap a printing and it stays put across all your devices
- Commander decks: create a collection as a Commander deck and Grimora keeps it to a single copy of each card (across printings), with an "Add Anyway" option when you mean it. Promote a card to your commander or trim duplicate copies in one step
- Reorganise by Type: file a deck's cards into Creatures, Instants, Lands and the rest with a single action
- Multi-category tags: tag a card with more than one category so it can sit in several groupings at once, shown as tags in list view and a badge on grid tiles
- Steadier syncing: sync no longer stalls on "unavailable", uploads only what actually changed, and a new Settings menu Sync panel shows the last sync and what's pending
- Simpler collections: every collection is now either a plain Collection or a Commander deck, and older decks carry over cleanly
```

## App Review Notes

```text
Version 1.6 (2026070702) requires no account or reviewer credentials. iCloud sync is optional. This release adds no new permissions.

Scry, the camera "Scry" tab on iPhone and iPad, uses the device camera to recognise cards. All recognition runs on-device with the Vision framework; the camera image is used only to read a card's name and set or collector number and is never uploaded. Grant camera access when prompted to try it, or skip it and the rest of the app works unchanged. Recognised cards are filed into a local "Scanned" collection. A Commander deck's menu offers "Re-scan Deck", which uses the same on-device camera recognition to reconcile a physical deck against the saved list; it needs no new permissions.

Grimora's card catalogue is a managed, prebuilt database. For an existing installation, the current library stays fully usable while any catalogue update stages on an allowed network and activates atomically on the next cold launch. A failed download, validation, or activation leaves the existing library untouched. A manual refresh (pull-to-refresh on the Cards screen, or the Library menu on Mac) may use any network.

iCloud sync is deterministic: changes from all signed-in devices merge automatically with no prompts and no manual conflict resolution. A new manual "Sync with iCloud" action (pull-to-refresh on iPhone and iPad, or the File menu and toolbar on Mac) forces an immediate two-way sync.

Card menus include a "Buy" link that opens the third-party MTG Mate marketplace in the device browser. Grimora has no in-app purchases and is not affiliated with or endorsed by MTG Mate or any marketplace.

All App Store screenshots contain fictional card names, fictional set data, and original placeholder artwork. Grimora is independently developed and is not affiliated with or endorsed by any card publisher, data provider, or marketplace.
```

## Local Screenshot Regeneration

```sh
python3 Tools/generate_app_store_screenshots.py
```

The screenshot generator overwrites the ignored PNG release artifacts under
`AppStoreScreenshots/` while preserving every existing filename and dimension.
