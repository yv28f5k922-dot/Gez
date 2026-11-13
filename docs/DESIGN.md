# Gez — Design Document

A real-time-with-pause grand strategy game for Mac and iPad, in the spirit of
Europa Universalis V, with Total War–style battles and sieges. Time runs on a
daily tick like EU4, never turn-based.

## Vision

- Grand strategy on a historical map, starting **30 May 1453**, the day after
  Mehmed II's conquest of Constantinople.
- EU5-like depth: pops, economy, estates, religion, government, diplomacy.
- When armies meet, the player can **fight the battle in real time in a 2D
  top-down view** or **auto-resolve**. Sieges work the same way.
- Runs smoothly on an M1 Mac (minimum spec) and an M5 iPad.

## Map scope

Europe, North Africa, the Horn of Africa, the Middle East, Central Asia up to
the modern China border, and the Indian subcontinent. Target: roughly
1,500–2,500 land provinces plus sea zones.

Map data is built from public-domain geography (e.g. Natural Earth). No data
or art from Paradox or Creative Assembly games may be used.

## Map structure

Region (e.g. *Anatolia*) → State (e.g. *Karaman*) → Province (e.g. *Konya*).
Provinces are the unit of ownership, sieges and movement. Province shapes
grow from their towns and stop at 73 major rivers, 20 mountain ridges and a
few hand-drawn frontier lines, so borders follow real geography. Borders
that run along a river are marked (crossing them will be slower and favour
the defender). A state can be
split between several owners. The map data lives in `data/map/` and is
turned into game files by `tools/mapgen/mapgen.py`.

## Time

- Calendar: 365-day years, no leap years (as in Paradox games).
- Speeds: paused + 5 speeds (0.5, 1, 2.5, 6, 20 days per real second).
- Controls: Space = pause, 1–5 = set speed, +/- = faster/slower.
- Tick order (fixed, deterministic):
  1. advance date
  2. daily systems: movement, supply, sieges, battles, combat
  3. monthly systems (1st of month): economy, population, estates, diplomacy AI
  4. yearly systems (1 January): long-term changes

## Systems (first version)

### Economy & pops
- Provinces have population, base tax, production, terrain, religion.
- Later: pop classes (peasants, burghers, nobles, clergy), goods, trade nodes
  and routes, buildings, food, disease, war devastation.

### Diplomacy & war
- Relations, alliances, royal marriages, vassals, guarantees.
- Claims and casus belli, war goals, war score, peace deals.
- Armies move province to province along a graph; movement takes days.

### Sieges & forts
- Fort levels; forts exert zone of control and block movement.
- Daily siege progress affected by artillery, fort level, terrain, supply,
  disease and a random siege roll.
- Player can **assault** (casualties, fast) or **starve** (slow).
- Assaults can be fought in the battle view.

### Battles
- Triggered when hostile armies end up in the same province.
- Player chooses: **fight** (2D real-time tactical battle) or **auto-resolve**.
- 2D battle view: unit blocks with facing, formation, morale and fatigue;
  infantry, cavalry, artillery, archers/handgunners; flanking and terrain.
- Auto-resolve uses the same unit stats, so results are consistent.
- Designed so a 3D battle view could be added later without changing rules.

### Estates, religion, government
- Estates (nobles, clergy, burghers, plus regional ones) with loyalty and
  influence.
- Religions: Catholic, Orthodox, Miaphysite, Sunni, Shia, Hindu (more later).
- Government types: monarchy, republic, theocracy, steppe horde; reforms and
  laws later.

## Architecture

| Layer | Tech | Notes |
|---|---|---|
| Simulation (`Packages/GezCore`) | Pure Swift | No Apple-only frameworks. Fully unit-tested. Portable. |
| App shell | SwiftUI | Menus, panels, top bar, input. One codebase for Mac and iPad. |
| Map renderer | Metal | Province-ID texture + one shader for all map modes. |
| Battle view | Metal or SpriteKit | Instanced 2D sprites for thousands of soldiers. |

Principles:
- **Data-oriented**: provinces and countries are stored as struct-of-arrays.
- **Deterministic**: all randomness comes from a seeded `GameRandom`, so the
  same save + inputs always gives the same result.
- **Simulation is separate from rendering**: the renderer only reads state.

## Art direction

"Parchment map and tabletop pieces": a painted-parchment map, clean UI,
procedurally generated flags, and stylized unit blocks in battles. All of this
is built in code. Portraits, event pictures and detailed sprites can be added
later from asset packs, an artist, or an AI image pipeline.

## Milestones

1. **Foundation** (done in first commit): calendar, clock, daily tick,
   placeholder world, monthly income and growth, SwiftUI app shell with a
   placeholder map, CI.
2. **Real map** (done): 1,189 provinces in 228 states and 36 regions,
   neighbours and sea crossings, map modes (political, states, terrain,
   religion, development), zoom and pan, tap to select. Drawn on the CPU for
   now; a Metal renderer can replace it when borders start moving often.
   Historical judgment calls are listed in `docs/HISTORY_NOTES.md`.
3. **Economy & pops**: pop classes, goods, trade, buildings.
4. **Armies, diplomacy & war**: movement, alliances, war score, peace.
5. **Sieges & forts**.
6. **2D battles** with fight / auto-resolve.
7. **Estates, religion & government**.
8. **AI**, save/load, polish.
