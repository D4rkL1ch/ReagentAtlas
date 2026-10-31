"""Download the DB2 tables build_data.py needs from wago.tools into tools/db2/.

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
TABLES = ["SkillLine", "SkillLineAbility", "SpellReagents", "SpellEffect", "ItemSparse", "SpellName", "SpellClassOptions"]
OUT_DIR = Path(__file__).resolve().parent / "db2"


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
    print(f"build {version} -> {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
