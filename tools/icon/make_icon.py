#!/usr/bin/env python3
"""Draw the Gez app icon: a 15th-century portolan sea chart.

The eastern Mediterranean, Aegean, Black Sea and Anatolia on aged parchment,
with inked coastlines, a wind-rose in the Libyan Sea and rhumb lines fanning
out across the chart.

Input
  Packages/GezCore/Sources/GezCore/Resources/provinces1453.idmap
      (the game's own 1453 coastline: id 0 is water)
Output
  App/Resources/Assets.xcassets/AppIcon.appiconset/   (iPad 1024 + all Mac sizes)
  docs/icon_preview.png

Run:
  python3 tools/icon/make_icon.py
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# Same projection as tools/terrain (plain latitude/longitude grid).
LAT_MAX, LON_MIN, PPD = 71.5, -25.0, 32

# Chart window. 30 degrees of longitude by 24 of latitude looks square at ~38N.
LON0, LON1 = 13.0, 43.0
LAT0, LAT1 = 26.5, 50.5

S = 2048          # draw at 2x, shrink at the end for smooth edges
OUT = 1024

PAPER = np.array([236, 220, 182], np.float32)
SEA_WASH = np.array([206, 208, 178], np.float32)   # faded verdigris
LAND = np.array([214, 178, 118], np.float32)       # warm ochre
INK = (64, 40, 22)
RED = (150, 36, 28)
GREEN = (52, 92, 60)


def load_idmap(path):
    b = open(path, "rb").read()
    w, h, n = np.frombuffer(b[4:16], "<u4")
    runs = np.frombuffer(b[16:], "<u2").reshape(-1, 2)
    return np.repeat(runs[:, 0], runs[:, 1]).reshape(h, w)


def land_mask():
    ids = load_idmap(os.path.join(ROOT, "Packages/GezCore/Sources/GezCore/Resources/provinces1453.idmap"))
    y0, y1 = int((LAT_MAX - LAT1) * PPD), int((LAT_MAX - LAT0) * PPD)
    x0, x1 = int((LON0 - LON_MIN) * PPD), int((LON1 - LON_MIN) * PPD)
    land = (ids[y0:y1, x0:x1] != 0).astype(np.float32)
    # Drop specks too small to read on an icon (tiny islets, shoals).
    labels, n = ndimage.label(land > 0.5)
    sizes = ndimage.sum(land > 0.5, labels, range(1, n + 1))
    keep = np.isin(labels, 1 + np.flatnonzero(sizes >= 60))
    # Fill small lakes so the land reads as solid.
    sea_lbl, m = ndimage.label(~keep)
    sea_sizes = ndimage.sum(~keep, sea_lbl, range(1, m + 1))
    keep |= np.isin(sea_lbl, 1 + np.flatnonzero(sea_sizes < 400))
    # Smooth upscale: blur, resize, threshold.
    img = Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    img = img.resize((S, S), Image.BICUBIC).filter(ImageFilter.GaussianBlur(3))
    return np.array(img) > 127


def noise(shape, scale, seed):
    rng = np.random.default_rng(seed)
    small = rng.random((max(2, shape[0] // scale), max(2, shape[1] // scale))).astype(np.float32)
    return np.array(Image.fromarray((small * 255).astype(np.uint8)).resize(shape[::-1], Image.BICUBIC)).astype(np.float32) / 255


def chart_xy(lon, lat):
    return ((lon - LON0) / (LON1 - LON0) * S, (LAT1 - lat) / (LAT1 - LAT0) * S)


def paint_base(land):
    h, w = land.shape
    grain = 0.55 * noise((h, w), 6, 1) + 0.3 * noise((h, w), 40, 2) + 0.15 * noise((h, w), 200, 3)
    img = np.empty((h, w, 3), np.float32)
    img[:] = PAPER
    # Sea: a faint wash that deepens near the coast, like a hand-tinted chart.
    dist = ndimage.distance_transform_edt(~land)
    near = np.exp(-dist / 70)[..., None]
    sea = PAPER * 0.55 + SEA_WASH * 0.45
    sea = sea * (1 - 0.35 * near) + np.array([150, 170, 150], np.float32) * 0.35 * near
    img[~land] = np.broadcast_to(sea, img.shape)[~land]
    # Land: ochre, a touch lighter away from the shore.
    dland = ndimage.distance_transform_edt(land)
    inland = np.clip(dland / 120, 0, 1)[..., None]
    land_col = LAND * (1 - 0.25 * inland) + PAPER * 0.25 * inland
    img[land] = np.broadcast_to(land_col, img.shape)[land]
    img *= (0.9 + 0.16 * grain)[..., None]
    # Age: darker, browner towards the edges, plus a few stains.
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.hypot(xx / w - 0.5, yy / h - 0.5) / 0.7071
    vignette = np.clip((r - 0.45) / 0.55, 0, 1) ** 1.6
    stains = np.clip(noise((h, w), 300, 4) - 0.55, 0, 1) * 0.5
    burn = np.clip(vignette * 0.55 + stains, 0, 0.7)[..., None]
    img = img * (1 - burn) + np.array([120, 78, 38], np.float32) * burn
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def coast_ink(land):
    """Coastline ink: a firm line plus a lighter echo just offshore."""
    edge = land ^ ndimage.binary_erosion(land, iterations=3)
    echo = ndimage.binary_dilation(land, iterations=14) ^ ndimage.binary_dilation(land, iterations=16)
    a = np.zeros(land.shape, np.float32)
    a[echo & ~land] = 0.35
    a[edge] = 1.0
    alpha = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    layer = Image.new("RGB", (S, S), INK)
    return layer, alpha


def draw_rhumbs(base, cx, cy):
    """32 rhumb lines from the rose, coloured like portolan charts:
    black for the 8 winds, green for half-winds, red for quarter-winds."""
    over = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    reach = S * 1.6
    for i in range(32):
        ang = math.radians(i * 11.25)
        colour, width = ((INK, 5) if i % 4 == 0 else (GREEN, 4) if i % 2 == 0 else (RED, 3))
        d.line([(cx, cy), (cx + reach * math.sin(ang), cy - reach * math.cos(ang))],
               fill=colour + (120,), width=width)
    base.alpha_composite(over)


def star(cx, cy, r_out, r_in, n, rot=0.0):
    pts = []
    for k in range(n * 2):
        r = r_out if k % 2 == 0 else r_in
        a = rot + k * math.pi / n
        pts.append((cx + r * math.sin(a), cy - r * math.cos(a)))
    return pts


def draw_rose(base, cx, cy, R):
    over = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    # Disc of clean parchment behind the rose so it reads over the lines.
    d.ellipse([cx - R * 0.9, cy - R * 0.9, cx + R * 0.9, cy + R * 0.9], fill=(240, 226, 190, 235))
    d.ellipse([cx - R * 0.9, cy - R * 0.9, cx + R * 0.9, cy + R * 0.9], outline=INK + (255,), width=6)
    d.ellipse([cx - R * 0.8, cy - R * 0.8, cx + R * 0.8, cy + R * 0.8], outline=INK + (255,), width=3)

    def point(angle, length, half, light, dark):
        # One compass point as two half-blades, light and dark, for depth.
        tip = (cx + length * math.sin(angle), cy - length * math.cos(angle))
        left = (cx + half * math.sin(angle - math.pi / 2), cy - half * math.cos(angle - math.pi / 2))
        right = (cx + half * math.sin(angle + math.pi / 2), cy - half * math.cos(angle + math.pi / 2))
        d.polygon([(cx, cy), tip, left], fill=light, outline=INK + (255,))
        d.polygon([(cx, cy), tip, right], fill=dark, outline=INK + (255,))

    paper = (244, 232, 200, 255)
    # Half-winds (between the eight main points), shorter.
    for k in range(8):
        point(math.radians(22.5 + k * 45), R * 0.62, R * 0.09, paper, GREEN + (255,))
    # Intercardinals.
    for k in range(4):
        point(math.radians(45 + k * 90), R * 0.82, R * 0.13, paper, INK + (255,))
    # Cardinals; north in red.
    for k in range(4):
        dark = RED + (255,) if k == 0 else INK + (255,)
        point(math.radians(k * 90), R * 1.18 if k == 0 else R * 1.05, R * 0.16, paper, dark)
    # Hub.
    d.ellipse([cx - R * 0.1, cy - R * 0.1, cx + R * 0.1, cy + R * 0.1], fill=(196, 150, 60, 255), outline=INK + (255,), width=4)
    # North marker: a small ink-and-red pennant beyond the north tip.
    ny = cy - R * 1.18
    d.polygon([(cx, ny - R * 0.2), (cx - R * 0.09, ny - R * 0.02), (cx + R * 0.09, ny - R * 0.02)], fill=RED + (255,), outline=INK + (255,))
    # Soft shadow under the rose to lift it off the paper.
    shadow = over.split()[3].filter(ImageFilter.GaussianBlur(10)).point(lambda v: int(v * 0.35))
    shadow = ImageChops.offset(shadow, 8, 10)
    base.paste((70, 45, 20, 255), (0, 0), shadow)
    base.alpha_composite(over)


def render():
    land = land_mask()
    base = paint_base(land).convert("RGBA")
    # Wind-rose in the open Ionian Sea, clear of Greece and Crete.
    cx, cy = chart_xy(18.6, 34.6)
    draw_rhumbs(base, cx, cy)
    ink, alpha = coast_ink(land)
    base.paste(ink, (0, 0), alpha)
    draw_rose(base, cx, cy, S * 0.105)
    return base.convert("RGB").resize((OUT, OUT), Image.LANCZOS)


def mac_shape(square):
    """Mac icons carry their own rounded-square shape on a transparent canvas
    (824 of 1024 px, per Apple's icon grid), with a soft drop shadow."""
    size, inner = 1024, 824
    art = square.resize((inner, inner), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (inner * 4, inner * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner * 4 - 1, inner * 4 - 1], radius=int(inner * 4 * 0.225), fill=255)
    mask = mask.resize((inner, inner), Image.LANCZOS)
    art.putalpha(mask)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (off, off + 10), mask)
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(14)))
    canvas.alpha_composite(art, (off, off))
    return canvas


def write_iconset(square):
    folder = os.path.join(ROOT, "App/Resources/Assets.xcassets")
    iconset = os.path.join(folder, "AppIcon.appiconset")
    os.makedirs(iconset, exist_ok=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")

    images = []
    square.save(os.path.join(iconset, "icon_ios_1024.png"))
    images.append({"filename": "icon_ios_1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"})

    mac = mac_shape(square)
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_mac_{pt}@{scale}x.png"
            mac.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})

    with open(os.path.join(iconset, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    mac.save(os.path.join(ROOT, "docs/icon_preview.png"))


if __name__ == "__main__":
    write_iconset(render())
    print("Wrote App/Resources/Assets.xcassets/AppIcon.appiconset and docs/icon_preview.png")
