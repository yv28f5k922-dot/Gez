#!/usr/bin/env python3
"""Download elevation for the game area and save it on the map grid.

Source: the open "Terrain Tiles" dataset on AWS (terrarium encoding), built
from public-domain SRTM, GMTED and ETOPO1 elevation (and other open sources;
see docs/CREDITS.md). Zoom 6 tiles (~2.4 km per pixel at the equator) are
reprojected from Web Mercator to the game's equirectangular grid.

Output: data/terrain/elevation.png, 16-bit greyscale, same size as the
province map. value = metres + 12000 (so sea floor stays positive).

This needs internet access, so it runs on GitHub Actions
(.github/workflows/terrain.yml), not in the cloud workspace.
"""
import io
import math
import os
import sys
import time
import urllib.request

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LON_MIN, LON_MAX = -25.0, 98.0
LAT_MIN, LAT_MAX = -3.0, 71.5
PPD = 32
WIDTH = int(round((LON_MAX - LON_MIN) * PPD))
HEIGHT = int(round((LAT_MAX - LAT_MIN) * PPD))
ZOOM = 6
TILE = 256
URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
OFFSET = 12000


def tile_x(lon):
    return (lon + 180.0) / 360.0 * (2 ** ZOOM)


def tile_y(lat):
    lat = math.radians(lat)
    return (1.0 - math.log(math.tan(lat) + 1.0 / math.cos(lat)) / math.pi) / 2.0 * (2 ** ZOOM)


def fetch(x, y):
    url = URL.format(z=ZOOM, x=x, y=y)
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                img = Image.open(io.BytesIO(r.read())).convert("RGB")
            a = np.asarray(img).astype(np.float64)
            return a[..., 0] * 256 + a[..., 1] + a[..., 2] / 256 - 32768
        except Exception as e:  # network hiccup: retry
            print(f"retry {x},{y}: {e}", file=sys.stderr)
            time.sleep(2 + attempt * 3)
    sys.exit(f"could not download tile {x},{y}")


def main():
    x0, x1 = int(math.floor(tile_x(LON_MIN))), int(math.floor(tile_x(LON_MAX)))
    y0, y1 = int(math.floor(tile_y(LAT_MAX))), int(math.floor(tile_y(LAT_MIN)))
    cols, rows = x1 - x0 + 1, y1 - y0 + 1
    print(f"downloading {cols * rows} tiles")
    mosaic = np.zeros((rows * TILE, cols * TILE))
    for ty in range(y0, y1 + 1):
        for tx in range(x0, x1 + 1):
            mosaic[(ty - y0) * TILE:(ty - y0 + 1) * TILE, (tx - x0) * TILE:(tx - x0 + 1) * TILE] = fetch(tx, ty)
        print(f"row {ty - y0 + 1}/{rows}")

    # Reproject: for every game pixel find its place in the Mercator mosaic.
    lons = LON_MIN + (np.arange(WIDTH) + 0.5) / PPD
    lats = LAT_MAX - (np.arange(HEIGHT) + 0.5) / PPD
    mx = (np.array([tile_x(v) for v in lons]) - x0) * TILE - 0.5
    my = (np.array([tile_y(v) for v in lats]) - y0) * TILE - 0.5
    X, Y = np.meshgrid(mx, my)
    xi = np.clip(np.floor(X).astype(int), 0, mosaic.shape[1] - 2)
    yi = np.clip(np.floor(Y).astype(int), 0, mosaic.shape[0] - 2)
    fx, fy = X - xi, Y - yi
    h = (mosaic[yi, xi] * (1 - fx) * (1 - fy) + mosaic[yi, xi + 1] * fx * (1 - fy)
         + mosaic[yi + 1, xi] * (1 - fx) * fy + mosaic[yi + 1, xi + 1] * fx * fy)
    out = np.clip(np.round(h + OFFSET), 0, 65535).astype(np.uint16)
    path = os.path.join(ROOT, "data/terrain/elevation.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(out).save(path, optimize=True)
    print(f"wrote {path}: {WIDTH}x{HEIGHT}, {h.min():.0f} to {h.max():.0f} m")


if __name__ == "__main__":
    main()
