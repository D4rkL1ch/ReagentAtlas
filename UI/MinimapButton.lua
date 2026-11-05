local addonName, ns = ...

local MinimapButton = ns:RegisterModule("MinimapButton", {})

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local TITLE = "Reagent Atlas"
local DEFAULT_ANGLE = 225 -- degrees; bottom left of the minimap
local RADIUS_OFFSET = 5   -- past the minimap's edge

local button

-- Left click: browser. Right click: settings.
local function OnClick(buttonName)
	if buttonName == "RightButton" then
		ns.SettingsUI:Open()
	else
		ns.Browser:Toggle()
	end
end

local function ShowHint(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine(TITLE)
	GameTooltip:AddLine("Left-click: reagent browser", 1, 1, 1)
	GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
	GameTooltip:Show()
end

local function HideHint()
	GameTooltip:Hide()
end

local function Place()
	local angle = math.rad(ns.db.ui.minimapAngle or DEFAULT_ANGLE)
	local radius = Minimap:GetWidth() / 2 + RADIUS_OFFSET
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Follow the cursor around the minimap while dragging.
local function OnDragUpdate()
	local cx, cy = Minimap:GetCenter()
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.db.ui.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
	Place()
end

local function CreateButton()
	button = CreateFrame("Button", nil, Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER")
	icon:SetTexture(ICON)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetScript("OnClick", function(_, mouseButton) OnClick(mouseButton) end)
	button:SetScript("OnEnter", ShowHint)
	button:SetScript("OnLeave", HideHint)
	button:SetScript("OnDragStart", function(self)
		HideHint()
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	Place()
end

local function UpdateShown()
	if button then button:SetShown(ns.db.settings.minimapIcon) end
end

function MinimapButton:OnLogin()
	-- Blizzard's AddOns button by the minimap; custom registration needs no global.
	if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		AddonCompartmentFrame:RegisterAddon({
			text = TITLE,
			icon = ICON,
			func = function(_, inputData) OnClick(inputData and inputData.buttonName) end,
			funcOnEnter = ShowHint,
			funcOnLeave = HideHint,
		})
	end
	if Minimap then
		CreateButton()
		UpdateShown()
		ns:RegisterMessage("SETTINGS_CHANGED", UpdateShown)
	end
end
