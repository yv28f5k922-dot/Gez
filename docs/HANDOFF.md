# Gez: handoff for the next session

Read this first, then `docs/DESIGN.md`, `docs/HISTORY_NOTES.md` and
`CLAUDE.md`. This file says where the project stands, how to work on it,
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

## What to do next (recommended order)

1. **Check the new Metal map look with the owner** (send `metal_start.png`
   and `metal_europe.png` from the snapshots branch) and tune: tint
   strength, border band width, terrain colours, water. Settings live in
   `MapShaders.metal` and `bake_terrain.py`.
2. **Interface art pass** (the other half of "ugly"):
   - Period fonts: Cinzel or IM Fell (SIL Open Font License), bundled.
   - Textured parchment panels with drawn frames; proper icons (e.g.
     game-icons.net, CC BY 3.0, needs credit).
   - Generated coats of arms or flags per country instead of coloured dots.
   - Curved country names that follow the shape of the land.
3. **Owner decisions still open:**
   - Split India into more provinces (recommended; Indian provinces now hold
     millions of people each)?
   - Link Hungary, Bohemia and Austria in a personal union under Ladislaus?
   - The 30 uncertain borders in `HISTORY_NOTES.md`.
4. **Economy milestone:** goods per province, trade, buildings, army
   upkeep, estates' share of income. Uses pops (burghers, peasants).
5. **Armies, diplomacy and war:** units, movement along province
   neighbours (river crossings slower), supply and attrition, alliances,
   claims, war score, peace deals.
6. **Sieges and forts:** fort levels already exist per province.
7. **Battles:** fight or auto-resolve, same unit stats for both. Decide 2D
   sprites vs 3D with the owner; free CC0 3D medieval models exist
   (Quaternius). Instanced rendering handles thousands of soldiers on M1.
8. **Path to the 3D map:** replace the full-screen triangle in
   `MapShaders.metal` with a terrain mesh displaced by
   `data/terrain/elevation.png`, keep the fragment shading, add a camera
   that tilts as you zoom in. Then 3D cities, forts and army models.
9. Estates, government, religion mechanics (conversion, the Safaviyya,
   Hussites), AI, save/load, main menu, sound.

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
