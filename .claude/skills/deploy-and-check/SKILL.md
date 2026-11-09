---
name: deploy-and-check
description: Run the offline checks (tests, LuaLS diagnostics, local-path scan) and deploy Reagent Atlas into the WoW Forever client, then tell the user whether /reload is enough or the game needs a full restart. Use whenever code changed and the user will test in-game, or when asked to deploy.
---

# Deploy and check

Run the steps in order. Stop at the first failure, fix it (or report it), and don't deploy a build that fails a check.

## 1. Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1
```

The `-ExecutionPolicy Bypass` is needed on this machine; the script uses the LuaLS binary from the VS Code extension as its Lua interpreter. Expect `N passed, 0 failed`. A new test file must also be added to the list at the bottom of `tools/tests/run.lua`, or it never runs.

## 2. Diagnostics

Use the editor's diagnostics (`mcp__claude-vscode__getDiagnostics`, one call per changed `.lua` file, by `file:///` URI). The editor loads the Ketho WoW API annotations from `ReagentAtlas.code-workspace`.

Don't trust `lua-language-server --check` on the command line: it doesn't load the annotations and reports hundreds of false `undefined-global` warnings. If the editor isn't available, run it anyway but only act on findings other than `undefined-global`.

- Fix every warning the change introduced.
- Expected and fine: the `Unused local addonName` hint (every file starts with `local addonName, ns = ...`), and `redundant-parameter` on `Settings.CreateDropdown` / `CreateCheckbox` calls (the annotation is short a parameter; existing calls have it too).
- A real WoW global missing from the annotations (e.g. `WorldMapFrame`, `GetMinimapShape`): guard it in code and add it to `diagnostics.globals` in both `.luarc.json` and `ReagentAtlas.code-workspace`.
- Diagnostics reported right after an edit can be stale (mid-edit state). Re-query before acting on them.

## 3. Local-path scan

The repo is public. Nothing may contain the user's paths, account or user names:

```bash
git diff HEAD | grep -inE '[A-Z]:\\\\|[A-Z]:/|Users[\\/]|scratchpad|WTF[\\/]Account' || echo "no local paths"
```

Also check untracked files (`git status --short`). Only the generic examples already in `tools/deploy.ps1` are fine.

## 4. Game path: only from REAGENTATLAS_GAME_PATH

Never pass `-GamePath`, never guess a path, never use a path from memory or earlier conversation. Read the environment variable, in this session first and then at user level (it may have been set after Claude Code started):

```powershell
$p = $env:REAGENTATLAS_GAME_PATH
if (-not $p) { $p = [Environment]::GetEnvironmentVariable('REAGENTATLAS_GAME_PATH', 'User') }
if ($p) { "game path: $p" } else { "NOT SET" }
```

If it is **not set**, stop and warn the user. Don't deploy. Tell them to set it once to their Forever client folder (the one containing `Interface`) and restart the terminal / VS Code:

```powershell
[Environment]::SetEnvironmentVariable("REAGENTATLAS_GAME_PATH", "<Forever client folder>", "User")
```

If it's set but the folder doesn't exist or has no `Interface` folder, stop and say so.

## 5. Reload or restart?

Decide **before** deploying, by comparing the repo TOC with the deployed one:

```powershell
$deployed = Join-Path $p 'Interface\AddOns\ReagentAtlas\ReagentAtlas.toc'
if (-not (Test-Path -LiteralPath $deployed)) { "RESTART: first deploy" }
elseif (Compare-Object (Get-Content ReagentAtlas.toc) (Get-Content -LiteralPath $deployed)) { "RESTART: TOC changed" }
else { "RELOAD" }
```

The client reads the TOC (file list, SavedVariables, metadata) only at startup. A new or renamed Lua file, or any TOC change, needs a full game restart; `/reload` would load the changed old files without the new ones and cause errors. New files under `Media/` also need a restart. Everything else: `/reload`.

## 6. Deploy

Run in the same PowerShell call as step 4, so `$p` is set for the child process:

```powershell
$env:REAGENTATLAS_GAME_PATH = $p
powershell -NoProfile -ExecutionPolicy Bypass -File tools/deploy.ps1
```

It wipes and recreates `Interface\AddOns\ReagentAtlas` with the shipped files only. If a new top-level folder must ship, it belongs in `$ShipDirs` in `tools/deploy.ps1`, and anything new at the repo root that must not ship belongs in `.pkgmeta`'s `ignore` list.

## 7. Report

Tell the user, briefly:

- tests (N passed) and diagnostics (clean, or what remains and why it's fine)
- deployed N files
- **/reload** or **exit and restart the game**, from step 5, said plainly
- what to test in-game: what to do, where to look, the expected result, and to check BugSack. Name anything that only the game can confirm (APIs marked "verify" or added to SPEC.md's open questions).
