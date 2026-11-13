#!/usr/bin/env python3
"""Search Wikimedia Commons for each country's arms/flag candidates.

Runs on GitHub Actions (the cloud workspace has no general internet).
Reads data/heraldry/queries.txt, writes into an output folder:
  candidates.json  - per tag: list of {n, title, url, license, artist}
  sheet_XX.png     - contact sheets: one row per country, numbered thumbnails
Claude looks at the sheets and writes data/heraldry/choices.txt.
"""
import io, json, sys, time, urllib.parse, urllib.request
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

API = "https://commons.wikimedia.org/w/api.php"
UA = "GezGame/0.1 (https://github.com/yv28f5k922-dot/Gez; heraldry research)"
PER_QUERY = 6
MAX_PER_TAG = 12
THUMB = 96


def get(url, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read()
        except Exception as e:
            if i == tries - 1:
                print("fail", url, e, file=sys.stderr)
                return None
            time.sleep(2 * (i + 1))


def api(**params):
    params.update(format="json", formatversion="2")
    data = get(API + "?" + urllib.parse.urlencode(params))
    return json.loads(data) if data else {}


def search(q):
    r = api(action="query", list="search", srnamespace="6", srlimit=str(PER_QUERY),
            srsearch=q + " filetype:bitmap|drawing")
    return [h["title"] for h in r.get("query", {}).get("search", [])]


def info(titles):
    out = {}
    for i in range(0, len(titles), 40):
        r = api(action="query", prop="imageinfo", iiprop="url|extmetadata",
                iiurlwidth=str(THUMB), titles="|".join(titles[i:i + 40]))
        for p in r.get("query", {}).get("pages", []):
            ii = (p.get("imageinfo") or [{}])[0]
            md = ii.get("extmetadata", {})
            out[p["title"]] = {
                "thumb": ii.get("thumburl"),
                "url": ii.get("url"),
                "license": md.get("LicenseShortName", {}).get("value", "?"),
                "artist": md.get("Artist", {}).get("value", "?"),
            }
    return out


def main(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for line in Path("data/heraldry/queries.txt").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        tag, name, qs = [x.strip() for x in line.split("|", 2)]
        rows.append((tag, name, [q.strip() for q in qs.split(";") if q.strip()]))

    result = {}
    for tag, name, qs in rows:
        titles = []
        for q in qs:
            for t in search(q):
                if t not in titles:
                    titles.append(t)
            time.sleep(0.2)
        titles = titles[:MAX_PER_TAG]
        meta = info(titles) if titles else {}
        result[tag] = {"name": name, "candidates": [
            {"n": i + 1, "title": t, **meta.get(t, {})} for i, t in enumerate(titles)]}
        print(tag, len(titles), flush=True)
    (out / "candidates.json").write_text(json.dumps(result, indent=1, ensure_ascii=False))

    # Contact sheets
    font = ImageFont.load_default()
    tags = list(result)
    per_sheet = 14
    cell = THUMB + 8
    for s in range(0, len(tags), per_sheet):
        chunk = tags[s:s + per_sheet]
        W, H = 170 + MAX_PER_TAG * cell, len(chunk) * (cell + 14)
        sheet = Image.new("RGB", (W, H), (235, 235, 235))
        d = ImageDraw.Draw(sheet)
        for r, tag in enumerate(chunk):
            y = r * (cell + 14)
            d.text((4, y + 4), tag, fill=(0, 0, 0), font=font)
            d.text((4, y + 18), result[tag]["name"][:26], fill=(60, 60, 60), font=font)
            for c in result[tag]["candidates"]:
                x = 170 + (c["n"] - 1) * cell
                d.text((x, y), str(c["n"]), fill=(200, 0, 0), font=font)
                if not c.get("thumb"):
                    continue
                data = get(c["thumb"])
                if not data:
                    continue
                try:
                    im = Image.open(io.BytesIO(data)).convert("RGBA")
                    im.thumbnail((THUMB, THUMB))
                    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
                    bg.alpha_composite(im)
                    sheet.paste(bg.convert("RGB"), (x, y + 12))
                except Exception:
                    pass
        sheet.save(out / f"sheet_{s // per_sheet:02d}.png")
        print("sheet", s // per_sheet, flush=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "heraldry_out")
