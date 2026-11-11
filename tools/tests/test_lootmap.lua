---@diagnostic disable: undefined-global, lowercase-global, assign-type-mismatch
-- Loot map: where reagents and recipe items were looted, and the world map pins.
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

local FEATHER, ARCANITE, LINEN_CLOTH = 17056, 12360, 2589
local JUNK = 424242   -- no recipe uses it
local PATTERN = 9001  -- teaches 990004
local ELWYNN, WESTFALL, CAVE, DUNGEON = 1429, 1436, 2001, 3001

-- Loot window and map state, read by the API stubs below.
local L

local function vec(x, y)
	return { GetXY = function() return x, y end }
end

local function install()
	L = {
		slots = {}, -- slot -> { itemID, count, guid }
		fishing = false,
		mapID = ELWYNN, x = 0.423, y = 0.651,
		target = nil, -- { guid, name }
		mapInfo = {
			[ELWYNN] = { name = "Elwynn Forest", mapType = 3, parentMapID = 13 },
			[WESTFALL] = { name = "Westfall", mapType = 3, parentMapID = 13 },
			[CAVE] = { name = "Jasperlode Mine", mapType = 5, parentMapID = ELWYNN },
			[DUNGEON] = { name = "The Deadmines", mapType = 4, parentMapID = WESTFALL },
		},
		opened = nil,
		unitSwap = false, -- UnitPosition gives the world axes in the other order
		calls = { vec = 0, info = 0, pos = 0 }, -- allocating API calls, for the minimap
	}
	Enum.UIMapType = { Zone = 3, Dungeon = 4, Micro = 5 }
	CreateVector2D = function(x, y)
		L.calls.vec = L.calls.vec + 1
		return vec(x, y)
	end
	-- World axes as in WoW: the first grows north, the second west. Zones are
	-- 1000 x 600 yards with their top-left corner at the origin.
	UnitPosition = function()
		if L.x == nil or L.mapID == DUNGEON then return nil end
		local a, b = -600 * L.y, -1000 * L.x
		if L.unitSwap then a, b = b, a end
		return a, b, 0, 0
	end
	GetNumLootItems = function() return #L.slots end
	GetLootSlotLink = function(slot)
		local s = L.slots[slot]
		return s and s[1] and ("|cffffffff|Hitem:%d::::|h[x]|h|r"):format(s[1]) or nil
	end
	GetLootSlotInfo = function(slot)
		local s = L.slots[slot]
		return 1, "x", s and s[2] or 0
	end
	GetLootSourceInfo = function(slot)
		local s = L.slots[slot]
		return s and s[3], s and s[2]
	end
	IsFishingLoot = function() return L.fishing end
	UnitGUID = function(unit) return unit == "target" and L.target and L.target[1] or nil end
	local unitName = UnitName
	UnitName = function(unit)
		if unit == "target" and L.target then return L.target[2] end
		return unitName(unit)
	end
	C_Map = {
		GetBestMapForUnit = function() return L.mapID end,
		GetPlayerMapPosition = function(mapID)
			L.calls.pos = L.calls.pos + 1
			if L.x == nil or mapID == DUNGEON then return nil end
			return vec(L.x, L.y)
		end,
		GetMapInfo = function(mapID)
			L.calls.info = L.calls.info + 1
			return L.mapInfo[mapID]
		end,
		GetWorldPosFromMapPos = function(mapID, pos)
			local x, y = pos:GetXY()
			if mapID == CAVE then return 0, vec(x, y) end
			if mapID == ELWYNN or mapID == WESTFALL then return 0, vec(-600 * y, -1000 * x) end
			return nil
		end,
		-- The cave covers (0.3-0.4, 0.5-0.6) of Elwynn.
		GetMapPosFromWorldPos = function(_, worldPos, mapID)
			local x, y = worldPos:GetXY()
			return mapID, vec(0.3 + x * 0.1, 0.5 + y * 0.1)
		end,
		OpenWorldMap = function(mapID) L.opened = mapID end,
		GetMapWorldSize = function() return 1000, 600 end,
	}
	C_Minimap = { GetViewRadius = function() return 100 end }
	issecretvalue = nil
end

local function uninstall()
	GetNumLootItems, GetLootSlotLink, GetLootSlotInfo, GetLootSourceInfo, IsFishingLoot = nil, nil, nil, nil, nil
	UnitGUID, C_Map, CreateVector2D, Enum.UIMapType, issecretvalue = nil, nil, nil, nil, nil
	UnitPosition = nil
	WorldMapFrame, MapCanvasDataProviderMixin, CreateFromMixins = nil, nil, nil
	C_Minimap, GetMinimapShape, GetPlayerFacing, C_CVar = nil, nil, nil, nil
end

local savedUnitName = UnitName

local function boot(savedVars, setup)
	UnitName = savedUnitName
	install()
	local ns = T.boot(savedVars or { version = 2 }, function(ns)
		T.useFixture(ns)
		if setup then setup(ns) end
	end)
	ns.RecipeSources = { [990004] = { i = PATTERN } }
	stubs.printed = {}
	return ns
end

local function npc(id) return ("Creature-0-3767-0-27-%d-0000ABCDEF"):format(id) end
local function obj(id) return ("GameObject-0-3767-0-27-%d-0000ABCDEF"):format(id) end

-- Opens a loot window with `slots`, takes the slots listed in `take` (all by
-- default), then closes it.
local function loot(slots, take)
	L.slots = slots
	stubs.fire("LOOT_READY")
	stubs.fire("LOOT_OPENED")
	for slot = 1, #slots do
		if not take or take[slot] then
			stubs.fire("LOOT_SLOT_CLEARED", slot)
			L.slots[slot] = {}
		end
	end
	stubs.fire("LOOT_CLOSED")
end

local function cellAt(ns, x, y) return ns.LootMap:ToCell(x, y) end

-- Recording -----------------------------------------------------------------

test("loot map: taken reagents are counted at the spot, with the mob's name", function()
	local ns = boot()
	L.target = { npc(448), "Hogger" }
	loot({ { FEATHER, 3, npc(448) }, { JUNK, 1, npc(448) } })
	local store = ns.db.lootMap
	eq(store.items[FEATHER][ELWYNN][cellAt(ns, 0.423, 0.651)], 3, "count in the cell")
	eq(store.items[JUNK], nil, "items no recipe uses are not recorded")
	eq(store.sources[FEATHER]["npc:448"], 3, "source")
	eq(store.names["npc:448"], "Hogger", "mob name from the target")

	-- Same spot, a step away: same cell, adds up.
	L.x = 0.428
	loot({ { FEATHER, 2, npc(448) } })
	eq(store.items[FEATHER][ELWYNN][cellAt(ns, 0.423, 0.651)], 5, "binned")
	eq(#stubs.errors, 0, "no errors")
end)

test("loot map: loot left in the window is not recorded", function()
	local ns = boot()
	loot({ { FEATHER, 1, npc(448) }, { ARCANITE, 2, npc(448) } }, { [2] = true })
	eq(ns.db.lootMap.items[FEATHER], nil, "left behind")
	eq(ns.db.lootMap.items[ARCANITE][ELWYNN][cellAt(ns, 0.423, 0.651)], 2, "taken")
	-- A later window reusing slot 1 doesn't inherit the old snapshot.
	loot({ { LINEN_CLOTH, 1, npc(1) } })
	eq(ns.db.lootMap.items[FEATHER], nil, "still not recorded")
	eq(ns.db.lootMap.items[LINEN_CLOTH][ELWYNN][cellAt(ns, 0.423, 0.651)], 1, "new window")
end)

test("loot map: recipe items, gathering nodes, fishing and containers", function()
	local ns = boot()
	local store = ns.db.lootMap
	loot({ { PATTERN, 1, npc(9) } })
	eq(store.items[PATTERN][ELWYNN][cellAt(ns, 0.423, 0.651)], 1, "recipe item")

	stubs.now = 100
	stubs.fire("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "Cast-1", 2575)
	loot({ { ARCANITE, 1, obj(1731) } })
	eq(store.sources[ARCANITE]["obj:1731"], 1, "node source")
	eq(store.names["obj:1731"], "Copper Vein", "node name from the gathering cast")

	stubs.now = 200 -- the cast is too old to name another object
	loot({ { ARCANITE, 1, obj(1732) } })
	eq(store.names["obj:1732"], nil, "stale cast not used")
	eq(ns.LootMap:GetSourceName("obj:1732"), "an object", "fallback name")

	L.fishing = true
	loot({ { LINEN_CLOTH, 2, nil } })
	L.fishing = false
	eq(store.sources[LINEN_CLOTH].fish, 2, "fishing")
	eq(ns.LootMap:GetSourceName("fish"), "Fishing", "fishing name")

	loot({ { FEATHER, 4, "Item-3767-0-4000000ABCDEF" } })
	eq(store.items[FEATHER], nil, "containers from bags say nothing about the place")
	eq(store.sources[FEATHER].item, 4, "but count as a source")
end)

test("loot map: instances without a position, caves moved onto their zone", function()
	local ns = boot()
	local store = ns.db.lootMap
	L.mapID = DUNGEON
	loot({ { FEATHER, 2, npc(639) } })
	eq(store.items[FEATHER][DUNGEON][0], 2, "no position: cell 0")
	eq(#ns.LootMap:GetSpots(DUNGEON, true), 0, "no pin without a position")
	contains(ns.LootMap:GetSummaryText(FEATHER), "The Deadmines 2", "summary still counts it")

	L.mapID, L.x, L.y = CAVE, 0.5, 0.5
	loot({ { ARCANITE, 1, obj(1731) } })
	eq(store.items[ARCANITE][CAVE], nil, "not on the cave map")
	eq(store.items[ARCANITE][ELWYNN][cellAt(ns, 0.35, 0.55)], 1, "on Elwynn, inside the cave's area")
end)

test("loot map: recording off, secret values", function()
	local ns = boot()
	ns.db.settings.lootMap = false
	loot({ { FEATHER, 1, npc(448) } })
	eq(ns.db.lootMap.items[FEATHER], nil, "off")

	ns.db.settings.lootMap = true
	issecretvalue = function(v) return v == npc(448) end
	loot({ { FEATHER, 1, npc(448) } })
	eq(ns.db.lootMap.items[FEATHER][ELWYNN][cellAt(ns, 0.423, 0.651)], 1, "recorded without a source")
	eq(ns.db.lootMap.sources[FEATHER], nil, "secret source skipped")
	eq(#stubs.errors, 0, "no errors")
end)

test("loot map: cells round-trip to their centers", function()
	local ns = boot()
	local LM = ns.LootMap
	local x, y = LM:FromCell(LM:ToCell(0.423, 0.651))
	T.near(x, 0.425, "x")
	T.near(y, 0.655, "y")
	eq(LM:ToCell(0, 0), 1, "corner")
	eq(LM:ToCell(1, 1), 10000, "far corner clamps")
	eq(LM:FromCell(0), nil, "no position")
end)

-- Queries -------------------------------------------------------------------

test("loot map: shown items follow tracking (no goal needed) and the selection", function()
	local ns = boot()
	local LM = ns.LootMap
	eq(next(LM:GetShownItems()), nil, "nothing tracked or selected")
	ns.Tracker:Add("item", ARCANITE) -- no goal
	ns.Tracker:Add("recipe", 2963)   -- uses Linen Cloth
	LM:SetFocus(FEATHER)
	local shown = LM:GetShownItems()
	eq(shown[ARCANITE], true, "tracked reagent without a goal")
	eq(shown[LINEN_CLOTH], true, "reagent of a tracked recipe")
	eq(shown[FEATHER], true, "selected")
	ns.db.settings.mapPins = LM.SHOW_ALL
	eq(LM:GetShownItems(), true, "everything")
	ns.db.settings.mapPins = LM.SHOW_OFF
	eq(LM:GetShownItems(), nil, "off")
end)

test("loot map: spots merge items per cell, summary names zones and sources", function()
	local ns = boot()
	L.target = { npc(448), "Hogger" }
	loot({ { FEATHER, 5, npc(448) }, { ARCANITE, 1, npc(448) } })
	L.mapID, L.x, L.y = WESTFALL, 0.5, 0.5
	L.target = { npc(500), "Defias Thug" }
	loot({ { FEATHER, 2, npc(500) } })

	local spots = ns.LootMap:GetSpots(ELWYNN, true)
	eq(#spots, 1, "one cell")
	eq(spots[1].total, 6, "both items")
	eq(spots[1].items[1].itemID, FEATHER, "most looted first")
	eq(#ns.LootMap:GetSpots(ELWYNN, { [ARCANITE] = true })[1].items, 1, "filtered")

	eq(ns.LootMap:GetSummaryText(FEATHER), "Elwynn Forest 5, Westfall 2 · mostly Hogger", "summary")
	eq(ns.LootMap:GetSummaryText(ARCANITE), "Elwynn Forest 1 · from Hogger", "single source")
	eq(ns.LootMap:GetSummaryText(LINEN_CLOTH), nil, "never looted")
	eq(ns.LootMap:GetBestMap(FEATHER), ELWYNN, "best map")
end)

test("loot map: Show on map opens the best map, not in combat", function()
	local ns = boot()
	loot({ { FEATHER, 1, npc(448) } })
	eq(ns.LootMap:ShowOnMap(FEATHER), true, "opened")
	eq(L.opened, ELWYNN, "on Elwynn")
	eq(ns.LootMap:GetFocus(), FEATHER, "focused")

	L.opened = nil
	stubs.combat = true
	eq(ns.LootMap:ShowOnMap(FEATHER), false, "combat")
	eq(L.opened, nil, "not opened in combat")
	stubs.combat = false
	eq(ns.LootMap:ShowOnMap(ARCANITE), false, "nothing recorded")
	contains(stubs.printed[#stubs.printed], "no looted spots", "says why")
end)

-- World map pins ------------------------------------------------------------

local function fakeWorldMap()
	local canvas = stubs.newWidget("Frame")
	function canvas:GetWidth() return 1000 end
	function canvas:GetHeight() return 600 end
	function canvas:GetFrameLevel() return 10 end
	local map = { mapID = ELWYNN, shown = true, scale = 2, providers = {} }
	function map:AddDataProvider(p) self.providers[#self.providers + 1] = p; p:OnAdded(self) end
	function map:GetCanvas() return canvas end
	function map:GetMapID() return self.mapID end
	function map:IsShown() return self.shown end
	function map:GetCanvasScale() return self.scale end
	MapCanvasDataProviderMixin = {
		OnAdded = function(self, owner) self.owningMap = owner end,
		GetMap = function(self) return self.owningMap end,
	}
	CreateFromMixins = function(...)
		local t = {}
		for i = 1, select("#", ...) do
			for k, v in pairs((select(i, ...))) do t[k] = v end
		end
		return t
	end
	WorldMapFrame = map
	return map, canvas
end

local function shownPins(canvas)
	local pins = {}
	for _, w in ipairs(stubs.allWidgets()) do
		if w.parent and w.parent.parent == canvas and w.spot and w.shown then pins[#pins + 1] = w end
	end
	return pins
end

test("map pins: tracked items on the open map, sized for the zoom", function()
	local map, canvas
	local ns = boot(nil, function() map, canvas = fakeWorldMap() end)
	eq(ns.MapPins:IsAttached(), true, "provider added")
	loot({ { FEATHER, 1, npc(448) } })
	L.x = 0.1
	loot({ { ARCANITE, 9, npc(448) } })

	map.providers[1]:RefreshAllData()
	stubs.runTimers()
	eq(#shownPins(canvas), 0, "nothing tracked or selected")

	ns.Tracker:Add("item", ARCANITE)
	stubs.runTimers()
	local pins = shownPins(canvas)
	eq(#pins, 1, "tracked reagent")
	eq(pins[1].spot.items[1].itemID, ARCANITE, "its spot")
	local point = pins[1].points[#pins[1].points]
	T.near(point[4], 0.105 * 1000, "x on the canvas")
	T.near(point[5], -0.655 * 600, "y on the canvas")

	ns.db.settings.mapPins = ns.LootMap.SHOW_ALL
	ns:Fire("SETTINGS_CHANGED", "mapPins")
	stubs.runTimers()
	eq(#shownPins(canvas), 2, "everything")

	map.mapID = WESTFALL
	map.providers[1]:RefreshAllData()
	stubs.runTimers()
	eq(#shownPins(canvas), 0, "other map")

	map.mapID = ELWYNN
	ns.db.settings.mapPins = ns.LootMap.SHOW_OFF
	map.providers[1]:RefreshAllData()
	stubs.runTimers()
	eq(#shownPins(canvas), 0, "off")
	eq(#stubs.errors, 0, "no errors")
end)

-- Minimap pins --------------------------------------------------------------

test("minimap: offsets point the right way, rotate, and stop at the edge", function()
	local ns = boot()
	local P = ns.MinimapPins.Project
	-- 1000 x 600 yard map, 100 yard radius, 70 px half size: 0.7 px per yard.
	local x, y = P(0.05, 0, 1000, 600, 100, 70)
	T.near(x, 35, "50 yards east: right")
	T.near(y, 0, "east: level")
	x, y = P(0, -0.05, 1000, 600, 100, 70)
	T.near(x, 0, "30 yards north: centered")
	T.near(y, 21, "north: up")
	-- Facing west (pi/2): north is to the right, west is up.
	x, y = P(0, -0.05, 1000, 600, 100, 70, math.pi / 2)
	T.near(x, 21, "rotated: north to the right")
	T.near(y, 0, "rotated: level")
	x, y = P(-0.05, 0, 1000, 600, 100, 70, math.pi / 2)
	T.near(y, 35, "rotated: west is up")
	-- 80 yards each way: 113 yards away, outside a round map, inside a square one.
	eq(P(0.08, -80 / 600, 1000, 600, 100, 70), nil, "round: hidden")
	eq(P(0.08, -80 / 600, 1000, 600, 100, 70, nil, true) ~= nil, true, "square: shown")
	eq(P(0.2, 0, 1000, 600, 100, 70, nil, true), nil, "square: far away hidden")
end)

local function minimapPins()
	local list = {}
	for _, w in ipairs(stubs.allWidgets()) do
		if w.parent == Minimap and w.spot and w.shown then list[#list + 1] = w end
	end
	return list
end

test("minimap: tracked spots near you, hidden when far or off", function()
	local ns = boot()
	L.x, L.y = 0.5, 0.5
	loot({ { FEATHER, 1, npc(448) } }) -- spot at the cell center, 0.505, 0.505
	ns.Tracker:Add("item", FEATHER)
	stubs.runTimers()
	ns.MinimapPins:Update()
	local pins = minimapPins()
	eq(#pins, 1, "shown")
	local point = pins[1].points[#pins[1].points]
	T.near(point[4], 5 * 0.7, "5 yards east")
	T.near(point[5], -3 * 0.7, "3 yards south")

	L.x = 0.9 -- 395 yards away
	ns.MinimapPins:Update()
	eq(#minimapPins(), 0, "out of range")

	L.x = 0.5
	ns.db.settings.mapPins = ns.LootMap.SHOW_OFF
	ns:Fire("SETTINGS_CHANGED", "mapPins")
	ns.MinimapPins:Update()
	eq(#minimapPins(), 0, "off")

	ns.db.settings.mapPins = ns.LootMap.SHOW_TRACKED
	ns:Fire("SETTINGS_CHANGED", "mapPins")
	L.mapID = DUNGEON -- no position
	ns.MinimapPins:Update()
	eq(#minimapPins(), 0, "instance")
	eq(#stubs.errors, 0, "no errors")
end)

test("minimap: updates allocate nothing once the zone is set up", function()
	local ns = boot()
	L.x, L.y = 0.5, 0.5
	loot({ { FEATHER, 1, npc(448) } })
	ns.Tracker:Add("item", FEATHER)
	stubs.runTimers()
	ns.MinimapPins:Update() -- builds the zone's frame and checks the axis order
	L.calls = { vec = 0, info = 0, pos = 0 }
	for i = 1, 50 do
		L.x = 0.5 + i * 0.0001 -- walking
		ns.MinimapPins:Update()
	end
	eq(L.calls.vec, 0, "no Vector2D per update")
	eq(L.calls.pos, 0, "no map position per update")
	eq(L.calls.info, 0, "no map info per update")
	eq(#minimapPins(), 1, "still shown")

	-- No spots on the zone: not even the frame is built.
	L.mapID = WESTFALL
	L.calls = { vec = 0, info = 0, pos = 0 }
	ns.MinimapPins:Update()
	ns.MinimapPins:Update()
	eq(L.calls.vec + L.calls.pos, 0, "nothing to show, nothing asked")
	eq(L.calls.info, 1, "zone looked up once per map")
end)

test("minimap: either axis order from UnitPosition lands in the same place", function()
	local ns = boot()
	L.x, L.y = 0.5, 0.5
	loot({ { FEATHER, 1, npc(448) } })
	ns.Tracker:Add("item", FEATHER)
	stubs.runTimers()
	L.unitSwap = true
	ns.MinimapPins:Update()
	local pins = minimapPins()
	eq(#pins, 1, "shown")
	local point = pins[1].points[#pins[1].points]
	T.near(point[4], 5 * 0.7, "5 yards east")
	T.near(point[5], -3 * 0.7, "3 yards south")
end)

test("minimap: in a cave, spots on the zone around it", function()
	local ns = boot()
	L.x, L.y = 0.5, 0.5
	loot({ { FEATHER, 1, npc(448) } })
	ns.Tracker:Add("item", FEATHER)
	stubs.runTimers()
	L.mapID = CAVE -- UnitPosition stays world-based
	ns.MinimapPins:Update()
	eq(#minimapPins(), 1, "shown from the cave")
end)

-- Browser -------------------------------------------------------------------

test("browser detail: where it was looted", function()
	local ns = boot()
	eq(ns.Browser:GetDetail(FEATHER).looted, nil, "nothing yet")
	eq(ns.Browser:GetDetail(FEATHER).onMap, false, "no map")
	L.target = { npc(448), "Hogger" }
	loot({ { FEATHER, 4, npc(448) } })
	local d = ns.Browser:GetDetail(FEATHER)
	eq(d.looted, "Elwynn Forest 4 · from Hogger", "summary")
	eq(d.onMap, true, "map button enabled")
	ns.LootMap:SetFocus(FEATHER)
	ns.Browser:Select(ARCANITE)
	eq(ns.LootMap:GetFocus(), FEATHER, "selecting doesn't change the map focus")
	ns.LootMap:SetFocus(nil)
	eq(ns.LootMap:GetShownItems()[FEATHER], nil, "cleared focus leaves the map")
end)

uninstall()
UnitName = savedUnitName
