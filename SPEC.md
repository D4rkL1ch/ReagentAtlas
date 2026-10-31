# Reagent Atlas — Implementation Spec

Last updated: Oct 31, 2026

## Overview & goals

Reagent Atlas is a WoW Forever (client 1.60.x, modern addon API) addon that tells players whether an item they picked up is worth keeping: which profession recipes use it, which of their characters can craft those recipes, and a predicted value tier.

**Goals**

- Item tooltip shows every recipe that uses the item, across all professions.
- Recipes the current character or any alt can craft are highlighted.
- A value tier (Vendor / Useful / Valuable / Keep!) is predicted from recipe data, refined by Auctionator prices when available.
- A browser window lists all reagents with filters for profession, tier, owned and craftable.
- Owned counts cover bags and bank of every character on the account.

**Non-goals**

- No automation of any kind: no auto-looting, auto-selling, auto-posting or AH scanning loops. Information only.
- No own AH scanner in v1; prices come only from Auctionator.
- No cross-account or cross-realm sync.

## Features

| Feature | Behavior | Priority |
| --- | --- | --- |
| Item tooltip (collapsed) | Tier badge, recipe count, top professions, highest skill level, owned total, AH price if known. Max ~5 lines. Spell reagents read "Spell reagent for your class" (green) for your own class, otherwise "Spell reagent for <classes>" in class colors. | P0 |
| Item tooltip (Shift held) | Full recipe list grouped by profession, sorted by skill desc. Craftable recipes marked with a check and the character name. | P0 |
| Alt-aware highlighting | Recipes known by the current character are green; known by an alt are blue with the alt's name; unknown are grey. | P0 |
| Account-wide inventory | Counts per character for bags + bank; tooltip shows total and a per-character breakdown on Shift. | P1 |
| Browser window | `/ratlas` opens a two-pane window: filterable reagent list (left), detail pane (right). Movable, position saved. | P1 |
| Bag markers | Small tier-colored corner pip on Valuable / Keep! items in default bags. Toggleable. | P2 |
| Settings | Toggles for tooltip, markers, Auctionator use, minimum tier for markers. Uses the modern Settings panel. | P2 |

Tier colors: Vendor = grey, Useful = white, Valuable = blue, Keep! = orange.

## Architecture & file layout

Plain Lua + XML-free frames (create everything in Lua), no external libraries in v1. One shared namespace table via `local addonName, ns = ...`.

```
ReagentAtlas/
  ReagentAtlas.toc          -- Interface version, SavedVariables, load order
  Core.lua                  -- ns init, event dispatcher, slash command, ADDON_LOADED
  Data/
    Reagents.lua            -- generated: itemID -> recipe refs, spell reagent info
    Recipes.lua             -- generated: recipeID -> profession, skill, output itemID, reagents
  Modules/
    Inventory.lua           -- scans bags/bank, writes per-character counts
    Professions.lua         -- records known recipes per character
    Pricing.lua             -- Auctionator bridge, returns price or nil
    Valuation.lua           -- tier heuristic, combines data + price
    Tooltip.lua             -- TooltipDataProcessor hook, collapsed/expanded render
    BagMarkers.lua          -- tier pips on bag item buttons
  UI/
    Browser.lua             -- main window, list (ScrollBox), filters, detail pane
    Settings.lua            -- Settings panel registration
  tools/
    build_data.py           -- generates Data/*.lua from exported DB2 CSVs (not shipped)
```

**TOC essentials:** `## Interface:` = value of `select(4, GetBuildInfo())` on the Forever client; `## SavedVariables: ReagentAtlasDB`; `## OptionalDeps: Auctionator`. Load order: Data → Core → Modules → UI.

**Module contract:** each module registers with `ns:RegisterModule(name, mod)` and may implement `OnInit()` (after ADDON_LOADED) and `OnLogin()` (after PLAYER_LOGIN). Modules talk through `ns.<Module>` functions, never through globals.

## Data model

Static data is generated and read-only; everything learned in-game lives in one account-wide SavedVariable.

**Static (generated)**

```lua
-- Data/Recipes.lua
ns.Recipes[recipeSpellID] = {
  prof = 165,            -- profession skill line ID (165 = Leatherworking)
  skill = 285,           -- required skill
  out = 15090,           -- output itemID
  outQ = 3,              -- output quality (0-5), used by valuation
  reagents = { [17012] = 2, [15407] = 1 }, -- itemID -> count
}

-- Data/Reagents.lua (inverted index, built by the tool)
ns.Reagents[itemID] = {
  r = { recipeSpellID, ... },  -- sorted by skill desc
  spell = { "MAGE", "ROGUE" }, -- optional: classes using it as a spell reagent
}
```

**SavedVariables: `ReagentAtlasDB`**

```lua
ReagentAtlasDB = {
  version = 1,
  settings = { tooltip = true, markers = true, useAuctionator = true, markerMinTier = 3 },
  ui = { point = {...}, filters = {...} },
  chars = {
    ["Name-Realm"] = {
      class = "MAGE", faction = "Horde", lastSeen = 1730000000,
      profs = { [165] = { rank = 240, known = { [recipeSpellID] = true } } },
      bags = { [itemID] = count },
      bank = { [itemID] = count },
    },
  },
  account = { bank = { [itemID] = count } },  -- warband bank, shared by all characters
}
```

Keys are `Name-Realm`. Only counts are stored, never item links, and only for items in `ns.Reagents`, to keep the file small. `/ratlas forget Name-Realm` removes a deleted character. A migration function runs on `version` mismatch.

## Data sourcing

The in-game API only lists recipes a character knows, so the full recipe database is generated offline from the client's DB2 tables and shipped with the addon.

1. Download the DB2 tables as CSV with `python tools/fetch_db2.py [version]`. It pulls them from wago.tools, which tracks WoW Forever as product `wowf` (first build seen: 1.60.1.70707). They land in `tools/db2/` (git-ignored). Exporting from a local client with wow.tools.local or DBC2CSV also works.
2. Join them in `tools/build_data.py`:
   - `SkillLineAbility` → recipe spell ID to profession skill line and skill. Forever leaves `MinSkillLineRank` at 1, so the skill used is `TrivialSkillLineRankLow` (where the recipe turns yellow).
   - `SpellReagents` → reagent itemIDs and counts per spell (recipes and class spells)
   - `SpellEffect` (create-item effect) → output itemID
   - `ItemSparse` → item quality, vendor sell price
   - `SkillLine` → child (tier) skill lines folded into their parent profession; class skill lines
   - `SpellClassOptions` → class of a spell (spell family) for spell reagents
   - `SpellName` → used to drop test/DND spells
3. Filter to primary + secondary professions plus Poisons, drop internal or test spells and Season of Discovery engraving leftovers, drop duplicate recipes (same profession, output and reagents).
4. Emit `Data/Recipes.lua` (with `ns.DATA_BUILD` and `ns.MAX_SKILL`, the highest recipe skill) and the inverted `Data/Reagents.lua` (recipes, own quality `q`, vendor sell price `sell`, spell classes, `vendor` flag).
5. Re-run on every client build. Chat shows a one-time warning per client build if `ns.DATA_BUILD` differs from `GetBuildInfo()`.

Two hand-maintained lists cover what the DB2 data lacks: `tools/spell_reagents.csv` (overrides for the spell reagent mapping) and `tools/vendor_reagents.csv` (reagents NPC vendors sell; vendor inventories are server data).

**Fallback / validation:** `Professions.lua` notes learned recipes seen in an open profession window that the generated data lacks. `/ratlas diff` lists them (session only; reagent lists are not compared yet).

## Value tier & Auctionator

The tier is a prediction, not a price: a score from recipe data, optionally nudged by Auctionator. All weights live in one table in `Valuation.lua` so they can be tuned after launch.

**Heuristic score (0–100)** — calibrated on the Forever 1.60.1 data (613 reagents)

| Signal | Points |
| --- | --- |
| Highest skill of any recipe using it | min(skill / `MAX_SKILL`, 1) × 35 (`MAX_SKILL` = 325 in 1.60.1) |
| Number of recipes using it | min(log(1 + count) / log(41), 1) × 15 (full at 40 recipes) |
| Best output quality among those recipes | +5 rare, +10 epic |
| Used in 2+ professions | +5 |
| The reagent's own quality | +10 uncommon, +15 rare, +20 epic or better |
| Spell reagent | tier at least Useful (no score bonus) |
| Sold by NPC vendors | tier capped at Useful |
| Not used in any recipe and not a spell reagent | no tier (nothing shown) |

Tiers: 0–14 Vendor, 15–39 Useful, 40–69 Valuable, 70+ Keep!

Resulting spread on 1.60.1: 31 Keep!, 239 Valuable, 301 Useful, 42 Vendor. Examples: Arcanite Bar, Essences, Large Brilliant Shard, Nexus Crystal → Keep!; Thorium Bar, Rugged Leather, Black Lotus, Runecloth → Valuable; Linen, Wool, Light Leather, Peacebloom → Useful; dyes, threads, vials, spices → Useful (vendor cap). Pure-price outliers (Black Lotus) are expected to be lifted by the Auctionator rule below.

The first draft (skill / 300 × 40, min(count, 10) × 2, +10/+20 for output quality, +10 for spell reagents) put 114 reagents on Keep! and most vendor goods on Valuable or Keep!, because recipe counts saturate at 10 and common materials are used in 50–200 recipes.

**Auctionator bridge (`Pricing.lua`)**

- Detect with `Auctionator and Auctionator.API and Auctionator.API.v1`.
- Price: `Auctionator.API.v1.GetAuctionPriceByItemID("ReagentAtlas", itemID)` → copper or nil.
- Freshness: `Auctionator.API.v1.GetAuctionAgeByItemID("ReagentAtlas", itemID)` → days or nil; ignore prices older than 7 days.
- Wrap every call in `pcall`; on any error disable the bridge for the session.
- When a fresh price exists: if price ≥ 5 × vendor price, raise the tier one step (max Keep!); if price < vendor price, cap at Useful. Show the price beside the tier.
- Verify in-game during Phase 1 that the Forever build of Auctionator keeps API v1.

## Key WoW APIs and events

Forever uses the modern retail-style API. Names below are from the retail API; confirm each with the LuaLS/Ketho annotations and in-game before relying on it. Forever's own UI source and generated API docs are mirrored in the `forever` branch of github.com/Gethe/wow-ui-source; check there first for what Forever actually has.

| Area | API / event | Use |
| --- | --- | --- |
| Tooltip | `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` | Append lines; `data.id` is the itemID. Guard against non-bag tooltips if needed. |
| Tooltip | `MODIFIER_STATE_CHANGED` | Refresh the tooltip when Shift is pressed or released. |
| Bags | `C_Container.GetContainerNumSlots`, `C_Container.GetContainerItemInfo` | Count items; info table has `itemID` and `stackCount`. |
| Bags | `BAG_UPDATE_DELAYED` | Rescan bags (debounced). |
| Bank | `BANKFRAME_OPENED/CLOSED`, `PLAYERBANKSLOTS_CHANGED`, `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED`, `C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character/Account)`, `C_Bank.CanViewBank` | Bank is only readable while open; scan then and cache. Forever uses retail-style tabs: character tabs are bag IDs 6-14, warband tabs 15-23. |
| Professions | `GetProfessions`, `GetProfessionInfo`, `SKILL_LINES_CHANGED` | Profession ranks at login, no window needed. Forever returns prof1, prof2, first aid, fishing, cooking. |
| Professions | `TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE`, `C_TradeSkillUI.GetAllRecipeIDs`, `C_TradeSkillUI.GetRecipeInfo` (`learned`), `IsTradeSkillLinked/Guild/NPCCrafting` | Record learned recipes when your own window is open (debounced). `NEW_RECIPE_LEARNED` adds single recipes without the window. |
| Professions | `C_TradeSkillUI.GetBaseProfessionInfo` | Profession skill line and rank. |
| Items | `C_Item.GetItemInfo`, `Item:CreateFromItemID():ContinueOnItemLoad` | Names, icons, quality; handle uncached items async. |
| Character | `UnitName`, `GetNormalizedRealmName`, `UnitClass` | Build the `Name-Realm` key. |
| UI list | `CreateScrollBoxListLinearView`, `ScrollUtil.InitScrollBoxListWithScrollBar` | Virtualized reagent list in the browser. |
| Settings | `Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterAddOnCategory` | Options panel. |

Addon restrictions introduced in Midnight target combat data; none of the above should be affected, but never touch protected frames in combat (check `InCombatLockdown()` before showing/moving the browser).

## Implementation phases

Build in five phases; each ends with an in-game check (`/reload`, BugSack shows no errors). Hand Claude Code one phase at a time.

1. **Skeleton.** TOC, Core.lua, module registry, SavedVariables init with migration stub, `/ratlas` prints version. Verify the `## Interface` number and that Auctionator API v1 exists. *Done when:* addon loads with zero errors and `/ratlas` responds.
2. **Data + tooltip.** `build_data.py`, generated Data files (start with a hand-written 10-item sample if DB2 export is not ready), Valuation.lua heuristic, Tooltip.lua collapsed and Shift views. *Done when:* hovering Light Feather shows tier, recipe count and the Shift list.
3. **Characters.** Professions.lua and Inventory.lua; alt highlighting and owned counts in the tooltip. *Done when:* a recipe learned on alt B shows as blue with B's name while logged in on A; bank items count after the bank was opened once.
4. **Pricing.** Pricing.lua bridge, tier adjustment, price line in tooltip. *Done when:* with Auctionator scanned, prices appear; with Auctionator disabled, nothing errors.
5. **Browser, markers, settings.** Browser window per the design mockup, bag pips, settings panel. *Done when:* filters combine correctly, list scrolls smoothly with 1,000+ rows, window position persists.

**Design reference:** UI mockups (browser window, tooltip collapsed/Shift, bag pips) live in the Reagent Atlas UI design canvas; screenshots go in `docs/`.

## Open questions and risks

- [x] Does wow.tools.local / DBC2CSV read the Forever client cleanly (WoWDBDefs coverage for the Forever build)? Yes: wago.tools serves Forever (`wowf`, 1.60.1.70707) tables, used by `tools/fetch_db2.py`.
- [ ] Does the Forever build of Auctionator keep `Auctionator.API.v1`?
- [x] Forever bank layout: classic bank bags or retail-style bank tabs? Retail-style tabs (Enum.BagIndex 6-14 character, 15-23 warband) plus a reagent bag (5), per the Forever 1.60.1 API docs. Confirm in-game that the warband bank is enabled.
- [x] Spell reagents: which classes and spells use reagents in Forever? Derived from DB2 (`SpellReagents` + `SpellClassOptions` + class skill lines): 23 items in 1.60.1. Gaps (e.g. Levitate) fixed in `tools/spell_reagents.csv`.
- [ ] Vendor-sold reagents: `tools/vendor_reagents.csv` (58 items) is from Classic knowledge; verify against Forever vendors after launch.
- [ ] Heuristic weights are guesses until the live economy settles after launch; plan a tuning pass a few weeks in.
- [ ] Name for the addon: "Reagent Atlas" is a working title.

**Risk:** data drift. Every Forever patch can change recipes; the build warning in Data sourcing step 5 is the guard.
