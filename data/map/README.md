# Map source data

Hand-written data for the 30 May 1453 start. `tools/mapgen` turns these files
plus public-domain Natural Earth coastlines into the game's map files.

## Files

- `countries.txt`: one country per line: `TAG | Name | R G B | government | religion`
- `provinces/*.txt`: provinces grouped into regions and states.
- `lakes.txt`: hand-drawn outlines of major lakes (as they were around 1453).

## Province file format

```
# Region Name                     <- starts a region (a group of states)
@ State Name                      <- starts a state (a group of provinces)
@ State Name | religion           <- same, with the people's religion if it
                                     differs from the ruler's
Province Name | lat lon | OWNER t d
Province Name | lat lon | OWNER t d | religion   <- religion for one province
! Wasteland label | lat lon       <- impassable land (deserts, high mountains, off-map)
```

- `OWNER` is a country tag, or `-` for land nobody controls (nomads, tribes).
- `t` is terrain: `f` farmland, `p` plains, `h` hills, `m` mountains,
  `w` forest, `x` marsh, `d` desert, `s` steppe.
- `d` is development, 1 (empty) to 10 (great city).
- Religion, when not given, is the owner's religion (for unowned land, the
  most common religion among its neighbours). Religions: catholic, orthodox,
  miaphysite, sunni, shia, hindu, buddhist, folk.
- The province shape grows outward from its lat/lon point, so put the point
  on the province's main town.

## Hierarchy

Region (e.g. Anatolia) → State (e.g. Karaman) → Province (e.g. Konya).
States never change owner as a whole; each province has its own owner, so a
state can be split between countries.
