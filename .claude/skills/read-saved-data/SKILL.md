---
name: read-saved-data
description: Read Reagent Atlas's SavedVariables file (ReagentAtlasDB) from the WoW Forever client folder to see what the addon actually recorded in-game, e.g. settings, tracking list, characters, loot map data. Use when debugging something that works in tests but not in-game, or when the user asks what the addon has saved.
---

# Read the saved data

## Find the file

The game path comes only from `REAGENTATLAS_GAME_PATH`, in this session or at user level. Never guess a path or use one from memory. If it isn't set, stop and tell the user how to set it (see the `deploy-and-check` skill, step 4).

```powershell
$p = $env:REAGENTATLAS_GAME_PATH
if (-not $p) { $p = [Environment]::GetEnvironmentVariable('REAGENTATLAS_GAME_PATH', 'User') }
Get-ChildItem -LiteralPath (Join-Path $p 'WTF\Account') -Directory | ForEach-Object {
    Get-Item -LiteralPath (Join-Path $_.FullName 'SavedVariables\ReagentAtlas.lua') -ErrorAction SilentlyContinue
} | Select-Object FullName, Length, LastWriteTime
```

`ReagentAtlasDB` is account-wide: one file per account folder in `WTF\Account\<ACCOUNT>\SavedVariables\`, none per character. If there are several account folders, ask which one.

## Is it current?

The client writes the file only on `/reload`, logout or exit, never during play. Compare `LastWriteTime` with what the user describes (and with `Get-Date`). If the file is older than the thing to check (a loot, a setting change), ask the user to `/reload` first, then read it again.

A file written by an older build is recognizable: settings added by the new build (defaults in `Core.lua` → `DEFAULT_SETTINGS`) are missing. That means the new code never ran. Usually the game wasn't restarted after a TOC change.

## Read it

It's a Lua table dump, one key per line. Read it as text; never run it. Pull out one top-level table at a time:

```bash
sed -n '/^\["settings"\]/,/^},/p' "<file>"
sed -n '/^\["tracked"\]/,/^},/p' "<file>"
sed -n '/^\["lootMap"\]/,/^},/p' "<file>" | head -80
```

The structure is in SPEC.md → "Data model" → "SavedVariables". Useful facts:

- Numeric keys (itemIDs, mapIDs, grid cells) are saved as numbers: `[2251] = {`.
- Loot map grid cell = `gx * 100 + gy + 1`, so map position ≈ `((gx + 0.5) / 100, (gy + 0.5) / 100)`; cell `0` = no position (instances).
- Item and map names aren't saved. Look up IDs in `Data/Reagents.lua` (`G[itemID]`) or ask the user.

## Rules

- Read-only. Never edit the file: the game overwrites it on logout, and the user may be logged in.
- It contains the account folder name and character names. Don't copy them into the repo, commits, artifacts, or tests. Quote only what's needed to explain the finding.
