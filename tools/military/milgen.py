#!/usr/bin/env python3
"""
Generate Packages/GezCore/Sources/GezCore/Resources/military1453.json from:
  - data/military/units.txt
  - data/military/armies_1453.txt
  - Packages/GezCore/Sources/GezCore/Resources/scenario1453.json
  - Packages/GezCore/Sources/GezCore/Resources/economy1453.json
  - Packages/GezCore/Sources/GezCore/Resources/government1453.json
  - Packages/GezCore/Sources/GezCore/Resources/characters1453.json

Run from repo root:
    python3 tools/military/milgen.py
"""

from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "military"
RES = ROOT / "Packages" / "GezCore" / "Sources" / "GezCore" / "Resources"
SCENARIO = RES / "scenario1453.json"
ECONOMY = RES / "economy1453.json"
GOVERNMENT = RES / "government1453.json"
CHARACTERS = RES / "characters1453.json"
OUT = RES / "military1453.json"

CATEGORIES = {"infantry", "cavalry", "ranged", "artillery"}
ORIGINS = {"professional", "mercenary", "levy"}
GOVERNMENTS = {
    "monarchy", "feudalMonarchy", "electiveMonarchy", "iqta", "sultanate",
    "imperial", "timuridPrincedom", "mamlukSultanate", "merchantRepublic",
    "signoria", "oligarchicRepublic", "freeCity", "peasantRepublic",
    "confederation", "papacy", "theocracy", "monasticOrder", "steppeHorde",
    "tribalFederation", "tribalKingdom", "iqtaEmirate",
}


def rows(name: str):
    path = DATA / name
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        yield lineno, [p.strip() for p in line.split("|")]


def parse_goods(cell: str, known_goods: set[str], ctx: str) -> dict[str, float]:
    out: dict[str, float] = {}
    if not cell:
        return out
    for part in cell.split(","):
        part = part.strip()
        if not part:
            continue
        toks = part.split()
        if len(toks) != 2:
            raise SystemExit(f"{ctx}: expected '<good> <amount>', got '{part}'")
        good, amt_s = toks
        if good not in known_goods:
            raise SystemExit(f"{ctx}: unknown good '{good}'")
        amt = float(amt_s)
        if amt <= 0:
            raise SystemExit(f"{ctx}: non-positive good amount '{part}'")
        out[good] = amt
    return out


def parse_requires(
    cell: str,
    known_estates: set[str],
    known_cultures: set[str],
    known_regions: set[str],
    known_tags: set[str],
    ctx: str,
) -> list[dict]:
    rules: list[dict] = []
    if not cell:
        return rules
    for clause in cell.split(";"):
        clause = clause.strip()
        if not clause:
            continue
        if ":" not in clause:
            raise SystemExit(f"{ctx}: bad requires clause '{clause}'")
        kind, raw_vals = [x.strip() for x in clause.split(":", 1)]
        vals = [v.strip() for v in raw_vals.split(",") if v.strip()]
        if not vals:
            raise SystemExit(f"{ctx}: empty requires values in '{clause}'")
        if kind == "estate":
            for v in vals:
                if v not in known_estates:
                    raise SystemExit(f"{ctx}: unknown estate '{v}'")
        elif kind == "government":
            for v in vals:
                if v not in GOVERNMENTS:
                    raise SystemExit(f"{ctx}: unknown government '{v}'")
        elif kind == "culture":
            for v in vals:
                if v not in known_cultures:
                    raise SystemExit(f"{ctx}: unknown culture '{v}'")
        elif kind == "region":
            for v in vals:
                if v not in known_regions:
                    raise SystemExit(f"{ctx}: unknown region '{v}'")
        elif kind == "tags":
            for v in vals:
                if v not in known_tags:
                    raise SystemExit(f"{ctx}: unknown country tag '{v}'")
        else:
            raise SystemExit(f"{ctx}: unknown requirement kind '{kind}'")
        rules.append({"kind": kind, "values": vals})
    return rules


def load_units(
    known_goods: set[str],
    known_estates: set[str],
    known_cultures: set[str],
    known_regions: set[str],
    known_tags: set[str],
) -> tuple[list[dict], dict[str, int]]:
    units: list[dict] = []
    index: dict[str, int] = {}
    for lineno, parts in rows("units.txt"):
        ctx = f"units.txt:{lineno}"
        if len(parts) != 13:
            raise SystemExit(f"{ctx}: expected 13 columns, got {len(parts)}")
        (
            key, name, category, men_s, speed_s,
            atk_s, def_s, morale_s, siege_s,
            cost_s, upkeep_s, goods_s, req_s,
        ) = parts
        if key in index:
            raise SystemExit(f"{ctx}: duplicate unit key '{key}'")
        if category not in CATEGORIES:
            raise SystemExit(f"{ctx}: unknown category '{category}'")
        men = int(men_s)
        speed = float(speed_s)
        attack = float(atk_s)
        defence = float(def_s)
        morale = float(morale_s)
        siege = float(siege_s)
        cost = float(cost_s)
        upkeep = float(upkeep_s)
        if men <= 0 or speed <= 0 or morale <= 0 or cost <= 0 or upkeep < 0:
            raise SystemExit(f"{ctx}: invalid numeric stats on '{key}'")
        goods = parse_goods(goods_s, known_goods, ctx)
        requires = parse_requires(
            req_s, known_estates, known_cultures, known_regions, known_tags, ctx
        )
        index[key] = len(units)
        units.append({
            "key": key,
            "name": name,
            "category": category,
            "men": men,
            "speed": speed,
            "attack": attack,
            "defence": defence,
            "morale": morale,
            "siege": siege,
            "cost": cost,
            "upkeep": upkeep,
            "goods": goods,
            "requires": requires,
        })
    return units, index


def load_armies(
    unit_index: dict[str, int],
    units: list[dict],
    provinces_by_name: dict[str, tuple[int, str | None]],
    known_tags: set[str],
    chars_by_id: dict[str, dict],
) -> list[dict]:
    armies: list[dict] = []
    used_commanders: set[str] = set()
    for lineno, parts in rows("armies_1453.txt"):
        ctx = f"armies_1453.txt:{lineno}"
        if len(parts) != 5:
            raise SystemExit(f"{ctx}: expected 5 columns, got {len(parts)}")
        tag, name, prov_name, commander_id, regs_s = parts
        if tag not in known_tags:
            raise SystemExit(f"{ctx}: unknown country tag '{tag}'")
        if prov_name not in provinces_by_name:
            raise SystemExit(f"{ctx}: unknown province '{prov_name}'")
        prov_id, prov_owner = provinces_by_name[prov_name]
        if prov_owner != tag:
            raise SystemExit(
                f"{ctx}: province '{prov_name}' is owned by '{prov_owner}', not '{tag}'"
            )
        commander: str | None = None
        if commander_id and commander_id != "-":
            ch = chars_by_id.get(commander_id)
            if ch is None:
                raise SystemExit(f"{ctx}: unknown character '{commander_id}'")
            if ch.get("died") is not None:
                raise SystemExit(f"{ctx}: commander '{commander_id}' is already dead")
            if ch.get("country") != tag:
                raise SystemExit(
                    f"{ctx}: commander '{commander_id}' belongs to '{ch.get('country')}', not '{tag}'"
                )
            if commander_id in used_commanders:
                raise SystemExit(
                    f"{ctx}: commander '{commander_id}' assigned to multiple armies"
                )
            used_commanders.add(commander_id)
            commander = commander_id

        regiments: list[dict] = []
        for entry in regs_s.split(","):
            entry = entry.strip()
            if not entry:
                continue
            origin = "professional"
            if "@" in entry:
                entry, origin = [x.strip() for x in entry.split("@", 1)]
                if origin not in ORIGINS:
                    raise SystemExit(f"{ctx}: unknown origin '{origin}'")
            if ":" not in entry:
                raise SystemExit(f"{ctx}: expected '<unit>:<count>', got '{entry}'")
            ukey, count_s = [x.strip() for x in entry.split(":", 1)]
            if ukey not in unit_index:
                raise SystemExit(f"{ctx}: unknown unit key '{ukey}'")
            count = int(count_s)
            if count <= 0:
                raise SystemExit(f"{ctx}: non-positive regiment count in '{entry}'")
            utype = units[unit_index[ukey]]
            for _ in range(count):
                regiments.append({
                    "type": ukey,
                    "origin": origin,
                    "men": utype["men"],
                })
        if not regiments:
            raise SystemExit(f"{ctx}: army '{name}' has no regiments")
        armies.append({
            "country": tag,
            "name": name,
            "province": prov_id,
            "commander": commander,
            "regiments": regiments,
        })
    return armies


def main():
    scenario = json.loads(SCENARIO.read_text(encoding="utf-8"))
    economy = json.loads(ECONOMY.read_text(encoding="utf-8"))
    government = json.loads(GOVERNMENT.read_text(encoding="utf-8"))
    characters = json.loads(CHARACTERS.read_text(encoding="utf-8"))

    known_goods = {g["key"] for g in economy["goods"]}
    known_estates = {e["key"] for e in government["estates"]}
    known_cultures = {c["id"] for c in scenario["cultures"]}
    known_regions = set(scenario["regions"])
    known_tags = {c["tag"] for c in scenario["countries"]}
    provinces_by_name = {
        p["name"]: (idx, p["owner"]) for idx, p in enumerate(scenario["provinces"])
    }
    chars_by_id = {c["id"]: c for c in characters["characters"]}

    units, unit_index = load_units(
        known_goods, known_estates, known_cultures, known_regions, known_tags
    )
    armies = load_armies(
        unit_index, units, provinces_by_name, known_tags, chars_by_id
    )

    payload = {
        "units": units,
        "armies": armies,
    }
    OUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    total_regs = sum(len(a["regiments"]) for a in armies)
    total_men = sum(r["men"] for a in armies for r in a["regiments"])
    print(
        f"Wrote {OUT.relative_to(ROOT)}: "
        f"{len(units)} unit types, {len(armies)} starting armies, "
        f"{total_regs} regiments ({total_men:,} standing troops)"
    )


if __name__ == "__main__":
    main()
