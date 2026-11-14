# Gez

A grand strategy game for Mac and iPad, starting 30 May 1453, with EU-style
real-time-with-pause gameplay and Total War–style battles and sieges.

See [docs/HANDOFF.md](docs/HANDOFF.md) for the current state and
[docs/DESIGN.md](docs/DESIGN.md) for the full design.

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
- **= / -**: faster / slower
- **Q W E R T Y U I**: political, states, terrain, religion, culture,
  development, goods and markets map modes
- Click or tap a province for its panel (Overview, Economy, People).
- Pinch or scroll to zoom; drag or two-finger scroll to pan.
- Top bar: treasury opens the **Budget** (taxes, loans, coinage);
  **Trade** (routes, tolls, embargoes); **Court** (ruler, family, council,
  vassals, marriages, chronicle); **Stability** opens **Government**
  (estates, privileges, laws, reforms).

## Layout

```
App/Shared/           SwiftUI app (Mac + iPad) and Metal map
App/Tests/            Snapshot tests (render PNGs on CI)
Packages/GezCore/     Simulation: calendar, tick, world, systems, scenario
data/                 Hand-written game data (map, economy, characters,
                      government, heraldry)
tools/                Generators that turn data/ into game files
docs/                 Handoff, roadmap, design, history notes, credits
project.yml           XcodeGen spec (generates Gez.xcodeproj)
```

## Changing game data

Edit the text files in `data/`, then run the matching generator and commit
both. Full table and run order: [docs/HANDOFF.md](docs/HANDOFF.md)
("Data pipelines").

```sh
tools/mapgen/fetch_coastlines.sh /tmp/geo        # once
pip install numpy scipy pillow
python3 tools/mapgen/mapgen.py --land /tmp/geo/land10m.geojson
python3 tools/terrain/bake_terrain.py
python3 tools/economy/econgen.py
python3 tools/characters/chargen.py
python3 tools/government/govgen.py
```

## Tests

```sh
swift test --package-path Packages/GezCore
```

GitHub Actions runs the simulation tests (macOS and Linux), builds both
apps and renders snapshots on every push.

## Documents

- [docs/HANDOFF.md](docs/HANDOFF.md): where things stand and how to work on it
- [docs/ROADMAP.md](docs/ROADMAP.md): the agreed plan, phase by phase
- [docs/DESIGN.md](docs/DESIGN.md): how each system works
- [docs/HISTORY_NOTES.md](docs/HISTORY_NOTES.md): historical judgment calls
- [docs/CREDITS.md](docs/CREDITS.md): outside data and art

## Copyright

© 2026 the author of Gez. All rights reserved. This repository is public
so its development can be followed, but no licence is granted to copy,
modify or redistribute it. See [LICENSE](LICENSE); third-party material
is credited in [docs/CREDITS.md](docs/CREDITS.md).
