local addonName, ns = ...

local SettingsUI = ns:RegisterModule("SettingsUI", {})

local TITLE = "Reagent Atlas"
local PANEL_TITLE = "Status & characters"

local PAD = 16
local CHAR_ROW_HEIGHT = 26
local MISSING_ROW_HEIGHT = 18
local MISSING_LIST_HEIGHT = 90
local POPUP = "REAGENTATLAS_FORGET"

-- Checkboxes in panel order: key in ns.db.settings, label, tooltip.
local TOGGLES = {
	{ "tooltip", "Item tooltips", "Add recipes, tier and owned counts to item tooltips." },
	{ "markers", "Bag markers", "Show a tier-colored pip on bag items at or above the minimum tier." },
	{ "minimapIcon", "Minimap icon", "Show the Reagent Atlas icon on the minimap. It is always listed under the AddOns button there too." },
	{ "useAuctionator", "Use Auctionator prices", "Adjust tiers and show AH prices from Auctionator scans, if Auctionator is installed." },
	{ "trackerSound", "Tracking list sound", "Play a sound when you have enough of something on the tracking list." },
}

local category

-- Registers one ns.db.settings key with the Settings panel. The panel writes
-- the saved table directly; we only announce the change.
local function Register(key, label, varType)
	local variable = addonName .. "_" .. key
	local setting = Settings.RegisterAddOnSetting(category, variable, key, ns.db.settings, varType, label,
		ns.db.settings[key])
	Settings.SetOnValueChangedCallback(variable, function()
		ns:Fire("SETTINGS_CHANGED", key)
	end)
	return setting
end

-- Status & characters panel -------------------------------------------------

local panel, status, charList, missingText, missingList
local pendingForget -- key shown in the confirmation popup

-- Tracked characters for the panel, the current one first.
function SettingsUI:GetCharacterRows()
	local me = ns:GetCharKey()
	local rows = {}
	for key, char in pairs(ns.db.chars) do
		rows[#rows + 1] = {
			key = key, name = ns:CharDisplayName(key), class = char.class,
			lastSeen = char.lastSeen, isMe = key == me,
		}
	end
	table.sort(rows, function(a, b)
		if a.isMe ~= b.isMe then return a.isMe end
		return a.key < b.key
	end)
	return rows
end

local function ClassColored(name, class)
	local color = class and C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
	return color and color:WrapTextInColorCode(name) or name
end

local function InitCharRow(row, char)
	if not row.Name then
		row.Forget = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.Forget:SetSize(80, 22)
		row.Forget:SetPoint("RIGHT", -4, 0)
		row.Forget:SetText("Forget")
		row.Forget:SetScript("OnClick", function(self)
			pendingForget = self:GetParent().key
			StaticPopup_Show(POPUP, pendingForget)
		end)
		row.Seen = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.Seen:SetPoint("RIGHT", row.Forget, "LEFT", -12, 0)
		row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.Name:SetPoint("LEFT", 4, 0)
		row.Name:SetPoint("RIGHT", row.Seen, "LEFT", -8, 0)
		row.Name:SetJustifyH("LEFT")
	end
	row.key = char.key
	row.Name:SetText(ClassColored(char.name, char.class))
	if char.isMe then
		row.Seen:SetText("this character")
	else
		row.Seen:SetText(char.lastSeen and ("last seen " .. date("%Y-%m-%d", char.lastSeen)) or "")
	end
	row.Forget:SetShown(not char.isMe)
end

local function InitMissingRow(row, line)
	if not row.Text then
		row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Text:SetPoint("LEFT", 4, 0)
		row.Text:SetJustifyH("LEFT")
	end
	row.Text:SetText(line.text)
end

local function Header(parent, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetText(text)
	return fs
end

local function BuildPanel()
	local statusHead = Header(panel, "Status")
	statusHead:SetPoint("TOPLEFT", PAD, -PAD)
	status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", statusHead, "BOTTOMLEFT", 0, -6)
	status:SetPoint("RIGHT", -PAD, 0)
	status:SetJustifyH("LEFT")

	-- The data check sits at the bottom, sized by its fixed list; characters
	-- take the space in between.
	missingList = ns.Browser:CreateList(panel, MISSING_ROW_HEIGHT, InitMissingRow)
	missingList:SetPoint("BOTTOMLEFT", PAD, PAD)
	missingList:SetPoint("BOTTOMRIGHT", -PAD - 12, PAD)
	missingList:SetHeight(MISSING_LIST_HEIGHT)
	missingText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	missingText:SetPoint("BOTTOMLEFT", missingList, "TOPLEFT", 0, 6)
	missingText:SetPoint("RIGHT", -PAD, 0)
	missingText:SetJustifyH("LEFT")
	local missingHead = Header(panel, "Recipe data check")
	missingHead:SetPoint("BOTTOMLEFT", missingText, "TOPLEFT", 0, 6)

	local charHead = Header(panel, "Characters")
	charHead:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -16)
	charList = ns.Browser:CreateList(panel, CHAR_ROW_HEIGHT, InitCharRow)
	charList:SetPoint("TOPLEFT", charHead, "BOTTOMLEFT", 0, -6)
	charList:SetPoint("RIGHT", -PAD - 12, 0)
	charList:SetPoint("BOTTOM", missingHead, "TOP", 0, 12)
end

function SettingsUI:RefreshPanel()
	if not (status and panel:IsShown()) then return end
	status:SetText(table.concat(ns:GetStatusLines(), "\n"))
	local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
	charList:SetDataProvider(CreateDataProvider(self:GetCharacterRows()), retain)
	local missing = {}
	for i, text in ipairs(ns.Professions:GetMissingRecipes()) do
		missing[i] = { text = text }
	end
	missingText:SetText(("Learned recipes missing from the data: %d. Only profession windows opened this session are checked."):format(#missing))
	missingList:SetDataProvider(CreateDataProvider(missing), retain)
	missingList:SetShown(#missing > 0)
end

local function CreatePanel()
	panel = CreateFrame("Frame")
	panel:SetScript("OnShow", function()
		if not status then BuildPanel() end
		SettingsUI:RefreshPanel()
	end)
	panel:Hide()
	Settings.RegisterCanvasLayoutSubcategory(category, panel, PANEL_TITLE)

	StaticPopupDialogs[POPUP] = {
		text = "Forget %s? Its saved professions and item counts are removed. They return if you log in on that character.",
		button1 = YES,
		button2 = NO,
		OnAccept = function() ns:ForgetCharacter(pendingForget) end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
	ns:RegisterMessage("CHAR_DATA_CHANGED", function() SettingsUI:RefreshPanel() end)
end

-- Lifecycle -----------------------------------------------------------------

function SettingsUI:OnInit()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
		return
	end
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory(TITLE)

	if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("Reagent browser", "Open",
			function() ns.Browser:Open() end, "Open the reagent browser window.", true))
		layout:AddInitializer(CreateSettingsButtonInitializer("Tracking list", "Open",
			function() ns.TrackerUI:Open() end, "Open the list of tracked recipes and reagents.", true))
	end

	for _, toggle in ipairs(TOGGLES) do
		local key, label, tooltip = toggle[1], toggle[2], toggle[3]
		Settings.CreateCheckbox(category, Register(key, label, Settings.VarType.Boolean), tooltip)
	end

	local tierSetting = Register("markerMinTier", "Minimum tier for markers", Settings.VarType.Number)
	local function TierOptions()
		local container = Settings.CreateControlTextContainer()
		for tier = ns.Valuation.TIER_COMMON, ns.Valuation.TIER_KEEP do
			container:Add(tier, ns.Valuation:ColorTier(tier))
		end
		return container:GetData()
	end
	Settings.CreateDropdown(category, tierSetting, TierOptions, "Bag items below this tier get no pip.")

	if Settings.RegisterCanvasLayoutSubcategory then
		CreatePanel()
	end
	Settings.RegisterAddOnCategory(category)
end

-- Opens the panel on our category. The Settings panel is a Blizzard UI panel,
-- so stay out of it in combat. Returns true if it opened.
function SettingsUI:Open()
	if not (category and Settings.OpenToCategory) then
		ns:Print("the Settings panel is not available in this client.")
	elseif InCombatLockdown() then
		ns:Print("can't open settings in combat.")
	else
		Settings.OpenToCategory(category:GetID())
		return true
	end
	return false
end

ns:RegisterCommand("config", "config - open settings", function() SettingsUI:Open() end)
