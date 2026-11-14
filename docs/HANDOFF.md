# Gez: handoff

Read this first, then `docs/ROADMAP.md` (the agreed plan), `docs/DESIGN.md`
(how every system works, with all numbers), `docs/HISTORY_NOTES.md` (history
judgment calls) and `CLAUDE.md` (rules). This file says where the project
stands, how to work on it, and what to do next.

Last updated: session 6 (13 November 2026). Phases 0–8 are done (Gemini wrote 7–8, Claude reviewed); next: the owner play-tests the first playable version, then Phase 9.

## The owner

- Does **not** write code. Claude writes everything. Explain in plain
  language; keep replies short (they often read on a phone).
- Ask design and history questions as **multiple-choice questions** (2–4
  options, recommended first, marked "(Recommended)"), one topic at a time.
  The owner usually picks the recommended option but reads them all.
- Wants an **EU5-style grand strategy game** (pops, economy, estates,
  religion, government, diplomacy) with **Total War–style real-time battles
  and sieges**, on a **daily tick with pause and 5 speeds like EU4**, never
  turn-based. Before a battle: **fight it yourself or auto-resolve**.
- Characters should be **fully like CK3**: real people of 1453 with their
  real families; invent people **only** where history records no one.
- Platforms: **Mac and iPad** (owner has an M1 Mac and an M5 iPad).
  Swift / Xcode. **Windows might come later**, so keep `Packages/GezCore`
  pure Swift. (13 Nov: owner asked about moving to Godot; advised staying
  with Xcode for now. Decision point before Phase 9: switch the screens to
  Godot then if Windows/Linux matter, else finish on Apple tools.)
- Start date: **30 May 1453**, the day after Mehmed II took Constantinople.
- Map: Europe, North Africa, Horn of Africa, Middle East, Central Asia to
  the modern China border, Indian subcontinent.
- **Graphics matter a lot.** A good-looking map now, built so it can become
  3D later (Phase 17). The EU-style interface and art pass is the **last
  phase (Phase 20)**; don't style panels before then unless asked.
- Wants historical uncertainties raised so they can decide; record them in
  `docs/HISTORY_NOTES.md`.
- No music or instruments ever (sound effects only, Phase 16). Saves are
  local only (no iCloud).
- **Build names**: the alpha (after Phase 20) is called **"Kayser"**; each
  beta gets its own name, theme still open. See ROADMAP "Build names".
- May use **Gemini** for art later. That needs a Gemini API key stored by
  the owner as a GitHub Actions secret (`GEMINI_API_KEY`). **Never ask for
  or paste the key in chat.** Not started.

## Where things stand

Everything below is built, tested on CI and visible in the app.

| Area | State |
|---|---|
| Simulation core | Pure-Swift package `Packages/GezCore`: 365-day calendar, EU4-style speeds, deterministic `GameRandom`, daily tick with monthly and yearly systems (order in `Simulation.swift`) |
| Map (Phase 1) | 1,373 provinces, 238 states, 36 regions, 266 countries (incl. tribes and subjects), 79 sea zones with straits; borders follow 72 rivers and 20 ridges; Metal renderer with real-elevation terrain, borders, water, icons for towns, capitals, forts and ports |
| People (pops) | 187 cultures, 25 religions with sects, Sufi orders, pops by class (nobles, clergy, burghers, peasants, slaves); 202 million people |
| Heraldry | Real 1453 arms and banners from Wikimedia Commons (200 real, 9 invented at the owner's request, 57 plain banners); see "Heraldry workflow" below |
| Economy (Phase 2) | 62 goods, 42 markets, supply-and-demand prices, class needs and contentment, 34 building types (levels 1–5, slots), taxes by class with sliders, 15 named banks, loans, debasement, inflation, bankruptcy |
| Trade (Phase 3) | Player-drawn and historical routes, merchants and tolls, route and link capacity, embargoes, closed markets, AI routes |
| Characters (Phase 4) | 2,244 people: 560 real living people of 1453 and 79 dead ancestors with their real families (parents, siblings, children, bastards); invented only where history is silent. CK-style traits and skills, councils, succession laws, births, deaths, marriages |
| Great vassals | Real lords hold 75 provinces (Hunyadi, Rožmberk, Olelko of Kiev, Ottoman march lords, Georgian princes...). They keep 40% of the tax, inherit by family law, can be granted or stripped of land, refuse taxes when unhappy and may plot to poison the ruler. Court chronicle logs it all |
| Government (Phase 5) | Stability −3…+3; 11 law areas with trade-offs (6 months to change); estates tied to pops (core four plus Janissaries, Mamluks, Rajputs, Tribes, Dhimmi) with power, loyalty and 23 privileges; a 4-tier reform tree per government type that can change the government |
| Armies & logistics (Phase 6) | 15 unit types (5 core + 10 regional 1453 units), 39 starting standing armies (235 regiments, 225,000 men), three origins (levies from pops, standing professionals from manpower + market goods, mercenaries for gold), daily province-to-province movement (distance, terrain, rivers, roads, unit speed, commander Martial), supply limit & monthly attrition/reinforcement, great vassal open revolts, military AI |
| App windows | Top bar: treasury (Budget), Trade, Court, Stability (Government), Armies (manpower, field armies, commanders, levies, recruitment). Province panel tabs: Overview (holder, supply, levy, buildings), Economy, People. Market panel. Map modes Q–I; 2D army counters and marching arrows |
| Tests | 109 simulation tests (GezCore) and 11 snapshot tests (App); all green |

Not started (later phases): diplomacy, war and peace, sieges, save/load,
battles, navies, religion and culture change, plague, rebels, technology,
events, sound, menus, settings, multiplayer.

## What to do next

1. **Play-test the first playable version** with the owner (Phase 8 says so
   before going on): pick a country, run a few decades, fight a war, save
   and load. Fix balance from what they report.
2. **Decision point before Phase 9:** stay on Apple tools, or move the
   screens to Godot (keeps the Swift simulation) if Windows/Linux matter.
3. **Phase 9: battle view.** Owner's choices are already in the roadmap.
   Model advice given to the owner (no Carbon available, weekly limit):
   Argon for the core battle engine, Gemini 4 Hydrogen for the rest.

Phase 7 history additions by Claude's review: the Albanian–Ottoman war and
the Delhi–Jaunpur war were active on 30 May 1453 and are now in
`data/diplomacy/wars_1453.txt`. Still doubtful: Scotland as an active
co-belligerent in the Hundred Years' War in 1453, and the Ottoman–Genoese
truce (Galata surrendered on 1 June 1453, two days after the start).

## Working with Gemini (from session 6)

The owner now has **Gemini write the code** and **Claude test and review
it**. Gemini's rules are in `GEMINI.md` (and the same text in `AGENTS.md`
for Jules): it works on `gemini/<topic>` branches and opens pull requests
into `main`; it never pushes to `main`.

When the owner asks Claude to test Gemini's work:
1. `gh pr list` and `gh pr view <n>` / `gh pr diff <n>`; check out the
   branch (`git fetch origin <branch> && git checkout <branch>`).
2. Wait for CI on the pull request (all four jobs) and read failing logs.
3. Check the rules: GezCore pure Swift, `GameRandom` only, struct-of-arrays,
   tests for every new system, regenerated data committed and
   reproducible (rerun the generator, expect no diff), resources listed
   in `Package.swift`, no `Gez.xcodeproj`, docs and HISTORY_NOTES updated.
4. Read the logic for bugs, and run quick balance checks in Python where
   numbers changed. Look at the `ci-snapshots` images for UI changes.
   Snapshots come from `main` pushes; for a pull request, judge the UI
   from the code or run the snapshot job on the branch with
   `gh workflow run ci.yml --ref <branch>`.
5. Report to the owner in plain language: works or not, what is wrong,
   and what to tell Gemini. Leave review comments on the pull request
   (`gh pr review <n> --comment -b "..."` or `--request-changes`).
6. Merge only when CI is green and the owner agrees
   (`gh pr merge <n> --squash`), then mirror HANDOFF and ROADMAP to the
   Project if they changed.

## Website (session 6)

Public coming-soon site at https://yv28f5k922-dot.github.io, from the
separate public repo `yv28f5k922-dot/yv28f5k922-dot.github.io` (plain HTML,
no build; GitHub Pages deploys every push to `main`). Owner's choices:
free github.io address; Mac download free, iPad "later" (needs Apple's
$99/year account); no download until the first playable version (Phase 8);
the site never links to this repo, because the owner plans to make the game
repo **private near release** (watch CI minutes then: private repos get
about 2,000 free minutes a month and macOS counts 10x). Screenshots come
from `ci-snapshots`, with the yellow button placeholders painted over.
When a download exists: build an unsigned Mac app on CI, attach it to a
GitHub Release on the website repo, and add "how to open an app from an
unidentified developer" steps to the page.

## How to work on it

### Limits of the cloud workspace
- **Cannot compile Swift** and has **no general internet**. It can reach
  PyPI, npm and GitHub (git, and the API through `gh` for this repository
  only; `gh api graphql` is blocked, use REST).
- **Verify everything through GitHub Actions** (`.github/workflows/ci.yml`),
  which runs on every push to `main`:
  - *Simulation tests (Linux)*: `swift:6.0` container. Fastest signal.
  - *Long simulation tests (Linux)*: the four decade-long simulations
    (`skipUnlessLongTests()`, env `GEZ_LONG_TESTS=1`); daily, on pushes to
    `main` and by hand, never on pull requests. Branch pushes no longer run
    CI by themselves (only pull requests and `main`).
  - *Simulation tests*: macOS arm64.
  - *Build Mac and iPad apps*: `macos-15-intel`.
  - *Render map snapshots*: macOS arm64 (needs Metal); force-pushes PNGs
    to the `ci-snapshots` branch.
  - arm64 Mac runners are sometimes unavailable for hours, and a newer push
    cancels older runs, so "cancelled" jobs are normal.
- Watching CI from the workspace:
  ```sh
  gh api "repos/yv28f5k922-dot/Gez/actions/runs?head_sha=$(git rev-parse HEAD)" \
    --jq '.workflow_runs[] | "\(.id) \(.name) \(.status) \(.conclusion)"'
  gh api repos/yv28f5k922-dot/Gez/actions/runs/<run id>/jobs --jq '.jobs[] | "\(.id) \(.name) \(.conclusion)"'
  gh api repos/yv28f5k922-dot/Gez/actions/jobs/<job id>/logs | tail -100
  ```
- Push with `git -c push.negotiate=true push -q origin main` (plain push
  sometimes stalls). GitHub prints a "repository moved" note; harmless.
- **To see the app:** `git clone --depth 1 -b ci-snapshots
  https://github.com/yv28f5k922-dot/Gez /tmp/snap`, then open the PNGs
  (`screen_main.png`, `metal_*.png`, `budget.png`, `trade.png`,
  `court.png`, `government.png`, `market_venice.png`, `panel_*.png`...).
  Artifact downloads are blocked by the proxy; use the branch. Buttons and
  menus show as yellow placeholder boxes in snapshots (an `ImageRenderer`
  limit); they are fine in the real app.
- **Anything needing internet** runs as a GitHub Actions job that commits
  its output (`terrain.yml` fetches elevation, `heraldry.yml` fetches arms).

### When the owner's Mac is linked
Install Xcode and Homebrew, then `brew install xcodegen`, `xcodegen
generate`, open `Gez.xcodeproj`. Schemes: `GezMac`, `GeziPad` (signing team is
set in `project.yml`), `GezMacTests`. Never commit `Gez.xcodeproj`.

### Data pipelines (hand-written text → generated JSON)
Edit the text files, run the generator, commit both. Every generator
validates its input and exits with a clear message on mistakes, and all
of them are reproducible (same input, byte-identical output).

| Data | Generator | Output (in `Packages/GezCore/Sources/GezCore/Resources/` unless noted) |
|---|---|---|
| `data/map/` | `python3 tools/mapgen/mapgen.py --land /tmp/geo/land10m.geojson` (coastlines once: `tools/mapgen/fetch_coastlines.sh /tmp/geo`; `pip install numpy scipy pillow --break-system-packages`) | `scenario1453.json`, `provinces1453.idmap`, `seas1453.idmap`, `docs/map_preview.png` |
| terrain | `python3 tools/terrain/bake_terrain.py` (after mapgen; elevation comes from the "Fetch elevation" CI job) | `App/Resources/Terrain/terrain.jpg` |
| `data/economy/` | `python3 tools/economy/econgen.py` (balance with `tools/economy/prototype.py`, a Python copy of the monthly market; keep constants in step) | `economy1453.json` |
| `data/characters/` | `python3 tools/characters/chargen.py` | `characters1453.json` |
| `data/government/` | `python3 tools/government/govgen.py` | `government1453.json` |
| `data/military/` | `python3 tools/military/milgen.py` | `military1453.json` |
| `data/diplomacy/` | `python3 tools/diplomacy/dipgen.py` | `diplomacy1453.json` |
| `data/heraldry/choices.txt` | push it; the Heraldry workflow downloads and converts | `App/Resources/Heraldry/arms_<TAG>.png`, `data/heraldry/credits.json` |
| app icon (portolan chart, drawn from the province map) | `python3 tools/icon/make_icon.py` | `App/Resources/Assets.xcassets/AppIcon.appiconset/`, `docs/icon_preview.png` |

Run order after a map change: mapgen → bake_terrain → econgen → chargen →
govgen (later ones read `scenario1453.json`). A new JSON resource must also
be listed in `Packages/GezCore/Package.swift`.

People file format (`data/characters/people_*.txt`): `role | id | Name |
Dynasty | m/f | born | relations | traits | note [| culture religion]`.
Roles: ruler, heir, spouse, child, sibling, parent, kin, figure, vassal,
dead, link. Relations: `f:` `m:` `s:` ids, `d:YYYY[-MM-DD]` death,
`illegit`, `holds:Prov1,Prov2` (underscores for spaces). `link | id |
...` adds relations to someone defined elsewhere. Notes with "?" are
uncertain and get listed in HISTORY_NOTES.

### Rules (also in CLAUDE.md)
- `GezCore` stays pure Swift (Foundation is fine; no SwiftUI, Metal, UIKit,
  AppKit or Combine).
- All randomness through `GameRandom`, so a game replays the same way.
- Bulk data as struct-of-arrays (`ProvinceTable`, `CountryTable`,
  `CharacterTable`, `Government`...).
- Every new system gets unit tests in `Packages/GezCore/Tests`.
- Never use Paradox or Creative Assembly data or art.
- Credit outside data in `docs/CREDITS.md`.
- Keep `docs/DESIGN.md` current when design changes; tick phases in
  `docs/ROADMAP.md`; update this file at the end of a session; mirror this
  file and ROADMAP to the claude.ai Project (`claude/HANDOFF.md`,
  `claude/ROADMAP.md`).
- Commit messages end with the attribution lines from the session's
  system reminder.

## Key files

```
Packages/GezCore/Sources/GezCore/
  Simulation.swift   tick order (monthly: trade paths, market, buildings,
                     finance, AI, population, characters, vassals, government)
  Calendar/          GameDate, GameClock (speeds)
  Core/              GameRandom, IDs, MapInfo, RGB, Terrain, GovernmentType
  World/             World, ProvinceTable, StateTable, CountryTable, ProvinceIDMap
  Faith/, Population/  religions, cultures, pops, class split
  Economy/           Goods, Markets, Buildings, Finance, Trade, queries
  Characters/        CharacterTable, traits, names, chronicle
  Government/        Modifier, Effects, laws, estates, privileges, reforms
  Military/          UnitType, Regiment, ArmyTable, Military, Battle
  Diplomacy/         Treaty, War, CasusBelli, WarDeclaration, PeaceTreaty, coalitions, war reparations, opinions, trust, relation slots
  Systems/           MarketSystem (+ EconomySystem/PopulationSystem),
                     BuildingSystem, CharacterSystem, VassalSystem,
                     GovernmentSystem, ArmySystem, BattleSystem, DiplomacySystem, DiplomacyAISystem
  Scenario/          Scenario1453 + Economy/Character/Government/Military/Diplomacy loaders
  Resources/         generated JSON and ID maps
App/Shared/
  GameModel.swift    bridge between simulation and UI; game loop; player actions
  ContentView.swift  top bar, speeds, map-mode bar, province panel, overlays
  EconomyViews.swift, BudgetView.swift, TradeView.swift, CourtView.swift,
  GovernmentView.swift, ArmyView.swift, DiplomacyView.swift, CountryArmsView.swift
  Map/               MapCanvasView (camera, gestures, labels, icons, routes, armies),
                     Metal/ (MapShaders.metal, renderer), MapRenderer (CPU fallback)
App/Tests/SnapshotTests.swift   renders PNGs on CI
data/              hand-written source data (see table above)
tools/             generators and helpers (see table above)
docs/              HANDOFF (this), ROADMAP, DESIGN, HISTORY_NOTES, CREDITS, previews
```

## Known issues and tech debt

- Map labels are drawn by SwiftUI over the Metal view and don't curve yet.
- Wasteland beyond the game area uses rough biomes; Tibet looks very snowy.
- `MapRenderer` (CPU) duplicates some palette and border logic with the
  shader; keep them in step or retire it once Metal is proven everywhere.
- Population figures are regional estimates spread by development.
- The AI does not change laws yet (it does take reforms, raise stability
  and grant privileges).
- Vassal plots can kill the player's ruler; there is no event pop-up yet,
  only the Court chronicle.
- GitHub warns that `actions/setup-python@v5` and `upload-artifact@v4` run
  on Node 20; bump to the next major versions when convenient (the
  workspace could not check which exist).
- 208 uncertain facts about people and the 1453 government choices are
  waiting for the owner in `docs/HISTORY_NOTES.md`.

## Heraldry workflow

The owner rejected generated arms. Rules from the owner:
- Real arms and flags as used in 1453, from Wikimedia Commons, credited.
- If none from 1453 is known, use one from a few decades earlier or later.
- Indian kingdoms: their 1800s princely-state flags where they exist.
- Sultanates: Catalan Atlas (1375) flags and modern online guesses are OK.
- Turkic tribes use tamgas. Other tribes: ask the owner one by one.
- Otherwise a plain banner in the map colour.

How to change one: edit `data/heraldry/choices.txt` (`TAG | File:Name.svg |
note`) and push; the "Heraldry" workflow downloads, converts to PNG and
commits. To look for candidates: put rows in `data/heraldry/check.txt`
(`TAG | Name | wiki articles | commons searches | File: titles`) and run the
workflow by hand with mode `check` (`gh api -X POST
repos/yv28f5k922-dot/Gez/actions/workflows/heraldry.yml/dispatches -f
ref=main -f 'inputs[mode]=check'`). Contact sheets go to the
`heraldry-candidates` branch. CC BY-SA credits must be shown in-game
(credits screen still to do).

Owner decisions on tribes: Shammar = Ha'il flag; Asir = Idrisid flag;
Cyrenaica = Senussi flag; Yam = the owner-supplied Yam banner; Ja'alin,
Baloch, Hazara, Beja, Hakkari, Khokhars, Dards, Khasi, Bhuyan = invented
simple banners (`data/heraldry/designed/*.svg`); Pashtun = 1839 banner;
Kabarda = Kabardian noble banner; Oirats = Dzungar banner; Jats =
Bharatpur; Sami = 1986 Sami flag; Alania/Vainakh = later-era flags; Kirat
= modern Kirat flag; Albania = Kastrioti arms; Komi, Mordvins, Berbers,
Guanches, Somali, Najd = plain banner.
