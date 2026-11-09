local addonName, ns = ...

-- Where reagents and recipe items were looted, account-wide. Positions are
-- binned to a grid so farming one spot adds to a counter, not to the file.
local LootMap = ns:RegisterModule("LootMap", {})

local GRID = 100          -- cells per map side: 1% of the map, ~10-30 yards in a zone
local NO_POSITION = 0     -- cell for loot without a map position (instances)
local NAME_WINDOW = 10    -- seconds a gathering cast's target name stays usable

LootMap.SHOW_OFF, LootMap.SHOW_TRACKED, LootMap.SHOW_ALL = 0, 1, 2

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

local function Store()
	return ns.db.lootMap
end

-- Only what the addon knows about: reagents and recipe items.
function LootMap:IsWanted(itemID)
	if ns.Reagents[itemID] then return true end
	local _, taught = ns.Tooltip:GetRecipesFor(itemID)
	return #taught > 0
end

-- Grid cells ----------------------------------------------------------------

function LootMap:ToCell(x, y)
	local gx = math.min(GRID - 1, math.max(0, math.floor(x * GRID)))
	local gy = math.min(GRID - 1, math.max(0, math.floor(y * GRID)))
	return gx * GRID + gy + 1
end

-- Center of a cell in map coordinates (0-1), or nil for NO_POSITION.
function LootMap:FromCell(cell)
	if cell == NO_POSITION then return nil end
	local gx = math.floor((cell - 1) / GRID)
	local gy = (cell - 1) % GRID
	return (gx + 0.5) / GRID, (gy + 0.5) / GRID
end

-- Position ------------------------------------------------------------------

-- Caves and other micro maps are moved onto their zone, so the zone map shows
-- them. Stays on the micro map if the client can't convert.
local function ToZone(mapID, x, y)
	local micro = Enum and Enum.UIMapType and Enum.UIMapType.Micro
	if not (micro and C_Map.GetMapInfo and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos
		and CreateVector2D) then
		return mapID, x, y
	end
	for _ = 1, 3 do
		local info = C_Map.GetMapInfo(mapID)
		if not (info and info.mapType == micro and info.parentMapID and info.parentMapID > 0) then break end
		local ok, continentID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
		if not (ok and continentID and worldPos) then break end
		local ok2, parentID, pos = pcall(C_Map.GetMapPosFromWorldPos, continentID, worldPos, info.parentMapID)
		if not (ok2 and parentID and pos) then break end
		local px, py = pos:GetXY()
		if px < 0 or px > 1 or py < 0 or py > 1 then break end
		mapID, x, y = parentID, px, py
	end
	return mapID, x, y
end

-- The player's map and position on it (0-1), caves moved onto their zone.
-- x and y are nil where the client gives no position (instances); everything
-- is nil if there's no map at all.
function LootMap:GetPlayerPosition()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local mapID = C_Map.GetBestMapForUnit("player")
	if type(mapID) ~= "number" or IsSecret(mapID) then return nil end
	local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
	local x, y
	if pos and not IsSecret(pos) then x, y = pos:GetXY() end
	if type(x) ~= "number" or type(y) ~= "number" or IsSecret(x) or IsSecret(y) or (x == 0 and y == 0) then
		return mapID
	end
	return ToZone(mapID, x, y)
end

-- mapID and cell where the player stands; cell is NO_POSITION where the
-- client gives no position (instances). nil if there's no map at all.
function LootMap:GetPlayerSpot()
	local mapID, x, y = self:GetPlayerPosition()
	if not mapID then return nil end
	if not x then return mapID, NO_POSITION end
	return mapID, self:ToCell(x, y)
end

-- Sources -------------------------------------------------------------------

local lastCast -- { name, time } of your last spell with a named target (gathering)

local function OnSpellcastSent(_, unit, target)
	if IsSecret(unit) or IsSecret(target) then return end
	if unit == "player" and type(target) == "string" and target ~= "" then
		lastCast = { name = target, time = GetTime() }
	end
end

local function UnitNameFor(guid)
	for _, unit in ipairs({ "target", "mouseover" }) do
		local unitGUID = UnitGUID and UnitGUID(unit)
		if unitGUID and not IsSecret(unitGUID) and unitGUID == guid then
			local name = UnitName(unit)
			if type(name) == "string" and not IsSecret(name) then return name end
		end
	end
	return nil
end

-- Source key of a loot slot ("npc:448", "obj:1731", "fish", "item" for
-- containers from your bags) and a display name if one is known now.
function LootMap:GetSlotSource(slot)
	if IsFishingLoot and IsFishingLoot() then return "fish" end
	if not GetLootSourceInfo then return nil end
	local ok, guid = pcall(GetLootSourceInfo, slot)
	if not ok or type(guid) ~= "string" or IsSecret(guid) then return nil end
	local unitType, _, _, _, _, id = strsplit("-", guid)
	local recentCast = lastCast and GetTime() - lastCast.time <= NAME_WINDOW and lastCast.name or nil
	if (unitType == "Creature" or unitType == "Vehicle") and tonumber(id) then
		return "npc:" .. id, UnitNameFor(guid) or recentCast
	elseif unitType == "GameObject" and tonumber(id) then
		return "obj:" .. id, recentCast
	elseif unitType == "Item" then
		return "item"
	end
	return nil
end

function LootMap:GetSourceName(src)
	local name = Store().names[src]
	if name then return name end
	if src == "fish" then return "Fishing" end
	if src == "item" then return "containers" end
	local kind, id = src:match("^(%a+):(%d+)$")
	local npc = kind == "npc" and ns.SourceNPCs and ns.SourceNPCs[tonumber(id)]
	if npc then return npc[1] end
	return kind == "obj" and "an object" or "a creature"
end

-- Recording -----------------------------------------------------------------

local snapshot = {} -- loot slot -> { itemID, count, src, mapID, cell }

local function Debug(text)
	if ns.lootDebug then ns:Print("map: " .. text) end
end

-- Remembers what each slot holds. Runs on LOOT_READY and again on
-- LOOT_OPENED; slots already noted, or already taken, are left alone.
local function Snapshot()
	if not ns.db.settings.lootMap then return end
	local mapID, cell
	for slot = 1, GetNumLootItems() do
		local link = not snapshot[slot] and GetLootSlotLink(slot)
		local itemID = type(link) == "string" and not IsSecret(link) and tonumber(link:match("item:(%d+)"))
		if itemID and LootMap:IsWanted(itemID) then
			if not mapID then mapID, cell = LootMap:GetPlayerSpot() end
			local _, _, quantity = GetLootSlotInfo(slot)
			local src, name = LootMap:GetSlotSource(slot)
			if src and name then Store().names[src] = name end
			snapshot[slot] = {
				itemID = itemID, count = tonumber(quantity) or 1, src = src,
				-- Containers opened from your bags say nothing about the place.
				mapID = src ~= "item" and mapID or nil, cell = cell,
			}
		end
	end
end

local function Add(tbl, key, count)
	tbl[key] = (tbl[key] or 0) + count
end

local function Sub(tbl, key)
	local sub = tbl[key]
	if not sub then
		sub = {}
		tbl[key] = sub
	end
	return sub
end

function LootMap:Record(itemID, count, src, mapID, cell)
	local store = Store()
	if mapID then
		Add(Sub(Sub(store.items, itemID), mapID), cell or NO_POSITION, count)
	end
	if src then
		Add(Sub(store.sources, itemID), src, count)
	end
	Debug(("item %d x%d, map %s cell %s, from %s"):format(itemID, count, tostring(mapID), tostring(cell), tostring(src)))
	ns:Fire("LOOT_MAP_CHANGED", itemID)
end

-- A slot is recorded once it's taken, so loot left behind doesn't count.
local function OnSlotCleared(_, slot)
	local entry = snapshot[slot]
	if not entry then return end
	snapshot[slot] = nil
	LootMap:Record(entry.itemID, entry.count, entry.src, entry.mapID, entry.cell)
end

local function OnLootClosed()
	wipe(snapshot)
end

-- Queries -------------------------------------------------------------------

local focus -- item picked in the browser, shown on the map with tracked ones

function LootMap:SetFocus(itemID)
	if focus == itemID then return end
	focus = itemID
	ns:Fire("LOOT_MAP_FOCUS")
end

function LootMap:GetFocus()
	return focus
end

-- Items the world map shows: a set, true for everything, or nil for none.
function LootMap:GetShownItems()
	local mode = ns.db.settings.mapPins
	if mode == self.SHOW_ALL then return true end
	if mode ~= self.SHOW_TRACKED then return nil end
	local items = ns.Tracker:GetNeededItems()
	if focus then items[focus] = true end
	return items
end

-- Looted spots on a map: array of { x, y, total, items = array of { itemID,
-- count } (most first) }. `items` is a set of itemIDs, or true for all.
function LootMap:GetSpots(mapID, items)
	local byCell = {}
	local spots = {}
	for itemID, maps in pairs(Store().items) do
		local cells = (items == true or items[itemID]) and maps[mapID]
		for cell, count in pairs(cells or {}) do
			local x, y = self:FromCell(cell)
			if x then
				local spot = byCell[cell]
				if not spot then
					spot = { x = x, y = y, total = 0, items = {} }
					byCell[cell] = spot
					spots[#spots + 1] = spot
				end
				spot.total = spot.total + count
				spot.items[#spot.items + 1] = { itemID = itemID, count = count }
			end
		end
	end
	for _, spot in ipairs(spots) do
		table.sort(spot.items, function(a, b)
			if a.count ~= b.count then return a.count > b.count end
			return a.itemID < b.itemID
		end)
	end
	return spots
end

local function MapName(mapID)
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	return info and info.name or ("Map " .. mapID)
end

local function SortedCounts(tbl)
	local list = {}
	for key, count in pairs(tbl or {}) do list[#list + 1] = { key = key, count = count } end
	table.sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return tostring(a.key) < tostring(b.key)
	end)
	return list
end

-- Where an item was looted: { total, maps = array of { mapID, name, count,
-- spots } (most first), sources = array of { key, name, count } }.
function LootMap:GetSummary(itemID)
	local summary = { total = 0, maps = {}, sources = {} }
	for mapID, cells in pairs(Store().items[itemID] or {}) do
		local count, spots = 0, 0
		for cell, n in pairs(cells) do
			count = count + n
			if cell ~= NO_POSITION then spots = spots + 1 end
		end
		summary.maps[#summary.maps + 1] = { mapID = mapID, name = MapName(mapID), count = count, spots = spots }
	end
	table.sort(summary.maps, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.mapID < b.mapID
	end)
	for _, src in ipairs(SortedCounts(Store().sources[itemID])) do
		summary.sources[#summary.sources + 1] = { key = src.key, name = self:GetSourceName(src.key), count = src.count }
		summary.total = summary.total + src.count
	end
	-- Sources are missing where the client gave none; maps then hold the count.
	local mapTotal = 0
	for _, m in ipairs(summary.maps) do mapTotal = mapTotal + m.count end
	summary.total = math.max(summary.total, mapTotal)
	return summary
end

-- "Elwynn Forest 52, Westfall 8 · mostly Copper Vein", or nil if never looted.
function LootMap:GetSummaryText(itemID)
	local summary = self:GetSummary(itemID)
	if summary.total == 0 then return nil end
	local parts = {}
	for i = 1, math.min(3, #summary.maps) do
		parts[i] = ("%s %d"):format(summary.maps[i].name, summary.maps[i].count)
	end
	if #summary.maps > 3 then parts[#parts + 1] = ("+%d more"):format(#summary.maps - 3) end
	local text = #parts > 0 and table.concat(parts, ", ") or ("%d"):format(summary.total)
	local top = summary.sources[1]
	if top then
		text = text .. " · " .. (#summary.sources > 1 and "mostly " or "from ") .. top.name
	end
	return text
end

-- The map with the most looted spots for an item, or nil.
function LootMap:GetBestMap(itemID)
	local best, bestSpots = nil, 0
	for _, m in ipairs(self:GetSummary(itemID).maps) do
		if m.spots > bestSpots then best, bestSpots = m.mapID, m.spots end
	end
	return best
end

-- Shows the item on the world map, opened on its best map. Not in combat:
-- opening the map from addon code is restricted then.
function LootMap:ShowOnMap(itemID)
	self:SetFocus(itemID)
	local mapID = self:GetBestMap(itemID)
	if not mapID then
		ns:Print("no looted spots recorded for that item yet.")
		return false
	end
	if ns.db.settings.mapPins == self.SHOW_OFF then
		ns:Print("world map pins are off (Settings > World map shows).")
	end
	if InCombatLockdown() then
		ns:Print("can't open the world map in combat.")
		return false
	end
	if C_Map.OpenWorldMap and pcall(C_Map.OpenWorldMap, mapID) then return true end
	if WorldMapFrame then
		if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
		if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
		return true
	end
	return false
end

-- Lifecycle -----------------------------------------------------------------

function LootMap:OnLogin()
	ns:RegisterEvent("LOOT_READY", Snapshot)
	ns:RegisterEvent("LOOT_OPENED", Snapshot)
	ns:RegisterEvent("LOOT_SLOT_CLEARED", OnSlotCleared)
	ns:RegisterEvent("LOOT_CLOSED", OnLootClosed)
	ns:RegisterEvent("UNIT_SPELLCAST_SENT", OnSpellcastSent)
end
