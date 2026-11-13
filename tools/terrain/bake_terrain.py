#!/usr/bin/env python3
"""Paint the terrain picture the map shader draws on top of.

Inputs
  data/terrain/elevation.png                (from fetch_elevation.py, via CI)
  Packages/GezCore/Sources/GezCore/Resources/provinces1453.idmap
  Packages/GezCore/Sources/GezCore/Resources/scenario1453.json
Output
  App/Resources/Terrain/terrain.jpg          (same size as the province map)
  docs/terrain_preview.jpg                   (small preview)

How it paints:
  1. A smooth "climate" colour from each province's terrain type (farmland,
     forest, desert...), blurred so it never shows province shapes.
  2. Wasteland is desert in the south, taiga in the north, alpine above 3.5 km.
  3. High ground turns to rock, then snow (snow line drops further north).
  4. Hill shading from the elevation, lit from the north-west.
  5. Sea colour from water depth; lakes a fixed blue.
  6. Rivers painted on, anti-aliased.

Run after mapgen.py whenever the map or terrain types change:
  python3 tools/terrain/bake_terrain.py
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LAT_MAX = 71.5
PPD = 32
OFFSET = 12000

PALETTE = {
    "farmland": (128, 142, 80),
    "plains": (150, 150, 94),
    "steppe": (172, 162, 108),
    "desert": (212, 186, 136),
    "forest": (68, 98, 60),
    "marsh": (98, 118, 84),
    "hills": (140, 132, 94),
    "mountains": (130, 122, 104),
}
TAIGA = (62, 86, 64)
TUNDRA = (142, 142, 122)
ROCK = (122, 114, 106)
SNOW = (238, 240, 244)
SHALLOW = (92, 152, 160)
DEEP = (28, 54, 84)
LAKE = (72, 122, 142)
RIVER = (70, 114, 140)


def load_idmap(path):
    b = open(path, "rb").read()
    w, h, n = np.frombuffer(b[4:16], "<u4")
    runs = np.frombuffer(b[16:], "<u2").reshape(-1, 2)
    return np.repeat(runs[:, 0], runs[:, 1]).reshape(h, w).astype(np.int32)


def value_noise(shape, cell, rng):
    gh, gw = shape[0] // cell + 3, shape[1] // cell + 3
    g = rng.random((gh, gw))
    return ndimage.zoom(g, cell, order=3)[: shape[0], : shape[1]]


def main():
    elev = np.array(Image.open(os.path.join(ROOT, "data/terrain/elevation.png"))).astype(np.float32) - OFFSET
    ids = load_idmap(os.path.join(ROOT, "Packages/GezCore/Sources/GezCore/Resources/provinces1453.idmap"))
    scenario = json.load(open(os.path.join(ROOT, "Packages/GezCore/Sources/GezCore/Resources/scenario1453.json")))
    H, W = ids.shape
    assert elev.shape == ids.shape, "elevation and province map sizes differ"
    lat = (LAT_MAX - (np.arange(H) + 0.5) / PPD)[:, None] * np.ones((1, W), dtype=np.float32)
    water = ids == 0
    waste = ids == 1
    land = ~water

    # 1. Climate colour per province terrain type, blurred.
    terrain_names = list(PALETTE)
    prov_terrain = np.array([terrain_names.index(p["terrain"]) for p in scenario["provinces"]])
    lut = np.array([PALETTE[t] for t in terrain_names], dtype=np.float32)
    climate = np.zeros((H, W, 3), dtype=np.float32)
    prov = ids >= 2
    climate[prov] = lut[prov_terrain[ids[prov] - 2]]
    # 2. Wasteland by latitude, blended gradually (desert -> taiga -> tundra).
    rng0 = np.random.default_rng(7)
    wobble = (value_noise((H, W), 60, rng0) - 0.5) * 6   # degrees of latitude
    lat_w = lat + wobble
    taiga_w = np.clip((lat_w - 47) / 8, 0, 1)[..., None]
    tundra_w = np.clip((lat_w - 63) / 6, 0, 1)[..., None]
    w_color = np.array(PALETTE["desert"], np.float32) * (1 - taiga_w) + np.array(TAIGA, np.float32) * taiga_w
    w_color = w_color * (1 - tundra_w) + np.array(TUNDRA, np.float32) * tundra_w
    climate[waste] = w_color[waste]
    climate[water] = 0
    # Blur over land only (normalised), so coasts don't pull in sea colour.
    weight = ndimage.gaussian_filter(land.astype(np.float32), 9)
    for c in range(3):
        climate[..., c] = ndimage.gaussian_filter(climate[..., c], 9) / np.maximum(weight, 1e-3)
    rng = np.random.default_rng(1453)
    n1 = value_noise((H, W), 40, rng) - 0.5
    n2 = value_noise((H, W), 9, rng) - 0.5
    climate *= (1 + 0.10 * n1 + 0.06 * n2)[..., None]

    # 3. Rock and snow on high ground.
    h = np.maximum(elev, 0)
    rock = np.clip((h - 1800) / 1400, 0, 1)
    snowline = np.clip(4300 - np.maximum(lat - 30, 0) * 70, 1500, 4600)
    # Snow on peaks that stand above their surroundings (so high plateaus
    # like Tibet stay brown, with white ranges on them).
    local = ndimage.gaussian_filter(h, 25)
    peak = np.clip((h - local + 150) / 500, 0, 1)
    snow = np.clip((h - snowline) / 700, 0, 1) * np.maximum(peak, np.clip((h - snowline - 1800) / 800, 0, 1))
    snow = ndimage.gaussian_filter(snow, 0.8) * np.clip(0.75 + n2 * 1.5, 0, 1)
    alpine = np.clip((h - 3500) / 800, 0, 1) * waste
    color = climate * (1 - rock[..., None]) + np.array(ROCK, np.float32) * rock[..., None]
    color = color * (1 - alpine[..., None]) + np.array(TUNDRA, np.float32) * alpine[..., None]
    color = color * (1 - snow[..., None]) + np.array(SNOW, np.float32) * snow[..., None]

    # 4. Hill shading (exaggerated so hills read at map scale).
    smooth = ndimage.gaussian_filter(np.where(land, elev, 0), 1.2)
    dy_m = 111320.0 / PPD
    dx_m = dy_m * np.cos(np.radians(lat))
    gy, gx = np.gradient(smooth)
    exaggerate = 7.0
    nx = -gx / dx_m * exaggerate
    ny = gy / dy_m * exaggerate   # image rows go south; flip so north is up
    nz = np.ones_like(nx)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    az, alt = np.radians(315), np.radians(42)
    lx, ly, lz = np.cos(alt) * np.sin(az), np.cos(alt) * np.cos(az), np.sin(alt)
    shade = (nx * lx + ny * ly + nz * lz) / norm
    flat = lz
    light = np.clip(0.62 + 0.9 * (shade - flat) + 0.38, 0.45, 1.25)
    color *= light[..., None]

    # 5. Water by depth; lakes fixed.
    depth = np.clip(-elev, 0, None)
    t = np.sqrt(np.clip(depth / 3000, 0, 1))[..., None]
    sea = np.array(SHALLOW, np.float32) * (1 - t) + np.array(DEEP, np.float32) * t
    lake = water & (elev > -5)
    sea[lake] = LAKE
    sea *= (1 + 0.04 * n1)[..., None]
    color[water] = sea[water]

    img = Image.fromarray(np.clip(color, 0, 255).astype(np.uint8), "RGB")

    # 6. Rivers, drawn at double size then shrunk for smooth edges.
    scale = 2
    overlay = Image.new("L", (W * scale, H * scale), 0)
    draw = ImageDraw.Draw(overlay)
    for river in scenario.get("rivers", []):
        pts = [(x * scale, y * scale) for x, y in river["points"]]
        draw.line(pts, fill=255, width=3 * scale // 2 + 1, joint="curve")
    overlay = overlay.filter(ImageFilter.GaussianBlur(1.0)).resize((W, H), Image.LANCZOS)
    a = (np.array(overlay).astype(np.float32) / 255 * 0.9)[..., None]
    arr = np.array(img).astype(np.float32)
    arr = arr * (1 - a) + np.array(RIVER, np.float32) * a
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")

    out = os.path.join(ROOT, "App/Resources/Terrain/terrain.jpg")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, quality=90, optimize=True)
    img.resize((W // 3, H // 3), Image.LANCZOS).save(os.path.join(ROOT, "docs/terrain_preview.jpg"), quality=85)
    print(f"wrote {out} ({os.path.getsize(out) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
