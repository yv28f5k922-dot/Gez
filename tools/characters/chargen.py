#!/usr/bin/env python3
"""Build the 1453 characters: real people from data/characters/people_1453.txt,
plus invented ones where history is silent (owner's rule: a country with no
one recorded gets an invented ruler and an invented sibling heir), and an
invented courtier for every council seat no real figure fills.

Writes Packages/GezCore/Sources/GezCore/Resources/characters1453.json.
Run after mapgen.py:  python3 tools/characters/chargen.py
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data/characters"
RES = ROOT / "Packages/GezCore/Sources/GezCore/Resources"
START_YEAR = 1453
MUSLIM = {"sunni", "twelver", "zaydi", "ismaili", "ibadi", "druze", "alawite", "yazidi"}
SKILLS = ["diplomacy", "martial", "stewardship", "intrigue", "learning"]
# Council seat -> skill it uses.
COUNCIL = [("chancellor", 0), ("marshal", 1), ("steward", 2), ("spymaster", 3), ("chaplain", 4)]


def h(*parts):
    return int(hashlib.sha1("/".join(map(str, parts)).encode()).hexdigest()[:8], 16)


def rows(path):
    for line in path.read_text().splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            yield s


def main():
    scen = json.loads((RES / "scenario1453.json").read_text())
    cultures = scen["cultures"]
    culture_family = {c["id"]: c["family"] for c in cultures}
    countries = {c["tag"]: c for c in scen["countries"]}
    provinces = scen["provinces"]
    province_names = {p["name"]: i for i, p in enumerate(provinces)}

    names = {}
    for line in rows(DATA / "names.txt"):
        fam, male, female = [x.strip() for x in line.split("|")]
        names[fam] = ([n.strip() for n in male.split(",")], [n.strip() for n in female.split(",")])

    traits = {}
    for line in rows(DATA / "traits.txt"):
        key, name, opposite, mods = [x.strip() for x in line.split("|")]
        traits[key] = {"key": key, "name": name, "opposite": opposite or None,
                       "skills": [int(v) for v in mods.split()]}
    trait_keys = list(traits)

    ruling_culture = {}
    totals = {}
    for p in provinces:
        tag = p.get("owner")
        if not tag:
            continue
        for cult, rel, _sect, share in p.get("pops") or []:
            if rel == countries[tag]["religion"]:
                key = (tag, cult)
                totals[key] = totals.get(key, 0) + share * (p.get("population") or 0)
    for (tag, cult), v in totals.items():
        if tag not in ruling_culture or v > totals[(tag, ruling_culture[tag])]:
            ruling_culture[tag] = cult

    def capital_culture(tag):
        """Main culture of the people who share the ruler's faith."""
        if tag in ruling_culture:
            return cultures[ruling_culture[tag]]["id"]
        p = provinces[countries[tag]["capital"]]
        best = max(p["pops"], key=lambda x: x[3]) if p.get("pops") else None
        return cultures[best[0]]["id"] if best else cultures[0]["id"]

    people = {}      # id -> dict
    order = []
    roles = {tag: {"ruler": None, "heir": None, "court": []} for tag in countries}

    def add_person(pid, **kw):
        if pid in people:
            sys.exit(f"duplicate person id {pid}")
        people[pid] = kw
        order.append(pid)

    holdings = {}    # province name -> person id
    links = []       # (person id, "f:x m:y s:z") added after everyone is read
    tag = None
    lines = []
    for path in sorted(DATA.glob("people_*.txt")):
        lines += list(rows(path))
    for line in lines:
        if line.startswith("@"):
            tag = line[1:].strip()
            if tag not in countries:
                sys.exit(f"people: unknown country {tag}")
            continue
        parts = [x.strip() for x in line.split("|")]
        role = parts[0]
        if role == "link":
            links.append((parts[1], parts[2]))
            continue
        if parts[1].startswith("="):
            ref = parts[1][1:]
            if role in ("ruler", "heir"):
                roles[tag][role] = ref
            else:
                roles[tag]["court"].append(ref)
            continue
        while len(parts) < 10:
            parts.append("")
        _, pid, name, dynasty, sex, born, rel, tr, note, cr = parts[:10]
        culture_override, religion_override = (cr.split() + [None, None])[:2] if cr else (None, None)
        if culture_override and culture_override not in culture_family:
            sys.exit(f"people: unknown culture {culture_override} for {pid}")
        relations = {}
        died = None
        illegitimate = False
        for item in rel.split():
            if item == "illegit":
                illegitimate = True
                continue
            k, v = item.split(":", 1)
            if k == "d":
                d = v.split("-")
                died = [int(d[0]), int(d[1]) if len(d) > 1 else 6, int(d[2]) if len(d) > 2 else 15]
            elif k == "holds":
                for prov in v.split(","):
                    prov = prov.replace("_", " ")
                    if prov not in province_names:
                        sys.exit(f"{pid}: holds unknown province '{prov}'")
                    if provinces[province_names[prov]].get("owner") != tag:
                        sys.exit(f"{pid}: holds {prov}, which {tag} does not own")
                    if prov in holdings:
                        sys.exit(f"{prov} held by both {holdings[prov]} and {pid}")
                    holdings[prov] = pid
            else:
                relations[k] = v.split(",")
        tlist = [t.strip() for t in tr.split(",") if t.strip()]
        for t in tlist:
            if t not in traits:
                sys.exit(f"people: unknown trait '{t}' for {pid}")
        b = born.split("-")
        add_person(pid, name=name, dynasty=dynasty or None, female=(sex == "f"),
                   born=[int(b[0]), int(b[1]) if len(b) > 1 else 1 + h(pid, "m") % 12,
                         int(b[2]) if len(b) > 2 else 1 + h(pid, "d") % 28],
                   father=relations.get("f", [None])[0], mother=relations.get("m", [None])[0],
                   spouses=relations.get("s", []), traits=tlist, country=tag,
                   culture=culture_override, religion=religion_override, invented=False, note=note or None,
                   died=died, illegitimate=illegitimate)
        if role in ("ruler", "heir"):
            roles[tag][role] = pid
        else:
            roles[tag]["court"].append(pid)

    for pid, rel in links:
        if pid not in people:
            sys.exit(f"link: unknown person {pid}")
        for item in rel.split():
            if item == "illegit":
                people[pid]["illegitimate"] = True
                continue
            k, v = item.split(":", 1)
            if k == "f":
                people[pid]["father"] = v
            elif k == "m":
                people[pid]["mother"] = v
            elif k == "s":
                people[pid]["spouses"] += [x for x in v.split(",") if x not in people[pid]["spouses"]]
            elif k == "holds":
                tag_of = people[pid]["country"]
                for prov in v.split(","):
                    prov = prov.replace("_", " ")
                    if prov not in province_names:
                        sys.exit(f"{pid}: holds unknown province '{prov}'")
                    if provinces[province_names[prov]].get("owner") != tag_of:
                        sys.exit(f"{pid}: holds {prov}, which {tag_of} does not own")
                    if prov in holdings:
                        sys.exit(f"{prov} held by both {holdings[prov]} and {pid}")
                    holdings[prov] = pid
            else:
                sys.exit(f"link: unknown relation {k}")

    # Check relations and make marriages two-way.
    for pid, p in people.items():
        for k in ("father", "mother"):
            if p[k] and p[k] not in people:
                sys.exit(f"{pid}: unknown {k} {p[k]}")
        for s in p["spouses"]:
            if s not in people:
                sys.exit(f"{pid}: unknown spouse {s}")
            if pid not in people[s]["spouses"]:
                people[s]["spouses"].append(pid)

    def invent(tag, kind, female=False, age=None, dynasty=None, culture=None, salt=""):
        culture = culture or capital_culture(tag)
        fam = culture_family.get(culture, "arab")
        muslim = countries[tag]["religion"] in MUSLIM
        male_names, female_names = names.get(f"{fam}@muslim" if muslim and f"{fam}@muslim" in names else fam, names["arab"])
        pool = female_names if female else male_names
        pid = f"inv_{tag.lower()}_{kind}{salt}"
        k = 0
        while pid in people:
            k += 1
            pid = f"inv_{tag.lower()}_{kind}{salt}_{k}"
        given = pool[h(pid, "name") % len(pool)]
        age = age if age is not None else 25 + h(pid, "age") % 30
        n_traits = 1 + h(pid, "nt") % 2
        tlist = []
        for j in range(n_traits):
            t = trait_keys[h(pid, "t", j) % len(trait_keys)]
            if t in tlist or t in ("blind",) or (traits[t]["opposite"] in tlist):
                continue
            tlist.append(t)
        add_person(pid, name=given, dynasty=dynasty, female=female,
                   born=[START_YEAR - age, 1 + h(pid, "m") % 12, 1 + h(pid, "d") % 28],
                   father=None, mother=None, spouses=[], traits=tlist, country=tag,
                   culture=culture, religion=None, invented=True, note=None, died=None, illegitimate=False)
        return pid

    for tag, c in countries.items():
        r = roles[tag]
        capital_name = provinces[c["capital"]]["name"]
        if r["ruler"] is None:
            if c["government"] == "republic":
                dyn = None
            else:
                dyn = f"House of {capital_name}"
            age = 30 + h(tag, "rage") % 25
            ruler = invent(tag, "ruler", age=age, dynasty=dyn)
            r["ruler"] = ruler
            if c["government"] not in ("republic", "theocracy"):
                wife = invent(tag, "wife", female=True, age=max(18, age - 5 - h(tag, "w") % 6))
                people[ruler]["spouses"].append(wife)
                people[wife]["spouses"].append(ruler)
                r["court"].append(wife)
            if r["heir"] is None and c["government"] not in ("republic", "theocracy"):
                sib = invent(tag, "brother", age=max(16, age - 2 - h(tag, "b") % 8), dynasty=dyn)
                r["heir"] = sib
                r["court"].append(sib)

    # Spouses of rulers and heirs live at that court.
    for tag, r in roles.items():
        for who in (r["ruler"], r["heir"]):
            if not who:
                continue
            for sp in people[who]["spouses"]:
                if people[sp]["died"]:
                    continue
                if people[sp]["country"] != tag and roles[people[sp]["country"]]["ruler"] != sp:
                    old = people[sp]["country"]
                    if sp in roles[old]["court"]:
                        roles[old]["court"].remove(sp)
                    people[sp]["country"] = tag
                    roles[tag]["court"].append(sp)

    # Council: best real figure of the country for each seat, else invented.
    councils = {}
    for tag, c in countries.items():
        r = roles[tag]
        capital_name = provinces[c["capital"]]["name"]
        skill_traits = {"diplomat", "strategist", "administrator", "schemer", "scholar"}
        ruler_spouses = set(people[r["ruler"]]["spouses"])
        candidates = [p for p in r["court"] if p != r["ruler"] and p not in ruler_spouses
                      and not people[p]["died"]
                      and START_YEAR - people[p]["born"][0] >= 16 and "blind" not in people[p]["traits"]
                      and (not people[p]["female"] or skill_traits & set(people[p]["traits"]))]
        owned = [pp["name"] for pp in provinces if pp.get("owner") == tag] or [capital_name]
        seats = {}
        used = set()
        for seat, skill in COUNCIL:
            best = None
            for p in candidates:
                if p in used or p == r["heir"]:
                    continue
                score = sum(traits[t]["skills"][skill] for t in people[p]["traits"])
                if best is None or score > best[0]:
                    best = (score, p)
            if best and best[0] > 0:
                seats[seat] = best[1]
                used.add(best[1])
            else:
                home = owned[h(tag, seat, "home") % len(owned)]
                pid = invent(tag, seat, age=28 + h(tag, seat) % 30, dynasty=f"of {home}")
                seats[seat] = pid
                r["court"].append(pid)
        councils[tag] = seats

    # Skills: 5 + trait changes + a little noise, children lower.
    out = []
    index = {pid: i for i, pid in enumerate(order)}
    for pid in order:
        p = people[pid]
        age = START_YEAR - p["born"][0]
        skills = []
        for s in range(5):
            v = 5 + sum(traits[t]["skills"][s] for t in p["traits"]) + (h(pid, "sk", s) % 5) - 2
            if age < 16:
                v = round(v * max(age, 0) / 16)
            skills.append(max(0, min(20, v)))
        out.append({
            "id": pid, "name": p["name"], "dynasty": p["dynasty"], "female": p["female"],
            "born": p["born"],
            "father": index.get(p["father"]) if p["father"] else None,
            "mother": index.get(p["mother"]) if p["mother"] else None,
            "spouses": [index[s] for s in p["spouses"]],
            "culture": p["culture"] or capital_culture(p["country"]),
            "religion": p["religion"] or countries[p["country"]]["religion"],
            "traits": [trait_keys.index(t) for t in p["traits"]],
            "skills": skills, "country": p["country"], "invented": p["invented"], "note": p["note"],
            "died": p["died"], "illegitimate": p["illegitimate"],
        })

    succession = {}
    for line in rows(DATA / "succession.txt"):
        t, law = [x.strip() for x in line.split("|")]
        if t in countries:
            succession[t] = law
    for tag, r in roles.items():
        for who in (r["ruler"], r["heir"]):
            if who and people[who]["died"]:
                sys.exit(f"{tag}: {who} is dead but ruler/heir")
    result = {
        "holdings": {str(province_names[k]): index[v] for k, v in holdings.items()},
        "names": {k: {"male": v[0], "female": v[1]} for k, v in names.items()},
        "succession": succession,
        "traits": list(traits.values()),
        "characters": out,
        "countries": {tag: {"ruler": index[r["ruler"]], "heir": index[r["heir"]] if r["heir"] else None,
                            "council": {k: index[v] for k, v in councils[tag].items()}}
                      for tag, r in roles.items()},
    }
    (RES / "characters1453.json").write_text(json.dumps(result, separators=(",", ":"), ensure_ascii=False))
    real = sum(1 for p in out if not p["invented"] and not p["died"])
    dead = sum(1 for p in out if p["died"])
    print(f"{len(out)} characters ({real} real living, {dead} real ancestors, "
          f"{len(out) - real - dead} invented); {len(holdings)} provinces held by vassals")


if __name__ == "__main__":
    main()
