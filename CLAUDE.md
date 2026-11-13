# Notes for Claude

The owner does not write code; Claude writes everything. Explain changes in
plain language, not jargon.

**Start with `docs/HANDOFF.md`**: current state, the owner's wishes, how to
build and verify from the cloud workspace. **The agreed plan is
`docs/ROADMAP.md`**: work through its phases in order.
- Ask the owner design or history questions as multiple-choice questions
  (2–4 options, recommended first), one topic at a time.
- Read `docs/DESIGN.md` next. Keep it up to date when design decisions change.
- `Packages/GezCore` must stay pure Swift: never import SwiftUI, Metal, UIKit,
  AppKit, or Combine there.
- All simulation randomness goes through `GameRandom` (deterministic).
- Store bulk data as struct-of-arrays (`ProvinceTable`, `CountryTable`).
- Every new system gets unit tests in `Packages/GezCore/Tests`.
- The Xcode project is generated from `project.yml` by XcodeGen; never commit
  `Gez.xcodeproj`.
- The cloud workspace cannot compile Swift. Verify via GitHub Actions
  (`.github/workflows/ci.yml`: Linux and macOS tests, app build, snapshots)
  or on the owner's Mac when linked.
- Minimum spec: M1 Mac with 8 GB RAM. Target: M5 iPad.
- Never use map data or art from Paradox or Creative Assembly games.
- Game data: edit `data/` (map, economy, characters, government), run the
  matching generator in `tools/` and commit the regenerated files (table
  and run order in `docs/HANDOFF.md`). Characters: invent people only
  where history records no one. Record uncertain history in
  `docs/HISTORY_NOTES.md`.
- To see the app without a Mac: CI's snapshot job renders the map and main
  screen and force-pushes the PNGs to the `ci-snapshots` branch
  (`git clone -b ci-snapshots ...`). Artifact downloads are blocked here.
- Terrain look: `tools/terrain/bake_terrain.py` makes `App/Resources/Terrain/terrain.jpg`
  from `data/terrain/elevation.png` (fetched by the "Fetch elevation" CI job,
  because the workspace has no internet). The Metal shader is
  `App/Shared/Map/Metal/MapShaders.metal`.
- Credit external data in `docs/CREDITS.md`.
- At the end of a session: update `docs/HANDOFF.md` and `docs/ROADMAP.md`,
  and mirror both to the claude.ai Project (`claude/HANDOFF.md`,
  `claude/ROADMAP.md`).
- Never ask for or paste API keys in chat; the owner stores secrets in
  GitHub Actions.
