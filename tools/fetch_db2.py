"""Download the data build_data.py needs into tools/db2/.

DB2 tables come from wago.tools. Recipe sources come from QuestieDB at the
pinned QUESTIEDB_COMMIT; bump it on purpose and review the Data/Sources.lua
diff, because QuestieDB changes independently of client builds.

Besides QuestieDB's raw Forever tables this fetches the correction layers that
build_data.py applies on top (legacy Classic fixes, player traces, authored
Forever fixes) and the zone enum they refer to. The generated delta-base in
src/corrections/Forever/generated/ is deliberately not fetched: it is scraped
from Wowhead, whose data we have no licence to ship (SPEC.md > Open questions).

Forever's client data has no "learned at" skill for recipes (MinSkillLineRank
is 1). For trainer recipes it comes from the CMaNGOS Classic world database
(GPL-3.0) at the pinned CMANGOS_COMMIT, mapped to recipes and to Forever's
rebalanced skill ranks through Classic Era's SkillLineAbility and SpellEffect
(ERA_BUILD). Saved into tools/db2/era/; only the trainer rows of the CMaNGOS
dump are kept (trainer_spells.csv).

Usage:
    python tools/fetch_db2.py                 # latest WoW Forever build (product "wowf")
    python tools/fetch_db2.py 1.60.1.70707    # a specific build
"""

from __future__ import annotations

import csv
import gzip
import json
import re
import sys
import urllib.request
from pathlib import Path

PRODUCT = "wowf"
TABLES = [
    "SkillLine", "SkillLineAbility", "SpellReagents", "SpellEffect", "ItemSparse", "SpellName", "SpellClassOptions",
    "Item", "ItemEffect", "ItemXItemEffect", "Faction", "AreaTable",
]
OUT_DIR = Path(__file__).resolve().parent / "db2"
QUESTIEDB_COMMIT = "5fba5d86641d1a64a787884e28e15ee16b115060"
QUESTIEDB_FILES = ["foreverItemDB.lua", "foreverNpcDB.lua", "foreverQuestDB.lua"]
# Saved by file name into tools/db2/questie/corrections/.
QUESTIEDB_CORRECTIONS = [
    "src/corrections/Forever/legacy/classicItemFixes.lua",
    "src/corrections/Forever/legacy/classicNPCFixes.lua",
    "src/corrections/Forever/legacy/classicQuestFixes.lua",
    "src/corrections/Forever/traces/foreverItemTraces.lua",
    "src/corrections/Forever/traces/foreverNpcTraces.lua",
    "src/corrections/Forever/traces/foreverQuestTraces.lua",
    "src/corrections/Forever/foreverItemFixes.lua",
    "src/corrections/Forever/foreverNPCFixes.lua",
    "src/corrections/Forever/foreverQuestFixes.lua",
    "src/corrections/enum/zones.lua",
]
ERA_BUILD = "1.15.9.70576"
ERA_TABLES = ["SkillLineAbility", "SpellEffect"]
CMANGOS_COMMIT = "c33f90b8eeb3f8bacb53d5cbfee45075c80b416c"
CMANGOS_DUMP = "Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
# Leading columns of npc_trainer / npc_trainer_template: entry, spell, spellcost, reqskill, reqskillvalue.
TRAINER_ROW = re.compile(r"\((\d+),(\d+),(\d+),(\d+),(\d+),")
TRAINER_INSERT = re.compile(r"^INSERT INTO `npc_trainer(?:_template)?` VALUES ")


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "ReagentAtlas build tool"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def latest_build() -> str:
    builds = json.loads(fetch("https://wago.tools/api/builds"))
    return builds[PRODUCT][0]["version"]


def trainer_spells(dump: bytes) -> list[tuple[int, int, int]]:
    """(spell, reqskill, reqskillvalue) for every trainer row in a CMaNGOS SQL dump."""
    rows = set()
    for line in gzip.decompress(dump).decode("utf-8", "replace").splitlines():
        if TRAINER_INSERT.match(line):
            for m in TRAINER_ROW.finditer(line):
                rows.add((int(m[2]), int(m[4]), int(m[5])))
    return sorted(rows)


def fetch_era(out_dir: Path) -> None:
    out_dir.mkdir(exist_ok=True)
    for table in ERA_TABLES:
        data = fetch(f"https://wago.tools/db2/{table}/csv?build={ERA_BUILD}")
        (out_dir / f"{table}.csv").write_bytes(data)
        print(f"era {table}: {len(data) // 1024} KB")
    rows = trainer_spells(fetch(f"https://raw.githubusercontent.com/cmangos/classic-db/{CMANGOS_COMMIT}/{CMANGOS_DUMP}"))
    with (out_dir / "trainer_spells.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["spell", "reqskill", "reqskillvalue"])
        writer.writerows(rows)
    print(f"trainer_spells.csv: {len(rows)} rows")
    (out_dir / "source.txt").write_text(f"era {ERA_BUILD}\ncmangos/classic-db {CMANGOS_COMMIT}\n", encoding="utf-8")


def main() -> int:
    version = sys.argv[1] if len(sys.argv) > 1 else latest_build()
    OUT_DIR.mkdir(exist_ok=True)
    for table in TABLES:
        data = fetch(f"https://wago.tools/db2/{table}/csv?build={version}")
        (OUT_DIR / f"{table}.csv").write_bytes(data)
        print(f"{table}: {len(data) // 1024} KB")
    (OUT_DIR / "build.txt").write_text(version + "\n", encoding="utf-8")

    questie_dir = OUT_DIR / "questie"
    questie_dir.mkdir(exist_ok=True)
    for name in QUESTIEDB_FILES:
        data = fetch(f"https://raw.githubusercontent.com/Questie/QuestieDB/{QUESTIEDB_COMMIT}/data/Forever/{name}")
        (questie_dir / name).write_bytes(data)
        print(f"{name}: {len(data) // 1024} KB")
    corrections_dir = questie_dir / "corrections"
    corrections_dir.mkdir(exist_ok=True)
    for path in QUESTIEDB_CORRECTIONS:
        data = fetch(f"https://raw.githubusercontent.com/Questie/QuestieDB/{QUESTIEDB_COMMIT}/{path}")
        (corrections_dir / Path(path).name).write_bytes(data)
        print(f"{Path(path).name}: {len(data) // 1024} KB")
    (questie_dir / "commit.txt").write_text(QUESTIEDB_COMMIT + "\n", encoding="utf-8")
    fetch_era(OUT_DIR / "era")
    print(f"build {version} -> {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
