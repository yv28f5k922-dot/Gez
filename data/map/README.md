# Map source data

Hand-written data for the 30 May 1453 start. `tools/mapgen` turns these files
plus public-domain Natural Earth coastlines into the game's map files.

## Files

- `countries.txt`: one country per line: `TAG | Name | R G B | government | religion`
- `provinces/*.txt`: provinces grouped into regions and states.
- `lakes.txt`: hand-drawn outlines of major lakes (as they were around 1453).
- `barriers.txt`: rivers (`~`), mountain ridges (`^`) and historical frontier
  lines (`=`). Provinces avoid growing across them, so borders follow real
  geography. Rivers are also drawn on the map, and borders that follow a
  river are recorded for battles and movement.
- `subjects.txt`: vassals, tributaries and personal unions at the start.
- `coast_1453.txt`: places where the 1453 coast differs from today's
  (the Zuiderzee and the Dollart were open water).

Towns drawn exactly on a river are moved a few kilometres onto the bank that
faces the rest of their own country, so the river stays a clean border.

## Province file format

```
# Region Name                     <- starts a region (a group of states)
@ State Name                      <- starts a state (a group of provinces)
Province Name | lat lon | OWNER t d
! Wasteland label | lat lon       <- impassable land (deserts, high mountains, off-map)
```

- `OWNER` is a country tag, or `-` for land nobody controls (nomads, tribes).
- `t` is terrain: `f` farmland, `p` plains, `h` hills, `m` mountains,
  `w` forest, `x` marsh, `d` desert, `s` steppe.
- `d` is development, 1 (empty) to 10 (great city).
- Who lives in each province (culture, religion, sect, share) is in
  `pops/`; see its README. `population_1453.txt` holds the estimated
  population of each region, spread over its provinces by development and
  size. `slavery.txt` holds each country's enslaved share.
- The province shape grows outward from its lat/lon point, so put the point
  on the province's main town.

## Hierarchy

Region (e.g. Anatolia) → State (e.g. Karaman) → Province (e.g. Konya).
States never change owner as a whole; each province has its own owner, so a
state can be split between countries.
