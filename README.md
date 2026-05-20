# Grimora

Grimora is a SwiftUI card library and list manager for Magic: The Gathering on Apple platforms. It is built around a local SQLite library, Scryfall-style search, deck/list organization, image caching, and MTGJSON price-history support.

## Features

- Local-first card database backed by SQLite.
- Scryfall-style search parsing and offline query support.
- Card list, deck, category, quantity, and zone management.
- Archidekt text import and list export support.
- Scryfall bulk-data import with local image caching.
- MTGJSON price-history import for value tracking.
- SwiftUI UI shared across macOS, iOS, and visionOS targets.

## Project Layout

- `GrimoraApp/` contains the app entry point, assets, privacy manifest, entitlements, and platform plists.
- `GrimoraKit/` contains the Swift package for core data/search logic and reusable SwiftUI views.
- `GrimoraUITests/` and `GrimoraCrossPlatformUITests/` contain UI test targets.
- `project.yml` is the XcodeGen source of truth for the generated Xcode project.

The generated `Grimora.xcodeproj` is intentionally ignored. Regenerate it from `project.yml` when needed.

## Requirements

- macOS with Xcode installed.
- Swift 6.2 toolchain.
- XcodeGen 2.45.4 or newer.

The macOS app target currently deploys to macOS 14. The iOS and visionOS targets are configured for iOS 26 and visionOS 26.

## Build

Generate the Xcode project:

```sh
xcodegen generate
```

Open the project in Xcode:

```sh
open Grimora.xcodeproj
```

Or build the macOS app from the command line with signing disabled:

```sh
xcodebuild -project Grimora.xcodeproj -scheme GrimoraMac -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Test

Run the package tests:

```sh
cd GrimoraKit
swift test
```

## Local Data

Generated build products, local card bulk JSON, local databases, logs, App Store artifacts, signing keys/profiles, and local environment files are ignored by Git. Keep user data and signing material out of the repository.

## License

Grimora is licensed under the GNU Affero General Public License v3.0 or later. In broad strokes, AGPL is a strong copyleft license: if someone distributes a modified version or runs a modified network-accessible version, they must make the corresponding source available under the same license.

See [LICENSE](LICENSE) for the full terms. This README is only a summary, not legal advice.
