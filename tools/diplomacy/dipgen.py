#!/usr/bin/env python3
"""
Generate Packages/GezCore/Sources/GezCore/Resources/diplomacy1453.json from:
  - data/diplomacy/treaties_1453.txt
  - data/diplomacy/wars_1453.txt
  - Packages/GezCore/Sources/GezCore/Resources/scenario1453.json

Run from repo root:
    python3 tools/diplomacy/dipgen.py
"""

from __future__ import annotations
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "diplomacy"
RES = ROOT / "Packages" / "GezCore" / "Sources" / "GezCore" / "Resources"
SCENARIO = RES / "scenario1453.json"
OUT = RES / "diplomacy1453.json"

VALID_TREATY_TYPES = {
    "alliance",
    "guarantee",
    "non_aggression",
    "military_access",
    "truce",
}

VALID_CBS = {
    "reconquest",
    "claim",
    "holyWar",
    "subjugation",
    "tribute",
    "succession",
    "coalition",
    "noCB",
}

VALID_WAR_GOAL_TYPES = {
    "conquer_province",
    "superiority",
    "defend_capital",
}


def rows(name: str):
    path = DATA / name
    if not path.exists():
        raise SystemExit(f"Missing file: {path}")
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        yield lineno, [p.strip() for p in line.split("|")]


def main():
    if not SCENARIO.exists():
        raise SystemExit(f"Missing scenario file: {SCENARIO}")

    scenario = json.loads(SCENARIO.read_text(encoding="utf-8"))
    valid_tags = {c["tag"] for c in scenario["countries"]}
    valid_provinces = {p["name"] for p in scenario["provinces"]}

    treaties = []
    for lineno, parts in rows("treaties_1453.txt"):
        if len(parts) < 4:
            raise SystemExit(f"treaties_1453.txt:{lineno}: expected at least 4 columns, got {len(parts)}")
        tag_a, tag_b, t_type, expiry = parts[0], parts[1], parts[2], parts[3]
        note = parts[4] if len(parts) > 4 else ""

        if tag_a not in valid_tags:
            raise SystemExit(f"treaties_1453.txt:{lineno}: unknown tag '{tag_a}'")
        if tag_b not in valid_tags:
            raise SystemExit(f"treaties_1453.txt:{lineno}: unknown tag '{tag_b}'")
        if tag_a == tag_b:
            raise SystemExit(f"treaties_1453.txt:{lineno}: self-treaty not allowed for '{tag_a}'")
        if t_type not in VALID_TREATY_TYPES:
            raise SystemExit(f"treaties_1453.txt:{lineno}: unknown treaty type '{t_type}'")

        expiry_val = None if expiry in ("-", "", "none") else expiry
        if t_type == "truce" and expiry_val is None:
            raise SystemExit(f"treaties_1453.txt:{lineno}: truce must specify an expiry date")

        treaties.append({
            "firstTag": tag_a,
            "secondTag": tag_b,
            "type": t_type,
            "expiry": expiry_val,
            "note": note,
        })

    wars = []
    for lineno, parts in rows("wars_1453.txt"):
        if len(parts) < 7:
            raise SystemExit(f"wars_1453.txt:{lineno}: expected at least 7 columns, got {len(parts)}")
        war_id, name, start_date, cb, goal_str, attackers_str, defenders_str = parts[:7]
        note = parts[7] if len(parts) > 7 else ""

        if cb not in VALID_CBS:
            raise SystemExit(f"wars_1453.txt:{lineno}: unknown CB '{cb}'")

        goal_parts = goal_str.split(":", 1)
        if len(goal_parts) != 2:
            raise SystemExit(f"wars_1453.txt:{lineno}: invalid war goal '{goal_str}', expected type:target")
        goal_type, goal_target = goal_parts
        if goal_type not in VALID_WAR_GOAL_TYPES:
            raise SystemExit(f"wars_1453.txt:{lineno}: unknown war goal type '{goal_type}'")

        if goal_type in ("conquer_province", "defend_capital"):
            if goal_target not in valid_provinces:
                raise SystemExit(f"wars_1453.txt:{lineno}: unknown province '{goal_target}' for war goal")

        attackers = [t.strip() for t in attackers_str.split(",") if t.strip()]
        defenders = [t.strip() for t in defenders_str.split(",") if t.strip()]

        if not attackers:
            raise SystemExit(f"wars_1453.txt:{lineno}: war must have at least one attacker")
        if not defenders:
            raise SystemExit(f"wars_1453.txt:{lineno}: war must have at least one defender")

        for tag in attackers:
            if tag not in valid_tags:
                raise SystemExit(f"wars_1453.txt:{lineno}: unknown attacker tag '{tag}'")
        for tag in defenders:
            if tag not in valid_tags:
                raise SystemExit(f"wars_1453.txt:{lineno}: unknown defender tag '{tag}'")

        # Attackers and defenders must be disjoint
        common = set(attackers).intersection(set(defenders))
        if common:
            raise SystemExit(f"wars_1453.txt:{lineno}: tags {common} cannot be on both sides of war")

        wars.append({
            "id": war_id,
            "name": name,
            "startDate": start_date,
            "casusBelli": cb,
            "warGoalType": goal_type,
            "warGoalTarget": goal_target if goal_target != "-" else None,
            "attackers": attackers,
            "defenders": defenders,
            "note": note,
        })

    payload = {
        "treaties": treaties,
        "wars": wars,
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    out_json = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    OUT.write_text(out_json, encoding="utf-8")
    print(f"Generated {OUT} with {len(treaties)} treaties and {len(wars)} active wars.")


if __name__ == "__main__":
    main()
