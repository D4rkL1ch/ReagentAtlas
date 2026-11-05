local addonName, ns = ...

-- The browser's Crafting tab: the reverse of the Reagents tab. Lists every
-- recipe and what it crafts; the detail pane shows what it takes to make.
local CraftingUI = ns:RegisterModule("CraftingUI", {})

local ROW_HEIGHT = 30
local ICON_SIZE = 22
local INFO_COL = 130
local DETAIL_ROW_HEIGHT = 24
local DETAIL_ICON = 18
local COUNT_COL = 70
local PAD = 12

local COLOR_TEXT = "ffe8e2d0"
local COLOR_HINT = "ffa39a85"
local COLOR_MET = "ff1eff00"
local COLOR_ALT = "ff66b3ff"
local COLOR_UNKNOWN = "ff9d9d9d"
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "

local KNOWN_COLOR = { me = COLOR_MET, alt = COLOR_ALT, none = COLOR_UNKNOWN }
local DEFAULT_FILTERS = { prof = 0, known = false, ready = false }

local function Color(text, color)
	return ns.Browser.Color(text, color)
end

-- Model ---------------------------------------------------------------------
-- Pure data, no frames: tested offline.

function CraftingUI:GetFilters()
	local ui = ns.db.ui
	ui.craftFilters = ui.craftFilters or {}
	for k, v in pairs(DEFAULT_FILTERS) do
		if ui.craftFilters[k] == nil then ui.craftFilters[k] = v end
	end
	return ui.craftFilters
end

-- One craft of the recipe, in the tracker's terms.
local function Status(recipeID)
	return ns.Tracker:GetStatus({ kind = "recipe", id = recipeID, need = 1 })
end

local function KnownState(recipeID)
	local isMe, alts = ns.Professions:GetKnownBy(recipeID)
	return isMe and "me" or (#alts > 0 and "alt" or "none"), isMe, alts
end

local function Matches(search, name)
	return name ~= nil and name:lower():find(search, 1, true) ~= nil
end

-- Rows matching the filters, highest skill first, then by name. filters:
--   search  substring of the crafted item or recipe name, case-insensitive
--   prof    skill line ID of the recipe (0 = any)
--   known   only recipes some character knows
--   ready   only recipes with enough reagents for one craft (account-wide)
function CraftingUI:BuildRows(filters)
	local search = (filters.search or ""):lower()
	local rows = {}
	for recipeID, recipe in pairs(ns.Recipes) do
		if filters.prof == 0 or recipe.prof == filters.prof then
			local known = KnownState(recipeID)
			local itemName = recipe.out and ns.Browser:GetItemName(recipe.out)
			local recipeName = ns.Tooltip:GetRecipeName(recipeID)
			local keep = (not filters.known or known ~= "none")
				and (search == "" or Matches(search, itemName) or Matches(search, recipeName))
				and (not filters.ready or Status(recipeID).met)
			if keep then
				rows[#rows + 1] = {
					recipeID = recipeID, itemID = recipe.out, name = itemName or recipeName,
					quality = recipe.outQ, prof = ns.Tooltip:GetProfessionName(recipe.prof),
					skill = recipe.skill, known = known,
				}
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.skill ~= b.skill then return a.skill > b.skill end
		if a.name ~= b.name then return a.name < b.name end
		return a.recipeID < b.recipeID
	end)
	return rows
end

-- Everything the detail pane shows for one recipe. rows: headings, one row per
-- reagent, then who knows the recipe or where to get it.
function CraftingUI:GetDetail(recipeID)
	local recipe = ns.Recipes[recipeID]
	if not recipe then return nil end
	local recipeName = ns.Tooltip:GetRecipeName(recipeID)
	local itemName = recipe.out and ns.Browser:GetItemName(recipe.out)
	local recipeItem = ns.Browser:GetRecipeItem(recipeID)
	if recipeItem then ns.Browser:GetItemName(recipeItem) end -- cached for links

	local status = Status(recipeID)
	local rows = {}
	if #status.reagents > 0 then
		rows[1] = { type = "head", text = "Reagents" }
	end
	for _, reagent in ipairs(status.reagents) do
		rows[#rows + 1] = {
			type = "reagent", itemID = reagent.itemID, have = reagent.have, need = reagent.need,
			name = ns.Browser:GetItemName(reagent.itemID) or ("Item #" .. reagent.itemID),
		}
	end
	rows[#rows + 1] = { type = "head", text = "Recipe" }
	if ns.Tracker:AddRecipeInfo(rows, recipeID) then
		rows[#rows + 1] = { type = "note", text = ns.Sources.UNCONFIRMED_NOTE }
	end

	return {
		recipeID = recipeID,
		itemID = recipe.out,
		name = itemName or recipeName,
		recipeName = itemName and recipeName ~= itemName and recipeName or nil,
		quality = recipe.outQ,
		prof = ns.Tooltip:GetProfessionName(recipe.prof),
		skill = recipe.skill,
		isReagent = recipe.out ~= nil and ns.Reagents[recipe.out] ~= nil,
		rows = rows,
	}
end

-- View ----------------------------------------------------------------------

---@type table
local left
---@type table
local list
---@type table
local detail
local search = ""   -- not saved, as in the Reagents tab
local selected      -- recipeID in the detail pane
local lastQuery     -- search and filters of the last refresh

local function Icon(recipeID)
	local recipe = ns.Recipes[recipeID]
	return recipe.out and C_Item.GetItemIconByID(recipe.out) or ns.Browser:GetRecipeIcon(recipeID)
end

local function InitRow(button, row)
	if not button.Name then
		local CreateLabel = ns.Browser.CreateLabel
		button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		button.Selected = button:CreateTexture(nil, "BACKGROUND")
		button.Selected:SetAllPoints()
		button.Selected:SetColorTexture(1, 0.82, 0, 0.12)
		button.Icon = button:CreateTexture(nil, "ARTWORK")
		button.Icon:SetSize(ICON_SIZE, ICON_SIZE)
		button.Icon:SetPoint("LEFT", 6, 0)
		button.Info = CreateLabel(button, "GameFontHighlightSmall")
		button.Info:SetPoint("RIGHT", -8, 0)
		button.Info:SetWidth(INFO_COL)
		button.Info:SetJustifyH("RIGHT")
		button.Info:SetWordWrap(false)
		button.Name = CreateLabel(button, "GameFontHighlight")
		button.Name:SetPoint("LEFT", button.Icon, "RIGHT", 8, 0)
		button.Name:SetPoint("RIGHT", button.Info, "LEFT", -4, 0)
		button.Name:SetJustifyH("LEFT")
		button.Name:SetWordWrap(false)
		button:SetScript("OnClick", function(self)
			if not ns.Browser:HandleCraftedClick(self.recipeID) and not IsModifiedClick() then
				CraftingUI:Select(self.recipeID)
			end
		end)
		button:SetScript("OnEnter", function(self) ns.Browser:ShowCrafted(self, self.recipeID, self.recipeName) end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	button.recipeID, button.recipeName = row.recipeID, row.name
	button.Icon:SetTexture(Icon(row.recipeID))
	button.Name:SetText(Color(row.name, ns.Browser.QualityColor(row.quality)))
	local mark = row.known == "none" and "" or CHECK
	button.Info:SetText(mark .. Color(("%s %d"):format(row.prof, row.skill), KNOWN_COLOR[row.known]))
	button.Selected:SetShown(row.recipeID == selected)
end

local function OnDetailRowEnter(row)
	local data = row.data
	if data.type == "reagent" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(data.itemID)
		GameTooltip:Show()
	elseif data.recipeID then
		ns.Browser:ShowRecipe(row, data.recipeID, ns.Tooltip:GetRecipeName(data.recipeID))
	end
end

-- A reagent row opens that reagent; source rows stand for the recipe.
local function OnDetailRowClick(row)
	local data = row.data
	if data.type == "reagent" then
		if not ns.Browser:HandleItemClick(data.itemID) and not IsModifiedClick() then
			ns.Browser:OpenReagent(data.itemID)
		end
	elseif data.recipeID then
		ns.Browser:HandleRecipeClick(data.recipeID)
	end
end

local function InitDetailRow(row, data)
	if not row.Text then
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:SetScript("OnEnter", OnDetailRowEnter)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:SetScript("OnClick", OnDetailRowClick)
		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetSize(DETAIL_ICON, DETAIL_ICON)
		row.Icon:SetPoint("LEFT", 2, 0)
		row.Count = ns.Browser.CreateLabel(row, "GameFontHighlight")
		row.Count:SetPoint("RIGHT", -4, 0)
		row.Count:SetWidth(COUNT_COL)
		row.Count:SetJustifyH("RIGHT")
		row.Text = ns.Browser.CreateLabel(row, "GameFontHighlight")
		row.Text:SetJustifyH("LEFT")
		row.Text:SetWordWrap(false)
	end
	row.data = data
	local isReagent = data.type == "reagent"
	row.Icon:SetShown(isReagent)
	row.Count:SetShown(isReagent)
	row.Text:ClearAllPoints()
	if isReagent then
		row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
		row.Text:SetPoint("RIGHT", row.Count, "LEFT", -4, 0)
		row.Icon:SetTexture(C_Item.GetItemIconByID(data.itemID))
		row.Text:SetText(Color(data.name, COLOR_TEXT))
		row.Count:SetText(Color(("%d / %d"):format(data.have, data.need), data.have >= data.need and COLOR_MET or COLOR_TEXT))
		return
	end
	row.Text:SetPoint("LEFT", 2, 0)
	row.Text:SetPoint("RIGHT", -4, 0)
	if data.type == "head" then
		row.Text:SetText(Color(data.text, "ffffd100"))
	elseif data.known then
		row.Text:SetText(Color(data.text, KNOWN_COLOR[data.known]))
	else
		row.Text:SetText(Color(data.text, COLOR_HINT))
	end
end

local function CreateDetail(parent)
	local CreateLabel = ns.Browser.CreateLabel
	local d = {}
	d.Item = CreateFrame("Button", nil, parent)
	d.Item:SetSize(44, 44)
	d.Item:SetPoint("TOPLEFT", PAD, -PAD)
	d.Icon = d.Item:CreateTexture(nil, "ARTWORK")
	d.Icon:SetAllPoints()
	d.Item:SetScript("OnClick", function() ns.Browser:HandleCraftedClick(selected) end)
	d.Item:SetScript("OnEnter", function(self) ns.Browser:ShowCrafted(self, selected, ns.Tooltip:GetRecipeName(selected)) end)
	d.Item:SetScript("OnLeave", function() GameTooltip:Hide() end)

	d.Track = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	d.Track:SetSize(70, 22)
	d.Track:SetPoint("TOPRIGHT", -PAD, -PAD)
	d.Track:SetScript("OnClick", function() ns.Browser.ToggleTracked("recipe", selected) end)

	d.AsReagent = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	d.AsReagent:SetSize(120, 22)
	d.AsReagent:SetPoint("TOPRIGHT", d.Track, "BOTTOMRIGHT", 0, -4)
	d.AsReagent:SetText("Used as reagent")
	d.AsReagent:SetScript("OnClick", function() ns.Browser:OpenReagent(ns.Recipes[selected].out) end)

	d.Name = CreateLabel(parent, "GameFontNormalHuge")
	d.Name:SetPoint("TOPLEFT", d.Item, "TOPRIGHT", 12, -2)
	d.Name:SetPoint("RIGHT", d.Track, "LEFT", -8, 0)
	d.Name:SetJustifyH("LEFT")
	d.Name:SetWordWrap(false)
	d.Info = CreateLabel(parent, "GameFontHighlight")
	d.Info:SetPoint("TOPLEFT", d.Name, "BOTTOMLEFT", 0, -6)
	d.Info:SetPoint("RIGHT", d.AsReagent, "LEFT", -8, 0)
	d.Info:SetJustifyH("LEFT")
	d.Info:SetWordWrap(false)

	d.Rows = ns.Browser:CreateList(parent, DETAIL_ROW_HEIGHT, InitDetailRow)
	d.Rows:SetPoint("TOPLEFT", d.Item, "BOTTOMLEFT", 0, -14)
	d.Rows:SetPoint("BOTTOMRIGHT", -PAD - 12, PAD)

	d.Empty = CreateLabel(parent, "GameFontDisable", "Select a recipe on the left.")
	d.Empty:SetPoint("CENTER")
	return d
end

local function UpdateTrackButton()
	if detail and selected then
		detail.Track:SetText(ns.Tracker:Find("recipe", selected) and "Untrack" or "Track")
	end
end

local function UpdateDetail()
	local d = detail
	-- Refreshes of the same recipe keep the scroll; a new recipe starts at the top.
	local sameRecipe = d.ShownRecipe == selected
	d.ShownRecipe = selected
	local data = selected and CraftingUI:GetDetail(selected)
	local show = data ~= nil
	for _, region in ipairs({ d.Item, d.Track, d.Name, d.Info, d.Rows }) do
		region:SetShown(show)
	end
	d.AsReagent:SetShown(data ~= nil and data.isReagent)
	d.Empty:SetShown(not show)
	if not data then return end

	d.Icon:SetTexture(Icon(selected))
	d.Name:SetText(Color(data.name, ns.Browser.QualityColor(data.quality)))
	local info = ("%s %d"):format(data.prof, data.skill)
	if data.recipeName then info = info .. " · " .. data.recipeName end
	d.Info:SetText(Color(info, COLOR_HINT))
	UpdateTrackButton()
	d.Rows:SetDataProvider(CreateDataProvider(data.rows),
		sameRecipe and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
end

local function CreatePane()
	local CreateLabel = ns.Browser.CreateLabel
	local right
	left, right = ns.Browser:CreatePanes()
	CraftingUI.Right = right

	local searchBox = CreateFrame("EditBox", nil, left, "SearchBoxTemplate")
	searchBox:SetSize(ns.Browser.LIST_WIDTH - 2 * PAD - 4, 22)
	searchBox:SetPoint("TOPLEFT", PAD + 4, -PAD)
	searchBox:HookScript("OnTextChanged", function(self)
		search = self:GetText() or ""
		CraftingUI:Refresh()
	end)

	local filters = CraftingUI:GetFilters()
	local profLabel = CreateLabel(left, "GameFontNormalSmall", "Profession")
	profLabel:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -10)
	local profChoice = ns.Browser.CreateChoice(left, 160, function() return ns.Browser:GetProfessionChoices() end,
		function() return filters.prof end,
		function(value) filters.prof = value; CraftingUI:Refresh() end)
	profChoice:SetPoint("TOPLEFT", profLabel, "BOTTOMLEFT", 0, -2)

	local knownCheck = ns.Browser.CreateCheck(left, "Known", "known", CraftingUI)
	knownCheck:SetPoint("TOPLEFT", profChoice, "BOTTOMLEFT", -2, -6)
	local readyCheck = ns.Browser.CreateCheck(left, "Have reagents", "ready", CraftingUI)
	readyCheck:SetPoint("LEFT", knownCheck, "LEFT", 100, 0)

	list = ns.Browser:CreateList(left, ROW_HEIGHT, InitRow)
	list:SetPoint("TOPLEFT", knownCheck, "BOTTOMLEFT", 2, -8)
	list:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -16, 4)

	left.Empty = CreateLabel(left, "GameFontDisable", "No recipes match these filters.")
	left.Empty:SetPoint("CENTER", list, "CENTER")

	detail = CreateDetail(right)
end

-- Built the first time the tab opens: until then nothing here is needed, and
-- the list asks the client for every crafted item.
function CraftingUI:SetShown(show)
	if show and not left then CreatePane() end
	if left then
		left:SetShown(show)
		self.Right:SetShown(show)
	end
end

local function CountRecipes()
	local total = 0
	for _ in pairs(ns.Recipes) do total = total + 1 end
	return total
end

function CraftingUI:Refresh()
	if not left then return end
	local filters = self:GetFilters()
	local rows = self:BuildRows({
		search = search, prof = filters.prof, known = filters.known, ready = filters.ready,
	})
	-- Data arriving keeps your place; changing the search or filters starts over.
	local query = ("%s|%d|%s|%s"):format(search, filters.prof, tostring(filters.known), tostring(filters.ready))
	local retain = query == lastQuery
	lastQuery = query
	list:SetDataProvider(CreateDataProvider(rows), retain and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
	left.Empty:SetShown(#rows == 0)
	ns.Browser:SetSubtitle(#rows, CountRecipes(), "recipes")
	UpdateDetail()
end

function CraftingUI:Select(recipeID)
	selected = recipeID
	if not left then return end
	list:ForEachFrame(function(button)
		button.Selected:SetShown(button.recipeID == selected)
	end)
	UpdateDetail()
end

function CraftingUI:OnInit()
	ns:RegisterMessage("TRACKER_CHANGED", UpdateTrackButton)
end
