local addonName, ns = ...

local Browser = ns:RegisterModule("Browser", {})

-- Layout (SPEC.md > Browser window; design mockup in docs/).
local WIDTH, HEIGHT = 860, 560
local LIST_WIDTH = 380
local ROW_HEIGHT = 30
local RECIPE_ROW_HEIGHT = 22
local TIER_COL, OWNED_COL = 70, 50
local PAD = 12

local COLOR_TEXT = "ffe8e2d0"
local COLOR_HINT = "ffa39a85"
local COLOR_YOURS = "ff1eff00"
local COLOR_ALT = "ff66b3ff"
local COLOR_UNKNOWN = "ff9d9d9d"
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"

local DEFAULT_FILTERS = { prof = 0, minTier = 2, owned = false, craftable = false }

local function Color(text, color)
	return WrapTextInColorCode(text, color)
end

local function QualityColor(quality)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return c and c.hex and c.hex:gsub("^|c", "") or "ffffffff"
end

-- Model ---------------------------------------------------------------------
-- Pure data, no frames: tested offline.

local requested = {}

-- Item name, or nil while the client hasn't cached it yet (a load is
-- requested; ITEM_DATA_LOAD_RESULT refreshes the list).
function Browser:GetItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name and not requested[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
		requested[itemID] = true
		C_Item.RequestLoadItemDataByID(itemID)
	end
	return name
end

-- Number of recipes using the item that any character knows, and whether the
-- current character knows at least one.
local function CraftableCount(itemID)
	local count, mine = 0, false
	for _, recipeID in ipairs(ns.Reagents[itemID].r) do
		local isMe, alts = ns.Professions:GetKnownBy(recipeID)
		if isMe or #alts > 0 then
			count = count + 1
			mine = mine or isMe
		end
	end
	return count, mine
end

-- Rows matching the filters, best tier first, then by name. filters:
--   search    substring of the item name, case-insensitive ("" = any)
--   prof      skill line ID the item must be used in (0 = any)
--   minTier   lowest tier shown (1 = all)
--   owned     only items some character (or the warband bank) holds
--   craftable only items with a recipe some character knows
function Browser:BuildRows(filters)
	local search = (filters.search or ""):lower()
	local rows = {}
	for itemID in pairs(ns.Reagents) do
		local info = ns.Valuation:GetInfo(itemID)
		if info then
			local keep = filters.prof == 0 or (info.profCounts[filters.prof] or 0) > 0
			local tier, owned, craftable, name
			if keep then
				tier = ns.Valuation:GetTier(itemID)
				keep = tier >= filters.minTier
			end
			if keep then
				owned = ns.Inventory:GetCounts(itemID)
				keep = not filters.owned or owned > 0
			end
			if keep then
				craftable = CraftableCount(itemID)
				keep = not filters.craftable or craftable > 0
			end
			if keep then
				name = self:GetItemName(itemID)
				keep = search == "" or (name and name:lower():find(search, 1, true) ~= nil)
			end
			if keep then
				rows[#rows + 1] = {
					itemID = itemID, name = name, quality = info.quality,
					tier = tier, owned = owned, craftable = craftable,
				}
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.tier ~= b.tier then return a.tier > b.tier end
		if (a.name ~= nil) ~= (b.name ~= nil) then return a.name ~= nil end
		if a.name and a.name ~= b.name then return a.name < b.name end
		return a.itemID < b.itemID
	end)
	return rows
end

-- Everything the detail pane shows for one item.
function Browser:GetDetail(itemID)
	local info = ns.Valuation:GetInfo(itemID)
	if not info then return nil end
	local tier, price = ns.Valuation:GetTier(itemID)
	local total, holders, warband = ns.Inventory:GetCounts(itemID)

	local where = {}
	for _, h in ipairs(holders) do
		local parts = {}
		if h.bags > 0 then parts[#parts + 1] = "Bags " .. h.bags end
		if h.bank > 0 then parts[#parts + 1] = "Bank " .. h.bank end
		local who = h.isMe and "you" or ns:CharDisplayName(h.key)
		where[#where + 1] = ("%s (%s)"):format(table.concat(parts, " · "), who)
	end
	if warband > 0 then
		where[#where + 1] = "Warband bank " .. warband
	end

	local recipes = {}
	for _, recipeID in ipairs(ns.Reagents[itemID].r) do
		local recipe = ns.Recipes[recipeID]
		if recipe then
			local isMe, alts = ns.Professions:GetKnownBy(recipeID)
			recipes[#recipes + 1] = {
				recipeID = recipeID,
				name = ns.Tooltip:GetRecipeName(recipeID),
				prof = ns.Tooltip:GetProfessionName(recipe.prof),
				skill = recipe.skill,
				known = isMe and "me" or (#alts > 0 and "alt" or "none"),
				who = (isMe or #alts > 0) and ns.Tooltip:FormatNames(isMe, alts) or "",
			}
		end
	end

	return {
		itemID = itemID,
		name = self:GetItemName(itemID) or ("Item #" .. itemID),
		quality = info.quality,
		tier = tier,
		price = price,
		sellPrice = info.sellPrice,
		owned = total,
		where = where,
		recipeCount = info.recipeCount,
		craftable = CraftableCount(itemID),
		recipes = recipes,
		spellClasses = info.spellClasses,
	}
end

-- Professions that have at least one recipe, sorted by display name.
function Browser:GetProfessionChoices()
	local seen, list = {}, {}
	for _, recipe in pairs(ns.Recipes) do
		if not seen[recipe.prof] then
			seen[recipe.prof] = true
			list[#list + 1] = { value = recipe.prof, label = ns.Tooltip:GetProfessionName(recipe.prof) }
		end
	end
	table.sort(list, function(a, b) return a.label < b.label end)
	table.insert(list, 1, { value = 0, label = "All" })
	return list
end

function Browser:GetFilters()
	local ui = ns.db.ui
	ui.filters = ui.filters or {}
	for k, v in pairs(DEFAULT_FILTERS) do
		if ui.filters[k] == nil then ui.filters[k] = v end
	end
	return ui.filters
end

-- View ----------------------------------------------------------------------

-- The browser window, created on first open.
---@type table
local frame
local search = ""    -- not saved: a stale search on reopen is confusing
local selected       -- itemID in the detail pane

local function CreateLabel(parent, font, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	if text then fs:SetText(text) end
	return fs
end

-- A modern dropdown; falls back to a button that cycles through the options
-- if the client lacks the template. options: array of { value, label }.
local function CreateChoice(parent, width, getOptions, get, set)
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		dropdown:SetWidth(width)
		dropdown:SetupMenu(function(_, root)
			for _, option in ipairs(getOptions()) do
				root:CreateRadio(option.label, function(value) return get() == value end, set, option.value)
			end
		end)
		return dropdown
	end
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	local function Label()
		for _, option in ipairs(getOptions()) do
			if option.value == get() then button:SetText(option.label) end
		end
	end
	button:SetScript("OnClick", function()
		local options = getOptions()
		for i, option in ipairs(options) do
			if option.value == get() then
				set(options[i % #options + 1].value)
				break
			end
		end
		Label()
	end)
	Label()
	return button
end

local function CreateCheck(parent, label, key)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	local text = check.Text or CreateLabel(check, "GameFontHighlight")
	if not check.Text then text:SetPoint("LEFT", check, "RIGHT", 2, 0) end
	text:SetText(label)
	check:SetChecked(Browser:GetFilters()[key])
	check:SetScript("OnClick", function(self)
		Browser:GetFilters()[key] = self:GetChecked() and true or false
		Browser:Refresh()
	end)
	return check
end

-- Icon with a tier-colored edge, as in the mockup.
local function CreateIcon(parent, size)
	local edge = parent:CreateTexture(nil, "BORDER")
	edge:SetSize(size + 2, size + 2)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetSize(size, size)
	icon:SetPoint("CENTER", edge, "CENTER")
	return edge, icon
end

local function SetIcon(edge, icon, itemID, tier)
	icon:SetTexture(C_Item.GetItemIconByID(itemID))
	local hex = ns.Valuation.TIERS[tier].color
	edge:SetColorTexture(tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255,
		tonumber(hex:sub(7, 8), 16) / 255, 1)
end

local function InitItemRow(button, row)
	if not button.Name then
		button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		button.Selected = button:CreateTexture(nil, "BACKGROUND")
		button.Selected:SetAllPoints()
		button.Selected:SetColorTexture(1, 0.82, 0, 0.12)
		button.Edge, button.Icon = CreateIcon(button, ROW_HEIGHT - 8)
		button.Edge:SetPoint("LEFT", 6, 0)
		button.Owned = CreateLabel(button, "GameFontHighlight")
		button.Owned:SetPoint("RIGHT", -8, 0)
		button.Owned:SetWidth(OWNED_COL)
		button.Owned:SetJustifyH("RIGHT")
		button.Tier = CreateLabel(button, "GameFontNormal")
		button.Tier:SetPoint("RIGHT", button.Owned, "LEFT", -4, 0)
		button.Tier:SetWidth(TIER_COL)
		button.Tier:SetJustifyH("LEFT")
		button.Name = CreateLabel(button, "GameFontHighlight")
		button.Name:SetPoint("LEFT", button.Edge, "RIGHT", 8, 0)
		button.Name:SetPoint("RIGHT", button.Tier, "LEFT", -4, 0)
		button.Name:SetJustifyH("LEFT")
		button.Name:SetWordWrap(false)
		button:SetScript("OnClick", function(self) Browser:Select(self.itemID) end)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	button.itemID = row.itemID
	SetIcon(button.Edge, button.Icon, row.itemID, row.tier)
	button.Name:SetText(Color(row.name or ("Item #" .. row.itemID), QualityColor(row.quality)))
	button.Tier:SetText(ns.Valuation:ColorTier(row.tier))
	button.Owned:SetText(row.owned > 0 and row.owned or Color("—", COLOR_UNKNOWN))
	button.Selected:SetShown(row.itemID == selected)
end

local KNOWN_COLOR = { me = COLOR_YOURS, alt = COLOR_ALT, none = COLOR_UNKNOWN }

local function InitRecipeRow(row, recipe)
	if not row.Name then
		row.Who = CreateLabel(row, "GameFontHighlightSmall")
		row.Who:SetPoint("RIGHT", -6, 0)
		row.Who:SetWidth(110)
		row.Who:SetJustifyH("RIGHT")
		row.Who:SetWordWrap(false)
		row.Prof = CreateLabel(row, "GameFontHighlightSmall")
		row.Prof:SetPoint("RIGHT", row.Who, "LEFT", -6, 0)
		row.Prof:SetWidth(130)
		row.Prof:SetJustifyH("LEFT")
		row.Name = CreateLabel(row, "GameFontHighlight")
		row.Name:SetPoint("LEFT", 6, 0)
		row.Name:SetPoint("RIGHT", row.Prof, "LEFT", -6, 0)
		row.Name:SetJustifyH("LEFT")
		row.Name:SetWordWrap(false)
	end
	local color = KNOWN_COLOR[recipe.known]
	local mark = recipe.known == "none" and "·" or CHECK
	row.Name:SetText(Color(mark .. " " .. recipe.name, color))
	row.Prof:SetText(Color(("%s %d"):format(recipe.prof, recipe.skill), COLOR_HINT))
	row.Who:SetText(Color(recipe.who, color))
end

-- Returns the ScrollBox (typed loosely: the annotations miss its mixin).
---@return table
function Browser:CreateList(parent, rowHeight, initializer)
	local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(rowHeight)
	view:SetElementInitializer("Button", initializer)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	return box
end

local function SavePosition()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	ns.db.ui.point = { point, relPoint, x, y }
end

local function RestorePosition()
	frame:ClearAllPoints()
	local p = ns.db.ui.point
	if p and p[1] then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("CENTER")
	end
end

local function CreateDetail(parent)
	local d = {}
	d.Edge, d.Icon = CreateIcon(parent, 44)
	d.Edge:SetPoint("TOPLEFT", PAD, -PAD)
	d.Name = CreateLabel(parent, "GameFontNormalHuge")
	d.Name:SetPoint("TOPLEFT", d.Edge, "TOPRIGHT", 12, -2)
	d.Name:SetPoint("RIGHT", -PAD, 0)
	d.Name:SetJustifyH("LEFT")
	d.Name:SetWordWrap(false)
	d.Tier = CreateLabel(parent, "GameFontNormal")
	d.Tier:SetPoint("TOPLEFT", d.Name, "BOTTOMLEFT", 0, -6)
	d.Price = CreateLabel(parent, "GameFontHighlight")
	d.Price:SetPoint("LEFT", d.Tier, "RIGHT", 10, 0)

	-- Three stat boxes: owned, recipes, craftable.
	d.Stats = {}
	local labels = { "Owned total", "Recipes", "You can craft" }
	local statWidth = (WIDTH - LIST_WIDTH - 4 * PAD - 2 * 8) / 3
	for i, label in ipairs(labels) do
		local box = CreateFrame("Frame", nil, parent)
		box:SetSize(statWidth, 44)
		box:SetPoint("TOPLEFT", d.Edge, "BOTTOMLEFT", (i - 1) * (statWidth + 8), -14)
		local bg = box:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.35)
		local title = CreateLabel(box, "GameFontDisableSmall", label)
		title:SetPoint("TOPLEFT", 8, -6)
		local value = CreateLabel(box, "GameFontHighlightLarge")
		value:SetPoint("BOTTOMLEFT", 8, 6)
		d.Stats[i] = value
	end

	d.Where = CreateLabel(parent, "GameFontHighlight")
	d.Where:SetPoint("TOPLEFT", d.Edge, "BOTTOMLEFT", 0, -72)
	d.Where:SetPoint("RIGHT", -PAD, 0)
	d.Where:SetJustifyH("LEFT")

	d.UsedIn = CreateLabel(parent, "GameFontNormal", "Used in")
	d.UsedIn:SetPoint("TOPLEFT", d.Where, "BOTTOMLEFT", 0, -12)

	d.Legend = CreateLabel(parent, "GameFontHighlightSmall",
		Color(CHECK .. " this character", COLOR_YOURS) .. "    " .. Color(CHECK .. " an alt", COLOR_ALT)
		.. "    " .. Color("· nobody yet", COLOR_UNKNOWN))
	d.Legend:SetPoint("BOTTOMLEFT", PAD, PAD)

	d.Recipes = Browser:CreateList(parent, RECIPE_ROW_HEIGHT, InitRecipeRow)
	d.Recipes:SetPoint("TOPLEFT", d.UsedIn, "BOTTOMLEFT", 0, -6)
	d.Recipes:SetPoint("BOTTOMRIGHT", -PAD - 12, PAD + 20)

	d.Empty = CreateLabel(parent, "GameFontDisable", "Select a reagent on the left.")
	d.Empty:SetPoint("CENTER")
	return d
end

local function UpdateDetail()
	local d = frame.Detail
	local detail = selected and Browser:GetDetail(selected)
	local show = detail ~= nil
	for _, region in ipairs({ d.Edge, d.Icon, d.Name, d.Tier, d.Price, d.Where, d.UsedIn, d.Legend, d.Recipes }) do
		region:SetShown(show)
	end
	for _, stat in ipairs(d.Stats) do stat:GetParent():SetShown(show) end
	d.Empty:SetShown(not show)
	if not detail then return end

	SetIcon(d.Edge, d.Icon, detail.itemID, detail.tier)
	d.Name:SetText(Color(detail.name, QualityColor(detail.quality)))
	d.Tier:SetText(ns.Valuation:ColorTier(detail.tier))
	local ah = detail.price and ns.Pricing:FormatMoney(detail.price) or "—"
	local vendor = detail.sellPrice and detail.sellPrice > 0 and ns.Pricing:FormatMoney(detail.sellPrice) or "—"
	d.Price:SetText(Color(("AH %s · Vendor %s"):format(ah, vendor), COLOR_HINT))
	d.Stats[1]:SetText(detail.owned > 0 and detail.owned or "—")
	d.Stats[2]:SetText(detail.recipeCount > 0 and detail.recipeCount or "—")
	d.Stats[3]:SetText(detail.craftable)
	local where = #detail.where > 0 and table.concat(detail.where, ", ") or "—"
	d.Where:SetText(Color("Where it is: ", COLOR_HINT) .. Color(where, COLOR_TEXT))
	d.UsedIn:SetShown(#detail.recipes > 0)
	d.Recipes:SetDataProvider(CreateDataProvider(detail.recipes))
end

local function CountChars()
	local n = 0
	for _ in pairs(ns.db.chars) do n = n + 1 end
	return n
end

local function UpdateSubtitle(shown)
	local total = 0
	for itemID in pairs(ns.Reagents) do
		if ns.Valuation:GetInfo(itemID) then total = total + 1 end
	end
	local chars = CountChars()
	frame.Subtitle:SetText(Color(("%d of %d reagents · %d character%s tracked"):format(
		shown, total, chars, chars == 1 and "" or "s"), COLOR_HINT))
end

local function CreateBrowser()
	frame = CreateFrame("Frame", nil, UIParent, "ButtonFrameTemplate") --[[@as table]]
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetToplevel(true)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(frame) end
	if frame.Inset then frame.Inset:Hide() end
	if frame.SetTitle then frame:SetTitle("Reagent Atlas") end
	RestorePosition()

	-- Gear in the title bar. Closes the browser so it can't cover the panel.
	local gear = CreateFrame("Button", nil, frame)
	gear:SetSize(16, 16)
	if frame.CloseButton then
		gear:SetPoint("RIGHT", frame.CloseButton, "LEFT", -4, 0)
	else
		gear:SetPoint("TOPRIGHT", -28, -4)
	end
	gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	gear:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton", "ADD")
	gear:SetScript("OnClick", function()
		if ns.SettingsUI:Open() then frame:Hide() end
	end)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Settings")
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.Gear = gear

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 8, -26)
	content:SetPoint("BOTTOMRIGHT", -8, 8)

	frame.Subtitle = CreateLabel(content, "GameFontHighlightSmall")
	frame.Subtitle:SetPoint("TOPRIGHT", -PAD, -6)

	-- Left pane: filters, column headers, reagent list.
	local left = CreateFrame("Frame", nil, content)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(LIST_WIDTH)
	local leftBg = left:CreateTexture(nil, "BACKGROUND")
	leftBg:SetAllPoints()
	leftBg:SetColorTexture(0, 0, 0, 0.3)

	local searchBox = CreateFrame("EditBox", nil, left, "SearchBoxTemplate")
	searchBox:SetSize(LIST_WIDTH - 2 * PAD - 4, 22)
	searchBox:SetPoint("TOPLEFT", PAD + 4, -PAD)
	searchBox:HookScript("OnTextChanged", function(self)
		search = self:GetText() or ""
		Browser:Refresh()
	end)

	local filters = Browser:GetFilters()
	local profLabel = CreateLabel(left, "GameFontNormalSmall", "Profession")
	profLabel:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -10)
	local profChoice = CreateChoice(left, 160, function() return Browser:GetProfessionChoices() end,
		function() return filters.prof end,
		function(value) filters.prof = value; Browser:Refresh() end)
	profChoice:SetPoint("TOPLEFT", profLabel, "BOTTOMLEFT", 0, -2)

	local tierLabel = CreateLabel(left, "GameFontNormalSmall", "Min tier")
	tierLabel:SetPoint("LEFT", profLabel, "LEFT", 176, 0)
	local tierChoice = CreateChoice(left, 160, function()
		local options = {}
		for tier = 1, ns.Valuation.TIER_KEEP do
			options[tier] = { value = tier, label = tier == 1 and "All" or ns.Valuation:ColorTier(tier) }
		end
		return options
	end, function() return filters.minTier end,
		function(value) filters.minTier = value; Browser:Refresh() end)
	tierChoice:SetPoint("TOPLEFT", tierLabel, "BOTTOMLEFT", 0, -2)

	local ownedCheck = CreateCheck(left, "Owned", "owned")
	ownedCheck:SetPoint("TOPLEFT", profChoice, "BOTTOMLEFT", -2, -6)
	local craftCheck = CreateCheck(left, "Craftable", "craftable")
	craftCheck:SetPoint("LEFT", ownedCheck, "LEFT", 100, 0)

	-- The list leaves 16px on the right for the scroll bar; column headers
	-- line up with the row layout in InitItemRow.
	local rowWidth = LIST_WIDTH - 16
	frame.List = Browser:CreateList(left, ROW_HEIGHT, InitItemRow)
	frame.List:SetPoint("TOPLEFT", ownedCheck, "BOTTOMLEFT", 2, -24)
	frame.List:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -16, 4)
	local headItem = CreateLabel(left, "GameFontDisableSmall", "ITEM")
	headItem:SetPoint("BOTTOMLEFT", frame.List, "TOPLEFT", 6, 4)
	local headTier = CreateLabel(left, "GameFontDisableSmall", "TIER")
	headTier:SetPoint("BOTTOMLEFT", frame.List, "TOPLEFT", rowWidth - 8 - OWNED_COL - 4 - TIER_COL, 4)
	local headOwned = CreateLabel(left, "GameFontDisableSmall", "OWNED")
	headOwned:SetPoint("BOTTOMRIGHT", frame.List, "TOPLEFT", rowWidth - 8, 4)

	frame.Empty = CreateLabel(left, "GameFontDisable", "No reagents match these filters.")
	frame.Empty:SetPoint("CENTER", frame.List, "CENTER")

	-- Right pane: detail.
	local right = CreateFrame("Frame", nil, content)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", PAD, -20)
	right:SetPoint("BOTTOMRIGHT")
	frame.Detail = CreateDetail(right)

	frame:SetScript("OnShow", function() Browser:Refresh() end)
	frame:Hide()
end

-- Rebuilds the list and detail pane if the window is open.
function Browser:Refresh()
	if not frame or not frame:IsShown() then return end
	local filters = self:GetFilters()
	local rows = self:BuildRows({
		search = search, prof = filters.prof, minTier = filters.minTier,
		owned = filters.owned, craftable = filters.craftable,
	})
	local provider = CreateDataProvider(rows)
	frame.List:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
	frame.Empty:SetShown(#rows == 0)
	UpdateSubtitle(#rows)
	UpdateDetail()
end

function Browser:Select(itemID)
	selected = itemID
	if frame and frame:IsShown() then
		frame.List:ForEachFrame(function(button)
			button.Selected:SetShown(button.itemID == selected)
		end)
		UpdateDetail()
	end
end

function Browser:IsShown()
	return frame ~= nil and frame:IsShown()
end

function Browser:Toggle()
	if not frame then CreateBrowser() end
	frame:SetShown(not frame:IsShown())
end

function Browser:Open()
	if not frame then CreateBrowser() end
	frame:Show()
	frame:Raise()
end

-- Item names arrive in bursts after RequestLoadItemDataByID; refresh once.
local refreshQueued = false
local function QueueRefresh()
	if refreshQueued or not Browser:IsShown() then return end
	refreshQueued = true
	C_Timer.After(0.2, function()
		refreshQueued = false
		Browser:Refresh()
	end)
end

function Browser:OnInit()
	ns:RegisterMessage("CHAR_DATA_CHANGED", QueueRefresh)
	ns:RegisterMessage("PRICES_CHANGED", QueueRefresh)
	ns:RegisterMessage("SETTINGS_CHANGED", QueueRefresh)
	ns:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, itemID)
		if requested[itemID] then QueueRefresh() end
	end)
end
