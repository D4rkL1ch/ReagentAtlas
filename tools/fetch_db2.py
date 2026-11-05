"""Download the data build_data.py needs into tools/db2/.

DB2 tables come from wago.tools. Recipe sources come from QuestieDB at the
pinned QUESTIEDB_COMMIT; bump it on purpose and review the Data/Sources.lua
diff, because QuestieDB changes independently of client builds.

Usage:
    python tools/fetch_db2.py                 # latest WoW Forever build (product "wowf")
    python tools/fetch_db2.py 1.60.1.70707    # a specific build
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

PRODUCT = "wowf"
TABLES = [
    "SkillLine", "SkillLineAbility", "SpellReagents", "SpellEffect", "ItemSparse", "SpellName", "SpellClassOptions",
    "Item", "ItemEffect", "ItemXItemEffect", "Faction", "AreaTable",
]
OUT_DIR = Path(__file__).resolve().parent / "db2"
QUESTIEDB_COMMIT = "80866960788084ae1592abf66a08f0d306458a95"
QUESTIEDB_FILES = ["foreverItemDB.lua", "foreverNpcDB.lua", "foreverQuestDB.lua"]


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "ReagentAtlas build tool"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def latest_build() -> str:
    builds = json.loads(fetch("https://wago.tools/api/builds"))
    return builds[PRODUCT][0]["version"]


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
    (questie_dir / "commit.txt").write_text(QUESTIEDB_COMMIT + "\n", encoding="utf-8")
    print(f"build {version} -> {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
