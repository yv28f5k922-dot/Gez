#!/usr/bin/env python3
"""Build the economy part of the 1453 scenario.

Reads data/economy/*.txt and the map scenario, writes
Packages/GezCore/Sources/GezCore/Resources/economy1453.json:
goods, recipes, class needs, markets, off-map imports and, for every
province, its producers (staple, trade good, fish, workshops).

Run after mapgen.py:  python3 tools/economy/econgen.py
"""
import hashlib
from collections import defaultdict
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data/economy"
RES = ROOT / "Packages/GezCore/Sources/GezCore/Resources"

# Share of a province's rural workers (peasants + slaves) on each producer.
TRADE_SHARE = 0.15
FISH_SHARE = 0.06
# Share of burghers working in workshops (the rest trade and serve).
CRAFT_SHARE = 0.6
# Burgher jobs per workshop level (thousands).
JOBS_PER_LEVEL = 2.5

RELIGION_FAMILY = {
    **{r: "Christian" for r in "catholic hussite orthodox bosnian coptic ethiopian armenian syriac nestorian".split()},
    **{r: "Muslim" for r in "sunni twelver zaydi ismaili ibadi druze alawite yazidi".split()},
    **{r: "Dharmic" for r in "hindu jain theravada tibetan".split()},
    "zoroastrian": "Iranian", "jewish": "Jewish", "tengri": "Pagan", "folk": "Pagan",
}


def rows(name):
    for line in (DATA / name).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            yield line


def weights(text):
    out = {}
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        bits = part.split()
        w = float(bits[1]) if len(bits) > 1 else 1.0
        if w > 0:
            out[bits[0]] = out.get(bits[0], 0) + w
    return out


def pick(options, salt, n=1):
    """Deterministic weighted pick of up to n distinct keys."""
    opts = dict(options)
    chosen = []
    for k in range(n):
        if not opts:
            break
        total = sum(opts.values())
        h = int(hashlib.sha1(f"{salt}/{k}".encode()).hexdigest()[:8], 16) / 0xFFFFFFFF
        acc = 0.0
        for key in sorted(opts):
            acc += opts[key] / total
            if h <= acc:
                chosen.append(key)
                del opts[key]
                break
        else:
            key = sorted(opts)[-1]
            chosen.append(key)
            del opts[key]
    return chosen


STAPLE_YIELD = 1.5
TERRAIN_FOOD = {"farmland": 1.2, "plains": 1.0, "hills": 0.85, "mountains": 0.6,
                "forest": 0.75, "marsh": 0.75, "desert": 0.45, "steppe": 0.7}
RAW_VALUE = 2.5
TARGET = 1.15   # world supply / world demand at the start
WORKSHOP_SHARE = 0.7   # share of burghers who can fill workshop jobs


def approx_classes(p):
    pop = p["population"] / 1000
    burg = (0.02 + 0.016 * p["development"]) * pop
    return {"burghers": burg, "nobles": 0.015 * pop, "clergy": 0.015 * pop,
            "peasants": pop * (0.97) - burg, "slaves": 0.0}


def calibrate(goods, recipes, needs, provinces, producers, start_buildings, buildings, imports):
    """Set each trade good's yield and each recipe's output so that world
    supply is TARGET times world demand at the start. Staple food keeps its
    terrain yield. Goods nobody needs yet keep a default yield."""
    G = len(goods)
    unit = [0.0] * G          # supply at yield 1 (raw) or recipe output 1 (craft)
    staple_supply = [0.0] * G
    craft_seen = []
    for p, prods in zip(provinces, producers):
        c = approx_classes(p)
        rural = c["peasants"] + c["slaves"]
        for k, pr in enumerate(prods):
            if pr["kind"] == "raw":
                if k == 0:
                    staple_supply[pr["good"]] += rural * pr["share"] * STAPLE_YIELD * TERRAIN_FOOD[p["terrain"]]
                else:
                    unit[pr["good"]] += rural * pr["share"]
        jobs = {b: l * JOBS_PER_LEVEL for b, l in start_buildings[len(craft_seen)] if buildings[b]["effect"] == "workshop"}
        craft_seen.append(1)
        total = sum(jobs.values())
        fill = min(1.0, c["burghers"] * WORKSHOP_SHARE / total) if total else 0
        for b, j in jobs.items():
            unit[recipes[buildings[b]["recipe"]]["output"]] += j * fill
    imp = [0.0] * G
    for im in imports:
        imp[im["good"]] += im["amount"]
    recipe_of = {r["output"]: r for r in recipes}
    k = [RAW_VALUE / g["basePrice"] for g in goods]
    for g in range(G):
        if g in recipe_of:
            k[g] = recipe_of[g]["perThousand"]
    demand_needs = [0.0] * G
    for it in range(8):
        supply = [unit[g] * k[g] + staple_supply[g] + imp[g] for g in range(G)]
        for g in range(G):
            for bg, amt in goods[g].get("byproducts", []):
                supply[bg] += (unit[g] * k[g] + staple_supply[g]) * amt
        demand = [0.0] * G
        for nd in needs:
            size = sum(approx_classes(p)[nd["socialClass"]] for p in provinces) if it == 0 else None
            if size is None:
                size = nd["_size"]
            nd["_size"] = size
            ws = [supply[g] for g in nd["goods"]]
            tot = sum(ws)
            for g, w in zip(nd["goods"], ws):
                demand[g] += nd["amount"] * size / len(ws)
        for g, r in recipe_of.items():
            for ig, amt in r["inputs"]:
                demand[ig] += unit[g] * k[g] * amt
        for g in range(G):
            if unit[g] > 0 and demand[g] > 0:
                extra = supply[g] - unit[g] * k[g]
                k[g] = max(0.0, (TARGET * demand[g] - extra) / unit[g]) or k[g]
        demand_needs = demand
    for nd in needs:
        nd.pop("_size", None)
    for g in range(G):
        if g in recipe_of:
            recipe_of[g]["perThousand"] = round(k[g], 4)
        else:
            goods[g]["yield"] = round(k[g], 5)
    worst = sorted(((demand_needs[g] / (unit[g] * k[g] + staple_supply[g] + imp[g]) if (unit[g] * k[g] + staple_supply[g] + imp[g]) else 99, goods[g]["key"]) for g in range(G) if demand_needs[g] > 0), reverse=True)[:6]
    print("hardest to supply (demand/supply):", [(n, round(r, 2)) for r, n in worst])


def main():
    scen = json.loads((RES / "scenario1453.json").read_text())
    provinces = scen["provinces"]
    states = scen["states"]
    regions = scen["regions"]

    goods = []
    for line in rows("goods.txt"):
        key, name, cat, price, rgb = [x.strip() for x in line.split("|")]
        goods.append({"key": key, "name": name, "category": cat, "basePrice": float(price),
                      "color": [int(v) for v in rgb.split()]})
    gindex = {g["key"]: i for i, g in enumerate(goods)}

    def gid(key, where):
        if key not in gindex:
            sys.exit(f"{where}: unknown good '{key}'")
        return gindex[key]

    recipes = []
    for line in rows("recipes.txt"):
        out, per, inputs = [x.strip() for x in line.split("|")]
        recipes.append({"output": gid(out, "recipes"), "perThousand": float(per),
                        "inputs": [[gid(k, "recipes"), v] for k, v in weights(inputs).items()]})
    recipe_for = {r["output"]: i for i, r in enumerate(recipes)}

    buildings = []
    for line in rows("buildings.txt"):
        parts = [x.strip() for x in line.split("|")]
        key, name, cat, cost, months, mats, effect = parts[:7]
        req = parts[7] if len(parts) > 7 else ""
        b = {"key": key, "name": name, "category": cat, "cost": float(cost), "months": int(months),
             "materials": [[gid(k, "buildings"), v] for k, v in weights(mats).items()]}
        e = effect.split()
        if e[0] == "workshop":
            g = gid(e[1], "buildings")
            b["effect"] = "workshop"
            b["recipe"] = next(i for i, r in enumerate(recipes) if r["output"] == g)
            b["amount"] = 1.0
        else:
            b["effect"] = e[0]
            b["amount"] = float(e[1])
        if req:
            if req == "coastal":
                b["requiresCoast"] = True
            elif req.startswith("good:"):
                b["requiresGoods"] = [gid(k, "buildings") for k in req[5:].split("/")]
            elif req.startswith("terrain:"):
                b["requiresTerrain"] = req[8:].split("/")
            elif req.startswith("religion:"):
                b["requiresFamily"] = req[9:]
            else:
                sys.exit(f"buildings: unknown requirement '{req}'")
        buildings.append(b)
    bindex = {b["key"]: i for i, b in enumerate(buildings)}
    workshop_of = {b["recipe"]: i for i, b in enumerate(buildings) if b["effect"] == "workshop"}

    needs = []
    for line in rows("needs.txt"):
        parts = [x.strip() for x in line.split("|")]
        cls, group, amount, goods_list = parts[:4]
        need = {"socialClass": cls, "name": group, "amount": float(amount),
                "goods": [gid(k, "needs") for k in goods_list.split()]}
        if len(parts) > 4:
            kind, fam = parts[4].split(":")
            need["only" if kind == "only" else "not"] = fam
        needs.append(need)

    names = [p["name"] for p in provinces]
    markets = []
    for line in rows("markets.txt"):
        name, centre = [x.strip() for x in line.split("|")]
        if centre not in names:
            sys.exit(f"markets: unknown province '{centre}'")
        markets.append({"name": name, "centre": names.index(centre)})
    mindex = {m["name"]: i for i, m in enumerate(markets)}

    imports = []
    for line in rows("imports.txt"):
        market, items = [x.strip() for x in line.split("|")]
        for k, v in weights(items).items():
            imports.append({"market": mindex[market], "good": gid(k, "imports"), "amount": v})

    # Rule tables keyed by scope level.
    state_names = [s["name"] for s in states]

    def scope_level(scope):
        if scope == "*":
            return 0
        if scope in ("Christian", "Muslim", "Dharmic", "Jewish", "Iranian", "Pagan"):
            return 1
        if scope in regions:
            return 2
        if scope in state_names:
            return 3
        if scope in names:
            return 4
        sys.exit(f"unknown scope '{scope}'")

    staples, trade_rules, craft_rules = [], [], []
    for line in rows("resources.txt"):
        if line.startswith("byproduct "):
            src, items = [x.strip() for x in line[10:].split("|")]
            for k, v in weights(items).items():
                goods[gid(src, "byproduct")].setdefault("byproducts", []).append([gid(k, "byproduct"), v])
            continue
        if line.startswith("staple "):
            scope, good = [x.strip() for x in line[7:].split("|")]
            staples.append((scope_level(scope), scope, gid(good, "staple")))
            continue
        scope, items = [x.strip() for x in line.split("|")]
        terrain = None
        if "@" in scope:
            scope, terrain = [x.strip() for x in scope.split("@")]
        for k in weights(items):
            gid(k, "resources")
        trade_rules.append((scope_level(scope), scope, terrain, weights(items)))
    for line in rows("crafts.txt"):
        scope, items = [x.strip() for x in line.split("|")]
        for k in weights(items):
            if gid(k, "crafts") not in recipe_for:
                sys.exit(f"crafts: no recipe for '{k}'")
        craft_rules.append((scope_level(scope), scope, weights(items)))

    market_centres = {m["centre"] for m in markets}
    extra_start = {}
    for line in rows("buildings_1453.txt"):
        line = line.split("#")[0].strip()
        if not line:
            continue
        name, items = [x.strip() for x in line.split("|")]
        if name not in names:
            sys.exit(f"buildings_1453: unknown province '{name}'")
        for k in weights(items):
            if k not in bindex:
                sys.exit(f"buildings_1453: unknown building '{k}'")
        extra_start.setdefault(name, {}).update(weights(items))
    out_provinces, out_buildings = [], []
    for i, p in enumerate(provinces):
        st = states[p["state"]]
        scopes = {0: "*", 2: regions[st["region"]], 3: st["name"], 4: p["name"]}
        majority = max(p["pops"], key=lambda x: x[3])[1] if p["pops"] else "folk"
        scopes[1] = RELIGION_FAMILY.get(majority, "Pagan")

        def matches(level, scope):
            return scopes.get(level) == scope

        staple = max((s for s in staples if matches(s[0], s[1])), key=lambda s: s[0])[2]

        best = None
        for level, scope, terrain, w in trade_rules:
            if not matches(level, scope):
                continue
            if terrain and terrain != p["terrain"]:
                continue
            rank = (level, 1 if terrain else 0)
            if best is None or rank > best[0]:
                best = (rank, w)
        trade = gid(pick(best[1], p["name"])[0], "pick")

        merged, specific = {}, None
        for level, scope, w in craft_rules:
            if not matches(level, scope):
                continue
            if level <= 1:
                for k, v in w.items():
                    merged[k] = merged.get(k, 0) + v
            elif specific is None or level > specific[0]:
                specific = (level, w)
        craft_weights = specific[1] if specific else merged
        n_crafts = 3 if p["development"] >= 8 else (2 if p["development"] >= 4 else 1)
        crafts = [gid(k, "craft") for k in pick(craft_weights, p["name"] + "/craft", n_crafts)]

        producers = []
        rural_left = 1.0
        if p.get("coastal"):
            producers.append({"good": gindex["fish"], "kind": "raw", "share": FISH_SHARE})
            rural_left -= FISH_SHARE
        if trade != staple:
            producers.append({"good": trade, "kind": "raw", "share": TRADE_SHARE})
            rural_left -= TRADE_SHARE
        producers.insert(0, {"good": staple, "kind": "raw", "share": round(rural_left, 4)})
        start = {}
        burghers = approx_classes(p)["burghers"]
        for c in crafts:
            jobs = burghers * CRAFT_SHARE / len(crafts)
            level = max(1, min(5, round(jobs / JOBS_PER_LEVEL)))
            start[workshop_of[recipe_for[c]]] = level
        if i in market_centres:
            start[bindex["market_hall"]] = 2
        if p.get("coastal") and p["development"] >= 6:
            start[bindex["port"]] = 1
        if p["development"] >= 5:
            start[bindex["temple"]] = 1
        for k, v in extra_start.get(p["name"], {}).items():
            start[bindex[k]] = max(start.get(bindex[k], 0), int(v))
        out_provinces.append(producers)
        out_buildings.append(sorted([b, l] for b, l in start.items()))

    calibrate(goods, recipes, needs, provinces, out_provinces, out_buildings, buildings, imports)
    banks = []
    for line in rows("banks.txt"):
        name, home, capital, rate, reach = [x.strip() for x in line.split("|")]
        if home not in names:
            sys.exit(f"banks: unknown province '{home}'")
        reach_list = [x.strip() for x in reach.split(",")]
        for r in reach_list:
            if r != "*" and r not in regions:
                sys.exit(f"banks: unknown region '{r}'")
        banks.append({"name": name, "home": names.index(home), "capital": float(capital),
                      "rate": float(rate),
                      "regions": [] if "*" in reach_list else [regions.index(r) for r in reach_list]})

    routes = []
    tags = {c["tag"] for c in scen["countries"]}
    for line in rows("routes_1453.txt"):
        owner, good, a, b, volume = [x.strip() for x in line.split("|")]
        if owner not in tags:
            sys.exit(f"routes: unknown country '{owner}'")
        routes.append({"owner": owner, "good": gid(good, "routes"), "from": mindex[a], "to": mindex[b],
                       "volume": float(volume)})

    result = {"routes": routes, "banks": banks, "goods": goods, "recipes": recipes, "needs": needs, "markets": markets,
              "imports": imports, "producers": out_provinces, "buildings": buildings,
              "startBuildings": out_buildings}
    (RES / "economy1453.json").write_text(json.dumps(result, separators=(",", ":"), ensure_ascii=False))
    print(f"{len(goods)} goods, {len(recipes)} recipes, {len(needs)} needs, "
          f"{len(markets)} markets, {len(out_provinces)} provinces")


if __name__ == "__main__":
    main()
