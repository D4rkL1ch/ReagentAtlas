"""Generate Data/Recipes.lua and Data/Reagents.lua from exported DB2 CSVs.

Usage:
    python tools/build_data.py                 # reads tools/db2/ (real client export)
    python tools/build_data.py --sample        # reads tools/sample/ (small test fixture)
    python tools/build_data.py --src DIR --build 12345

Expected CSVs in the source dir (column names as in WoWDBDefs; array columns
may be written as Name[0] or Name_0):
    SkillLine.csv         ID, DisplayName_lang, ParentSkillLineID (optional)
    SkillLineAbility.csv  SkillLine, Spell, MinSkillLineRank
    SpellReagents.csv     SpellID, Reagent[0..7], ReagentCount[0..7]
    SpellEffect.csv       SpellID, Effect, EffectItemType
    ItemSparse.csv        ID, OverallQualityID
    SpellName.csv         ID, Name_lang (optional; used to drop test spells)
    build.txt             client build number (optional, else --build)

Spell reagents (items classes use for spells) come from spell_reagents.csv in the
source dir if present, else tools/spell_reagents.csv, which is maintained by hand:
there is no DB2 table that lists them directly. Columns: itemID, class, note.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Data"

# Top-level profession skill lines kept in the data. Child skill lines
# (retail-style expansion tiers) are folded into their parent.
PROFESSIONS = {
    164: "Blacksmithing",
    165: "Leatherworking",
    171: "Alchemy",
    182: "Herbalism",
    186: "Mining",
    197: "Tailoring",
    202: "Engineering",
    333: "Enchanting",
    393: "Skinning",
    755: "Jewelcrafting",
    773: "Inscription",
    129: "First Aid",
    185: "Cooking",
    356: "Fishing",
}

EFFECT_CREATE_ITEM = 24
TEST_SPELL = re.compile(r"\b(test|dnd|deprecated|unused|old)\b|\[ph\]", re.IGNORECASE)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def col(row: dict[str, str], name: str, index: int | None = None) -> str:
    """Read a column, accepting both Name[0] and Name_0 for arrays."""
    if index is None:
        return row.get(name, "")
    for key in (f"{name}[{index}]", f"{name}_{index}"):
        if key in row:
            return row[key]
    return ""


def to_int(value: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def load_professions(src: Path) -> dict[int, int]:
    """Map every relevant skill line ID to its top-level profession ID."""
    mapping = {pid: pid for pid in PROFESSIONS}
    path = src / "SkillLine.csv"
    if path.exists():
        for row in read_csv(path):
            parent = to_int(col(row, "ParentSkillLineID"))
            if parent in PROFESSIONS:
                mapping[to_int(row["ID"])] = parent
    return mapping


def load_spell_names(src: Path) -> dict[int, str]:
    path = src / "SpellName.csv"
    if not path.exists():
        return {}
    return {to_int(r["ID"]): col(r, "Name_lang") for r in read_csv(path)}


def load_reagents(src: Path) -> dict[int, dict[int, int]]:
    result: dict[int, dict[int, int]] = {}
    for row in read_csv(src / "SpellReagents.csv"):
        spell = to_int(col(row, "SpellID"))
        reagents: dict[int, int] = {}
        for i in range(8):
            item = to_int(col(row, "Reagent", i))
            count = to_int(col(row, "ReagentCount", i))
            if item > 0 and count > 0:
                reagents[item] = reagents.get(item, 0) + count
        if reagents:
            result[spell] = reagents
    return result


def load_outputs(src: Path) -> dict[int, int]:
    result: dict[int, int] = {}
    for row in read_csv(src / "SpellEffect.csv"):
        if to_int(col(row, "Effect")) == EFFECT_CREATE_ITEM:
            item = to_int(col(row, "EffectItemType"))
            if item > 0:
                result.setdefault(to_int(col(row, "SpellID")), item)
    return result


def load_item_quality(src: Path) -> dict[int, int]:
    return {to_int(r["ID"]): to_int(col(r, "OverallQualityID")) for r in read_csv(src / "ItemSparse.csv")}


def load_spell_reagent_classes(path: Path) -> dict[int, list[str]]:
    result: dict[int, set[str]] = {}
    if path.exists():
        for row in read_csv(path):
            item = to_int(row.get("itemID", ""))
            cls = row.get("class", "").strip().upper()
            if item and cls:
                result.setdefault(item, set()).add(cls)
    return {item: sorted(classes) for item, classes in result.items()}


def build(src: Path) -> tuple[dict[int, dict], dict[int, dict]]:
    prof_of = load_professions(src)
    names = load_spell_names(src)
    reagents = load_reagents(src)
    outputs = load_outputs(src)
    quality = load_item_quality(src)

    recipes: dict[int, dict] = {}
    for row in read_csv(src / "SkillLineAbility.csv"):
        prof = prof_of.get(to_int(col(row, "SkillLine")))
        spell = to_int(col(row, "Spell"))
        if not prof or spell not in reagents:
            continue
        if TEST_SPELL.search(names.get(spell, "")):
            continue
        recipe = {"prof": prof, "skill": to_int(col(row, "MinSkillLineRank")), "reagents": reagents[spell]}
        out = outputs.get(spell)
        if out:
            recipe["out"] = out
            recipe["outQ"] = quality.get(out, 1)
        # A spell can appear on several skill lines; keep the lowest requirement.
        prev = recipes.get(spell)
        if prev is None or recipe["skill"] < prev["skill"]:
            recipes[spell] = recipe

    index: dict[int, dict] = {}
    for spell, recipe in recipes.items():
        for item in recipe["reagents"]:
            index.setdefault(item, {"r": []})["r"].append(spell)
    for entry in index.values():
        entry["r"].sort(key=lambda s: (-recipes[s]["skill"], s))

    # A fixture may carry its own list; real exports use the hand-maintained one.
    spell_path = src / "spell_reagents.csv"
    if not spell_path.exists():
        spell_path = ROOT / "tools" / "spell_reagents.csv"
    for item, classes in load_spell_reagent_classes(spell_path).items():
        index.setdefault(item, {"r": []})["spell"] = classes

    return recipes, index


def lua_map(d: dict[int, int]) -> str:
    return "{ " + ", ".join(f"[{k}] = {d[k]}" for k in sorted(d)) + " }"


def lua_str_list(items: list[str]) -> str:
    return "{ " + ", ".join(f'"{s}"' for s in items) + " }"


def header(build_id: str) -> list[str]:
    return [
        "-- Generated by tools/build_data.py. Do not edit by hand.",
        f"-- Source build: {build_id}",
        "local addonName, ns = ...",
        "",
    ]


def write_recipes(recipes: dict[int, dict], build_id: str) -> None:
    lines = header(build_id)
    lines.append(f'ns.DATA_BUILD = "{build_id}"')
    lines.append("")
    lines.append("ns.ProfessionNames = {")
    for pid in sorted(PROFESSIONS):
        lines.append(f'\t[{pid}] = "{PROFESSIONS[pid]}",')
    lines.append("}")
    lines.append("")
    lines.append("local R = {}")
    lines.append("ns.Recipes = R")
    for spell in sorted(recipes):
        r = recipes[spell]
        fields = [f"prof = {r['prof']}", f"skill = {r['skill']}"]
        if "out" in r:
            fields += [f"out = {r['out']}", f"outQ = {r['outQ']}"]
        fields.append(f"reagents = {lua_map(r['reagents'])}")
        lines.append(f"R[{spell}] = {{ {', '.join(fields)} }}")
    (OUT_DIR / "Recipes.lua").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def write_reagents(index: dict[int, dict], build_id: str) -> None:
    lines = header(build_id)
    lines.append("local G = {}")
    lines.append("ns.Reagents = G")
    for item in sorted(index):
        e = index[item]
        fields = ["r = { " + ", ".join(str(s) for s in e["r"]) + " }" if e["r"] else "r = {}"]
        if "spell" in e:
            fields.append(f"spell = {lua_str_list(e['spell'])}")
        lines.append(f"G[{item}] = {{ {', '.join(fields)} }}")
    (OUT_DIR / "Reagents.lua").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sample", action="store_true", help="use the tools/sample fixture")
    parser.add_argument("--src", type=Path, help="directory with the DB2 CSVs (default tools/db2)")
    parser.add_argument("--build", help="client build number for ns.DATA_BUILD")
    args = parser.parse_args()

    src = args.src or (ROOT / "tools" / ("sample" if args.sample else "db2"))
    if not (src / "SpellReagents.csv").exists():
        print(f"error: no DB2 CSVs in {src}. Export them first (see SPEC.md > Data sourcing).", file=sys.stderr)
        return 1

    build_id = args.build
    if not build_id and (src / "build.txt").exists():
        build_id = (src / "build.txt").read_text(encoding="utf-8").strip()
    if not build_id:
        print("error: unknown client build. Pass --build or add build.txt to the source dir.", file=sys.stderr)
        return 1

    recipes, index = build(src)
    OUT_DIR.mkdir(exist_ok=True)
    write_recipes(recipes, build_id)
    write_reagents(index, build_id)
    print(f"build {build_id}: {len(recipes)} recipes, {len(index)} reagents -> {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
