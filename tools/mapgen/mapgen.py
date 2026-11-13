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
town). Each land pixel belongs to the nearest seed on the same landmass,
measured on the globe, with a smooth random warp so borders wiggle instead of
being straight lines. Wasteland seeds claim deserts and off-map land. Pieces
of a province that end up cut off from its seed are given to neighbours, so
every province is one connected shape.

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
MAX_REACH_KM = 450.0  # land further than this from any seed becomes wasteland
ISLAND_REACH_KM = 250.0  # seedless islands join the nearest province within this

WATER, WASTE, UNSET = -1, -2, -3

TERRAIN = {
    "f": "farmland", "p": "plains", "h": "hills", "m": "mountains",
    "w": "forest", "x": "marsh", "d": "desert", "s": "steppe",
}
GOVERNMENTS = {"monarchy", "republic", "theocracy", "steppeHorde"}
RELIGIONS = {"catholic", "orthodox", "miaphysite", "sunni", "shia", "hindu", "buddhist"}

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
                states.append({"name": line[1:].strip(), "region": region})
                state = len(states) - 1
            elif line.startswith("!"):
                name, coords = [p.strip() for p in line[1:].split("|")]
                lat, lon = [float(v) for v in coords.split()]
                wastes.append({"name": name, "lat": lat, "lon": lon})
            else:
                parts = [p.strip() for p in line.split("|")]
                if len(parts) != 3 or state is None:
                    sys.exit(f"{where}: bad province line: {line}")
                name, coords, rest = parts
                lat, lon = [float(v) for v in coords.split()]
                owner, t, dev = rest.split()
                if t not in TERRAIN:
                    sys.exit(f"{where}: bad terrain {t}")
                provinces.append({
                    "name": name, "lat": lat, "lon": lon, "state": state,
                    "owner": None if owner == "-" else owner,
                    "terrain": TERRAIN[t], "development": int(dev),
                })
    # Drop regions and states with no provinces (e.g. the wasteland file).
    used_states = sorted({p["state"] for p in provinces})
    state_map = {old: new for new, old in enumerate(used_states)}
    states = [states[i] for i in used_states]
    used_regions = sorted({s["region"] for s in states})
    region_map = {old: new for new, old in enumerate(used_regions)}
    regions = [regions[i] for i in used_regions]
    for s in states:
        s["region"] = region_map[s["region"]]
    for p in provinces:
        p["state"] = state_map[p["state"]]
    return regions, states, provinces, wastes


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


def land_mask(geojson_path, lakes):
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
    if problems:
        sys.exit("Data problems:\n  " + "\n  ".join(problems))

    print(f"{len(countries)} countries, {len(regions)} regions, {len(states)} states, "
          f"{len(provinces)} provinces, {len(wastes)} wasteland seeds")
    print(f"raster {WIDTH} x {HEIGHT}")

    land = land_mask(args.land, lakes)
    print(f"land pixels: {land.sum():,}")

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

    # Landmasses.
    comp, ncomp = ndimage.label(land, structure=np.ones((3, 3)))
    seed_comp = comp[seed_px[:, 1], seed_px[:, 0]]

    rng = np.random.default_rng(1453)
    warp_x = smooth_noise(rng, 48, 7.0) + smooth_noise(rng, 12, 2.0)
    warp_y = smooth_noise(rng, 48, 7.0) + smooth_noise(rng, 12, 2.0)

    lons, lats = lonlat_grid()
    labels = np.full((HEIGHT, WIDTH), WATER, dtype=np.int32)
    seed_vec = unit_vectors(np.array([s[0] for s in seeds]), np.array([s[1] for s in seeds]))
    max_chord = chord(MAX_REACH_KM)

    ys, xs = np.nonzero(land)
    wx = np.clip(xs + warp_x[ys, xs], 0, WIDTH - 1)
    wy = np.clip(ys + warp_y[ys, xs], 0, HEIGHT - 1)
    pvec = unit_vectors(LAT_MAX - (wy + 0.5) / PPD, LON_MIN + (wx + 0.5) / PPD)
    pcomp = comp[ys, xs]
    result = np.full(len(ys), WASTE, dtype=np.int64)

    order = np.argsort(pcomp, kind="stable")
    bounds = np.searchsorted(pcomp[order], np.arange(1, ncomp + 2))
    all_tree = cKDTree(seed_vec)
    comps_with_seeds = set(seed_comp.tolist())
    for c in range(1, ncomp + 1):
        idx = order[bounds[c - 1]:bounds[c]]
        if len(idx) == 0:
            continue
        if c in comps_with_seeds:
            members = np.nonzero(seed_comp == c)[0]
            tree = cKDTree(seed_vec[members])
            d, j = tree.query(pvec[idx])
            chosen = seed_owner[members[j]]
            chosen = np.where(d > max_chord, WASTE, chosen)
            result[idx] = chosen
        else:
            d, j = all_tree.query(pvec[idx])
            chosen = seed_owner[j]
            chosen = np.where(d > chord(ISLAND_REACH_KM), WASTE, chosen)
            result[idx] = chosen
    labels[ys, xs] = result

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

    tiny = [provinces[i]["name"] for i in range(n) if counts[i] < 40]
    if tiny:
        print(f"  note: very small provinces (<40 px): {', '.join(tiny)}")
    lonely = [provinces[i]["name"] for i in range(n) if not adjacent[i]]
    if lonely:
        print(f"  note: provinces with no land neighbours: {', '.join(lonely)}")

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
        "countries": [
            {"tag": c["tag"], "name": c["name"], "color": c["color"], "government": c["government"],
             "religion": c["religion"], "capital": int(c["capital"])}
            for c in countries
        ],
        "provinces": [
            {
                "name": p["name"], "state": p["state"], "owner": p["owner"],
                "latitude": p["lat"], "longitude": p["lon"],
                "terrain": p["terrain"], "development": p["development"],
                "coastal": bool(coastal[i]), "areaKm2": round(float(area[i])),
                "labelX": int(anchors[i][0]), "labelY": int(anchors[i][1]),
                "adjacent": sorted(adjacent[i]),
            }
            for i, p in enumerate(provinces)
        ],
        "straits": straits,
    }
    json_path = os.path.join(ROOT, "Packages/GezCore/Sources/GezCore/Resources/scenario1453.json")
    os.makedirs(os.path.dirname(json_path), exist_ok=True)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"), ensure_ascii=False)

    preview(labels, provinces, states, countries, tags, os.path.join(ROOT, "docs/map_preview.png"))
    if args.full_preview:
        preview(labels, provinces, states, countries, tags, args.full_preview, scale=1)
    print(f"wrote {idmap_path}\nwrote {json_path}")


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


def preview(labels, provinces, states, countries, tags, path, scale=2):
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
    out = Image.fromarray(img.astype(np.uint8))
    if scale > 1:
        out = out.resize((WIDTH // scale, HEIGHT // scale), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path, optimize=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--land", required=True, help="Natural Earth land GeoJSON")
    ap.add_argument("--full-preview", help="also write a full-size preview here")
    build(ap.parse_args())
