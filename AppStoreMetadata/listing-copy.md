# Grimora App Store Listing Copy

Use this copy for version 1.5 (build 2026070501). All public screenshots use
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
New in 1.5: Scry now shows each scanned card's value and celebrates your best pulls, and you can re-scan a whole Commander deck to reconcile it against your list.
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
Version 1.5 makes Scry more rewarding and Grimora easier to use on iPhone.

- Scry shows the value: every scanned card displays its price, and valuable pulls light up with a colour tier and a celebratory sound. Set your own alert thresholds in Settings
- Re-scan a Commander deck: point the camera at your physical deck and Grimora reconciles it against your saved list, so you can accept every change at once
- Bulk scanning holds focus more reliably, with a tap-to-focus hint, and now reads collector numbers on old-border retro reprints
- Rearrange your dashboard: drag collection tiles into any order, and drop one onto a pinned tile to pin or unpin it
- Collections and the New List source picker now lay out cleanly on small iPhones, with full-width cards that no longer clip at the edges
- Aftermath cards now turn the right way so both halves read upright, with clearer rotate and flip controls
```

## App Review Notes

```text
Version 1.5 (2026070501) requires no account or reviewer credentials. iCloud sync is optional. This release adds no new permissions.

Scry, the camera "Scry" tab on iPhone and iPad, uses the device camera to recognise cards. All recognition runs on-device with the Vision framework; the camera image is used only to read a card's name and set or collector number and is never uploaded. Grant camera access when prompted to try it, or skip it and the rest of the app works unchanged. Recognised cards are filed into a local "Scanned" collection. New in 1.5, a Commander deck's menu offers "Re-scan Deck", which uses the same on-device camera recognition to reconcile a physical deck against the saved list; it needs no new permissions.

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
