# Reagent Atlas — Implementation Spec

Last updated: Nov 9, 2026

## Overview & goals

Reagent Atlas is a WoW Forever (client 1.60.x, modern addon API) addon that tells players whether an item they picked up is worth keeping: which profession recipes use it, which of their characters can craft those recipes, and a predicted value tier.

**Goals**

- Item tooltip shows every recipe that uses the item, across all professions.
- Recipes the current character or any alt can craft are highlighted.
- A value tier (Vendor / Common / Useful / Valuable / Keep!) is predicted from recipe data, refined by Auctionator prices when available.
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
| Item tooltip (Shift held) | Full recipe list grouped by profession, sorted by skill desc. Craftable recipes marked with a check and the character name. Recipes nobody knows show where to get them (vendor and zone, drop, quest, likely trainer, reputation hint), with one note when any of that is unconfirmed. | P0 |
| Recipe item tooltip | "Teaches <recipe>", who knows it, and who could learn it: characters with the profession who don't know it, with their rank, or rank/required when it isn't enough yet (`req` in `Data/Sources.lua`, the recipe item's required skill). Otherwise says none of your characters has the profession. Known recipes are only recorded from an opened profession window, so "could learn" can include someone who already knows it. Shift adds the reagents, have / need. | P0 |
| Crafted item tooltip | "Crafted with <profession> <skill>", then who knows it, or that nobody does with a short source tag. Shift adds the full source and the reagents, have / need. An item that is also a reagent shows both sections. | P0 |
| Alt-aware highlighting | Recipes known by the current character are green; known by an alt are blue with the alt's name; unknown are grey. | P0 |
| Account-wide inventory | Counts per character for bags + bank; tooltip shows total and a per-character breakdown on Shift. | P1 |
| Browser window | `/ratlas` opens a two-pane window: filterable reagent list (left: search, profession, min tier, owned, craftable; filters are saved, the search is not), detail pane (right: tier, AH and vendor price, owned/recipes/craftable, where the items are, recipe list marked by who knows each, with the source of unknown recipes). Movable, position saved. Hovering a reagent row shows its item tooltip. A recipe row stands for the crafted item (the spell for enchants); its icon stands for the recipe (the recipe item, or the craft spell for trainer recipes) and its tooltip adds the full source. Modified clicks on any of these work as on an item link (Shift links to chat, Ctrl previews in the dressing room). | P1 |
| Crafting tab | The browser's second tab, the reverse of the first: every recipe and what it crafts, 2,518 rows in 1.60.1. Rows and crafted items are the same list because only 7 items have more than one recipe. Search matches the crafted item or the recipe name (Copper Bar and Smelt Copper find the same row); filters are profession, known by any character, reagents in hand for one craft (account-wide), and Can learn: a character has the profession and skill and doesn't know it. Trainer recipes have no recipe item, so Can learn compares them with where they turn yellow, a little above the real requirement. Sorted by skill, highest first. The detail pane shows the reagents with have / need, then who knows the recipe or where to get it, and a Track button. Clicking a reagent opens it on the Reagents tab, a crafted item that is also a reagent has a "Used as reagent" button, and clicking a recipe row on the Reagents tab opens it here. The tab is remembered; its filters are saved in `ui.craftFilters`, the search is not. Built on first open, since listing it asks the client for every crafted item. | P1 |
| Safe to sell | A Reagents tab filter for items you own that nothing of yours uses: no character has a profession that uses them or a class that casts with them, the tracking list isn't after them, and they rate Useful or below. It replaces the owned and min tier filters while on. | P2 |
| Vendor sightings | Merchant windows are read for recipe items, and who sold them is saved in `seenVendors`. Tooltips and the detail pane show these first, as confirmed sources, since they come from Forever and not from Classic-era data. Nothing is bought or changed. | P2 |
| Crafting value | With Auctionator, the Crafting detail pane shows cost per craft, what the output sells for (all items a craft makes) and the profit after the 5% AH cut. A "Sort by" choice orders the list by profit, best first, with the profit in place of the skill; recipes without one follow, by skill. A reagent costs the vendor price if vendors sell it (`buy` in `Data/Reagents.lua`, per item) or the AH price if that's lower; other reagents use the AH price, so a reagent with no fresh price leaves the cost unknown. Crafted reagents are priced as bought, not by what they cost to make. Listing deposits aren't included. The Auctionator lookups only run for the profit sort or the selected recipe. | P2 |
| Tracking list | A small movable window (browser button, Shift-click on the minimap entries, Settings, `/ratlas track`) listing tracked recipes and reagents; it stays open across reloads and can be left open in combat. Add with Track in the browser's detail pane or + on a recipe row; a recipe is reachable from any of its reagents. A recipe shows have / need per reagent, then who knows it, or where to get it (`Sources:GetDetailLines`, with the unconfirmed note). A plain click folds it. A reagent shows the owned count, optionally against a goal. Clicking a count sets the goal in the footer box: how many of a reagent (empty clears it), or how many crafts of a recipe (needs multiply; empty means one). Reaching a goal alerts: raid-warning text, a chat line and a sound (Settings toggle, Master channel). See "Tracking list" below. | P1 |
| Loot alerts | When you loot (your own "You receive loot" chat line; quest rewards, purchases and crafts don't count) a recipe item that one of your characters could learn, or a reagent at or above the minimum tier (Settings, default Keep!), a sound plays and a notice appears at the top of the screen (`UI/LootToast.lua`: click-through, fades after 8 s), with the same detail in chat. Each item gets its icon and name; a recipe shows "Could learn" with ranks, as on its tooltip, and who already knows it; a reagent shows its tier and AH price, then each character that knows recipes using it with up to 3 of them, highest skill first (you green, alts blue), or that none does. A loot window with several such items gives one notice (up to 3 items, then "+N more, see chat") and one sound. The same item stays quiet for 10 minutes, so farming doesn't spam. Toggles for the alerts and their sound; chat text that is a secret value is skipped. `/ratlas lootdebug` (session only, a diagnostic without a UI equivalent) prints every loot message and why it did or didn't alert. | P2 |
| Loot map | Records where you loot reagents and recipe items (account-wide, all characters) and what from: the mob, the gathering node or chest, fishing, or a container from your bags. A loot slot counts once you take it; loot left in the window doesn't. Positions snap to a 100×100 grid per map (1% of the map), so farming one spot adds to a counter. Caves (micro maps) are moved onto their zone; instances have no position and are counted per map without a pin. Mob names come from your target, node names from the gathering cast (`UNIT_SPELLCAST_SENT`, used for 10 s). The world map shows pins (item icon of the most looted item there, bigger where more was looted; tooltip lists the items with counts and their main source). The minimap shows the same items' spots on your current map within its view, rotating with it and fitting round or square (ElvUI) minimaps; spots out of view are hidden, not pinned to the edge. A Settings dropdown, "World map shows", picks Nothing, Tracked and selected (default: tracked reagents with or without a goal, reagents of tracked recipes, and the reagent selected in the browser), or Everything looted. The browser's detail pane shows "Looted at: Elwynn Forest 52, Westfall 8 · mostly Copper Vein" and a Map button that opens the world map on the zone with the most spots (not in combat). Recording can be turned off in Settings; `/ratlas lootdebug` also prints what it records. | P2 |
| Waylaid Crate fill cost | A Waylaid Crate's tooltip lists the bundles that fill it (any one: e.g. 20 Peacebloom or 10 Mageroyal), cheapest first: bundle cost at the vendor price if vendors sell the reagent and it's lower, else the fresh AH price (same rule as Crafting value), and the owned total. Collapsed shows the 3 cheapest and "N more"; Shift shows all, with price ages and vendor prices marked. Bundles without a price follow, most owned first. Without Auctionator only vendor prices show, with a note. Favor rewards are not shown. Bundles are `Data/Crates.lua`. | P2 |
| Bag markers | Small tier-colored diamond pip in the top-left corner of default bag slots at or above the minimum tier (default Valuable). Toggleable. Hooks each bag window's `UpdateItems` (retail container frames in Forever); the bank window is not marked. With ElvUI, whose bags replace those windows, it hooks ElvUI's `UpdateSlot` instead, which also marks ElvUI's bank windows. | P2 |
| Settings | Toggles for tooltip, markers, minimap icon, Auctionator use, tracking and loot alert sounds, loot alerts, loot map recording, minimum tiers for markers and loot alerts, what the world map shows, and an Open button for the browser. A "Status & characters" subpage shows version, data build and price source, lists tracked characters with a confirmed Forget button, and lists learned recipes missing from the data. Uses the modern Settings panel (Esc → Options → AddOns, the gear in the browser, right-click on the minimap icon, or `/ratlas config`; not in combat). | P2 |
| Minimap access | Always an entry in Blizzard's AddOns button by the minimap (runtime `AddonCompartmentFrame:RegisterAddon`, so no global), plus a draggable round icon that can be turned off. Left-click: browser. Right-click: settings. Angle saved in `ui.minimapAngle`. Own code, no LibDBIcon. | P2 |
| No typing required | Every slash command has a UI equivalent; the commands stay as shortcuts. | P1 |

Tier colors follow item quality: Vendor = grey, Common = white, Useful = green, Valuable = blue, Keep! = orange.

### Tracking list

The window has two views, switched by a button and remembered in `ui.trackerView`: the list itself, and a shopping list. The shopping list adds up what all tracked recipes need and shares your reagents out across them, then shows what is still to get (vendor goods marked), what to craft first and who can, and the totals. A reagent you're short of is broken down into what makes it when a character knows the recipe, unless vendors sell it or the recipe only converts another material (`conv` in `Data/Recipes.lua`). Stock is spent as it goes, and what a batch makes beyond the need (`n`, items per craft) serves the next demand. Reagent goals aren't included: they may be for the same recipes, and adding them would count those twice.

Counts are the same account-wide total as everywhere else (bags and banks of every character plus the warband bank), so a goal can be met by items on an alt; hovering a row shows where they are. Each entry counts on its own: two recipes needing the same 5 bars are both met by 5 bars.

Alerts fire when a goal goes from unmet to met, and a goal that falls short again re-arms. The `done` flag is saved, so a met goal stays quiet after a relog, and one you already meet when you set it never alerts: only a later gain does. A reagent without a goal never alerts.

Two guards keep counts in flux from causing false alerts:

- Items moved between bags and bank are counted twice or not at all until the bank scan runs (0.2 s after the bag scan). Goals are checked once counts have been quiet for 0.5 s, so that delay must stay above `BANK_SCAN_DELAY`.
- Bags can read as partly empty right after login, which would re-arm met goals and alert on every login. The first check runs 5 s after login.

## Architecture & file layout

Plain Lua + XML-free frames (create everything in Lua), no external libraries in v1. One shared namespace table via `local addonName, ns = ...`.

```
ReagentAtlas/
  ReagentAtlas.toc          -- Interface version, SavedVariables, load order
  Core.lua                  -- ns init, event dispatcher, slash command, ADDON_LOADED
  Data/
    Reagents.lua            -- generated: itemID -> recipe refs, spell reagent info
    Recipes.lua             -- generated: recipeID -> profession, skill, output itemID, reagents
    Sources.lua             -- generated: recipeID -> where to get the recipe
    Crates.lua              -- generated: Waylaid Crate -> bundles that fill it
  Modules/
    Inventory.lua           -- scans bags/bank, writes per-character counts
    Professions.lua         -- records known recipes per character
    Pricing.lua             -- Auctionator bridge, returns price or nil
    Valuation.lua           -- tier heuristic, combines data + price
    Sources.lua             -- recipe source tags and detail lines
    Tracker.lua             -- tracked recipes and reagents, goals, alerts
    Tooltip.lua             -- TooltipDataProcessor hook, collapsed/expanded render
    BagMarkers.lua          -- tier pips on bag item buttons
    LootAlert.lua           -- alerts for looted learnable recipes and valuable reagents
    LootMap.lua             -- records where reagents were looted and from what; map queries
  UI/
    Browser.lua             -- main window, tabs, reagent list (ScrollBox), filters, detail pane
    Crafting.lua            -- Crafting tab: recipe and crafted item list, detail pane
    TrackerWindow.lua       -- tracking list window
    LootToast.lua           -- on-screen loot alert notice
    MapPins.lua             -- world map pins for looted spots (data provider + own frames)
    MinimapPins.lua         -- minimap pins for looted spots near you
    Settings.lua            -- Settings panel, status & characters subpage
    MinimapButton.lua       -- minimap icon and AddOns button entry
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
  n = 5,                 -- optional: items made per craft, when more than one
  conv = true,           -- optional: only converts another material (see Crafting chain)
  reagents = { [17012] = 2, [15407] = 1 }, -- itemID -> count
}

-- Data/Reagents.lua (inverted index, built by the tool)
ns.Reagents[itemID] = {
  r = { recipeSpellID, ... },  -- sorted by skill desc
  spell = { "MAGE", "ROGUE" }, -- optional: classes using it as a spell reagent
}

-- Data/Sources.lua (recipes with a recipe item; absent = probably a trainer)
ns.RecipeSources[recipeSpellID] = {
  i = 12233,                 -- recipe item
  req = 300,                 -- skill the recipe item requires
  v = { npcID, ... },        -- vendors
  q = { "Quest name", ... }, -- quest rewards
  d = { npcID, ... },        -- droppers, when at most 5
  dn = 69, dz = { "Zone", ... }, dzn = 12, -- else: creature count, top 3 zones, zone count
  o = true,                  -- chests or containers
  fac = "Cenarion Circle", rep = "Friendly", -- required reputation
}
ns.SourceNPCs[npcID] = { "Name", "Zone", "AH" } -- sides: "A", "H", "AH" or "" (unrecorded)

-- Data/Crates.lua (Waylaid Crates; fill with any one bundle, no mixing)
ns.Crates[crateItemID] = { { 2447, 20 }, { 785, 10 }, ... } -- { reagent itemID, count }, client order
```

**SavedVariables: `ReagentAtlasDB`**

```lua
ReagentAtlasDB = {
  version = 1,
  settings = { tooltip = true, markers = true, useAuctionator = true, markerMinTier = 3, minimapIcon = true, trackerSound = true, lootAlerts = true, lootSound = true, lootMinTier = 5, lootMap = true, mapPins = 1 }, -- mapPins: 0 off, 1 tracked and selected, 2 all
  ui = { point = {...}, filters = {...}, craftFilters = {...}, browserTab = "reagents", minimapAngle = 225, trackerPoint = {...}, trackerShown = true },
  tracked = {  -- in the order added
    { kind = "item", id = itemID, need = 20, done = true },            -- need optional
    { kind = "recipe", id = recipeSpellID, need = 1, collapsed = true }, -- need = crafts
  },
  chars = {
    ["Name-Realm"] = {
      class = "MAGE", faction = "Horde", lastSeen = 1730000000,
      profs = { [165] = { rank = 240, known = { [recipeSpellID] = true } } },
      bags = { [itemID] = count },
      bank = { [itemID] = count },
    },
  },
  account = { bank = { [itemID] = count } },  -- warband bank, shared by all characters
  seenVendors = { [recipe itemID] = { [npcID] = { "Name", "Zone" } } }, -- from merchant windows
  lootMap = {
    items = { [itemID] = { [uiMapID] = { [cell] = count } } }, -- cell = gx * 100 + gy + 1; 0 = no position
    sources = { [itemID] = { ["npc:448"] = count, ["obj:1731"] = count, fish = count, item = count } },
    names = { ["npc:448"] = "Hogger", ["obj:1731"] = "Copper Vein" }, -- seen at loot time
  },
}
```

Keys are `Name-Realm`. Only counts are stored, never item links, and only for items in `ns.Reagents`, to keep the file small. `/ratlas forget Name-Realm` removes a deleted character. A migration function runs on `version` mismatch.

## Data sourcing

The in-game API only lists recipes a character knows, so the full recipe database is generated offline from the client's DB2 tables and shipped with the addon.

1. Download the DB2 tables as CSV with `python tools/fetch_db2.py [version]`. It pulls them from wago.tools, which tracks WoW Forever as product `wowf` (first build seen: 1.60.1.70707). They land in `tools/db2/` (git-ignored). Exporting from a local client with wow.tools.local or DBC2CSV also works.
2. Join them in `tools/build_data.py`:
   - `SkillLineAbility` → recipe spell ID to profession skill line and skill. Forever leaves `MinSkillLineRank` at 1, so the skill the recipe is learned at comes from, in order: the recipe item's `RequiredSkillRank` (exact); 1 for `AcquireMethod` 1 (learned with the profession); the trainer requirement from the CMaNGOS Classic world DB (`npc_trainer`, GPL-3.0, pinned in `tools/fetch_db2.py`), mapped from teaching spell to recipe with Classic Era's `SpellEffect` and shifted by how far Forever moved the recipe's yellow rank from Classic Era's `SkillLineAbility` (Forever rebalanced many recipes: Small Silk Pack is yellow 170 in Classic, 145 in Forever, so trainer 150 becomes 125); else `TrivialSkillLineRankLow` (where the recipe turns yellow), capped so a trainer value never exceeds it. On recipe items, where the answer is known, the shift is exact for 865 of 893. In 1.60.1.70862: 1,802 from items, 34 with the profession, 424 from trainers, 258 at yellow (mostly new Forever recipes).
   - `SpellReagents` → reagent itemIDs and counts per spell (recipes and class spells)
   - `SpellEffect` (create-item effect) → output itemID, items made per craft (`EffectBasePointsF`)
   - `ItemSparse` → item quality, vendor sell price, vendor buy price per item (`BuyPrice` / `VendorStackCount`)
   - `SkillLine` → child (tier) skill lines folded into their parent profession; class skill lines
   - `SpellClassOptions` → class of a spell (spell family) for spell reagents
   - `SpellName` → used to drop test/DND spells
3. Filter to primary + secondary professions plus Poisons, drop internal or test spells and Season of Discovery engraving leftovers, drop duplicate recipes (same profession, output and reagents).
4. Emit `Data/Recipes.lua` (with `ns.DATA_BUILD` and `ns.MAX_SKILL`, the highest recipe skill) and the inverted `Data/Reagents.lua` (recipes, own quality `q`, vendor sell price `sell`, spell classes, `vendor` flag with its price `buy`).
5. Re-run on every client build. Chat shows a one-time warning per client build if `ns.DATA_BUILD` differs from `GetBuildInfo()`.

Three hand-maintained lists cover what the DB2 data lacks: `tools/spell_reagents.csv` (overrides for the spell reagent mapping), `tools/vendor_reagents.csv` (reagents NPC vendors sell; vendor inventories are server data) and `tools/crate_bundles.csv` (Waylaid Crate bundles).

**Waylaid Crates:** typed crates (items 248682–248713, names starting "Waylaid Crate: ") are filled with one bundle of one reagent and turned in for Merchant's Favor. No API lists the bundles, and the client data holds only their counts: each crate's "Stock Crate" use spell (via `ItemXItemEffect` → `ItemEffect`) has one Dummy effect (type 3) per bundle with the count in `EffectBasePointsF`; which reagent goes with each count is server data. `tools/crate_bundles.csv` pairs them (from player guides, Nov 2026) in effect order, and the build stops if a count, the order, an item name or the set of crates differs from the client. 30 crates, 96 bundles in 1.60.1.70862.

**Recipe sources:** vendors and loot are server data, and Forever's API has no `GetRecipeSourceText`, so `Data/Sources.lua` joins two inputs:

- Client tables: `SpellEffect` (learn-spell effect) + `ItemEffect` + `ItemXItemEffect` + `Item` (class 9) link a recipe to its recipe item; `ItemSparse` gives the required reputation; `Faction` and `AreaTable` give names.
- QuestieDB's Forever tables at the commit pinned in `tools/fetch_db2.py`: vendors, drops, containers, quest rewards, NPC zones. They are read as text, never executed. Bump the pin on purpose and review the `Data/Sources.lua` diff.
- QuestieDB's static correction layers, applied over those tables in QuestieDB's order: legacy Classic fixes, then player traces (aggregated from Forever players' sessions), then authored Forever fixes. A field is replaced, or `_add` / `_remove` edits a list. Dynamic and faction-specific fixes are skipped. Read as text too; an unknown `zoneIDs` name stops the build.
- Left out on purpose: QuestieDB's generated delta-base (`src/corrections/Forever/generated/`), which sits between legacy and traces. It is scraped from Wowhead, so we have no licence to ship it (see Open questions). With it, named sources would rise to about 1,268.

Coverage in 1.60.1.70862 (2,518 recipes): 840 name a source, 98 have only a reputation hint, 865 have a recipe item with no known source, 715 have no recipe item and read "Trainer (likely)", which is an inference. 122 of the 1,059 recipe items with IDs of 25000 or above (new in the Forever client) have a source, all from the trace and authored layers. The named sources are mostly Classic-era and unconfirmed in Forever, so the UI says so.

**Fallback / validation:** `Professions.lua` notes learned recipes seen in an open profession window that the generated data lacks. `/ratlas diff` lists them (session only; reagent lists are not compared yet).

## Value tier & Auctionator

The tier is a prediction, not a price: a score from recipe data, optionally nudged by Auctionator. All weights live in one table in `Valuation.lua` so they can be tuned after launch.

**Heuristic score (0–100)** — calibrated on the Forever 1.60.1 data (613 reagents)

| Signal | Points |
| --- | --- |
| Highest skill of any recipe using it | min(skill / `MAX_SKILL`, 1) × 35 (`MAX_SKILL` = 325 in 1.60.1) |
| Number of recipes using it | min(log(1 + max(count, chain)) / log(41), 1) × 15 (full at 40 recipes) |
| High-end recipes in its crafting chain | min(log(1 + chain) / log(101), 1) × 20 (full at 100 recipes) |
| Best output quality among those recipes | +5 rare, +10 epic |
| Used in 2+ professions | +5 |
| The reagent's own quality | +10 uncommon, +15 rare, +20 epic or better |
| Spell reagent | tier at least Common (no score bonus) |
| Material: fills a Waylaid Crate, or a non-conversion recipe makes a reagent used in 10+ recipes (smelting, curing, bolts) | tier at least Common (no score bonus) |
| Sold by NPC vendors | tier capped at Common |
| Not used in any recipe and not a spell reagent | no tier (nothing shown) |

Tiers: 0–14 Vendor, 15–34 Common, 35–54 Useful, 55–74 Valuable, 75+ Keep! The browser sorts by tier, then score, then name. Before saved-data version 2 there were four tiers (15–44 Useful, 45–77 Valuable, 78+ Keep!), which put 215 reagents on Valuable, from Wool bolts to Fel Leather; saved tier settings are moved up one step by the DB migration.

**Crafting chain** (`deep` in `Data/Reagents.lua`): the number of distinct recipes at skill 250 or above that an item reaches, directly or through what it crafts, so a reagent with few recipes still counts for what its output feeds. Arcane Crystal has 3 direct recipes and 109 in its chain through Arcanite Bar. Only high-end recipes count, because raw chains favour starter materials (Copper Ore reaches 188 recipes, 1 of them high-end). Conversions are not followed, since their output also comes from elsewhere: single-input transmutes (Fire to Earth) and leather up-conversions (Light to Medium). Smelting and cloth bolts are followed. Skill 250 is `HIGH_END_SKILL` in `tools/build_data.py`.

Resulting spread on 1.60.1.70862: 63 Keep!, 114 Valuable, 177 Useful, 202 Common, 57 Vendor (data tiers, before AH prices). Examples: Arcanite Bar, Essences, Arcane Crystal, Black Lotus, Thorium Bar, Truesilver Bar, Mithril Bar, Rugged Leather → Keep!; Iron Bar, Mithril Ore, Heavy and Thick Leather, Thorium Ore, Runecloth → Valuable; Linen, Wool, Silk, Light Leather, Copper Bar → Useful; Peacebloom, Mageroyal → Common; Copper Ore, Tin Ore, Tin Bar, Light and Medium Hide → Common (material floor; Vendor by score); single-use meats and fish → Vendor; dyes, threads, vials, spices → Common (vendor cap).

The first draft (skill / 300 × 40, min(count, 10) × 2, +10/+20 for output quality, +10 for spell reagents) put 114 reagents on Keep! and most vendor goods on Valuable or Keep!, because recipe counts saturate at 10 and common materials are used in 50–200 recipes.

**Auctionator bridge (`Pricing.lua`)**

- Detect with `Auctionator and Auctionator.API and Auctionator.API.v1`.
- Price: `Auctionator.API.v1.GetAuctionPriceByItemID("ReagentAtlas", itemID)` → copper or nil.
- Freshness: `Auctionator.API.v1.GetAuctionAgeByItemID("ReagentAtlas", itemID)` → days or nil; ignore prices older than 7 days.
- Price age 0 means seen today. If Auctionator has no age function, the price is used without one.
- Wrap every call in `pcall`; on any error disable the bridge for the session (one chat notice; `/ratlas version` shows the reason).
- Optional: `Auctionator.API.v1.RegisterForDBUpdate("ReagentAtlas", fn)` fires the internal `PRICES_CHANGED` message after a scan, for UI that needs to redraw. Prices are not cached; ages are, for 60 seconds or until that message, because Auctionator sorts the item's whole price history to answer.
- When a fresh price exists: if price ≥ 5 × vendor price **and** ≥ 1g, raise the tier one step (max Keep!); if price < vendor price, cap at Common. Vendor-sold reagents stay capped at Common (their AH price is just the vendor markup). Items without a vendor sell price are not adjusted. The 1g floor keeps cheap commons (Linen, Copper Ore at 20× vendor) from rising; it is in `Valuation.WEIGHTS` with the other knobs.
- Tooltip shows the price beside the tier, as in the mockup: "Reagent Atlas: Valuable · AH 1s 20c", plus "(N days old)" from 1 day on.
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
| Vendors | `MERCHANT_SHOW`, `MERCHANT_UPDATE`, `GetMerchantNumItems`, `GetMerchantItemID`, `UnitGUID("npc")` | Record recipe items for sale. Auctionator uses the first three on Forever. |
| Items | `C_Item.GetItemInfo`, `Item:CreateFromItemID():ContinueOnItemLoad` | Names, icons, quality; handle uncached items async. |
| Character | `UnitName`, `GetNormalizedRealmName`, `UnitClass` | Build the `Name-Realm` key. |
| UI list | `CreateScrollBoxListLinearView`, `ScrollUtil.InitScrollBoxListWithScrollBar` | Virtualized reagent list in the browser. |
| Settings | `Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterAddOnCategory` | Options panel. |
| Alerts | `RaidNotice_AddMessage(RaidWarningFrame, text, color)`, fallback `UIErrorsFrame:AddMessage`; `PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master")`, fallback kit 888 | Tracking list goals (`ns:ShowAlert` in Core; loot alerts use their own notice and `ns:PlayAlertSound`). The names come from retail annotations; the raid notice and kit 888 are used by addons running on Forever. Loot alerts play `SOUNDKIT.RAID_WARNING`, fallback kit 8959. |
| Loot | `CHAT_MSG_LOOT`, `LOOT_ITEM_SELF`, `LOOT_ITEM_SELF_MULTIPLE`, `issecretvalue` | Your own loot, matched with the client's localized strings (English fallback). Secret chat text is skipped. |
| Loot map | `LOOT_READY`, `LOOT_OPENED`, `LOOT_SLOT_CLEARED`, `LOOT_CLOSED`, `GetNumLootItems`, `GetLootSlotLink`, `GetLootSlotInfo`, `IsFishingLoot`, `GetLootSourceInfo` (guarded, pcall), `UNIT_SPELLCAST_SENT`, `UnitGUID` | Slots are noted when the window opens and recorded when taken. Blizzard's Forever loot frame uses all of these except `GetLootSourceInfo` (a retail global, not in the generated docs). |
| Loot map | `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition`, `C_Map.GetMapInfo`, `C_Map.GetWorldPosFromMapPos` / `GetMapPosFromWorldPos`, `C_Map.OpenWorldMap` (restricted; pcall, fallback `ToggleWorldMap` + `SetMapID`) | Player position (nil in instances), caves onto their zone, opening the map. All in Forever's `MapDocumentation`. |
| World map | `WorldMapFrame:AddDataProvider`, `MapCanvasDataProviderMixin`, `GetCanvas`, `GetCanvasScale`, `GetMapID` | Forever's world map (Camelot variant) is the standard MapCanvas. Pins are own frames on the canvas, not Blizzard pin pools (those need an XML template). |
| Minimap | `C_Minimap.GetViewRadius` (yards), `C_Map.GetMapWorldSize` (yards), `C_Map.GetPlayerMapPosition`, `C_CVar.GetCVar("rotateMinimap")`, `GetPlayerFacing` (guarded, not in the generated docs), `GetMinimapShape` (defined by minimap addons such as ElvUI; "SQUARE") | Offset in yards = map position difference × map size, scaled by half the minimap width over the view radius, rotated by facing when the minimap rotates. Updated every 0.1 s; spots cached until the data, tracking, selection or settings change. |

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
- [x] `## Interface:` number: `16001` on Forever 1.60.1 (from the TOCs of ElvUI, BugSack, Auctionator and ToxiUI's Camelot build; the client reported 16000 as out of date). Re-check on every major patch.
- [x] Esc closing the browser would need a named frame in `UISpecialFrames`, i.e. a second global. Decided: keep one global, no Esc; the window closes with its X, the minimap entries or `/ratlas`.
- [x] Does the Forever build of Auctionator keep `Auctionator.API.v1`? Yes: version 341 has `GetAuctionPriceByItemID`, `GetAuctionAgeByItemID` and `RegisterForDBUpdate`.
- [x] Forever bank layout: classic bank bags or retail-style bank tabs? Retail-style tabs (Enum.BagIndex 6-14 character, 15-23 warband) plus a reagent bag (5), per the Forever 1.60.1 API docs. Confirm in-game that the warband bank is enabled.
- [x] Spell reagents: which classes and spells use reagents in Forever? Derived from DB2 (`SpellReagents` + `SpellClassOptions` + class skill lines): 23 items in 1.60.1. Gaps (e.g. Levitate) fixed in `tools/spell_reagents.csv`.
- [ ] Vendor-sold reagents: `tools/vendor_reagents.csv` (58 items) is from Classic knowledge; verify against Forever vendors after launch.
- [ ] Recipe sources: confirm Classic-era vendors and drops against Forever. New Forever recipes (most of the 865 unknown in 1.60.1.70862, some possibly unused Season of Discovery leftovers) have no source yet; re-check QuestieDB's trace layer as it fills in. Merchant-window recording now covers what you visit; each player's sightings stay local.
- [ ] Recipe learn skill: trainer values are Classic (CMaNGOS) shifted onto Forever's ranks. Spot-check trainer-taught recipes at a trainer in-game, especially rebalanced ones (Small Silk Pack should read 125).
- [x] Licensing: `Data/Sources.lua` derives from QuestieDB, which allows copying under GPLv3 terms but cannot promise every historic contributor agreed. Decided: the addon is GPL-3.0 (`LICENSE`, credited in the README), and QuestieDB's generated delta-base stays out, since it is scraped from Wowhead (its `docs/forever-delta-base.md`) and its licence says nothing about third-party data. Some legacy Questie data may also trace back to Wowhead; revisit if that becomes a problem.
- [ ] Tracking list alert: confirm in-game that `SOUNDKIT.IG_QUEST_LIST_COMPLETE` plays on Forever and is loud enough (Blizzard's Forever constants could not be checked offline).
- [ ] Loot alerts: confirm in-game that `CHAT_MSG_LOOT` arrives as "You receive loot: [item]" (and "...x3" for stacks) for mob loot, gathering and containers, that it isn't a secret value in dungeons or combat, and that `SOUNDKIT.RAID_WARNING` plays.
- [x] World map pins sit just above Blizzard's super-tracked quest pin level (`GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST")`, Blizzard pins start at 2000), so quest markers no longer hide them and the player arrow stays on top. Confirmed in-game (Nov 11).
- [ ] Loot map: confirm in-game that `GetLootSourceInfo` exists and returns `Creature-…` / `GameObject-…` GUIDs (without it, sources are just missing), that `GetPlayerMapPosition` gives positions outdoors, that `UNIT_SPELLCAST_SENT` names gathering nodes, that pins sit above the map art (frame level) and keep their size when zooming, and that the Map button opens the map (`C_Map.OpenWorldMap` is marked restricted). World map and minimap pins confirmed working in-game (Nov 9, ElvUI minimap). Group loot rolls may count an item whose slot was cleared for a roll you didn't win.
- [x] Waylaid Crates: the crate tooltip shows the fill block alongside ElvUI and Auctionator, and the bundles match the crate's own "Fill the crate with any bundle" list. Confirmed in-game (Nov 11).
- [x] Waylaid Crates: a 40-count bundle (more than one stack) fills: target a stack of the reagent and the crate takes the whole bundle. Confirmed in-game (Nov 11).
- [ ] Heuristic weights are guesses until the live economy settles after launch; plan a tuning pass a few weeks in.
- [ ] Name for the addon: "Reagent Atlas" is a working title.

**Risk:** data drift. Every Forever patch can change recipes; the build warning in Data sourcing step 5 is the guard.
