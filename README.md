<p align="center"><img src="docs/icon.png" width="128" alt="Reagent Atlas icon"></p>

# Reagent Atlas

A World of Warcraft: **Forever** addon that tells you whether the stuff you pick up is worth keeping.

Hover any item in your bags and Reagent Atlas shows:

- **Which profession recipes use it**, across all professions, with the required skill level.
- **Who can craft them**: recipes known by your current character are highlighted green, recipes known by one of your alts blue (with the alt's name).
- **A predicted value tier**: *Vendor*, *Useful*, *Valuable* or *Keep!*, estimated from recipe data and refined with Auctionator prices when available.
- **How many you own**, across bags and banks of all your characters.

A browser window (`/ratlas`) lists every reagent in the game with filters for profession, tier, owned and craftable, and optional pips mark valuable items right in your bags. Its Crafting tab works the other way round: search any recipe or craftable item to see what it takes to make, how many of each reagent you have, and who knows the recipe or where to get it.

A tracking list (`/ratlas track`, or the button in the browser) follows recipes and reagents: how many of each reagent you have and need, and where to get a recipe you don't know yet. Set a goal and you get a message and a sound when you have enough.

Reagent Atlas only displays information. It never loots, sells, posts or scans for you.

## Status

Pre-alpha, in development. Targets the WoW Forever client 1.60.x (modern addon API).

## Repository layout

| Path | What |
| --- | --- |
| `ReagentAtlas.toc`, `Core.lua`, `Data/`, `Modules/`, `UI/` | The addon itself (what gets deployed) |
| `tools/` | Data builder (`build_data.py`), deploy and setup scripts. Not shipped. |
| `docs/` | Icon and design references |
| `SPEC.md` | Full implementation spec |
| `CLAUDE.md` | Instructions for AI coding agents working on this repo |

## Development

1. Clone the repo anywhere (not inside the WoW folder).
2. Open it in VS Code with the **Lua** (LuaLS) and **WoW API** extensions.
3. Deploy to the game with `tools/deploy.ps1 -GamePath <Forever client folder>` (or set `REAGENTATLAS_GAME_PATH` once), which copies only the addon files into `Interface\AddOns\ReagentAtlas`.
4. In game: `/reload`, and keep BugSack/BugGrabber installed to catch errors.
5. Offline tests with stubbed WoW APIs: `tools/tests/run.ps1` (uses the LuaLS binary from the VS Code extension as the interpreter).
6. Regenerate `Data/` with Python 3.12+: `python tools/fetch_db2.py` (downloads the latest WoW Forever DB2 tables from wago.tools into `tools/db2/`), then `python tools/build_data.py`. `python tools/build_data.py --sample` builds from the small fixture in `tools/sample/` instead.

Recipe data in `Data/` is generated from the game client's DB2 tables with `tools/build_data.py`; don't edit it by hand. Recipe sources also use [QuestieDB](https://github.com/Questie/QuestieDB). See `SPEC.md` → *Data sourcing*.

## Optional dependencies

- [Auctionator](https://www.curseforge.com/wow/addons/auctionator): adds AH prices to the value tier.

## License

All rights reserved © TwinUnicorns (for now).
