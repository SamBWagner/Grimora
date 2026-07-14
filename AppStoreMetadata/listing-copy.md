# Grimora App Store Listing Copy

Use this copy for version 1.7 (build 2026071401). All public screenshots use
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
New in 1.7: card data updates are now a fraction of the size — only what changed is downloaded — plus smoother scrolling and faster search in big collections.
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
Version 1.7 shrinks data updates and smooths out scrolling, search, and editing.

- Much smaller, faster data updates: when the card catalogue changes, Grimora now downloads only what's actually different instead of the whole database — a fraction of the size, far quicker, and still applied safely in the background
- Update on your terms: a new Automatic Data Updates setting lets you switch off automatic catalogue downloads and refresh manually from the Library menu whenever you like
- Smoother scrolling: card art is now prepared off the main thread before it's shown, so scrolling through large grids stays fluid instead of hitching
- Faster in-list search: searching within a collection runs off the main thread, so typing no longer freezes the list
- Snappier editing: changing a card's category, quantity, or zone no longer recomputes every collection — large libraries stop stalling on each edit
- Tidier multi-category view: empty categories stay hidden until they're needed, and a card tagged into several categories appears as a dimmed ghost in the ones it isn't filed under
- Maybeboard for Commander decks: adding an extra card to a full Commander deck now offers to place it on the Maybeboard
- Card-back placeholder: cards without loaded art now show the classic card back instead of a blank tile
```

## App Review Notes

```text
Version 1.7 (2026071401) requires no account or reviewer credentials. iCloud sync is optional. This release adds no new permissions.

Scry, the camera "Scry" tab on iPhone and iPad, uses the device camera to recognise cards. All recognition runs on-device with the Vision framework; the camera image is used only to read a card's name and set or collector number and is never uploaded. Grant camera access when prompted to try it, or skip it and the rest of the app works unchanged. Recognised cards are filed into a local "Scanned" collection. A Commander deck's menu offers "Re-scan Deck", which uses the same on-device camera recognition to reconcile a physical deck against the saved list; it needs no new permissions.

Grimora's card catalogue is a managed, prebuilt database served from the developer's own endpoint. In 1.7 an update downloads incrementally where possible — only the data that changed since the installed version — and falls back to a full download otherwise; every downloaded update is integrity-checked before it is applied. The current library stays fully usable throughout, and a failed download, validation, or activation leaves the existing library untouched. Automatic catalogue downloads can be turned off in the new Automatic Data Updates setting; a manual refresh (pull-to-refresh on the Cards screen, or the Library menu on Mac) may use any network. No account is involved and no user data is sent to fetch catalogue data.

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
