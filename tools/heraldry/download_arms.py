#!/usr/bin/env python3
"""Download the chosen Wikimedia Commons arms/flags and make game PNGs.

Runs on GitHub Actions. Reads data/heraldry/choices.txt:
    TAG | File:Something.svg | optional note
Writes App/Resources/Heraldry/<TAG>.png (256 px tall, transparent background)
and data/heraldry/credits.json (file page, author, licence for every image).
"""
import json, subprocess, sys, tempfile, time, urllib.parse, urllib.request
from pathlib import Path
from PIL import Image

API = "https://commons.wikimedia.org/w/api.php"
UA = "GezGame/0.1 (https://github.com/yv28f5k922-dot/Gez; heraldry download)"
OUT = Path("App/Resources/Heraldry")
SIZE = 256


def get(url, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except Exception as e:
            if i == tries - 1:
                raise
            time.sleep(3 * (i + 1))


def strip_html(s):
    import re
    return re.sub(r"<[^>]+>", "", s or "").strip()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    choices = []
    for line in Path("data/heraldry/choices.txt").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = [x.strip() for x in line.split("|")]
        choices.append((parts[0], parts[1], parts[2] if len(parts) > 2 else ""))

    credits = {}
    keep = set()
    for tag, title, note in choices:
        r = json.loads(get(API + "?" + urllib.parse.urlencode(dict(
            action="query", prop="imageinfo", iiprop="url|extmetadata",
            titles=title, format="json", formatversion="2"))))
        page = r["query"]["pages"][0]
        if "imageinfo" not in page:
            print("MISSING", tag, title, file=sys.stderr)
            continue
        ii = page["imageinfo"][0]
        md = ii.get("extmetadata", {})
        data = get(ii["url"])
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / ("src" + Path(ii["url"]).suffix.lower())
            src.write_bytes(data)
            if src.suffix == ".svg":
                png = Path(tmp) / "r.png"
                subprocess.run(["rsvg-convert", "-h", str(SIZE * 2), "-o", str(png), str(src)], check=True)
                im = Image.open(png)
            else:
                im = Image.open(src)
            im = im.convert("RGBA")
            im.thumbnail((SIZE * 2, SIZE), Image.LANCZOS)
            bbox = im.getbbox()
            if bbox:
                im = im.crop(bbox)
            im.save(OUT / f"{tag}.png", optimize=True)
        keep.add(f"{tag}.png")
        credits[tag] = {
            "file": title,
            "page": ii.get("descriptionurl"),
            "author": strip_html(md.get("Artist", {}).get("value")),
            "license": md.get("LicenseShortName", {}).get("value", ""),
            "licenseUrl": md.get("LicenseUrl", {}).get("value", ""),
            "note": note,
        }
        print(tag, "ok", flush=True)
        time.sleep(0.3)
    for f in OUT.glob("*.png"):
        if f.name not in keep:
            f.unlink()
    Path("data/heraldry/credits.json").write_text(
        json.dumps(credits, indent=1, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
