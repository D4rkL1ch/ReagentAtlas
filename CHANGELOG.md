# Reagent Atlas

## 0.2.0

### New: loot map

- Reagent Atlas now remembers where you loot reagents and recipe items, and what they came from: the mob, the herb or ore node, fishing, or a container.
- Pins on the **world map** and the **minimap** show where you looted your tracked reagents and the reagent selected in the browser. Hover a pin to see what you looted there and what it came from.
- The browser shows **Looted at** for each reagent, with a **Map** button that opens the world map where you looted it most.
- New settings: **Record loot locations** and **World map shows** (Nothing, Tracked and selected, Everything looted).
- `/ratlas lootdebug` now also shows what the loot map records.

Only loot from after you update is recorded. After updating, exit the game completely and start it again: `/reload` doesn't load the new files.
