local addonName, ns = ...

-- Looted spots on the minimap, for the same items as the world map. There is
-- no data provider for the minimap, so pins are placed by hand: the offset
-- from the player in yards (map position difference times the map's size in
-- yards), scaled by the minimap's view radius, rotated with the minimap.
-- Spots outside the minimap are hidden.
local MinimapPins = ns:RegisterModule("MinimapPins", {})

local PIN_SIZE = 12
local UPDATE_INTERVAL = 0.1 -- seconds between position updates while visible

local pins = {}
local shown = 0
local spots          -- cached spots for spotsMapID, nil when stale
local spotsMapID

local function OnPinEnter(pin)
	ns.MapPins:ShowTooltip(pin, pin.spot)
end

local function OnPinLeave()
	GameTooltip:Hide()
end

local function CreatePin()
	local pin = CreateFrame("Frame", nil, Minimap)
	pin:SetSize(PIN_SIZE, PIN_SIZE)
	pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	pin.Border = pin:CreateTexture(nil, "BACKGROUND")
	pin.Border:SetAllPoints()
	pin.Border:SetColorTexture(0, 0, 0, 0.8)
	pin.Icon = pin:CreateTexture(nil, "ARTWORK")
	pin.Icon:SetPoint("TOPLEFT", 1, -1)
	pin.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
	pin.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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

-- Shows `count` pins: hides the ones past it that were shown before.
local function SetShownCount(count)
	for i = count + 1, shown do pins[i]:Hide() end
	shown = count
end

local function IsRotating()
	local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("rotateMinimap")
	return value == "1"
end

-- Offset of a spot from the player in minimap pixels (right, up), or nil if
-- it falls outside the minimap. dx, dy: map position difference (0-1 units,
-- y down); width, height: map size in yards; radius: view radius in yards;
-- half: minimap half size in pixels; facing: radians, nil when not rotating;
-- square: true for square minimaps (ElvUI).
function MinimapPins.Project(dx, dy, width, height, radius, half, facing, square)
	local east, north = dx * width, -dy * height
	local right, up = east, north
	if facing then
		local c, s = math.cos(facing), math.sin(facing)
		right = east * c + north * s
		up = north * c - east * s
	end
	local limit = radius * (1 - PIN_SIZE / 2 / half) -- keep the whole pin inside
	if square then
		if math.abs(right) > limit or math.abs(up) > limit then return nil end
	elseif right * right + up * up > limit * limit then
		return nil
	end
	local scale = half / radius
	return right * scale, up * scale
end

-- Spots on a map for the items shown, cached until the data, the tracking
-- list, the selection or the settings change.
local function GetSpots(mapID)
	if not spots or spotsMapID ~= mapID then
		local items = ns.LootMap:GetShownItems()
		spots, spotsMapID = items and ns.LootMap:GetSpots(mapID, items) or {}, mapID
	end
	return spots
end

function MinimapPins:Update()
	local mapID, px, py = ns.LootMap:GetPlayerPosition()
	local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
	local width, height
	if mapID and px and C_Map.GetMapWorldSize then width, height = C_Map.GetMapWorldSize(mapID) end
	if not (px and radius and radius > 0 and width and width > 0 and height and height > 0)
		or #GetSpots(mapID) == 0 then
		SetShownCount(0)
		return
	end
	local facing = IsRotating() and GetPlayerFacing and GetPlayerFacing() or nil
	local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
	local half = Minimap:GetWidth() / 2
	local count = 0
	for _, spot in ipairs(spots) do
		local x, y = self.Project(spot.x - px, spot.y - py, width, height, radius, half, facing, square)
		if x then
			count = count + 1
			local pin = pins[count] or CreatePin()
			pins[count] = pin
			pin.spot = spot
			pin.Icon:SetTexture(C_Item.GetItemIconByID(spot.items[1].itemID))
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
			pin:Show()
		end
	end
	-- Pins past the old count were just shown; only older extras need hiding.
	if count > shown then shown = count end
	SetShownCount(count)
end

-- Lifecycle -----------------------------------------------------------------

function MinimapPins:OnLogin()
	if not Minimap then return end
	local function Stale() spots = nil end
	ns:RegisterMessage("LOOT_MAP_CHANGED", Stale)
	ns:RegisterMessage("LOOT_MAP_FOCUS", Stale)
	ns:RegisterMessage("TRACKER_CHANGED", Stale)
	ns:RegisterMessage("SETTINGS_CHANGED", Stale)
	local driver = CreateFrame("Frame", nil, Minimap)
	local elapsed = 0
	driver:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < UPDATE_INTERVAL then return end
		elapsed = 0
		MinimapPins:Update()
	end)
end
