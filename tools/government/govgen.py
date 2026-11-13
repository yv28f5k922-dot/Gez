#!/usr/bin/env python3
"""Build the government part of the 1453 scenario (Phase 5).

Reads data/government/*.txt and the map scenario, validates them and writes
Packages/GezCore/Sources/GezCore/Resources/government1453.json: law areas
and options, estates, privileges, reform trees, and for every country its
1453 laws, reforms and estates.

Run after mapgen.py:  python3 tools/government/govgen.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data/government"
RES = ROOT / "Packages/GezCore/Sources/GezCore/Resources"

MODIFIERS = """tax trade build_cost interest learning reform_progress stability_cost
vassal_keep vassal_opinion crown_power mood_nobles mood_clergy mood_burghers
mood_peasants mood_other_faith tax_nobles tax_clergy tax_burghers tax_peasants
inflation_decay no_debase manpower levy_size army_quality fort_defence""".split()
GOVERNMENTS = ["monarchy", "republic", "theocracy", "steppeHorde", "tribal"]
MUSLIM = set("sunni twelver zaydi ismaili ibadi druze alawite yazidi".split())
CHRISTIAN = set("catholic hussite orthodox bosnian coptic ethiopian armenian syriac nestorian".split())
DHARMIC = set("hindu jain theravada tibetan".split())


def rows(name):
    for line in (DATA / name).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            yield [x.strip() for x in line.split("|")]


def main():
    scen = json.loads((RES / "scenario1453.json").read_text())
    tags = {c["tag"]: c for c in scen["countries"]}
    culture_keys = {c["id"] for c in scen["cultures"]}

    estates, estate_index = [], {}
    tribal, rajput = [], []
    where = {}
    loyal, disloyal = {}, {}
    for r in rows("estates.txt"):
        kind = r[0]
        if kind == "estate":
            _, key, name, source, weight = r[:5]
            estate_index[key] = len(estates)
            estates.append({"key": key, "name": name, "source": source,
                            "weight": float(weight) if weight else 0.0})
        elif kind == "where":
            where.setdefault(r[1], []).append(r[2])
        elif kind == "tribal_cultures":
            tribal = [c.strip() for c in r[1].split(",")]
        elif kind == "rajput_cultures":
            rajput = [c.strip() for c in r[1].split(",")]
        elif kind == "loyal":
            loyal[r[1]] = r[2]
        elif kind == "disloyal":
            disloyal[r[1]] = r[2]
    for c in tribal + rajput:
        if c not in culture_keys:
            sys.exit(f"estates: unknown culture '{c}'")

    def effects(text, where_):
        out = {"m": {}, "l": {}, "p": {}}
        for tok in (text or "").split():
            k, v = tok.split("=")
            v = float(v)
            if ":" in k:
                kind, est = k.split(":")
                if est not in estate_index:
                    sys.exit(f"{where_}: unknown estate '{est}'")
                out["l" if kind == "loyalty" else "p"][est] = v
            elif k in MODIFIERS:
                out["m"][k] = v
            else:
                sys.exit(f"{where_}: unknown effect '{k}'")
        return out

    for e in estates:
        e["loyal"] = effects(loyal.get(e["key"]), f"loyal {e['key']}")
        e["disloyal"] = effects(disloyal.get(e["key"]), f"disloyal {e['key']}")

    privileges = []
    for r in rows("privileges.txt"):
        _, est, key, name, loy, power, eff = r[:7]
        gold = r[7] if len(r) > 7 else ""
        if est not in estate_index:
            sys.exit(f"privilege {key}: unknown estate {est}")
        privileges.append({"estate": est, "key": key, "name": name, "loyalty": float(loy),
                           "power": float(power), "effects": effects(eff, key),
                           "gold": float(gold) if gold else 0.0})

    areas, area_index = [], {}
    for r in rows("laws.txt"):
        if r[0] == "area":
            area_index[r[1]] = len(areas)
            areas.append({"key": r[1], "name": r[2], "options": []})
        elif r[0] == "option":
            _, area, key, name, eff = r[:5]
            govs = r[5].split() if len(r) > 5 and r[5] else []
            for g in govs:
                if g not in GOVERNMENTS:
                    sys.exit(f"law {key}: unknown government {g}")
            areas[area_index[area]]["options"].append(
                {"key": key, "name": name, "effects": effects(eff, key), "governments": govs})

    reforms = {g: [] for g in GOVERNMENTS}
    for r in rows("reforms.txt"):
        if r[0] == "tier":
            _, g, n, cost = r[:4]
            reforms[g].append({"cost": float(cost), "options": []})
            assert len(reforms[g]) == int(n), f"tiers of {g} out of order"
        elif r[0] == "reform":
            _, g, n, key, name, eff = r[:6]
            becomes = r[6] if len(r) > 6 and r[6] else None
            if becomes and becomes not in GOVERNMENTS:
                sys.exit(f"reform {key}: unknown government {becomes}")
            reforms[g][int(n) - 1]["options"].append(
                {"key": key, "name": name, "effects": effects(eff, key), "becomes": becomes})
    for g, tiers in reforms.items():
        if not tiers:
            sys.exit(f"no reforms for {g}")

    # Country populations by culture/religion, for regional estates.
    cultures = [c["id"] for c in scen["cultures"]]
    by_country = {t: {} for t in tags}
    for p in scen["provinces"]:
        o = p.get("owner")
        if not o:
            continue
        for cult, rel, _sect, share in p.get("pops") or []:
            key = (cultures[cult] if isinstance(cult, int) else cult, rel)
            by_country[o][key] = by_country[o].get(key, 0) + share * (p.get("population") or 0)

    def religion_family(rel):
        return "muslim" if rel in MUSLIM else "christian" if rel in CHRISTIAN else "dharmic" if rel in DHARMIC else "other"

    def regional(tag, est):
        c = tags[tag]
        pops = by_country[tag]
        total = sum(pops.values()) or 1
        for rule in where.get(est, []):
            if rule.startswith("tags:"):
                listed = rule[5:].split(",")
                for t in listed:
                    if t not in tags:
                        sys.exit(f"where {est}: unknown tag {t}")
                if tag in listed and (est not in ("tribes",) or any(cu in tribal for cu, _ in pops)):
                    return True
            elif rule == "muslim":
                if c["religion"] in MUSLIM and sum(v for (cu, r), v in pops.items() if r not in MUSLIM) / total > 0.03:
                    return True
            elif rule == "india":
                if sum(v for (cu, r), v in pops.items() if cu in rajput and r == "hindu") / total > 0.05:
                    return True
            elif rule.startswith("government:"):
                if c["government"] in rule[11:].split(","):
                    return True
        return False

    # 1453 laws.
    defaults, sets, start_reforms, stability = [], {}, {}, {}
    for r in rows("laws_1453.txt"):
        if r[0] == "default":
            defaults.append((r[1], r[2], r[3]))
        elif r[0] == "set":
            if r[1] not in tags:
                sys.exit(f"laws_1453: unknown tag {r[1]}")
            sets.setdefault(r[1], {})[r[2]] = r[3]
        elif r[0] == "stability":
            if r[1] not in tags:
                sys.exit(f"laws_1453: unknown tag {r[1]}")
            stability[r[1]] = max(-3, min(3, int(r[2])))
        elif r[0] == "reform":
            if r[1] not in tags:
                sys.exit(f"laws_1453: unknown tag {r[1]}")
            start_reforms.setdefault(r[1], []).append(r[2])

    def option_index(area, key, gov, where_):
        opts = areas[area_index[area]]["options"]
        for i, o in enumerate(opts):
            if o["key"] == key:
                if o["governments"] and gov not in o["governments"]:
                    sys.exit(f"{where_}: {key} not allowed for {gov}")
                return i
        sys.exit(f"{where_}: unknown option {area}/{key}")

    countries = {}
    for tag, c in tags.items():
        gov, fam = c["government"], religion_family(c["religion"])
        laws = {}
        for area, opt, cond in defaults:
            ok = cond == "all" \
                or (cond.startswith("government:") and gov in cond[11:].split(",")) \
                or (cond.startswith("religion:") and fam == cond[9:]) \
                or (cond.startswith("tags:") and tag in cond[5:].split(","))
            if ok:
                laws[area] = opt
        laws.update(sets.get(tag, {}))
        law_idx = {a: option_index(a, k, gov, tag) for a, k in laws.items() if a != "succession"}

        tiers = reforms[gov]
        chosen = []
        wanted = start_reforms.get(tag, [])
        for t, tier in enumerate(tiers):
            keys = [o["key"] for o in tier["options"]]
            pick = next((w for w in wanted if w in keys), None)
            if pick is None:
                if t > 0 and not any(w in [o["key"] for tt in tiers[t:] for o in tt["options"]] for w in wanted):
                    break
                if t > 0:
                    pick = keys[0]
                elif gov == "monarchy":
                    pick = "sultanate" if fam == "muslim" else "feudal_monarchy"
                elif gov == "theocracy":
                    pick = "imamate" if fam == "muslim" else "prince_bishopric"
                elif gov == "republic":
                    pick = "noble_republic"
                else:
                    pick = keys[0]
            chosen.append(keys.index(pick))
        for w in wanted:
            if not any(w == tiers[t]["options"][i]["key"] for t, i in enumerate(chosen)):
                sys.exit(f"{tag}: reform {w} does not fit its {gov} tree")

        est = [e["key"] for e in estates if e["source"].startswith("class:")]
        est += [e["key"] for e in estates if not e["source"].startswith("class:") and regional(tag, e["key"])]
        countries[tag] = {"laws": law_idx, "reforms": chosen, "estates": est, "stability": stability.get(tag, 1)}

    out = {"modifiers": MODIFIERS, "estates": estates, "tribalCultures": tribal,
           "rajputCultures": rajput, "privileges": privileges, "lawAreas": areas,
           "reforms": reforms, "countries": countries}
    (RES / "government1453.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    counts = {}
    for c in countries.values():
        for e in c["estates"]:
            counts[e] = counts.get(e, 0) + 1
    print(f"{len(areas)} law areas, {len(privileges)} privileges, "
          f"{sum(len(t['options']) for g in reforms.values() for t in g)} reforms; estates: {counts}")


if __name__ == "__main__":
    main()
