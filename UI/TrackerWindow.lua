local addonName, ns = ...

local TrackerUI = ns:RegisterModule("TrackerUI", {})

local WIDTH, HEIGHT = 340, 400
local ROW_HEIGHT = 24
local ICON_SIZE = 18
local REMOVE_SIZE = 16
local INDENT = 20
local COUNT_WIDTH = 76
local FOOTER_HEIGHT = 30
local HEADER_HEIGHT = 20
local PAD = 12
local MAX_NEED_DIGITS = 5
local REFRESH_DELAY = 0.2

local COLOR_TEXT = "ffe8e2d0"
local COLOR_HINT = "ffa39a85"
local COLOR_MET = "ff1eff00"
local COLOR_ALT = "ff66b3ff"
local COLOR_HEAD = "ffffd100"
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
local EXPANDED = "|TInterface\\Buttons\\UI-MinusButton-Up:12|t "
local COLLAPSED = "|TInterface\\Buttons\\UI-PlusButton-Up:12|t "
local HINT = "Click a count to set how many you need."
local SHOPPING_HINT = "Totals for tracked recipes, reagents shared out."
local EMPTY = "Nothing tracked yet. In the reagent browser, press Track on a reagent or + on a recipe."
local EMPTY_SHOPPING = "No tracked recipes yet. Track a recipe to see what you need for all of them together."
local VIEW_SHOPPING = "shopping"

local function Color(text, color)
	return WrapTextInColorCode(text, color)
end

---@type table
local frame
local editing -- entry whose goal the footer box is changing
local shownShopping -- the view on screen, to tell a refresh from a switch

local function IsShopping()
	return ns.db.ui.trackerView == VIEW_SHOPPING
end

-- Footer: set a goal --------------------------------------------------------

local function EndEdit()
	if not editing then return end
	editing = nil
	frame.NeedBox:ClearFocus()
	frame.NeedBox:Hide()
	frame.Prompt:SetText(Color(HINT, COLOR_HINT))
end

local function CommitEdit()
	local entry = editing
	if not entry then return end
	local count = tonumber(frame.NeedBox:GetText())
	EndEdit()
	ns.Tracker:SetNeed(entry, count)
end

local function BeginEdit(entry, name)
	editing = entry
	local question = entry.kind == "recipe" and "Crafts of %s:" or "How many %s:"
	frame.Prompt:SetText(Color(question:format(name), COLOR_TEXT))
	frame.NeedBox:SetText(entry.need and tostring(entry.need) or "")
	frame.NeedBox:Show()
	frame.NeedBox:SetFocus()
	frame.NeedBox:HighlightText()
end

-- Rows ----------------------------------------------------------------------

local function ShowItem(owner, itemID)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(itemID)
	GameTooltip:Show()
end

local function HideTooltip()
	GameTooltip:Hide()
end

local function OnRowEnter(row)
	local data = row.data
	if data.itemID then
		ShowItem(row, data.itemID)
	elseif data.type == "entry" then
		ns.Browser:ShowCrafted(row, data.entry.id, data.name)
	elseif data.recipeID then
		ns.Browser:ShowRecipe(row, data.recipeID, ns.Tooltip:GetRecipeName(data.recipeID))
	end
end

-- As in the browser: rows stand for an item, source lines for the recipe.
-- A plain click on a recipe folds it.
local function OnRowClick(row)
	local data = row.data
	if data.itemID then
		ns.Browser:HandleItemClick(data.itemID)
	elseif data.type == "entry" then
		local used = ns.Browser:HandleCraftedClick(data.entry.id)
		if not used and not IsModifiedClick() then
			ns.Tracker:SetCollapsed(data.entry, not data.entry.collapsed)
		end
	elseif data.recipeID then
		ns.Browser:HandleRecipeClick(data.recipeID)
	end
end

local function CreateRow(row)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:SetScript("OnEnter", OnRowEnter)
	row:SetScript("OnLeave", HideTooltip)
	row:SetScript("OnClick", OnRowClick)

	row.Remove = CreateFrame("Button", nil, row)
	row.Remove:SetSize(REMOVE_SIZE, REMOVE_SIZE)
	row.Remove:SetPoint("RIGHT", -2, 0)
	row.Remove:SetHitRectInsets(-4, -2, -4, -4) -- the full row height
	row.Remove:SetNormalTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
	row.Remove:SetScript("OnClick", function()
		ns.Tracker:Remove(row.data.entry.kind, row.data.entry.id)
	end)
	row.Remove:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Stop tracking")
		GameTooltip:Show()
	end)
	row.Remove:SetScript("OnLeave", HideTooltip)

	-- A button on entry rows (it sets the goal), plain text on reagent rows.
	row.Count = CreateFrame("Button", nil, row)
	row.Count:SetSize(COUNT_WIDTH, ROW_HEIGHT)
	row.Count:SetPoint("RIGHT", -(REMOVE_SIZE + 8), 0)
	row.Count.Label = row.Count:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Count.Label:SetPoint("RIGHT")
	row.Count:SetScript("OnClick", function()
		BeginEdit(row.data.entry, row.data.name)
	end)
	row.Count:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(row.data.entry.kind == "recipe" and "Click to set how many to craft"
			or "Click to set how many you need")
		GameTooltip:Show()
	end)
	row.Count:SetScript("OnLeave", HideTooltip)

	row.IconButton = CreateFrame("Button", nil, row)
	row.IconButton:SetSize(ICON_SIZE, ICON_SIZE)
	row.IconButton:SetHitRectInsets(-3, -3, -3, -3)
	row.Icon = row.IconButton:CreateTexture(nil, "ARTWORK")
	row.Icon:SetAllPoints()
	row.IconButton:SetScript("OnClick", function()
		ns.Browser:HandleRecipeClick(row.data.entry.id)
	end)
	row.IconButton:SetScript("OnEnter", function(self)
		ns.Browser:ShowRecipe(self, row.data.entry.id, row.data.name)
	end)
	row.IconButton:SetScript("OnLeave", HideTooltip)

	row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Text:SetJustifyH("LEFT")
	row.Text:SetWordWrap(false)
end

local function Progress(have, need)
	return Color(("%d / %d"):format(have, need), have >= need and COLOR_MET or COLOR_TEXT)
end

local function PlaceText(row, left, right)
	row.Text:ClearAllPoints()
	row.Text:SetPoint("LEFT", left, "RIGHT", 4, 0)
	row.Text:SetPoint("RIGHT", right, "LEFT", -4, 0)
end

local function PlaceIcon(row, indent)
	row.IconButton:ClearAllPoints()
	row.IconButton:SetPoint("LEFT", indent, 0)
	PlaceText(row, row.IconButton, row.Count)
end

-- Source and note lines have no icon or count, so they take the whole row.
local function PlainLine(row, text, color)
	row.Text:ClearAllPoints()
	row.Text:SetPoint("LEFT", INDENT, 0)
	row.Text:SetPoint("RIGHT", -4, 0)
	row.Text:SetText(Color(text, color))
end

local function InitEntry(row, data)
	local entry, status = data.entry, data.status
	row.IconButton:EnableMouse(entry.kind == "recipe")
	PlaceIcon(row, 2)
	if entry.kind == "item" then
		row.Icon:SetTexture(C_Item.GetItemIconByID(entry.id))
		row.Text:SetText(Color(data.name, COLOR_TEXT))
		row.Count.Label:SetText(status.need and Progress(status.have, status.need)
			or Color(("%d / —"):format(status.have), COLOR_TEXT))
	else
		row.Icon:SetTexture(ns.Browser:GetRecipeIcon(entry.id))
		row.Text:SetText(Color((entry.collapsed and COLLAPSED or EXPANDED) .. data.name, COLOR_TEXT))
		row.Count.Label:SetText((status.met and CHECK or "") .. Color("x" .. entry.need, COLOR_HINT))
	end
end

-- Indented rows with an icon and a count: reagents and the shopping view.
local function InitItem(row, icon, text, count)
	row.IconButton:EnableMouse(false)
	PlaceIcon(row, INDENT)
	row.Icon:SetTexture(icon)
	row.Text:SetText(text)
	row.Count.Label:SetText(count)
end

local function InitRow(row, data)
	if not row.Text then CreateRow(row) end
	row.data = data
	local isEntry = data.type == "entry"
	local isItem = data.type == "reagent" or data.type == "shop" or data.type == "craft"
	row.Remove:SetShown(isEntry)
	row.Count:SetShown(isEntry or isItem)
	row.Count:EnableMouse(isEntry)
	row.IconButton:SetShown(isEntry or isItem)
	if isEntry then
		InitEntry(row, data)
	elseif data.type == "reagent" then
		InitItem(row, C_Item.GetItemIconByID(data.itemID), Color(data.name, COLOR_TEXT), Progress(data.have, data.need))
	elseif data.type == "shop" then
		local text = Color(data.name, COLOR_TEXT)
		if data.vendor then text = text .. Color(" (vendor)", COLOR_HINT) end
		InitItem(row, C_Item.GetItemIconByID(data.itemID), text, Color(tostring(data.count), COLOR_TEXT))
	elseif data.type == "craft" then
		local text = Color(data.name, COLOR_TEXT) .. Color((" (%s)"):format(data.who), data.mine and COLOR_MET or COLOR_ALT)
		InitItem(row, ns.Browser:GetRecipeIcon(data.recipeID), text, Color("x" .. data.count, COLOR_HINT))
	elseif data.type == "head" then
		row.Text:ClearAllPoints()
		row.Text:SetPoint("LEFT", 4, 0)
		row.Text:SetPoint("RIGHT", -4, 0)
		row.Text:SetText(Color(data.text, COLOR_HEAD))
	elseif data.known then
		PlainLine(row, data.text, data.known == "me" and COLOR_MET or COLOR_ALT)
	else
		PlainLine(row, data.text, COLOR_HINT)
	end
end

-- Window --------------------------------------------------------------------

local function CreateNeedBox(parent)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(54, 22)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(MAX_NEED_DIGITS)
	box:SetScript("OnEnterPressed", CommitEdit)
	box:SetScript("OnEscapePressed", EndEdit)
	box:HookScript("OnEditFocusLost", EndEdit)
	box:Hide()
	return box
end

local function CreateWindow()
	frame = ns.Browser:CreateWindow(WIDTH, HEIGHT, "Tracking list", "trackerPoint", "RIGHT", -60, 0)
	-- Below the browser: this one stays open while playing.
	frame:SetFrameStrata("MEDIUM")

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 8, -26)
	content:SetPoint("BOTTOMRIGHT", -8, 8)

	frame.NeedBox = CreateNeedBox(content)
	frame.NeedBox:SetPoint("BOTTOMRIGHT", -4, 6)
	frame.Prompt = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Prompt:SetPoint("BOTTOMLEFT", 4, 10)
	frame.Prompt:SetPoint("RIGHT", frame.NeedBox, "LEFT", -8, 0)
	frame.Prompt:SetJustifyH("LEFT")
	frame.Prompt:SetWordWrap(false)
	frame.Prompt:SetText(Color(HINT, COLOR_HINT))

	frame.ViewButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	frame.ViewButton:SetSize(120, HEADER_HEIGHT)
	frame.ViewButton:SetPoint("TOPLEFT", 2, -2)
	frame.ViewButton:SetScript("OnClick", function()
		EndEdit()
		ns.db.ui.trackerView = not IsShopping() and VIEW_SHOPPING or nil
		TrackerUI:Refresh()
	end)

	frame.List = ns.Browser:CreateList(content, ROW_HEIGHT, InitRow)
	frame.List:SetPoint("TOPLEFT", 0, -(HEADER_HEIGHT + 6))
	frame.List:SetPoint("BOTTOMRIGHT", -16, FOOTER_HEIGHT)

	frame.Empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.Empty:SetPoint("LEFT", PAD, 0)
	frame.Empty:SetPoint("RIGHT", -PAD, 0)
	frame.Empty:SetText(EMPTY)

	frame:SetScript("OnShow", function()
		ns.db.ui.trackerShown = true
		TrackerUI:Refresh()
	end)
	frame:SetScript("OnHide", function()
		ns.db.ui.trackerShown = false
		EndEdit()
	end)
end

function TrackerUI:Refresh()
	if not self:IsShown() then return end
	if editing and ns.Tracker:Find(editing.kind, editing.id) ~= editing then
		EndEdit()
	end
	local shopping = IsShopping()
	local rows = shopping and ns.Tracker:GetShoppingRows() or ns.Tracker:GetRows()
	-- Your place in a view is kept, but the other view starts at the top.
	local sameView = shopping == shownShopping
	shownShopping = shopping
	frame.List:SetDataProvider(CreateDataProvider(rows), sameView and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
	frame.Empty:SetText(shopping and EMPTY_SHOPPING or EMPTY)
	frame.Empty:SetShown(#rows == 0)
	frame.ViewButton:SetText(shopping and "Tracked items" or "Shopping list")
	if not editing then
		frame.Prompt:SetText(Color(shopping and SHOPPING_HINT or HINT, COLOR_HINT))
	end
end

function TrackerUI:IsShown()
	return frame ~= nil and frame:IsShown()
end

function TrackerUI:Toggle()
	if not frame then
		CreateWindow() -- created shown, so OnShow doesn't run
		ns.db.ui.trackerShown = true
		self:Refresh()
	else
		frame:SetShown(not frame:IsShown())
	end
end

function TrackerUI:Open()
	if not frame then
		self:Toggle()
	else
		frame:Show()
	end
end

-- Item names arrive in bursts after RequestLoadItemDataByID; refresh once.
local refreshQueued = false
local function QueueRefresh()
	if refreshQueued or not TrackerUI:IsShown() then return end
	refreshQueued = true
	C_Timer.After(REFRESH_DELAY, function()
		refreshQueued = false
		TrackerUI:Refresh()
	end)
end

function TrackerUI:OnInit()
	ns:RegisterMessage("TRACKER_CHANGED", function() TrackerUI:Refresh() end)
	ns:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, itemID)
		if ns.Browser:WasRequested(itemID) then QueueRefresh() end
	end)
end

function TrackerUI:OnLogin()
	if ns.db.ui.trackerShown then self:Open() end
end

ns:RegisterCommand("track", "track - open or close the tracking list", function() TrackerUI:Toggle() end)
