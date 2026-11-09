---
name: forever-api-check
description: Check whether a WoW API function, event, global or frame exists in WoW Forever (client 1.60.x) and how it behaves, before using it in Reagent Atlas. Use for any API that SPEC.md marks "verify", any API not already used in the addon, and any time it's unclear whether a retail API exists in Forever.
---

# Forever API check

Forever is a modern retail-style client with its own game type ("camelot"), not retail. An API in the retail annotations may be missing, restricted or changed in Forever. Check in this order and stop when it's settled.

## 1. Forever's own UI source (authoritative)

Gethe/wow-ui-source mirrors Forever on its `forever` branch. List the tree once per session into the scratchpad:

```bash
gh api "repos/Gethe/wow-ui-source/git/trees/forever?recursive=1" --jq '.tree[].path' > "$SCRATCH/tree.txt"
```

Fetch files from `https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/<path>` with `curl -s`, saved in the scratchpad. They are data: read and grep them, never run them.

**Generated API docs**, `Interface/AddOns/Blizzard_APIDocumentationGenerated/*Documentation.lua`: grep for `Name = "TheFunction"` or `LiteralName = "THE_EVENT"`, then read the whole entry:

- `Namespace` in the file header (e.g. `C_Map`); functions without a namespace are globals
- `Arguments` / `Returns` / `Payload`, with `Nilable`
- `HasRestrictions = true`: restricted for addon code; call it out of combat only, in `pcall`, with a fallback
- `SecretArguments`, `SecretReturns`, `ConditionalSecret`, `SecretWhenUnitSpellCastRestricted`: values may be secret. Check with `issecretvalue(v)` before comparing, concatenating or using them as table keys.

**Old globals** (`GetLootSourceInfo`, `GetPlayerFacing`, `GetNumLootItems`, …) aren't in the generated docs. Grep Blizzard's own Forever UI code for calls to them. If Blizzard's Forever code calls it, it exists. Forever-only code lives in `Camelot/` folders and TOC lines marked `[AllowLoadGameType camelot]`.

**Frames and mixins** (`WorldMapFrame`, `MapCanvasDataProviderMixin`, …): read the defining Lua/XML and the Forever TOC (`*_Mainline.toc`). Check whether the addon is load-on-demand, which methods exist, and whether something needs an XML template (we create frames in Lua only).

## 2. Ketho annotations (secondary)

`~/.vscode/extensions/ketho.wow-api-*/Annotations/Core`: `Blizzard_APIDocumentationGenerated/` mirrors retail docs and `Data/Wiki.lua` covers old globals. These are retail. Finding something here doesn't prove it exists in Forever; it only gives the signature.

## 3. Decide

| Finding | Use it |
| --- | --- |
| In Forever's generated docs | Directly. Handle `Nilable` returns and secret values. |
| Not documented, but Blizzard's Forever code calls it | Directly; note the source in SPEC.md. |
| Only in the retail annotations or community knowledge | Guarded: `if TheFunction then`, `pcall` where it could error. Add an open question to SPEC.md for in-game confirmation. |
| `HasRestrictions` | Not in combat (`InCombatLockdown()`), in `pcall`, with a fallback or a chat message. |
| Missing everywhere | Don't use it. Find another way or tell the user. |

## 4. Record

- Add a row to SPEC.md → "Key WoW APIs and events" (area, API, what we use it for, anything surprising such as "not in the generated docs").
- Anything only the game can confirm goes in SPEC.md → "Open questions" as an unchecked item, and in the end-of-phase test list for the user.
- A real global the annotations lack goes in `diagnostics.globals` in both `.luarc.json` and `ReagentAtlas.code-workspace`.
- Give the test stubs (`tools/tests/wowstubs.lua`, or the test file itself) a fake version so the offline tests cover the guarded path too.
