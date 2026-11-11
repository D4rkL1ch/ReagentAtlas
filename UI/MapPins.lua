local addonName, ns = ...

-- Looted spots on the world map. A data provider tells us when the map
-- changes or zooms; the pins are our own frames on the map canvas, so no
-- Blizzard pin pool or template is touched.
local MapPins = ns:RegisterModule("MapPins", {})

local PIN_SIZE = 14       -- on screen, at a single loot
local PIN_GROWTH = 8      -- extra size for the most looted spots
local MAX_TOOLTIP_ITEMS = 6
local FRAME_LEVEL = 500   -- fallback: above the map art, below Blizzard's dialogs
-- Pins are children of the holder, one level above it.
local PIN_LEVEL_BELOW = "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST"

local provider, holder
local pins = {}
local shown = 0

local function GetMap()
	return provider and provider:GetMap()
end

-- Tooltip for a looted spot, shared with the minimap pins.
function MapPins:ShowTooltip(owner, spot)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Looted here")
	for i = 1, math.min(#spot.items, MAX_TOOLTIP_ITEMS) do
		local item = spot.items[i]
		local name = ns.Browser:GetItemName(item.itemID) or ("Item #" .. item.itemID)
		local icon = C_Item.GetItemIconByID(item.itemID)
		local summary = ns.LootMap:GetSummary(item.itemID)
		local top = summary.sources[1]
		GameTooltip:AddDoubleLine(("|T%s:0|t %s"):format(tostring(icon), name), "x" .. item.count, 1, 1, 1, 1, 1, 1)
		if top then
			GameTooltip:AddLine("   from " .. top.name, 0.62, 0.62, 0.62)
		end
	end
	if #spot.items > MAX_TOOLTIP_ITEMS then
		GameTooltip:AddLine(("+%d more"):format(#spot.items - MAX_TOOLTIP_ITEMS), 0.62, 0.62, 0.62)
	end
	GameTooltip:Show()
end

local function OnPinEnter(pin)
	MapPins:ShowTooltip(pin, pin.spot)
end

local function OnPinLeave()
	GameTooltip:Hide()
end

local function CreatePin()
	local pin = CreateFrame("Frame", nil, holder)
	pin.Border = pin:CreateTexture(nil, "BACKGROUND")
	pin.Border:SetAllPoints()
	pin.Border:SetColorTexture(0, 0, 0, 0.8)
	pin.Icon = pin:CreateTexture(nil, "ARTWORK")
	pin.Icon:SetPoint("TOPLEFT", 1, -1)
	pin.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
	pin.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- Hover for the tooltip; clicks go through to the map.
	if pin.SetMouseMotionEnabled and pin.SetMouseClickEnabled then
		pin:SetMouseMotionEnabled(true)
		pin:SetMouseClickEnabled(false)
	else
		pin:EnableMouse(true)
	end
	pin:SetScript("OnEnter", OnPinEnter)
	pin:SetScript("OnLeave", OnPinLeave)
	return pin
end

local function HideAll()
	for i = 1, shown do pins[i]:Hide() end
	shown = 0
end

-- Pins keep their size on screen at any zoom.
local function ApplyScale()
	local map = GetMap()
	if not map then return end
	local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
	if not scale or scale <= 0 then scale = 1 end
	for i = 1, shown do
		local pin = pins[i]
		pin:SetSize(pin.baseSize / scale, pin.baseSize / scale)
	end
end

-- Bigger pins for spots looted more, relative to the busiest on the map.
local function PinSize(total, most)
	if most <= 1 then return PIN_SIZE end
	return PIN_SIZE + PIN_GROWTH * math.log(total) / math.log(most)
end

local function Debug(text)
	if ns.lootDebug then ns:Print("pins: " .. text) end
end

function MapPins:Refresh()
	HideAll()
	local map = GetMap()
	if not (map and holder and map:IsShown()) then
		Debug(("skipped: map %s, holder %s, shown %s"):format(tostring(map ~= nil), tostring(holder ~= nil),
			tostring(map and map:IsShown())))
		return
	end
	local mapID = map:GetMapID()
	local items = ns.LootMap:GetShownItems()
	if not (mapID and items) then
		Debug(("skipped: map %s, show mode %s"):format(tostring(mapID), tostring(ns.db.settings.mapPins)))
		return
	end
	local spots = ns.LootMap:GetSpots(mapID, items)
	local canvas = map:GetCanvas()
	local width, height = canvas:GetWidth(), canvas:GetHeight()
	if ns.lootDebug then Debug(("map %s, %d spots, canvas %.0fx%.0f scale %s, level %s/%s, holder %s %.0fx%.0f"):format(
		tostring(mapID), #spots, width, height, tostring(map.GetCanvasScale and map:GetCanvasScale()),
		tostring(canvas:GetFrameLevel()), tostring(holder:GetFrameLevel()),
		tostring(holder:IsVisible()), holder:GetWidth(), holder:GetHeight())) end
	local most = 1
	for _, spot in ipairs(spots) do most = math.max(most, spot.total) end
	for i, spot in ipairs(spots) do
		local pin = pins[i] or CreatePin()
		pins[i] = pin
		pin.spot = spot
		pin.baseSize = PinSize(spot.total, most)
		pin.Icon:SetTexture(C_Item.GetItemIconByID(spot.items[1].itemID))
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", holder, "TOPLEFT", spot.x * width, -spot.y * height)
		pin:Show()
	end
	shown = #spots
	ApplyScale()
	local pin = pins[1]
	if ns.lootDebug and shown > 0 then
		Debug(("first pin: visible %s, size %.1f, at %.0f, %.0f"):format(tostring(pin:IsVisible()), pin:GetWidth(),
			spots[1].x * width, -spots[1].y * height))
	end
end

-- Map events arrive in bursts (zooming, changing maps); one refresh per frame.
local queued = false
local function QueueRefresh()
	if queued then return end
	queued = true
	C_Timer.After(0, function()
		queued = false
		MapPins:Refresh()
	end)
end

-- Blizzard's pins take absolute frame levels from 2000 up (quest markers,
-- then the player arrow on top). Pins go just above the super-tracked quest,
-- so quest markers don't hide them but the player arrow still does; clicks
-- go through to the quest pin. Without the manager, a fixed offset.
local function HolderLevel(canvas)
	local manager = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
	if manager and manager.GetValidFrameLevel then
		local ok, level = pcall(manager.GetValidFrameLevel, manager, PIN_LEVEL_BELOW)
		if ok and type(level) == "number" then return level end
	end
	return canvas:GetFrameLevel() + FRAME_LEVEL
end

local function Attach()
	if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin
		and CreateFromMixins) then
		return
	end
	provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function provider:RefreshAllData() QueueRefresh() end
	function provider:RemoveAllData() HideAll() end
	function provider:OnCanvasScaleChanged() ApplyScale() end
	function provider:OnCanvasSizeChanged() QueueRefresh() end
	WorldMapFrame:AddDataProvider(provider)
	local canvas = WorldMapFrame:GetCanvas()
	holder = CreateFrame("Frame", nil, canvas)
	holder:SetAllPoints(canvas)
	holder:SetFrameLevel(HolderLevel(canvas))
end

function MapPins:IsAttached()
	return provider ~= nil
end

-- Lifecycle -----------------------------------------------------------------

function MapPins:OnLogin()
	Attach()
	if not provider then
		-- The world map may load on demand.
		local function OnAddonLoaded(event, name)
			if name ~= "Blizzard_WorldMap" then return end
			ns:UnregisterEvent(event, OnAddonLoaded)
			Attach()
		end
		ns:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
	end
	local function Changed()
		if GetMap() and GetMap():IsShown() then QueueRefresh() end
	end
	ns:RegisterMessage("LOOT_MAP_CHANGED", Changed)
	ns:RegisterMessage("LOOT_MAP_FOCUS", Changed)
	ns:RegisterMessage("TRACKER_CHANGED", Changed)
	ns:RegisterMessage("SETTINGS_CHANGED", Changed)
end
