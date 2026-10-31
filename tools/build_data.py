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
    SpellClassOptions.csv SpellID, SpellClassSet (optional; maps class spells)
    build.txt             client version, e.g. 1.60.1.70707 (optional, else --build)

Real Forever tables can be downloaded from wago.tools (product "wowf"), e.g.
https://wago.tools/db2/SpellReagents/csv?build=1.60.1.70707

Spell reagents (items consumed by class spells) are derived from SpellReagents
plus SpellClassOptions and the class skill lines. Gaps and mistakes in that
mapping are fixed in spell_reagents.csv (source dir if present, else
tools/spell_reagents.csv): columns itemID, class, note; "-CLASS" removes.

Vendor-sold reagents come from vendor_reagents.csv (source dir if present, else
tools/vendor_reagents.csv), maintained by hand: columns itemID, name.
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
    40: "Poisons",
}

# SpellClassOptions.SpellClassSet is the spell family, not the class ID.
SPELL_FAMILY_CLASS = {
    3: "MAGE", 4: "WARRIOR", 5: "WARLOCK", 6: "PRIEST", 7: "DRUID",
    8: "ROGUE", 9: "HUNTER", 10: "PALADIN", 11: "SHAMAN",
}
# SkillLineAbility.ClassMask bits (1 << (classID - 1)).
CLASS_MASK = {
    1: "WARRIOR", 2: "PALADIN", 4: "HUNTER", 8: "ROGUE", 16: "PRIEST",
    64: "SHAMAN", 128: "MAGE", 256: "WARLOCK", 1024: "DRUID",
}
SKILL_CATEGORY_CLASS = 7
# Class skill lines whose spells are not normal class spells (Season of
# Discovery rune engraving data still present in the Forever client).
EXCLUDED_CLASS_LINES = {2851}

EFFECT_CREATE_ITEM = 24
TEST_SPELL = re.compile(r"\b(test|dnd|dnt|deprecated|unused|old)\b|\[ph\]|^copy of", re.IGNORECASE)


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


def load_items(src: Path) -> dict[int, tuple[int, int]]:
    """itemID -> (quality, vendor sell price in copper)."""
    return {
        to_int(r["ID"]): (to_int(col(r, "OverallQualityID")), to_int(col(r, "SellPrice")))
        for r in read_csv(src / "ItemSparse.csv")
    }


def load_spell_classes(src: Path) -> dict[int, set[str]]:
    """Class spell ID -> classes, from SpellClassOptions and class skill lines."""
    result: dict[int, set[str]] = {}
    path = src / "SpellClassOptions.csv"
    if path.exists():
        for row in read_csv(path):
            cls = SPELL_FAMILY_CLASS.get(to_int(col(row, "SpellClassSet")))
            if cls:
                result.setdefault(to_int(col(row, "SpellID")), set()).add(cls)

    class_lines = set()
    path = src / "SkillLine.csv"
    if path.exists():
        for row in read_csv(path):
            if to_int(col(row, "CategoryID")) == SKILL_CATEGORY_CLASS:
                class_lines.add(to_int(row["ID"]))
    class_lines -= EXCLUDED_CLASS_LINES

    excluded_spells = set()
    for row in read_csv(src / "SkillLineAbility.csv"):
        line, spell = to_int(col(row, "SkillLine")), to_int(col(row, "Spell"))
        if line in EXCLUDED_CLASS_LINES:
            excluded_spells.add(spell)
        elif line in class_lines:
            mask = to_int(col(row, "ClassMask"))
            for bit, cls in CLASS_MASK.items():
                if mask & bit:
                    result.setdefault(spell, set()).add(cls)
    for spell in excluded_spells:
        result.pop(spell, None)
    return result


def apply_spell_reagent_overrides(path: Path, classes_by_item: dict[int, set[str]]) -> None:
    """Rows of itemID,class,note: "MAGE" adds a class, "-MAGE" removes it."""
    if not path.exists():
        return
    for row in read_csv(path):
        item = to_int(row.get("itemID", ""))
        cls = row.get("class", "").strip().upper()
        if not item or not cls:
            continue
        if cls.startswith("-"):
            classes_by_item.get(item, set()).discard(cls[1:])
        else:
            classes_by_item.setdefault(item, set()).add(cls)


def build(src: Path) -> tuple[dict[int, dict], dict[int, dict]]:
    prof_of = load_professions(src)
    names = load_spell_names(src)
    reagents = load_reagents(src)
    outputs = load_outputs(src)
    items = load_items(src)

    recipes: dict[int, dict] = {}
    for row in read_csv(src / "SkillLineAbility.csv"):
        prof = prof_of.get(to_int(col(row, "SkillLine")))
        spell = to_int(col(row, "Spell"))
        if not prof or spell not in reagents:
            continue
        if TEST_SPELL.search(names.get(spell, "")):
            continue
        # Forever leaves MinSkillLineRank at 1 for nearly every recipe; the
        # skill where the recipe turns yellow is the usable difficulty signal.
        skill = max(to_int(col(row, "MinSkillLineRank")), to_int(col(row, "TrivialSkillLineRankLow")))
        recipe = {"prof": prof, "skill": skill, "reagents": reagents[spell]}
        out = outputs.get(spell)
        if out:
            recipe["out"] = out
            recipe["outQ"] = items.get(out, (1, 0))[0]
        # A spell can appear on several skill lines; keep the lowest requirement.
        prev = recipes.get(spell)
        if prev is None or recipe["skill"] < prev["skill"]:
            recipes[spell] = recipe

    # Some recipes exist twice (an original and a re-added copy). Drop copies
    # with the same profession, output and reagents, keeping the lower spell ID.
    seen: dict[tuple, int] = {}
    for spell in sorted(recipes):
        r = recipes[spell]
        if "out" not in r:
            continue
        key = (r["prof"], r["out"], tuple(sorted(r["reagents"].items())))
        if key in seen:
            del recipes[spell]
        else:
            seen[key] = spell

    index: dict[int, dict] = {}
    for spell, recipe in recipes.items():
        for item in recipe["reagents"]:
            index.setdefault(item, {"r": []})["r"].append(spell)
    for entry in index.values():
        entry["r"].sort(key=lambda s: (-recipes[s]["skill"], s))

    # Spell reagents: items consumed by class spells.
    spell_classes = load_spell_classes(src)
    classes_by_item: dict[int, set[str]] = {}
    for spell, spell_reagents in reagents.items():
        classes = spell_classes.get(spell)
        if not classes or spell in recipes or TEST_SPELL.search(names.get(spell, "")):
            continue
        for item in spell_reagents:
            classes_by_item.setdefault(item, set()).update(classes)

    # A fixture may carry its own overrides; real exports use the repo one.
    override_path = src / "spell_reagents.csv"
    if not override_path.exists():
        override_path = ROOT / "tools" / "spell_reagents.csv"
    apply_spell_reagent_overrides(override_path, classes_by_item)
    for item, classes in classes_by_item.items():
        if classes:
            index.setdefault(item, {"r": []})["spell"] = sorted(classes)

    # Vendor-sold reagents. NPC vendor inventories are server data, not in the
    # client DB2, so this list is maintained by hand.
    vendor_path = src / "vendor_reagents.csv"
    if not vendor_path.exists():
        vendor_path = ROOT / "tools" / "vendor_reagents.csv"
    if vendor_path.exists():
        for row in read_csv(vendor_path):
            entry = index.get(to_int(row.get("itemID", "")))
            if entry is not None:
                entry["vendor"] = True

    for item, entry in index.items():
        entry["q"], entry["sell"] = items.get(item, (1, 0))

    return recipes, index


def lua_map(d: dict[int, int]) -> str:
    return "{ " + ", ".join(f"[{k}] = {d[k]}" for k in sorted(d)) + " }"


def lua_str_list(items: list[str]) -> str:
    return "{ " + ", ".join(f'"{s}"' for s in items) + " }"


def header(version: str) -> list[str]:
    return [
        "-- Generated by tools/build_data.py. Do not edit by hand.",
        f"-- Source: {version}",
        "local addonName, ns = ...",
        "",
    ]


def write_recipes(recipes: dict[int, dict], build_id: str, version: str) -> None:
    lines = header(version)
    lines.append(f'ns.DATA_BUILD = "{build_id}"')
    lines.append(f"ns.MAX_SKILL = {max((r['skill'] for r in recipes.values()), default=0)}")
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


def write_reagents(index: dict[int, dict], version: str) -> None:
    lines = header(version)
    lines.append("local G = {}")
    lines.append("ns.Reagents = G")
    for item in sorted(index):
        e = index[item]
        fields = ["r = { " + ", ".join(str(s) for s in e["r"]) + " }" if e["r"] else "r = {}"]
        fields += [f"q = {e['q']}", f"sell = {e['sell']}"]
        if "spell" in e:
            fields.append(f"spell = {lua_str_list(e['spell'])}")
        if e.get("vendor"):
            fields.append("vendor = true")
        lines.append(f"G[{item}] = {{ {', '.join(fields)} }}")
    (OUT_DIR / "Reagents.lua").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sample", action="store_true", help="use the tools/sample fixture")
    parser.add_argument("--src", type=Path, help="directory with the DB2 CSVs (default tools/db2)")
    parser.add_argument("--build", help="client version or build, e.g. 1.60.1.70707")
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

    # GetBuildInfo() reports the build number alone ("70707"), so compare on that.
    version = build_id
    build_id = build_id.rsplit(".", 1)[-1]

    recipes, index = build(src)
    OUT_DIR.mkdir(exist_ok=True)
    write_recipes(recipes, build_id, version)
    write_reagents(index, version)
    print(f"build {version}: {len(recipes)} recipes, {len(index)} reagents -> {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
