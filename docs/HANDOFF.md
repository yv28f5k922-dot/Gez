# Gez: handoff for the next session

Read this first, then `docs/ROADMAP.md` (the agreed plan),
`docs/DESIGN.md`, `docs/HISTORY_NOTES.md` and `CLAUDE.md`. This file says where the project stands, how to work on it,
and what to do next.

## The owner

- Does **not** write code. Claude writes everything. Explain in plain
  language; keep replies short (they often read on a phone).
- Wants an **EU5-style grand strategy game** (pops, economy, estates,
  religion, government, diplomacy) with **Total War–style real-time battles
  and sieges**, on a **daily tick with pause and 5 speeds like EU4**, never
  turn-based. Before a battle: **fight it yourself or auto-resolve**.
- Platforms: **Mac and iPad** (owner has an M1 Mac and an M5 iPad).
  Language chosen: **Swift / Xcode** (Rust was discussed; Swift won).
  **Windows might come later**, so keep `Packages/GezCore` pure Swift.
- Start date: **30 May 1453**, the day after Mehmed II took Constantinople.
- Map: Europe, North Africa, Horn of Africa, Middle East, Central Asia to
  the modern China border, Indian subcontinent.
- **The full feature plan and build order is in `docs/ROADMAP.md`.**
- **Graphics matter a lot.** The owner called the flat-colour map "very
  ugly". Agreed direction: a good-looking map now, built so it can become
  a real 3D map (tilting camera, 3D cities and armies) later. Battles were
  first planned 2D; 3D is now on the table because looks matter.
- Wants to be told about historical uncertainties so they can decide
  (see `docs/HISTORY_NOTES.md`).
- Interested in using **Gemini** (they have Gemini Pro) for art later.
  Automating it needs a Gemini API key stored as a GitHub Actions secret
  (`GEMINI_API_KEY`); never ask for the key in chat. Not started.

## Where things stand (end of session 1)

Done and tested on CI (Mac and iPad builds green, 38 simulation tests):

| Area | State |
|---|---|
| Simulation core | Pure-Swift package `Packages/GezCore`: 365-day calendar, EU4-style speed clock, deterministic RNG, daily tick with monthly economy and population growth |
| Map data | 1,189 provinces, 228 states, 36 regions, 207 countries at 30 May 1453; hand-written in `data/map/` |
| Map shapes | Grown from town points over Natural Earth coasts; stop at 72 rivers, 20 mountain ridges and 3 frontier lines (`data/map/barriers.txt`); 1453 coast edits; neighbours, straits, river borders |
| Countries | 247 countries incl. 27 tribal confederations (government `tribal`); subjects (vassal, tributary, personal union) in `data/map/subjects.txt`; no unclaimed land left |
| People | 187 cultures in families, 25 religions in 6 families, Sunni schools and Hindu traditions as sects, Sufi orders per province, pops split into nobles, clergy, burghers, peasants and slaves; 202 million people from regional 1453 estimates |
| App | SwiftUI shell for Mac and iPad: top bar (date, treasury, speeds), map modes (political, states, terrain, religion, culture, development; keys Q–Y), zoom and pan, tap to select, province panel with people breakdown (province or whole state) |
| Map look | **Metal renderer** (`App/Shared/Map/Metal/`): baked terrain texture from real elevation, map-mode tint over terrain, soft country border bands, state and province lines, animated water with coast foam, selection glow, paper grain, vignette. The CPU renderer (`MapRenderer.swift`) is kept as a fallback and for tests |

Not started: economy beyond flat taxes, armies, diplomacy, war, sieges,
battles, estates, government, AI, save/load, sound, menus, settings.

## How to work on it

### Limits of the cloud workspace
- **Cannot compile Swift** and has **no general internet**. It can reach
  PyPI, npm and GitHub (git and the API through `gh`).
- **Verify everything through GitHub Actions** (`.github/workflows/ci.yml`):
  simulation tests, Mac and iPad builds, and a snapshot job that renders
  the app on a Mac.
- **To see the app:** the snapshot job force-pushes PNGs to the
  `ci-snapshots` branch. Fetch them with
  `git clone --depth 1 -b ci-snapshots https://github.com/yv28f5k922-dot/gez /tmp/snap`.
  Artifact downloads are blocked by the proxy; use the branch.
  - `metal_*.png`: the real Metal map (start view, world, Europe, modes)
  - `screen_main.png`: the whole screen with the Metal map composited in
  - `map_*.png`: CPU fallback renders
- **Anything needing internet** (like elevation data) runs as a GitHub
  Actions job that commits its output (`.github/workflows/terrain.yml`).

### When the owner's Mac is linked
Install Xcode and Homebrew, then `brew install xcodegen`,
`xcodegen generate`, and open `Gez.xcodeproj`. Schemes: `GezMac`, `GeziPad`
(needs a signing team set once in Xcode), `GezMacTests` (via GezMac test).

### Regenerating map data
```sh
tools/mapgen/fetch_coastlines.sh /tmp/geo          # once per workspace
pip install numpy scipy pillow --break-system-packages
python3 tools/mapgen/mapgen.py --land /tmp/geo/land10m.geojson
python3 tools/terrain/bake_terrain.py              # after mapgen
```
`mapgen.py` validates everything (unknown owners, cultures, missing state
population mixes, duplicate names) and prints notes about odd provinces.
Commit the regenerated `scenario1453.json`, `provinces1453.idmap`,
`App/Resources/Terrain/terrain.jpg` and previews.

### Rules (also in CLAUDE.md)
- `GezCore` stays pure Swift (Foundation is fine; no SwiftUI, Metal, UIKit
  or AppKit).
- All randomness through `GameRandom`, so a game replays the same way.
- Bulk data as struct-of-arrays (`ProvinceTable`, `CountryTable`,
  `PopTable`).
- Every new system gets unit tests in `Packages/GezCore/Tests`.
- Never use Paradox or Creative Assembly data or art.
- Record uncertain history in `docs/HISTORY_NOTES.md`; ask the owner.
- Commit messages end with the attribution lines from the session's
  system reminder.

## Key files

```
Packages/GezCore/Sources/GezCore/
  Calendar/        GameDate, GameClock (speeds)
  Core/            GameRandom, IDs, MapInfo, RGB, Terrain, GovernmentType
  Faith/           Religion (+family, colour), Sect, SufiOrder
  Population/      CultureTable, PopTable, SocialClass, ClassSplit, breakdowns
  World/           World, ProvinceTable, StateTable, CountryTable, ProvinceIDMap
  Systems/         EconomySystem, PopulationSystem
  Scenario/        Scenario1453 loader (reads Resources/scenario1453.json)
  Simulation.swift daily tick order
App/Shared/
  GameModel.swift  bridge between simulation and UI; game loop; labels
  ContentView.swift top bar, speed controls, map-mode bar, province + people panels
  Map/MapCanvasView.swift  camera, gestures (pinch, drag, Mac scroll), labels
  Map/Metal/       MapShaders.metal, MetalMapRenderer, MetalMapView
  Map/MapRenderer.swift, MapMode.swift  CPU fallback + palettes
App/Resources/Terrain/terrain.jpg   baked terrain picture
App/Tests/SnapshotTests.swift       renders PNGs on CI
data/map/          countries, provinces/, pops/, cultures, barriers, lakes,
                   coast_1453, population_1453, slavery
data/terrain/elevation.png          16-bit elevation (fetched by CI)
tools/mapgen/      mapgen.py (+ fetch_coastlines.sh)
tools/terrain/     fetch_elevation.py (CI), bake_terrain.py
docs/              DESIGN, HISTORY_NOTES, HANDOFF (this), CREDITS, previews
```

## What to do next

**Follow `docs/ROADMAP.md`.** The owner chose every feature and the build
order in session 2. Next up is **Phase 1: finish the map** (split India,
sea zones, coats of arms, 2D map icons), then Phase 2 (economy).

Notes:
- The interface art pass was **skipped by the owner for now**; don't do it
  unless asked. The Metal map look can still be tuned when the owner
  comments on it.
- No music or instruments ever; sound effects only (Phase 16).
- Saves are local only; no iCloud.
- Characters are CK-style (courts, councils, relationships) and start with
  the real people of 1453.

## Known issues and tech debt

- Labels are drawn by SwiftUI over the Metal view and don't curve yet.
- Wasteland beyond the game area (Tibet, Siberia, Sahara) uses rough
  biomes; Tibet looks very snowy.
- `MapRenderer` (CPU) duplicates some palette and border logic with the
  shader; keep them in step or retire the CPU path once Metal is proven on
  all devices.
- Population figures are regional estimates spread by development; city
  provinces include their countryside.
- The old per-state religion parsing in `mapgen.py` is unused (pops now
  decide religion); safe to remove.
- GitHub Actions warns about Node 20 for `actions/setup-python@v5`;
  harmless for now.
