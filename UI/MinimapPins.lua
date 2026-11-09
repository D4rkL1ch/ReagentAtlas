local addonName, ns = ...

-- Looted spots on the minimap, for the same items as the world map. There is
-- no data provider for the minimap, so pins are placed by hand: the offset
-- from the player in yards (map position difference times the map's size in
-- yards), scaled by the minimap's view radius, rotated with the minimap.
-- Spots outside the minimap are hidden.
--
-- The update runs ten times a second, so it must not allocate: map position
-- APIs return a fresh Vector2D (16 mixin methods copied in) and GetMapInfo a
-- fresh table, which piled up as garbage counted against the addon. Per tick
-- it only uses UnitPosition (plain numbers); the zone's world frame, used to
-- turn world coordinates into map positions, is built once per zone.
local MinimapPins = ns:RegisterModule("MinimapPins", {})

local PIN_SIZE = 12
local UPDATE_INTERVAL = 0.1 -- seconds between position updates while visible

local pins = {}
local shown = 0
local spots          -- cached spots for spotsZone, nil when stale
local spotsZone
local frame          -- world frame of spotsZone, see BuildFrame
local zoneOf = {}    -- mapID -> its zone (caves resolved), cached
local swapped        -- UnitPosition's order vs map vectors; nil until checked

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

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

-- The zone a map belongs to: caves (micro maps) resolve to their parent, as
-- the loot map records them there. Once per mapID.
local function ZoneFor(mapID)
	local zone = zoneOf[mapID]
	if zone then return zone end
	zone = mapID
	local micro = Enum and Enum.UIMapType and Enum.UIMapType.Micro
	for _ = 1, 3 do
		local info = micro and C_Map.GetMapInfo and C_Map.GetMapInfo(zone)
		if not (info and info.mapType == micro and info.parentMapID and info.parentMapID > 0) then break end
		zone = info.parentMapID
	end
	zoneOf[mapID] = zone
	return zone
end

local function WorldPos(zone, x, y)
	local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, zone, CreateVector2D(x, y))
	if not (ok and continent and pos) then return nil end
	local a, b = pos:GetXY()
	return continent, a, b
end

-- A zone's world frame: world position of the map's top-left corner and the
-- world vectors for one full map width east (e) and height south (s).
-- Allocates, so built only when the zone or the spots change.
function MinimapPins.BuildFrame(zone)
	if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
	local continent, ox, oy = WorldPos(zone, 0, 0)
	local c2, ex, ey = WorldPos(zone, 1, 0)
	local c3, sx, sy = WorldPos(zone, 0, 1)
	if not (continent and c2 == continent and c3 == continent) then return nil end
	ex, ey, sx, sy = ex - ox, ey - oy, sx - ox, sy - oy
	local det = ex * sy - ey * sx
	if det == 0 then return nil end
	return {
		zone = zone, continent = continent, ox = ox, oy = oy, ex = ex, ey = ey, sx = sx, sy = sy, det = det,
		width = math.sqrt(ex * ex + ey * ey), height = math.sqrt(sx * sx + sy * sy),
	}
end

-- Map position (0-1) of a world point in a zone's frame.
function MinimapPins.ToMap(f, a, b)
	local da, db = a - f.ox, b - f.oy
	return (da * f.sy - db * f.sx) / f.det, (f.ex * db - f.ey * da) / f.det
end

-- Whether UnitPosition gives the two world axes in the opposite order to map
-- vectors. Checked once against the map position (which allocates); nil if
-- that isn't available yet.
local function CheckOrder(f, a, b)
	local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(f.zone, "player")
	if not pos or IsSecret(pos) then return nil end
	local px, py = pos:GetXY()
	if type(px) ~= "number" or IsSecret(px) then return nil end
	local u1, v1 = MinimapPins.ToMap(f, a, b)
	local u2, v2 = MinimapPins.ToMap(f, b, a)
	local err1 = (u1 - px) ^ 2 + (v1 - py) ^ 2
	local err2 = (u2 - px) ^ 2 + (v2 - py) ^ 2
	return err2 < err1
end

-- The player's map position in the frame's zone, without allocating.
local function PlayerOnMap(f)
	local a, b, _, instance = UnitPosition("player")
	if type(a) ~= "number" or type(b) ~= "number" or IsSecret(a) or IsSecret(b) or instance ~= f.continent then
		return nil
	end
	if swapped == nil then swapped = CheckOrder(f, a, b) end
	if swapped then a, b = b, a end
	return MinimapPins.ToMap(f, a, b)
end

-- Spots on a zone for the items shown, cached with the zone's frame until
-- the zone, the data, the tracking list, the selection or the settings change.
local function GetSpots(zone)
	if not spots or spotsZone ~= zone then
		local items = ns.LootMap:GetShownItems()
		spots, spotsZone = items and ns.LootMap:GetSpots(zone, items) or {}, zone
		frame = #spots > 0 and MinimapPins.BuildFrame(zone) or nil
	end
	return spots
end

function MinimapPins:Update()
	local mapID = C_Map.GetBestMapForUnit("player")
	if type(mapID) ~= "number" or IsSecret(mapID) or #GetSpots(ZoneFor(mapID)) == 0 or not frame then
		SetShownCount(0)
		return
	end
	local px, py = PlayerOnMap(frame)
	local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
	if not (px and radius and radius > 0) then
		SetShownCount(0)
		return
	end
	local facing = IsRotating() and GetPlayerFacing and GetPlayerFacing() or nil
	local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
	local half = Minimap:GetWidth() / 2
	local width, height = frame.width, frame.height
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
