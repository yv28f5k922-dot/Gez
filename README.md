# Gez

A grand strategy game for Mac and iPad, starting 30 May 1453, with EU-style
real-time-with-pause gameplay and Total War–style battles and sieges.

See [docs/DESIGN.md](docs/DESIGN.md) for the full design and milestones.

## Running it on your Mac

1. Install **Xcode** from the Mac App Store and open it once to finish setup.
2. Install [Homebrew](https://brew.sh) if you don't have it, then:
   ```sh
   brew install xcodegen
   ```
3. In this folder:
   ```sh
   xcodegen generate
   open Gez.xcodeproj
   ```
4. In Xcode, pick the **GezMac** scheme and press Run (⌘R).
   For the iPad, pick **GeziPad**, choose your iPad as the destination, and set
   your Apple ID team under *Signing & Capabilities* the first time.

## Controls

- **Space**: pause / resume
- **1–5**: set game speed
- **+ / -**: faster / slower
- Click or tap a province to see its details.

## Layout

```
App/Shared/           SwiftUI app (Mac + iPad)
Packages/GezCore/     Simulation: calendar, tick, world, systems, scenario
docs/DESIGN.md        Design document
project.yml           XcodeGen spec (generates Gez.xcodeproj)
```

## Tests

```sh
swift test --package-path Packages/GezCore
```

GitHub Actions runs the simulation tests and builds both apps on every push.
