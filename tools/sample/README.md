# Sample DB2 fixture

A tiny hand-made stand-in for a real DB2 CSV export, used until the Forever client
can be exported (and by the offline tests). Same file and column names as the real
export.

- Recipes 2963, 2657, 2152, 2660, 2330 and 3275 are real Classic-era spells.
- Recipes 990001-990007 and items 990101-990107 are **synthetic**: they give Light
  Feather (17056) a spread of 7 recipes across three professions, matching the
  tooltip mockup. In-game these show as "Recipe #990001" etc.

Regenerate the addon data from it with `python tools/build_data.py --sample`.
