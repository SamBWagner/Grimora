# Grimora App Store Listing Copy

Use this copy for version 1.4 (build 2026070301). All public screenshots use
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
New in 1.4: point your camera at a card and Grimora recognises it on-device and files it into your collection, plus living foil that shimmers as you tilt.
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
Version 1.4 brings camera card recognition and living foil to your whole library.

- Scry: point your camera at a card and Grimora recognises it on-device, then files it into a new Scanned collection. Scan one card at a time, or a whole stack in bulk mode
- When a card could be more than one printing, Grimora shows you the likely candidates to pick from rather than guessing
- Foil comes to life: foil, etched, and special-treatment cards shimmer as you tilt on iPhone and iPad, with a new finish picker in the card detail
- Foil now renders in search, collection grids, and detail alike, so foil cards read as foil everywhere
- Pull down to sync: refresh any collection to sync with iCloud, or pull on the Cards screen to check for new card data
- On Mac, sync with iCloud from the File menu or toolbar, and drag the card detail pane to the width you want
- A new animated launch screen, plus Favourites and Scanned now lead the sidebar as built-in lists
- Opening a collection is now instant, with artwork loading in the background
```

## App Review Notes

```text
Version 1.4 (2026070301) requires no account or reviewer credentials. iCloud sync is optional.

Scry, the new camera "Scry" tab on iPhone and iPad, uses the device camera to recognise cards. All recognition runs on-device with the Vision framework; the camera image is used only to read a card's name and set or collector number and is never uploaded. Grant camera access when prompted to try it, or skip it and the rest of the app works unchanged. Recognised cards are filed into a local "Scanned" collection.

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
