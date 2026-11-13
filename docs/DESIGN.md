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

### People (pops)
- Every province's people are split into groups by **culture** (187, in
  families), **religion** (25, in six families), optional **sect** (Sunni
  schools of law, Hindu traditions) and **social class** (nobles, clergy,
  burghers, peasants, slaves).
- Provinces, states and countries show their mix as percentages.
- Sufi orders are present per province with a strength (the Safaviyya in
  Ardabil will matter politically).
- Population comes from 1453 estimates per region (202 million in total),
  spread over provinces by development and size.
- Later: conversion, assimilation, migration, plague, unrest by unhappy
  groups, class-based estates.

### Estates, religion, government
- Estates (nobles, clergy, burghers, plus regional ones) with loyalty and
  influence.
- Religions: see `Packages/GezCore/Sources/GezCore/Faith/Religion.swift`.
- Government types: monarchy, republic, theocracy, steppe horde; reforms and
  laws later.

## Architecture

| Layer | Tech | Notes |
|---|---|---|
| Simulation (`Packages/GezCore`) | Pure Swift | No Apple-only frameworks. Fully unit-tested. Portable. |
| App shell | SwiftUI | Menus, panels, top bar, input. One codebase for Mac and iPad. |
| Map renderer | Metal | Province-ID texture + baked terrain texture + one shader for all map modes (CPU fallback kept). |
| Battle view | Metal or SpriteKit | Instanced 2D sprites for thousands of soldiers. |

Principles:
- **Data-oriented**: provinces and countries are stored as struct-of-arrays.
- **Deterministic**: all randomness comes from a seeded `GameRandom`, so the
  same save + inputs always gives the same result.
- **Simulation is separate from rendering**: the renderer only reads state.

## Art direction

The owner found the first flat-colour look ugly, so looks are a priority.

- **Map (now):** Metal renderer over a baked terrain picture made from real
  elevation (hill shading, biomes, rock and snow, sea depth, rivers).
  Country colours are a tint over the terrain, with soft coloured bands at
  country borders, animated water and a light paper grain.
- **Map (later):** the same shading on a 3D terrain mesh with a camera
  that tilts as you zoom in, then 3D cities, forts and armies.
- **Interface (next):** period fonts, parchment panels with frames, icons,
  coats of arms, curved country names.
- **Battles:** fight or auto-resolve. 2D sprites or 3D models (free CC0
  medieval models exist); to be decided with the owner.
- Art can come from code, free asset packs, an artist, or an AI image
  pipeline (Gemini via a GitHub secret); see `docs/HANDOFF.md`.

## Milestones

See `docs/ROADMAP.md` for the agreed feature decisions and build order.
