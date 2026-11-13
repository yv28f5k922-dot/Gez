#!/usr/bin/env python3
"""Python copy of the monthly market model in GezCore (MarketSystem.swift).

Used only to balance numbers, because the cloud workspace cannot run Swift.
Keep the constants in step with MarketSystem.swift.

    python3 tools/economy/prototype.py [months]
"""
import heapq
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "Packages/GezCore/Sources/GezCore/Resources"

STAPLE_YIELD = 1.5            # units per 1,000 workers per year
RAW_VALUE = 2.5               # ducats per 1,000 workers per year for trade goods
TERRAIN_FOOD = {"farmland": 1.2, "plains": 1.0, "hills": 0.85, "mountains": 0.6,
                "forest": 0.75, "marsh": 0.75, "desert": 0.45, "steppe": 0.7}
TERRAIN_COST = {"farmland": 1.0, "plains": 1.0, "hills": 1.5, "mountains": 3.0,
                "forest": 1.6, "marsh": 2.0, "desert": 2.0, "steppe": 1.2}
SEA_COST = 0.35
PRICE_SPEED = 0.25
PRICE_MIN, PRICE_MAX = 0.2, 5.0
SAT_SPEED = 0.2
TAX_RAW, TAX_CRAFT = 0.025, 0.03
SECONDARY_FLOOR = 0.6
JOBS_PER_LEVEL = 2.5
WORKSHOP_SHARE = 0.7
MIN_SOLD = 0.25
EXCHANGE_PASSES = 3
EXCHANGE_RATE = 0.5
EXCHANGE_LOSS = 0.1
FAMILY = {**{r: "christian" for r in "catholic hussite orthodox bosnian coptic ethiopian armenian syriac nestorian".split()},
          **{r: "muslim" for r in "sunni twelver zaydi ismaili ibadi druze alawite yazidi".split()},
          **{r: "dharmic" for r in "hindu jain theravada tibetan".split()},
          "zoroastrian": "iranian", "jewish": "jewish", "tengri": "pagan", "folk": "pagan"}


def km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 12742 * math.asin(math.sqrt(h))


def assign_markets(scen, centres):
    """Multi-source Dijkstra over land neighbours and sea zones."""
    prov = scen["provinces"]
    n = len(prov)
    loc = [(p["latitude"], p["longitude"]) for p in prov]
    seas = scen["seaZones"]
    sea_loc = []
    for z in seas:
        pts = [loc[i] for i in z["coast"]] or [(0, 0)]
        sea_loc.append((sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)))
    prov_seas = defaultdict(list)
    for zi, z in enumerate(seas):
        for pi in z["coast"]:
            prov_seas[pi].append(zi)
    dist = [math.inf] * (n + len(seas))
    owner = [-1] * (n + len(seas))
    heap = []
    for m, c in enumerate(centres):
        dist[c] = 0
        owner[c] = m
        heap.append((0.0, c, m))
    heapq.heapify(heap)
    while heap:
        d, u, m = heapq.heappop(heap)
        if d > dist[u]:
            continue
        edges = []
        if u < n:
            for v in prov[u]["adjacent"]:
                c = km(loc[u], loc[v]) * (TERRAIN_COST[prov[u]["terrain"]] + TERRAIN_COST[prov[v]["terrain"]]) / 2
                edges.append((v, c))
            for z in prov_seas[u]:
                edges.append((n + z, km(loc[u], sea_loc[z]) * SEA_COST + 50))
        else:
            z = u - n
            for w in seas[z]["adjacent"]:
                edges.append((n + w, km(sea_loc[z], sea_loc[w]) * SEA_COST))
            for pi in seas[z]["coast"]:
                edges.append((pi, km(sea_loc[z], loc[pi]) * SEA_COST + 50))
        for v, c in edges:
            nd = d + c
            if nd < dist[v]:
                dist[v] = nd
                owner[v] = m
                heapq.heappush(heap, (nd, v, m))
    return owner[:n]


def craft_factor(recipe, avail):
    """First input is essential; the others only slow the workshop."""
    ins = recipe["inputs"]
    if not ins:
        return 1.0
    f = avail[ins[0][0]]
    for ig, _ in ins[1:]:
        f *= SECONDARY_FLOOR + (1 - SECONDARY_FLOOR) * avail[ig]
    return f


def market_links(scen, market_of, M):
    """Pairs of markets that touch by land or share a sea zone."""
    links = set()
    prov = scen["provinces"]
    for i, p in enumerate(prov):
        for j in p["adjacent"]:
            a, b = market_of[i], market_of[j]
            if a != b:
                links.add((min(a, b), max(a, b)))
    for z in scen["seaZones"]:
        ms = sorted({market_of[i] for i in z["coast"]})
        for x in range(len(ms)):
            for y in range(x + 1, len(ms)):
                links.add((ms[x], ms[y]))
    for z in scen["seaZones"]:
        for w in z["adjacent"]:
            for i in z["coast"]:
                for j in scen["seaZones"][w]["coast"]:
                    a, b = market_of[i], market_of[j]
                    if a != b:
                        links.add((min(a, b), max(a, b)))
    return sorted(links)


def exchange(S, D, links, G):
    """Surplus flows to neighbouring markets that are short."""
    for _ in range(EXCHANGE_PASSES):
        for a, b in links:
            Sa, Sb, Da, Db = S[a], S[b], D[a], D[b]
            for g in range(G):
                ea = Sa[g] - Da[g]
                eb = Sb[g] - Db[g]
                if ea > 0 and eb < 0:
                    t = EXCHANGE_RATE * min(ea, -eb)
                    Sa[g] -= t
                    Sb[g] += t * (1 - EXCHANGE_LOSS)
                elif eb > 0 and ea < 0:
                    t = EXCHANGE_RATE * min(eb, -ea)
                    Sb[g] -= t
                    Sa[g] += t * (1 - EXCHANGE_LOSS)


def classes(p):
    dev = p["development"]
    pop = p["population"] / 1000
    burg = (0.02 + 0.016 * dev) * pop
    nob = 0.015 * pop
    cle = 0.015 * pop
    return {"burghers": burg, "nobles": nob, "clergy": cle, "peasants": pop - burg - nob - cle, "slaves": 0}


def main(months):
    scen = json.loads((RES / "scenario1453.json").read_text())
    eco = json.loads((RES / "economy1453.json").read_text())
    goods, recipes, needs, markets = eco["goods"], eco["recipes"], eco["needs"], eco["markets"]
    G, M = len(goods), len(markets)
    base = [g["basePrice"] for g in goods]
    market_of = assign_markets(scen, [m["centre"] for m in markets])
    prov = scen["provinces"]
    cls = [classes(p) for p in prov]
    fam = [FAMILY.get(max(p["pops"], key=lambda x: x[3])[1], "pagan") for p in prov]

    links = market_links(scen, market_of, M)
    print(len(links), "market links")
    price = [[base[g] for g in range(G)] for _ in range(M)]
    avail = [[1.0] * G for _ in range(M)]
    supply_prev = [[0.0] * G for _ in range(M)]
    sat = [defaultdict(lambda: 0.7) for _ in prov]
    imports = [[0.0] * G for _ in range(M)]
    for im in eco["imports"]:
        imports[im["market"]][im["good"]] += im["amount"]

    for month in range(months):
        S = [[imports[m][g] / 12 for g in range(G)] for m in range(M)]
        D = [[0.0] * G for _ in range(M)]
        raw_out = []  # (province, good, amount)
        craft_out = []  # (province, recipe, amount)
        for i, p in enumerate(prov):
            m = market_of[i]
            rural = cls[i]["peasants"] + cls[i]["slaves"]
            for pr in eco["producers"][i]:
                g = pr["good"]
                if pr["kind"] == "raw":
                    workers = rural * pr["share"]
                    if pr is eco["producers"][i][0]:
                        y = STAPLE_YIELD * TERRAIN_FOOD[p["terrain"]]
                    else:
                        y = goods[g]['yield']
                    out = workers * y / 12
                    S[m][g] += out
                    for bg, amt in goods[g].get("byproducts", []):
                        S[m][bg] += out * amt
                        raw_out.append((i, bg, out * amt))
                    raw_out.append((i, g, out))
            jobs = [(b, l * JOBS_PER_LEVEL) for b, l in eco["startBuildings"][i] if eco["buildings"][b]["effect"] == "workshop"]
            total = sum(j for _, j in jobs)
            fill = min(1.0, cls[i]["burghers"] * WORKSHOP_SHARE / total) if total else 0
            for b, j in jobs:
                    r = recipes[eco["buildings"][b]["recipe"]]
                    g = r["output"]
                    potential = j * fill * r["perThousand"] / 12
                    f = craft_factor(r, avail[m])
                    out = potential * f
                    for ig, amt in r["inputs"]:
                        D[m][ig] += potential * amt
                    S[m][g] += out
                    craft_out.append((i, eco["buildings"][b]["recipe"], out))
        # Needs
        need_alloc = []  # per province: list of (need, [(g, share)], amount)
        for i, p in enumerate(prov):
            m = market_of[i]
            alloc = []
            for k, nd in enumerate(needs):
                if nd.get("only") and fam[i] != nd["only"]:
                    continue
                if nd.get("not") and fam[i] == nd["not"]:
                    continue
                size = cls[i][nd["socialClass"]]
                if size <= 0:
                    continue
                amount = nd["amount"] * size / 12
                ws = [max(S[m][g], 0) for g in nd["goods"]]
                tot = sum(ws)
                shares = [w / tot for w in ws] if tot > 0 else [1 / len(ws)] * len(ws)
                for g, s in zip(nd["goods"], shares):
                    D[m][g] += amount * s
                alloc.append((k, list(zip(nd["goods"], shares)), amount, nd["socialClass"]))
            need_alloc.append(alloc)
        exchange(S, D, links, G)
        # Clearing
        met = [[1.0] * G for _ in range(M)]
        sold = [[1.0] * G for _ in range(M)]
        for m in range(M):
            for g in range(G):
                s, d = S[m][g], D[m][g]
                if d <= 0:
                    met[m][g] = 1.0
                    sold[m][g] = MIN_SOLD if s > 0 else 1.0
                    target = base[g] * PRICE_MIN
                elif s <= 0:
                    met[m][g] = 0.0
                    target = base[g] * PRICE_MAX
                else:
                    met[m][g] = min(1.0, s / d)
                    sold[m][g] = max(MIN_SOLD, min(1.0, d / s))
                    target = base[g] * min(PRICE_MAX, max(PRICE_MIN, math.sqrt(d / s)))
                price[m][g] += PRICE_SPEED * (target - price[m][g])
                avail[m][g] = met[m][g]
        # Satisfaction
        for i in range(len(prov)):
            m = market_of[i]
            byclass = defaultdict(lambda: [0.0, 0.0])
            for k, sh, amount, c in need_alloc[i]:
                value = amount * sum(base[g] * s for g, s in sh)
                ful = sum(met[m][g] * s for g, s in sh)
                byclass[c][0] += value * ful
                byclass[c][1] += value
            for c, (a, b) in byclass.items():
                sat[i][c] += SAT_SPEED * (a / b - sat[i][c])
        # Money
        income = defaultdict(float)
        old = defaultdict(float)
        for i, g, out in raw_out:
            m = market_of[i]
            v = out * price[m][g] * sold[m][g]
            if prov[i]["owner"]:
                income[prov[i]["owner"]] += v * TAX_RAW
        for i, r, out in craft_out:
            m = market_of[i]
            rec = recipes[r]
            v = out * (price[m][rec["output"]] * sold[m][rec["output"]] - sum(price[m][ig] * a for ig, a in rec["inputs"]))
            if prov[i]["owner"]:
                income[prov[i]["owner"]] += max(0, v) * TAX_CRAFT
        for p in prov:
            if p["owner"]:
                old[p["owner"]] += (p["development"] * 1.4 + 0.2) / 12

    # Report
    print(f"after {months} months")
    gs = defaultdict(float); gd = defaultdict(float)
    for m in range(M):
        for g in range(G):
            gs[g] += S[m][g]; gd[g] += D[m][g]
    print("good           supply  demand  ratio  price range")
    for g in range(G):
        ps = [price[m][g] / base[g] for m in range(M)]
        print(f"{goods[g]['key']:14s} {gs[g]*12:8.1f} {gd[g]*12:8.1f} {gs[g]/gd[g] if gd[g] else 0:6.2f}  {min(ps):.2f}-{max(ps):.2f}")
    for c in ["peasants", "burghers", "clergy", "nobles"]:
        vals = [sat[i][c] for i in range(len(prov)) if cls[i][c] > 0]
        print(c, "satisfaction avg", round(sum(vals) / len(vals), 2), "min", round(min(vals), 2), "max", round(max(vals), 2))
    for t in ["TUR", "FRA", "VEN", "MAM", "VIJ", "DEL", "ENG", "MOS", "BNG", "POR"]:
        print(t, "income/month new", round(income[t], 1), "old", round(old[t], 1))
    print("market sizes", sorted(((market_of.count(m), markets[m]["name"]) for m in range(M)), reverse=True)[:8], "...",
          sorted(((market_of.count(m), markets[m]["name"]) for m in range(M)))[:5])
    json.dump({"marketOf": market_of}, open("/tmp/market_of.json", "w"))


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 24)
