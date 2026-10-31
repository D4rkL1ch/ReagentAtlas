# Reagent Atlas — instructions for Claude Code

WoW Forever addon (client 1.60.x, modern retail-style addon API). Full spec: `SPEC.md`. Read it before any work.

## How to work
- Build one phase from `SPEC.md` → "Implementation phases" per session. Don't start the next phase until the user confirms the current one works in-game.
- At the end of a phase, list exactly what the user should test in-game (`/reload`, what to hover/click, expected result).
- When an API in `SPEC.md` is marked "verify" or you're unsure it exists in Forever, check the LuaLS/Ketho WoW API annotations first; if still unsure, add a guarded call (`if C_Something and C_Something.Func then`) and tell the user what to confirm in-game.
- Update the "Open questions" checklist in `SPEC.md` when one gets answered.

## Code rules
- Lua 5.1 (WoW runtime). No `goto`, no integer division `//`, no `require`.
- Namespace: `local addonName, ns = ...` at the top of every file. The only global is the SavedVariable `ReagentAtlasDB`.
- Create frames in Lua, not XML. Prefer Blizzard mixins/templates already in the client (ScrollBox, Settings API).
- Never touch protected frames in combat; check `InCombatLockdown()`.
- No automation of any kind (no auto-loot/sell/post, no AH scan loops). The addon only displays information.
- Wrap all Auctionator calls in `pcall`; Auctionator is optional.
- Keep generated files (`Data/*.lua`) out of hand edits; change `tools/build_data.py` instead.
- Run LuaLS diagnostics on changed files and fix warnings before finishing.

## Layout
See `SPEC.md` → "Architecture & file layout". Load order in the TOC: Data → Core → Modules → UI.

## Repo and deploy
- This repo is the source of truth. It is NOT inside the WoW folder.
- The repo root is the addon root. `tools/deploy.ps1` copies only what ships (`*.toc`, top-level `*.lua`, `Data/`, `Modules/`, `UI/`, `Media/`) into `Interface\AddOns\ReagentAtlas`. If you add a new shipped folder, add it to `$ShipDirs` there.
- Everything else (`tools/`, `docs/`, `SPEC.md`, `CLAUDE.md`, `README.md`) stays repo-only.

## Testing
The user runs the addon on Windows: deploy, then `/reload` in-game. Errors are checked with BugSack/BugGrabber.
Until WoW Forever launches (Nov 4, 2026) there is no game client to test in: favour offline checks (luacheck/LuaLS, unit tests with stubbed WoW APIs) and mark anything that needs in-game confirmation.
