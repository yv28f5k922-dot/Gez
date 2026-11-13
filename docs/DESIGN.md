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

### Economy & pops (Phase 2, owner's choices)
- **62 goods** (EU5-like): food, luxuries, materials, animals, manufactured.
  Data in `data/economy/` → `tools/economy/econgen.py` → `economy1453.json`.
- **42 markets** at the start (Venice, Bruges, Cairo, Calicut...). Every
  province joins the market cheapest to reach (distance × terrain, sea is
  cheaper). New markets can grow from big towns later.
- **Supply and demand prices**: each month a price moves 25% toward
  base × √(demand/supply), kept within 0.2×–5× base.
- **Producers**: each province has a staple food (grain/rice/millet, yield by
  terrain), one trade good, fish on coasts (peasants and slaves work these),
  and 1–3 workshops worked by burghers (recipes with inputs; the first input
  is essential, others only slow work).
- **Needs by class** (`needs.txt`): peasants need staples, salt, meat,
  clothing, tools, drink; burghers and nobles want much more (wine, spices,
  silk, horses, jewellery...). Muslims don't buy wine/beer but buy coffee.
  Pop **satisfaction** (0–1) is the value-weighted share of needs met.
- Until trade routes (Phase 3), surplus flows to neighbouring markets in a
  simple exchange step; off-map goods (Spice Islands, China, Sahara gold,
  Siberian furs) arrive as imports at gateway markets.
- **Taxes**: 2.5% of farm/mine value, 3% of workshop profit go to the owner.
- Start-of-game yields are calibrated so world supply ≈ 1.15 × demand; the
  market runs 12 months before the start so prices settle.
- **Buildings** (`data/economy/buildings.txt`, `Economy/Buildings.swift`,
  `Systems/BuildingSystem.swift`): 33 types in four categories
  (production, trade and towns, religion and learning, military), levels
  1–5. Cost = ducats (+50% per level) plus materials bought from the
  province's market (they raise demand there next month). Build time in
  months (+25% per level). The state pays upkeep per level per year: 2% of
  the level-1 cost for trade and religion buildings, 1% for military (the
  first fort level is free); production buildings are run by their owners.
  Slots: 4 + 2 × development (+2 on the coast, +2 in a market town); each
  level uses one.
  Requirements: coast, matching trade good (mines need metal/stone...).
- **You build, pops work**: workshop buildings give 2,500 burgher jobs per
  level; if a province has fewer burghers (×0.7) than jobs, all its
  workshops run short-handed. Starting workshops come from `crafts.txt`;
  other starting buildings (universities, arsenals, market halls, temples,
  ports, forts) from `buildings_1453.txt` and simple rules.
- Temples show as Church/Mosque/Synagogue/Temple, colleges as
  University/Madrasa, by local faith.
- **AI**: each month a twelfth of computer countries consider their 8 most
  productive provinces and build the best tax return per ducat if it pays
  back within ~15 years and leaves 6 months of income in reserve.
- **Taxes by class** (budget window sliders, 0–2× normal): land taxes on
  peasants (60% of farm/mine value base), nobles (30%) and clergy (10%),
  burghers on workshop profits. Normal rates give 2.5% of land value and 3%
  of workshop profit. Above normal: −12% satisfaction per +1 level for that
  class; below normal: up to +5%.
- **Banks** (`data/economy/banks.txt`): 15 houses of 1453 (Medici, Casa di
  San Giorgio, Venetian banks, Hanseatic merchants, Galata, Karimi,
  Gujarati shroffs, Multani moneylenders...). Each has limited money and
  lends only in its regions (judged by the borrower's capital). Rate =
  base × (1 + debt / yearly income). Loans of 50–500 for 5 years; interest
  goes to the bank; due loans are repaid or rolled over.
- **Out of money**: the cheapest willing bank lends the shortfall; if none
  will, **bankruptcy**: debts cancelled (banks lose them), 5 years of no
  loans, income ×0.75, −15% satisfaction.
- **Debasement**: once (+3 months' income, +5% inflation) or ongoing
  (+20% income, +0.4% inflation a month). Inflation raises building costs
  (later army costs), angers burghers (−0.8 × inflation), nobles (−0.4×)
  and others (−0.2×); falls 0.15% a month when not debasing.
- AI repays loans when it has a reserve; never debases.

### Trade (Phase 3, owner's choices)
- **Routes are drawn by players** (trade window, or tap a good in a market's
  price list): a good, a source market, a destination market and an amount
  (10–100 units a year). The path through linked markets is found
  automatically (sea steps cheaper); it avoids markets closed to you.
- The 1453 world starts with ~50 historical routes owned by the countries
  that ran them (`data/economy/routes_1453.txt`): Venice's spices from
  Cairo and silk from Aleppo, the Karimi Red Sea trade, Hormuz, Calicut,
  Gujarati cloth, the Hansa's furs, wax, grain and salt, English and
  Castilian wool to Bruges...
- **Earning: merchants + tolls.** The route owner buys at the source price,
  pays transport (2% a sea step, 4% a land step) and tolls, and sells at
  the destination. Owners of market towns passed through collect tolls
  (normal 4%, high 10% of the goods' value).
- **Capacity**: each country has merchant capacity (40 + 30 per market town
  owned + market halls, ports, caravanserais, roads); a route uses
  units × base price × steps / 10. Each market link also carries a limited
  value a year (land 1,500, sea 3,000, raised by ports, roads, market halls
  and the new Caravanserai); overloaded links squeeze every route on them.
  War and pirates will cut links later.
- **Control**: embargo a country (its merchants can't trade in or pass
  your market towns) or close your markets to all foreigners.
- The old neighbour exchange stays as small-scale local trade.
- **AI**: a twelfth of computer countries each month open the most
  profitable route into their home market (≤ 5 markets long, ≤ 8 routes);
  routes losing money 6 months running are dropped.
- Markets map mode draws routes (gold = yours), widths by value.

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

### Government, laws and estates (Phase 5, owner's choices)
Data in `data/government/` → `tools/government/govgen.py` →
`government1453.json`; code in `Government/Government.swift` and
`Systems/GovernmentSystem.swift`; Government window in the top bar.
- **Laws (EU5-style law areas)**: 11 areas: succession, crown authority,
  taxation, army, religious policy, trade, justice, peasants and land,
  towns, learning, coinage. Each has 2–4 options with trade-offs
  (`laws.txt`). Changing one costs a month's income and takes 6 months;
  only one change per area at a time. Changing succession costs 1
  stability. Some options need a government type (no primogeniture in a
  republic). Sound money forbids debasing.
- **Estates (core + regional)**: nobles, clergy, burghers and peasants
  everywhere; Janissaries (Ottomans), Mamluk emirs (Mamluks), Rajputs
  (Hindu nobles of Rajput cultures), Tribes (tribal cultures in tribal,
  steppe and listed Muslim realms) and Dhimmi (non-Muslims in Muslim
  realms, which they take from the other estates).
- **Power (from pops)**: raw power = thousands of people × weight (nobles
  30, clergy 25, Rajputs 30, burghers 5, tribes 3, dhimmi 0.6, peasants
  0.25) × (0.5 + contentment); Janissaries 12% and Mamluks 35% of the pop
  total; × (1 + power changes). The crown has its own share (monarchy 45%
  of the estates' total, theocracy 40, horde 35, republic 30, tribal 20,
  × crown-power changes). Shares add to 100%.
- **Loyalty** 0–100 heads 10% a month toward: 50 + laws and privileges +
  (contentment − 50%) × 40 + 3 per stability − 25 × power share − 20 per
  tax level above normal on their class − grudges. Loyal (60+) estates
  give bonuses, disloyal (<30) ones penalties scaled by their power.
  A disloyal (<20) estate with 35%+ power has a 5% monthly chance to
  seize its strongest missing privilege (−1 stability).
- **Privileges** (`privileges.txt`, 23): loyalty and power for the estate,
  plus effects; some pay or cost money once. Revoking: −1 stability and a
  grudge of 2× their loyalty, fading 3% a month.
- **Stability** −3…+3: each point ±3% tax, ±2 contentment, ±0.15 reform
  progress. Raising costs 2 months' income (min 25), +50% per point above
  0. Falls: ruler dies without an adult heir (−1), succession law change
  (−1), revoked privilege (−1), estate seizure (−1), bankruptcy (−2).
- **Reforms (a tree per government)**: 4 tiers costing 0/60/120/200
  progress; progress 0.4 a month + stability + laws. Some reforms change
  the government (tribal → kingdom/emirate, horde → settled khanate,
  theocracy → secular principality, republic → hereditary signore); the
  new type starts again at tier 1 and laws it does not allow fall back.
- **Effects reach**: tax (overall and per class), contentment by class and
  other faiths, merchant profit, vassal tax share and opinion, loan
  interest, building costs, learning, inflation. Manpower, levy size, army
  quality and fort defence are stored for Phase 6.
- **AI**: takes reforms (keeping its government unless tribal), raises
  stability below +1 when cheap, grants a privilege each January to a
  strong estate below 35 loyalty. AI does not change laws yet.
- Religions: see `Packages/GezCore/Sources/GezCore/Faith/Religion.swift`.

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

### Characters (Phase 4, owner's choices)
- **Real people of 1453**: rulers, heirs, spouses, children and key figures
  (`data/characters/people_1453.txt`, ~340 people: Mehmed II, Hunyadi,
  Skanderbeg, Vlad Dracula, Cosimo de' Medici, Zara Yaqob, Bahlul Lodi,
  Rana Kumbha...). Personal unions: one person can rule several countries
  (Ladislaus V: Hungary, Austria, Bohemia; Christian I: Denmark, Norway).
- **Gaps** (owner's rule): a country with no one recorded gets an invented
  ruler and an invented sibling heir; empty council seats get invented
  courtiers ("Isa of Silistra"). Invented people are flagged in the game.
  `tools/characters/chargen.py` builds `characters1453.json`.
- **CK-style traits and skills**: diplomacy, martial, stewardship,
  intrigue, learning (0–20); 28 traits (`traits.txt`) change skills and
  opinion (shared +10, opposite −15, family +20, faith −5/−20).
- **Life**: monthly deaths (adult risk roughly doubles every ten years;
  childhood is dangerous; sickly ×2), births to married women 16–42,
  children named from culture lists (often after a grandparent), inheriting
  a parent's trait half the time.
- **Succession laws** (`succession.txt`): primogeniture (sons, brothers,
  nephews, daughters, nearest of the dynasty), salic (France, Burgundy,
  Anjou, Lorraine: never women), seniority (steppe hordes, tribes),
  elective (republics, theocracies, Hungary, Bohemia, the Mamluks: ablest
  courtier). No heir at all: a relative is found or invented.
- **Council**: chancellor, marshal, steward, spymaster, court chaplain.
  Now: ruler stewardship ±1.5% tax per point from 5, steward ±1%
  (−15%…+25%); ruler learning/8 + chaplain learning/4 learning a year.
  Chancellor, marshal and spymaster matter from Phases 6–7.
- **Marriages**: you propose for unmarried members of your ruling family;
  refused for wrong age (<15 or >25 years apart), different faith family,
  or if a ruler/heir of a realm 2.5× bigger. Muslim men up to four wives.
  The wife joins her husband's court unless she rules. AI marries off its
  families each January (best realm first, else a local noble).
- **Whole real families** (owner: "fully like CK3"): parents (dead ones as
  ancestors), brothers, sisters, children and bastards are recorded where
  history knows them (`people_2_west.txt` … `people_5_south.txt`, ~560
  living real people and ~80 ancestors). Only gaps are invented.
- **Great vassals** (owner chose "real landed nobles"): real lords hold
  provinces for their liege (Hunyadi: Temesvár, Szörény, Szeben; Rožmberk:
  Budějovice; Olelko: Kiev; Ottoman march lords; Georgian princes...),
  about 75 provinces in all.
  - A vassal keeps 40% of his provinces' tax as private gold; the crown
    gets the rest (shown in the budget as "Kept by vassals").
  - Opinion of the liege: personal opinion of the ruler + 10, +15 same
    house, ± lasting favour (fades 1 a month), and −30 at the highest noble
    tax (+30 at none).
  - Below 0: discontent. Below −25: refuses all taxes. Below −50 with
    intrigue 8+: plots; 1% a month to strike. Success 30% ± 5% per point of
    intrigue over the spymaster's, +5% per 100 gold in bribes (5–60%); the
    ruler dies. If caught, the plotter loses all land.
  - Land passes to lawful sons (and their sons), then brothers and nephews,
    then daughters (not under Salic law), then bastard sons, else back to
    the crown. A vassal who becomes ruler merges his land into the crown.
  - The player grants crown provinces to courtiers (+40 favour) and can
    revoke them (−80 for the holder, −20 for every other vassal).
  - Vassal families marry local nobles each January so lines go on.
  - Open revolt with armies comes with Phase 6 (armies).
- **Chronicle**: inheritances, grants, refusals and plots are logged and
  shown in the Court window.
