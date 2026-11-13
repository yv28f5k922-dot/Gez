#!/usr/bin/env python3
"""Generate Gez map files from data/map/*.

Inputs
  data/map/countries.txt, data/map/provinces/*.txt, data/map/lakes.txt
  Natural Earth 10m land (public domain) as GeoJSON, made by fetch_coastlines.sh

Outputs
  Packages/GezCore/Sources/GezCore/Resources/provinces1453.idmap
      Province-ID map, run-length encoded (see write_idmap).
      0 = water, 1 = wasteland, n >= 2 = province index n - 2.
  Packages/GezCore/Sources/GezCore/Resources/scenario1453.json
      Countries, regions, states, provinces with owner, terrain, development,
      area, label position and neighbours.
  docs/map_preview.png
      Downscaled political map for quick visual checks.

How provinces get their shape: every province has a seed point (its main
town). Provinces grow outward over land from their towns; each land pixel
joins the town it can reach most cheaply. Stepping onto a river, mountain
ridge or hand-drawn frontier line (data/map/barriers.txt) costs a lot, so
borders snap onto those lines. A little random variation in step cost makes
borders wiggle. Wasteland seeds claim deserts and off-map land.

Usage: python3 tools/mapgen/mapgen.py --land /path/to/land10m.geojson
"""

import argparse
import json
import math
import os
import sys
from collections import defaultdict

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import cKDTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

LON_MIN, LON_MAX = -25.0, 98.0
LAT_MIN, LAT_MAX = -3.0, 71.5
PPD = 32  # pixels per degree
WIDTH = int(round((LON_MAX - LON_MIN) * PPD))
HEIGHT = int(round((LAT_MAX - LAT_MIN) * PPD))

EARTH_RADIUS_KM = 6371.0
ISLAND_REACH_KM = 250.0  # seedless islands join the nearest province within this

WATER, WASTE, UNSET = -1, -2, -3

TERRAIN = {
    "f": "farmland", "p": "plains", "h": "hills", "m": "mountains",
    "w": "forest", "x": "marsh", "d": "desert", "s": "steppe",
}
GOVERNMENTS = {"monarchy", "republic", "theocracy", "steppeHorde"}
RELIGIONS = {
    "catholic", "hussite", "orthodox", "bosnian", "coptic", "ethiopian", "armenian", "syriac", "nestorian",
    "sunni", "twelver", "zaydi", "ismaili", "ibadi", "druze", "alawite", "yazidi",
    "hindu", "jain", "theravada", "tibetan", "zoroastrian", "jewish", "tengri", "folk",
}
SECTS = {
    "hanafi": "sunni", "maliki": "sunni", "shafii": "sunni", "hanbali": "sunni",
    "vaishnava": "hindu", "shaiva": "hindu", "shakta": "hindu", "lingayat": "hindu",
}
ORDERS = {"safaviyya", "naqshbandi", "bektashi", "hurufi", "mevlevi", "qadiri", "chishti", "kubrawi", "shadhili"}

# Sea crossings that armies can use even though the land does not touch.
STRAITS = [
    ("Konstantiniyye", "Izmit"),
    ("Gallipoli", "Biga"),
    ("Gibraltar", "Ceuta"),
    ("Messina", "Reggio"),
    ("Copenhagen", "Lund"),
    ("Odense", "Copenhagen"),
    ("Odense", "Aarhus"),
    ("Kiel", "Odense"),
    ("Solkhat", "Matrega"),
    ("Kaffa", "Matrega"),
    ("Zeila", "Aden"),
    ("Hormuz", "Julfar"),
    ("Hormuz", "Minab"),
    ("Canterbury", "Calais"),
    ("Jaffna", "Madurai"),
    ("Djerba", "Gabes"),
    ("Negroponte", "Thebes"),
    ("Corfu", "Gjirokaster"),
    ("Chios", "Izmir"),
    ("Mytilene", "Balikesir"),
    ("Rhodes", "Milas"),
    ("Bahrain", "Qatif"),
    ("Mallorca", "Menorca"),
    ("Ibiza", "Mallorca"),
    ("Bastia", "Sassari"),
    ("Malta", "Agrigento"),
    ("Visby", "Kalmar"),
    ("Turku", "Stockholm"),
    ("Reval", "Turku"),
    ("Osel", "Pernau"),
    ("Isle of Man", "Lancaster"),
    ("Dublin", "Caernarfon"),
    ("Carrickfergus", "Ayr"),
    ("Orkney", "Wick"),
    ("Lewis", "Skye"),
    ("Skye", "Dingwall"),
    ("Islay", "Inveraray"),
]


# --------------------------------------------------------------------------
# Parsing


def parse_countries(path):
    countries = []
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) not in (5, 6):
            sys.exit(f"countries.txt: bad line: {line}")
        tag, name, rgb, gov, rel = parts[:5]
        color = [int(v) for v in rgb.split()]
        if gov not in GOVERNMENTS:
            sys.exit(f"{tag}: unknown government {gov}")
        if rel not in RELIGIONS:
            sys.exit(f"{tag}: unknown religion {rel}")
        countries.append({
            "tag": tag, "name": name, "color": color, "government": gov,
            "religion": rel, "capitalName": parts[5] if len(parts) == 6 else None,
        })
    return countries


def parse_provinces(folder):
    regions, states, provinces, wastes = [], [], [], []
    for fname in sorted(os.listdir(folder)):
        if not fname.endswith(".txt"):
            continue
        region = state = None
        for n, raw in enumerate(open(os.path.join(folder, fname), encoding="utf-8"), 1):
            line = raw.strip()
            where = f"{fname}:{n}"
            if not line:
                continue
            if line.startswith("#"):
                regions.append(line[1:].strip())
                region = len(regions) - 1
                state = None
            elif line.startswith("@"):
                if region is None:
                    sys.exit(f"{where}: state before region")
                head = [p.strip() for p in line[1:].split("|")]
                religion = head[1] if len(head) > 1 else None
                if religion is not None and religion not in RELIGIONS:
                    sys.exit(f"{where}: unknown religion {religion}")
                states.append({"name": head[0], "region": region, "religion": religion})
                state = len(states) - 1
            elif line.startswith("!"):
                name, coords = [p.strip() for p in line[1:].split("|")]
                lat, lon = [float(v) for v in coords.split()]
                wastes.append({"name": name, "lat": lat, "lon": lon})
            else:
                parts = [p.strip() for p in line.split("|")]
                if len(parts) not in (3, 4) or state is None:
                    sys.exit(f"{where}: bad province line: {line}")
                name, coords, rest = parts[:3]
                religion = parts[3] if len(parts) == 4 else states[state]["religion"]
                if religion is not None and religion not in RELIGIONS:
                    sys.exit(f"{where}: unknown religion {religion}")
                lat, lon = [float(v) for v in coords.split()]
                owner, t, dev = rest.split()
                if t not in TERRAIN:
                    sys.exit(f"{where}: bad terrain {t}")
                provinces.append({
                    "name": name, "lat": lat, "lon": lon, "state": state,
                    "owner": None if owner == "-" else owner,
                    "terrain": TERRAIN[t], "development": int(dev),
                    "religion": religion,
                })
    # Drop regions and states with no provinces (e.g. the wasteland file).
    used_states = sorted({p["state"] for p in provinces})
    state_map = {old: new for new, old in enumerate(used_states)}
    states = [{"name": states[i]["name"], "region": states[i]["region"]} for i in used_states]
    used_regions = sorted({s["region"] for s in states})
    region_map = {old: new for new, old in enumerate(used_regions)}
    regions = [regions[i] for i in used_regions]
    for s in states:
        s["region"] = region_map[s["region"]]
    for p in provinces:
        p["state"] = state_map[p["state"]]
    return regions, states, provinces, wastes


def parse_cultures(path):
    cultures = []
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        cid, name, family = [p.strip() for p in line.split("|")]
        cultures.append({"id": cid, "name": name, "family": family})
    ids = [c["id"] for c in cultures]
    dup = {x for x in ids if ids.count(x) > 1}
    if dup:
        sys.exit(f"cultures.txt: duplicate ids {sorted(dup)}")
    return cultures


def parse_pops(folder, culture_index):
    """Returns (state mixes, province mixes, province orders), keyed by name."""
    state_mix, province_mix, orders = {}, {}, defaultdict(list)
    for fname in sorted(os.listdir(folder)):
        if not fname.endswith(".txt"):
            continue
        current = None
        for n, raw in enumerate(open(os.path.join(folder, fname), encoding="utf-8"), 1):
            line = raw.strip()
            where = f"pops/{fname}:{n}"
            if not line or line.startswith("#"):
                continue
            if line.startswith("@"):
                name = line[1:].strip()
                if name in state_mix:
                    sys.exit(f"{where}: state {name} listed twice")
                state_mix[name] = current = []
            elif line.startswith(">"):
                name = line[1:].strip()
                if name in province_mix:
                    sys.exit(f"{where}: province {name} listed twice")
                province_mix[name] = current = []
            elif line.startswith("&"):
                name, rest = [x.strip() for x in line[1:].split("|")]
                order, strength = rest.split()
                if order not in ORDERS:
                    sys.exit(f"{where}: unknown Sufi order {order}")
                orders[name].append([order, float(strength)])
            else:
                if current is None:
                    sys.exit(f"{where}: pop line before any state or province")
                culture, faith, share = line.split()
                religion, _, sect = faith.partition(".")
                if culture not in culture_index:
                    sys.exit(f"{where}: unknown culture {culture}")
                if religion not in RELIGIONS:
                    sys.exit(f"{where}: unknown religion {religion}")
                if sect and SECTS.get(sect) != religion:
                    sys.exit(f"{where}: {sect} is not a sect of {religion}")
                current.append([culture_index[culture], religion, sect or None, float(share)])
    return state_mix, province_mix, orders


def parse_slavery(path):
    out = {}
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        tag, pct = line.split()
        out[tag] = float(pct) / 100
    return out


def parse_lakes(path):
    lakes, current = [], None
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("="):
            current = {"name": line[1:].strip(), "points": []}
            lakes.append(current)
        else:
            lat, lon = [float(v) for v in line.split()]
            current["points"].append((lat, lon))
    return lakes


# --------------------------------------------------------------------------
# Geometry


def to_px(lat, lon):
    return (lon - LON_MIN) * PPD, (LAT_MAX - lat) * PPD


def land_mask(geojson_path, lakes, coast=()):
    g = json.load(open(geojson_path))
    geom = g["geometry"] if g.get("type") == "Feature" else g["features"][0]["geometry"]
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    img = Image.new("L", (WIDTH, HEIGHT), 0)
    draw = ImageDraw.Draw(img)

    def ring_px(ring):
        return [((x - LON_MIN) * PPD, (LAT_MAX - y) * PPD) for x, y in ring]

    def visible(ring):
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        if max(xs) - min(xs) > 180:  # wraps around the antimeridian
            return False
        return not (max(xs) < LON_MIN - 1 or min(xs) > LON_MAX + 1 or max(ys) < LAT_MIN - 1 or min(ys) > LAT_MAX + 1)

    for poly in polys:
        outer = poly[0]
        if not visible(outer):
            # Big continents can cross the antimeridian (Eurasia). Clip their
            # longitudes instead of skipping them.
            xs = [p[0] for p in outer]
            if max(xs) - min(xs) > 180:
                outer = [(min(max(x, -179.9), 179.9), y) for x, y in outer]
                outer = [(x, y) for x, y in outer if x > -170]  # drop far-east wrap
                if len(outer) < 3:
                    continue
            else:
                continue
        draw.polygon(ring_px(outer), fill=255)
        for hole in poly[1:]:
            draw.polygon(ring_px(hole), fill=0)
    for lake in lakes:
        pts = [to_px(lat, lon) for lat, lon in lake["points"]]
        draw.polygon(pts, fill=0)
    for shape in coast:
        pts = [to_px(lat, lon) for lat, lon in shape["points"]]
        draw.polygon(pts, fill=0 if shape["kind"] == "sea" else 255)
    return np.array(img) > 0


def lonlat_grid():
    xs = (np.arange(WIDTH) + 0.5) / PPD + LON_MIN
    ys = LAT_MAX - (np.arange(HEIGHT) + 0.5) / PPD
    return xs, ys


def unit_vectors(lat, lon):
    lat = np.radians(lat)
    lon = np.radians(lon)
    c = np.cos(lat)
    return np.stack([c * np.cos(lon), c * np.sin(lon), np.sin(lat)], axis=-1)


def chord(km):
    return 2 * math.sin(km / EARTH_RADIUS_KM / 2)


def smooth_noise(rng, cell, amplitude):
    gh, gw = HEIGHT // cell + 3, WIDTH // cell + 3
    grid = rng.standard_normal((gh, gw))
    up = ndimage.zoom(grid, cell, order=3)[:HEIGHT, :WIDTH]
    return up / (np.std(up) + 1e-9) * amplitude


# --------------------------------------------------------------------------
# Main build


RIVER_COST = 14.0      # extra cost for stepping onto a river pixel
RIDGE_COST = 45.0      # mountain ridge
FRONTIER_COST = 90.0   # hand-drawn historical frontier
GROW_LIMIT = 170.0     # land further than this (in ~3.5 km steps) becomes wasteland


def parse_shapes(path):
    """Coast edits: '= sea Name' / '= land Name' followed by lat lon points."""
    shapes, current = [], None
    if not os.path.exists(path):
        return shapes
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("="):
            kind, name = line[1:].strip().split(" ", 1)
            if kind not in ("sea", "land"):
                sys.exit(f"coast_1453.txt: unknown kind {kind}")
            current = {"kind": kind, "name": name, "points": []}
            shapes.append(current)
        else:
            lat, lon = [float(v) for v in line.split()]
            current["points"].append((lat, lon))
    return shapes


def parse_barriers(path):
    kinds = {"~": "river", "^": "ridge", "=": "frontier"}
    lines, current = [], None
    for n, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line[0] in kinds:
            current = {"kind": kinds[line[0]], "name": line[1:].strip(), "points": []}
            lines.append(current)
        else:
            if current is None:
                sys.exit(f"barriers.txt:{n}: point before any line")
            lat, lon = [float(v) for v in line.split()]
            current["points"].append((lat, lon))
    for b in lines:
        if len(b["points"]) < 2:
            sys.exit(f"barriers.txt: {b['name']} needs at least two points")
    return lines


def barrier_masks(barriers):
    masks = {}
    for kind in ("river", "ridge", "frontier"):
        img = Image.new("L", (WIDTH, HEIGHT), 0)
        draw = ImageDraw.Draw(img)
        for b in barriers:
            if b["kind"] == kind:
                draw.line([to_px(lat, lon) for lat, lon in b["points"]], fill=255, width=3 if kind != "river" else 2)
        masks[kind] = np.array(img) > 0
    return masks["river"], masks["ridge"], masks["frontier"]


def move_off_rivers(seed_px, provinces, land, river_mask):
    """Towns drawn on a river are moved onto the bank that faces the rest of
    their own country, so the river stays an unbroken border."""
    seed_px = seed_px.copy()
    blocked = river_mask | ~land
    owners = [p["owner"] for p in provinces]
    by_owner = defaultdict(list)
    for k, o in enumerate(owners):
        if o:
            by_owner[o].append(k)
    moved = 0
    for k in range(len(provinces)):
        x, y = seed_px[k]
        y0, y1, x0, x1 = max(y - 2, 0), min(y + 3, HEIGHT), max(x - 2, 0), min(x + 3, WIDTH)
        if not river_mask[y0:y1, x0:x1].any():
            continue
        # Direction towards the owner's other towns (or away from the river if none).
        friends = [j for j in by_owner.get(owners[k], []) if j != k]
        if friends:
            fx = np.mean([seed_px[j][0] for j in friends]) - x
            fy = np.mean([seed_px[j][1] for j in friends]) - y
        else:
            fx, fy = 0.0, 1.0
        norm = math.hypot(fx, fy) or 1.0
        fx, fy = fx / norm, fy / norm
        best, best_score = None, -1e9
        for dy in range(-6, 7):
            for dx in range(-6, 7):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < WIDTH and 0 <= ny < HEIGHT) or blocked[ny, nx]:
                    continue
                # Stay clear of the river by a pixel so the town is firmly on one bank.
                if river_mask[max(ny - 1, 0):ny + 2, max(nx - 1, 0):nx + 2].any():
                    continue
                score = dx * fx + dy * fy - 0.35 * math.hypot(dx, dy)
                if score > best_score:
                    best, best_score = (nx, ny), score
        if best is not None:
            seed_px[k] = best
            moved += 1
    print(f"{moved} riverside towns placed on their own bank")
    return seed_px


def grow_provinces(land, seed_px, seed_owner, river_mask, ridge_mask, frontier_mask):
    """Each land pixel joins the seed it can reach most cheaply over land.

    Steps cost their true ground distance, randomly varied a little so borders
    wiggle, plus a large extra cost for stepping onto a river, ridge or
    frontier line. So provinces stop at those lines unless there is no other
    way to reach the land.
    """
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import dijkstra

    node = np.full(land.shape, -1, dtype=np.int64)
    ys, xs = np.nonzero(land)
    n = len(ys)
    node[ys, xs] = np.arange(n)

    rng = np.random.default_rng(1453)
    wobble = np.clip(1.0 + smooth_noise(rng, 24, 0.45) + smooth_noise(rng, 7, 0.15), 0.3, 2.6)
    cost = wobble.copy()
    cost[river_mask] += RIVER_COST
    cost[ridge_mask] += RIDGE_COST
    cost[frontier_mask] += FRONTIER_COST
    row_scale = np.cos(np.radians(LAT_MAX - (np.arange(HEIGHT) + 0.5) / PPD))

    rows, cols, weights = [], [], []
    # Horizontal neighbours.
    a = node[:, :-1]
    b = node[:, 1:]
    ok = (a >= 0) & (b >= 0)
    w = 0.5 * (cost[:, :-1] + cost[:, 1:]) * row_scale[:, None]
    rows.append(a[ok]); cols.append(b[ok]); weights.append(w[ok])
    # Vertical neighbours.
    a = node[:-1, :]
    b = node[1:, :]
    ok = (a >= 0) & (b >= 0)
    w = 0.5 * (cost[:-1, :] + cost[1:, :])
    rows.append(a[ok]); cols.append(b[ok]); weights.append(w[ok])
    graph = coo_matrix(
        (np.concatenate(weights), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n)
    ).tocsr()

    seed_nodes = node[seed_px[:, 1], seed_px[:, 0]]
    unique_nodes, first = np.unique(seed_nodes, return_index=True)
    if len(unique_nodes) < len(seed_nodes):
        print(f"  note: {len(seed_nodes) - len(unique_nodes)} seeds share a pixel with another seed")
    node_to_seed = {int(v): int(k) for v, k in zip(unique_nodes, first)}

    _, _, sources = dijkstra(graph, directed=False, indices=unique_nodes, min_only=True,
                             return_predecessors=True, limit=GROW_LIMIT)
    labels = np.full(land.shape, WATER, dtype=np.int32)
    reached = sources >= 0
    seed_index = np.full(n, -1, dtype=np.int64)
    src = sources[reached]
    lookup = np.vectorize(lambda v: node_to_seed[int(v)], otypes=[np.int64])
    uniq_src, inverse = np.unique(src, return_inverse=True)
    seed_index[reached] = lookup(uniq_src)[inverse]
    result = np.where(seed_index >= 0, seed_owner[np.maximum(seed_index, 0)], WASTE)

    # Islands with no seed of their own join the nearest province if close.
    unreached = ~reached
    if unreached.any():
        comp, _ = ndimage.label(land, structure=np.ones((3, 3)))
        seeded = set(comp[seed_px[:, 1], seed_px[:, 0]].tolist())
        pix_comp = comp[ys, xs]
        island = unreached & ~np.isin(pix_comp, list(seeded))
        if island.any():
            seed_vec = unit_vectors(LAT_MAX - (seed_px[:, 1] + 0.5) / PPD, LON_MIN + (seed_px[:, 0] + 0.5) / PPD)
            tree = cKDTree(seed_vec)
            pvec = unit_vectors(LAT_MAX - (ys[island] + 0.5) / PPD, LON_MIN + (xs[island] + 0.5) / PPD)
            d, j = tree.query(pvec)
            result[island] = np.where(d > chord(ISLAND_REACH_KM), WASTE, seed_owner[j])
    labels[ys, xs] = result
    return labels


def build(args):
    countries = parse_countries(os.path.join(ROOT, "data/map/countries.txt"))
    regions, states, provinces, wastes = parse_provinces(os.path.join(ROOT, "data/map/provinces"))
    lakes = parse_lakes(os.path.join(ROOT, "data/map/lakes.txt"))
    tags = {c["tag"]: i for i, c in enumerate(countries)}

    problems = []
    names = defaultdict(list)
    for i, p in enumerate(provinces):
        names[p["name"]].append(i)
        if p["owner"] is not None and p["owner"] not in tags:
            problems.append(f"province {p['name']}: unknown owner {p['owner']}")
        if not (LON_MIN < p["lon"] < LON_MAX and LAT_MIN < p["lat"] < LAT_MAX):
            problems.append(f"province {p['name']}: outside map")
    for name, idx in names.items():
        if len(idx) > 1:
            problems.append(f"duplicate province name {name}")
    owned = defaultdict(int)
    for p in provinces:
        if p["owner"]:
            owned[p["owner"]] += 1
    for c in countries:
        if owned[c["tag"]] == 0:
            problems.append(f"country {c['tag']} owns no provinces")
    cultures = parse_cultures(os.path.join(ROOT, "data/map/cultures.txt"))
    culture_index = {c["id"]: i for i, c in enumerate(cultures)}
    state_mix, province_mix, orders = parse_pops(os.path.join(ROOT, "data/map/pops"), culture_index)
    slavery = parse_slavery(os.path.join(ROOT, "data/map/slavery.txt"))
    state_names = [st["name"] for st in states]
    for name in state_names:
        if state_names.count(name) > 1:
            problems.append(f"duplicate state name {name}")
        if name not in state_mix:
            problems.append(f"state {name} has no population mix in data/map/pops")
    for name in state_mix:
        if name not in state_names:
            problems.append(f"pops: unknown state {name}")
    province_names = {p["name"] for p in provinces}
    for name in list(province_mix) + list(orders):
        if name not in province_names:
            problems.append(f"pops: unknown province {name}")
    for tag in slavery:
        if tag not in tags:
            problems.append(f"slavery.txt: unknown country {tag}")
    used = set()
    for mix in list(state_mix.values()) + list(province_mix.values()):
        if not mix or sum(m[3] for m in mix) <= 0:
            problems.append("empty population mix")
        used.update(m[0] for m in mix)
    unused = [cultures[i]["id"] for i in range(len(cultures)) if i not in used]
    if unused:
        print(f"  note: cultures nobody belongs to yet: {', '.join(unused)}")
    if problems:
        sys.exit("Data problems:\n  " + "\n  ".join(problems))

    print(f"{len(countries)} countries, {len(regions)} regions, {len(states)} states, "
          f"{len(provinces)} provinces, {len(wastes)} wasteland seeds")
    print(f"raster {WIDTH} x {HEIGHT}")

    coast = parse_shapes(os.path.join(ROOT, "data/map/coast_1453.txt"))
    land = land_mask(args.land, lakes, coast)
    print(f"land pixels: {land.sum():,}")

    barriers = parse_barriers(os.path.join(ROOT, "data/map/barriers.txt"))
    river_mask, ridge_mask, frontier_mask = barrier_masks(barriers)
    print(f"{sum(1 for b in barriers if b['kind'] == 'river')} rivers, "
          f"{sum(1 for b in barriers if b['kind'] == 'ridge')} ridges, "
          f"{sum(1 for b in barriers if b['kind'] == 'frontier')} frontier lines")

    # Seeds: provinces first (index = province id), then wasteland.
    seeds = [(p["lat"], p["lon"]) for p in provinces] + [(w["lat"], w["lon"]) for w in wastes]
    seed_owner = np.array(list(range(len(provinces))) + [WASTE] * len(wastes))
    seed_px = []
    # Snap seeds that fall in water to the nearest land pixel.
    _, (iy, ix) = ndimage.distance_transform_edt(~land, return_indices=True)
    for k, (lat, lon) in enumerate(seeds):
        x, y = to_px(lat, lon)
        xi, yi = min(max(int(x), 0), WIDTH - 1), min(max(int(y), 0), HEIGHT - 1)
        if not land[yi, xi]:
            nx, ny = ix[yi, xi], iy[yi, xi]
            dist_km = math.hypot(nx - xi, ny - yi) / PPD * 111
            if k < len(provinces) and dist_km > 40:
                print(f"  note: {provinces[k]['name']} seed moved {dist_km:.0f} km onto land")
            xi, yi = nx, ny
        seed_px.append((xi, yi))
    seed_px = np.array(seed_px)
    on_barrier = [provinces[k]["name"] for k in range(len(provinces))
                  if (ridge_mask | frontier_mask)[seed_px[k][1], seed_px[k][0]]]
    if on_barrier:
        print(f"  note: towns sitting on a ridge or frontier line: {', '.join(on_barrier)}")

    seed_px = move_off_rivers(seed_px, provinces, land, river_mask)
    labels = grow_provinces(land, seed_px, seed_owner, river_mask, ridge_mask, frontier_mask)

    # Make each province one connected piece.
    for _ in range(3):
        moved = 0
        objs = ndimage.find_objects(np.where(labels >= 0, labels + 1, 0))
        for pid, sl in enumerate(objs):
            if sl is None:
                continue
            mask = labels[sl] == pid
            lab, n = ndimage.label(mask)
            if n <= 1:
                continue
            sx, sy = seed_px[pid]
            ly, lx = sy - sl[0].start, sx - sl[1].start
            keep = 0
            if 0 <= ly < mask.shape[0] and 0 <= lx < mask.shape[1]:
                keep = lab[ly, lx]
            if keep == 0:
                keep = np.argmax(np.bincount(lab.ravel())[1:]) + 1
            cut = (lab > 0) & (lab != keep)
            region = labels[sl]
            region[cut] = UNSET
            moved += int(cut.sum())
        if moved == 0:
            break
        unset = labels == UNSET
        _, (fy, fx) = ndimage.distance_transform_edt((labels == UNSET) | (labels == WATER), return_indices=True)
        labels[unset] = labels[fy[unset], fx[unset]]
    # Seeds always belong to their own province.
    for pid in range(len(provinces)):
        sx, sy = seed_px[pid]
        labels[sy, sx] = pid

    # ----------------------------------------------------------------------
    # Province statistics
    n = len(provinces)
    flat = labels.ravel()
    is_prov = flat >= 0
    counts = np.bincount(flat[is_prov], minlength=n)
    row_lat = LAT_MAX - (np.arange(HEIGHT) + 0.5) / PPD
    km_per_px = 111.32 / PPD
    px_area = (km_per_px ** 2) * np.cos(np.radians(row_lat))
    area = np.bincount(flat[is_prov], weights=np.repeat(px_area, WIDTH)[is_prov], minlength=n)

    # Label anchor: the pixel deepest inside each province.
    anchors = np.zeros((n, 2), dtype=np.int32)
    objs = ndimage.find_objects(np.where(labels >= 0, labels + 1, 0))
    for pid, sl in enumerate(objs):
        if sl is None:
            anchors[pid] = seed_px[pid]
            continue
        mask = np.pad(labels[sl] == pid, 1)
        dist = ndimage.distance_transform_edt(mask)
        yy, xx = np.unravel_index(np.argmax(dist), dist.shape)
        anchors[pid] = (xx - 1 + sl[1].start, yy - 1 + sl[0].start)

    # Adjacency and coast.
    adjacent = defaultdict(set)
    coastal = np.zeros(n, dtype=bool)
    for a, b in ((labels[:, :-1], labels[:, 1:]), (labels[:-1, :], labels[1:, :])):
        diff = a != b
        pa, pb = a[diff], b[diff]
        both = (pa >= 0) & (pb >= 0)
        for u, v in set(zip(pa[both].tolist(), pb[both].tolist())):
            adjacent[u].add(v)
            adjacent[v].add(u)
        coastal[np.unique(pa[(pa >= 0) & (pb == WATER)])] = True
        coastal[np.unique(pb[(pb >= 0) & (pa == WATER)])] = True
    index_of = {p["name"]: i for i, p in enumerate(provinces)}
    straits = []
    for a, b in STRAITS:
        if a in index_of and b in index_of:
            u, v = index_of[a], index_of[b]
            if v not in adjacent[u]:
                straits.append([u, v])
            adjacent[u].add(v)
            adjacent[v].add(u)

    # Borders that mostly follow a river (matters for battles and movement).
    near_river = ndimage.binary_dilation(river_mask, iterations=2)
    pair_total = defaultdict(int)
    pair_river = defaultdict(int)
    for a, b, ra, rb in ((labels[:, :-1], labels[:, 1:], near_river[:, :-1], near_river[:, 1:]),
                         (labels[:-1, :], labels[1:, :], near_river[:-1, :], near_river[1:, :])):
        diff = (a != b) & (a >= 0) & (b >= 0)
        pa, pb = np.minimum(a[diff], b[diff]), np.maximum(a[diff], b[diff])
        riv = (ra | rb)[diff]
        for u, v, r in zip(pa.tolist(), pb.tolist(), riv.tolist()):
            pair_total[(u, v)] += 1
            if r:
                pair_river[(u, v)] += 1
    river_borders = sorted([list(k) for k, t in pair_total.items() if pair_river[k] >= 0.35 * t and t >= 6])
    print(f"{len(river_borders)} province borders follow a river")

    tiny = [provinces[i]["name"] for i in range(n) if counts[i] < 40]
    if tiny:
        print(f"  note: very small provinces (<40 px): {', '.join(tiny)}")
    lonely = [provinces[i]["name"] for i in range(n) if not adjacent[i]]
    if lonely:
        print(f"  note: provinces with no land neighbours: {', '.join(lonely)}")

    # Population: each region's 1453 estimate spread over its provinces,
    # weighted mostly by development and a little by size.
    region_total = {}
    for raw in open(os.path.join(ROOT, "data/map/population_1453.txt"), encoding="utf-8"):
        line = raw.strip()
        if line and not line.startswith("#"):
            name, total = [x.strip() for x in line.split("|")]
            region_total[name] = float(total)
    missing = [r for r in regions if r not in region_total]
    if missing:
        sys.exit(f"population_1453.txt: no estimate for {', '.join(missing)}")
    weight = np.array([p["development"] ** 1.25 * max(area[i], 50.0) ** 0.5 for i, p in enumerate(provinces)])
    population = np.zeros(n)
    for r, name in enumerate(regions):
        members = [i for i, p in enumerate(provinces) if states[p["state"]]["region"] == r]
        wsum = weight[members].sum()
        for i in members:
            population[i] = region_total[name] * weight[i] / wsum
    print(f"total population {population.sum() / 1e6:.0f} million")

    # Capitals.
    for c in countries:
        mine = [i for i, p in enumerate(provinces) if p["owner"] == c["tag"]]
        if c["capitalName"]:
            if c["capitalName"] not in index_of or provinces[index_of[c["capitalName"]]]["owner"] != c["tag"]:
                sys.exit(f"{c['tag']}: capital {c['capitalName']} is not one of its provinces")
            c["capital"] = index_of[c["capitalName"]]
        else:
            c["capital"] = max(mine, key=lambda i: (provinces[i]["development"], -i))

    # ----------------------------------------------------------------------
    # Write outputs
    value = np.where(labels >= 0, labels + 2, np.where(labels == WASTE, 1, 0)).astype(np.uint16)
    idmap_path = os.path.join(ROOT, "Packages/GezCore/Sources/GezCore/Resources/provinces1453.idmap")
    write_idmap(value, idmap_path)

    out = {
        "map": {
            "width": WIDTH, "height": HEIGHT, "pixelsPerDegree": PPD,
            "longitudeMin": LON_MIN, "latitudeMax": LAT_MAX,
        },
        "startDate": {"year": 1453, "month": 5, "day": 30},
        "regions": regions,
        "states": states,
        "cultures": [{"id": c["id"], "name": c["name"], "family": c["family"]} for c in cultures],
        "countries": [
            {"tag": c["tag"], "name": c["name"], "color": c["color"], "government": c["government"],
             "religion": c["religion"], "capital": int(c["capital"]), "slavery": slavery.get(c["tag"], 0.0)}
            for c in countries
        ],
        "provinces": [
            {
                "name": p["name"], "state": p["state"], "owner": p["owner"],
                "latitude": p["lat"], "longitude": p["lon"],
                "terrain": p["terrain"], "development": p["development"],
                "population": int(round(population[i], -2)),
                "pops": normalised_mix(province_mix.get(p["name"]) or state_mix[states[p["state"]]["name"]]),
                "orders": orders.get(p["name"], []),
                "coastal": bool(coastal[i]), "areaKm2": round(float(area[i])),
                "labelX": int(anchors[i][0]), "labelY": int(anchors[i][1]),
                "adjacent": sorted(adjacent[i]),
            }
            for i, p in enumerate(provinces)
        ],
        "straits": straits,
        "riverBorders": river_borders,
        "rivers": [
            {"name": b["name"], "points": [[round(x, 1), round(y, 1)] for x, y in (to_px(lat, lon) for lat, lon in b["points"])]}
            for b in barriers if b["kind"] == "river"
        ],
    }
    json_path = os.path.join(ROOT, "Packages/GezCore/Sources/GezCore/Resources/scenario1453.json")
    os.makedirs(os.path.dirname(json_path), exist_ok=True)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"), ensure_ascii=False)

    preview(labels, provinces, states, countries, tags, os.path.join(ROOT, "docs/map_preview.png"), river_mask=river_mask)
    if args.full_preview:
        preview(labels, provinces, states, countries, tags, args.full_preview, scale=1, river_mask=river_mask,
                ridge_mask=ridge_mask if args.show_ridges else None)
    print(f"wrote {idmap_path}\nwrote {json_path}")


def normalised_mix(mix):
    """[[culture, religion, sect, share]] with shares summing to 1."""
    total = sum(m[3] for m in mix)
    return [[m[0], m[1], m[2], round(m[3] / total, 4)] for m in mix if m[3] > 0]


def write_idmap(value, path):
    """Run-length encoded province-ID map.

    Layout (little endian):
      4 bytes  magic "GZID"
      u32      width
      u32      height
      u32      number of runs
      runs     (u16 value, u16 length) repeated; runs cover the image row by
               row, left to right, and may continue across rows.
    value: 0 = water, 1 = wasteland, n >= 2 = province n - 2.
    """
    flat = value.ravel()
    change = np.nonzero(np.diff(flat))[0] + 1
    starts = np.concatenate([[0], change])
    lengths = np.diff(np.concatenate([starts, [len(flat)]]))
    vals = flat[starts]
    runs_v, runs_l = [], []
    for v, l in zip(vals.tolist(), lengths.tolist()):
        while l > 0xFFFF:
            runs_v.append(v)
            runs_l.append(0xFFFF)
            l -= 0xFFFF
        runs_v.append(v)
        runs_l.append(l)
    runs = np.empty(len(runs_v) * 2, dtype="<u2")
    runs[0::2] = runs_v
    runs[1::2] = runs_l
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"GZID")
        f.write(np.array([value.shape[1], value.shape[0], len(runs_v)], dtype="<u4").tobytes())
        f.write(runs.tobytes())


def preview(labels, provinces, states, countries, tags, path, scale=2, river_mask=None, ridge_mask=None):
    n = len(provinces)
    owner_color = np.zeros((n + 3, 3), dtype=np.uint8)
    for i, p in enumerate(provinces):
        owner_color[i] = countries[tags[p["owner"]]]["color"] if p["owner"] else (150, 140, 120)
    owner_color[n] = (64, 96, 128)      # water
    owner_color[n + 1] = (90, 80, 70)   # wasteland
    idx = np.where(labels >= 0, labels, np.where(labels == WATER, n, n + 1))
    img = owner_color[idx]

    prov_owner = np.array([tags.get(p["owner"], -1) if p["owner"] else -1 for p in provinces] + [-2, -3, -4])
    prov_state = np.array([p["state"] for p in provinces] + [-2, -3, -4])
    o, s = prov_owner[idx], prov_state[idx]

    def edges(arr):
        e = np.zeros(arr.shape, dtype=bool)
        e[:, 1:] |= arr[:, 1:] != arr[:, :-1]
        e[1:, :] |= arr[1:, :] != arr[:-1, :]
        return e

    land = labels != WATER
    pe, se, oe = edges(idx) & land, edges(s) & land, edges(o) & land
    img = img.astype(np.float32)
    img[pe] *= 0.82
    img[se] *= 0.55
    img[oe] = (20, 20, 20)
    if river_mask is not None:
        img[river_mask & land] = (64, 110, 150)
    if ridge_mask is not None:
        img[ridge_mask & land] = (120, 80, 40)
    out = Image.fromarray(img.astype(np.uint8))
    if scale > 1:
        out = out.resize((WIDTH // scale, HEIGHT // scale), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path, optimize=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--land", required=True, help="Natural Earth land GeoJSON")
    ap.add_argument("--full-preview", help="also write a full-size preview here")
    ap.add_argument("--show-ridges", action="store_true", help="draw ridges in the full preview")
    build(ap.parse_args())
