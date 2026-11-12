---@diagnostic disable: undefined-global, lowercase-global, undefined-field
-- Minimal WoW API stubs for offline tests. Extend as modules need more.

local M = {}

local frames = {}
local tooltipPostCalls = {}

-- Widgets (frames, textures, font strings) share one method table. Methods
-- record state the tests read back (shown, text, color, points); the rest
-- are no-ops. Unknown methods error, so a typo in UI code fails the tests.
local W = {}
local widgetMT = { __index = W }

local function noop() end
for _, name in ipairs({
	"SetSize", "SetWidth", "SetHeight", "SetAllPoints", "SetToplevel", "SetFrameStrata",
	"SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving",
	"StopMovingOrSizing", "SetJustifyH", "SetWordWrap", "SetRotation", "SetHighlightTexture",
	"SetOwner", "SetItemByID", "SetSpellByID", "SetElementExtent", "SetFrameLevel", "RegisterForClicks",
	"SetNormalTexture", "Raise", "AddLine", "SetAutoFocus", "SetNumeric", "SetMaxLetters", "SetFocus",
	"ClearFocus", "HighlightText", "SetHitRectInsets", "SetTexCoord", "AddDoubleLine",
}) do W[name] = noop end

local function newWidget(kind, parent)
	local w = setmetatable({ kind = kind, parent = parent, events = {}, scripts = {}, shown = true, points = {} }, widgetMT)
	frames[#frames + 1] = w
	return w
end

function W:RegisterEvent(e) self.events[e] = true end
function W:UnregisterEvent(e) self.events[e] = nil end
function W:SetScript(name, fn) self.scripts[name] = fn end
function W:HookScript(name, fn)
	local old = self.scripts[name]
	self.scripts[name] = function(...)
		if old then old(...) end
		fn(...)
	end
end
function W:GetParent() return self.parent end
function W:Show()
	local was = self.shown
	self.shown = true
	if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function W:Hide()
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function W:SetShown(shown) if shown then self:Show() else self:Hide() end end
function W:IsShown() return self.shown end
function W:SetPoint(...) self.points[#self.points + 1] = { ... } end
function W:ClearAllPoints() self.points = {} end
function W:GetPoint(i)
	local p = self.points[i or 1]
	if not p then return nil end
	-- point, relativeTo, relativePoint, x, y as SetPoint(point, rel, relPoint, x, y)
	return p[1], p[2], p[3], p[4], p[5]
end
function W:SetEnabled(enabled) self.enabled = enabled end
function W:SetText(text) self.text = text end
function W:GetText() return self.text end
function W:SetChecked(v) self.checked = v end
function W:GetChecked() return self.checked end
function W:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function W:SetTexture(t) self.texture = t end
function W:CreateTexture() return newWidget("Texture", self) end
function W:CreateFontString() return newWidget("FontString", self) end
function W:SetTitle(text) self.title = text end
function W:SetAlpha(a) self.alpha = a end
function W:GetAlpha() return self.alpha or 1 end
-- 12 pixels per line of text.
function W:GetStringHeight()
	local _, breaks = (self.text or ""):gsub("\n", "")
	return self.text and self.text ~= "" and (breaks + 1) * 12 or 0
end

-- WowScrollBoxList: SetDataProvider "renders" up to 40 elements through the
-- view's initializer, reusing row frames like the real ScrollBox. `scroll`
-- stands in for its position: back to the top unless told to retain it.
local SCROLLBOX_VISIBLE = 40
function W:SetDataProvider(provider, retainScrollPosition)
	self.provider = provider
	if not retainScrollPosition then self.scroll = 0 end
	self.rows = self.rows or {}
	local view = self.view
	for i = 1, math.min(#provider.list, SCROLLBOX_VISIBLE) do
		self.rows[i] = self.rows[i] or newWidget("Button", self)
		view.initializer(self.rows[i], provider.list[i])
	end
	for i = #provider.list + 1, #self.rows do self.rows[i]:Hide() end
end
function W:ForEachFrame(fn)
	for i = 1, math.min(#(self.provider and self.provider.list or {}), #(self.rows or {})) do
		fn(self.rows[i])
	end
end

function M.newWidget(kind, parent) return newWidget(kind, parent) end
function M.allWidgets() return frames end

-- A bag window like Blizzard's ContainerFrameMixin: one item button per slot
-- of `bagID`; UpdateItems is what the game calls when contents change.
function M.newBagFrame(bagID, slots)
	local f = newWidget("Frame")
	f.buttons = {}
	for slot = 1, slots and #slots or 0 do
		local b = newWidget("ItemButton", f)
		function b:GetBagID() return bagID end
		function b:GetID() return slot end
		f.buttons[slot] = b
	end
	function f:EnumerateValidItems()
		local i = 0
		return function()
			i = i + 1
			if self.buttons[i] then return i, self.buttons[i] end
		end
	end
	function f:UpdateItems() self.updates = (self.updates or 0) + 1 end
	return f
end

-- Deliver an event to every frame registered for it.
function M.fire(event, ...)
	for i = 1, #frames do
		local f = frames[i]
		if f.events[event] and f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end

-- Run a slash command as if typed in chat.
function M.slash(cmd, msg)
	for key, fn in pairs(SlashCmdList) do
		local i = 1
		while _G["SLASH_" .. key .. i] do
			if _G["SLASH_" .. key .. i] == cmd then
				return fn(msg)
			end
			i = i + 1
		end
	end
	error("no slash command " .. cmd)
end

-- Fake GameTooltip: records lines; SetItem runs the item post-calls the way
-- TooltipDataProcessor does, RefreshData rebuilds from the last item.
function M.newTooltip()
	local tt = { lines = {}, shown = false }
	function tt:AddLine(text) self.lines[#self.lines + 1] = text end
	function tt:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " | " .. r end
	function tt:IsShown() return self.shown end
	function tt:Hide() self.shown = false end
	function tt:SetItem(itemID)
		self.itemID, self.shown, self.lines = itemID, true, {}
		self.data = { type = Enum.TooltipDataType.Item, id = itemID }
		for _, fn in ipairs(tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do
			fn(self, self.data)
		end
	end
	-- The same tooltip reused for a unit (e.g. hovering a party frame).
	function tt:SetUnit(unit)
		self.itemID, self.shown, self.lines = nil, true, { unit }
		self.data = { type = Enum.TooltipDataType.Unit }
	end
	function tt:RefreshData()
		if not self.itemID then error("RefreshData on a non-item tooltip") end
		self:SetItem(self.itemID)
	end
	-- Lines with color codes stripped, joined by newlines.
	function tt:Text()
		local out = {}
		for i, line in ipairs(self.lines) do
			out[i] = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t ", "[v] ")
		end
		return table.concat(out, "\n")
	end
	return tt
end

function M.reset()
	frames = {}
	tooltipPostCalls = {}
	M.printed = {}
	M.errors = {}
	M.shift = false
	M.classToken = "WARRIOR"
	M.timers = {}
	M.now = 0
	M.sounds = {}
	M.notices = {}
	-- Character state, changed by tests.
	M.professions = {}       -- array of { skillLine, rank, maxRank } in GetProfessions order
	M.tradeSkill = nil       -- open window: { profID, skillLevel, recipes = { [id] = learned }, linked, filteredOnly }
	M.containers = {}        -- [bagID] = array of { itemID, count } (nil = empty slot)
	M.bankTabs = { [0] = { 6, 7 }, [2] = { 15 } }
	M.accountBankViewable = true
	M.noBankAPI = false
	M.combat = false
	M.popup = nil
	M.compartment = {}
	AddonCompartmentFrame = { RegisterAddon = function(_, data) M.compartment[#M.compartment + 1] = data end }
	M.noDropdown = false
	M.itemLoads = {}
	M.modifier = nil
	M.linked = {}
	M.uncachedItems = {}
	SlashCmdList = {}
	Settings = M.newSettings()
	ContainerFrameCombinedBags = nil
	ContainerFrameContainer = { ContainerFrames = { M.newBagFrame(0, {}) } }
	Auctionator = nil
	ElvUI = nil
	ReagentAtlasDB = nil
end

-- Run pending C_Timer callbacks in due order on a virtual clock (including
-- ones they schedule). With `seconds`, stops that far ahead of now.
function M.runTimers(seconds)
	local limit = seconds and M.now + seconds
	while #M.timers > 0 do
		local nextIndex = 1
		for i = 2, #M.timers do
			if M.timers[i].at < M.timers[nextIndex].at then nextIndex = i end
		end
		if limit and M.timers[nextIndex].at > limit then break end
		local timer = table.remove(M.timers, nextIndex)
		M.now = timer.at
		timer.fn()
	end
	if limit then M.now = limit end
end

-- Globals -------------------------------------------------------------------

unpack = unpack or table.unpack

function print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	M.printed[#M.printed + 1] = table.concat(parts, " ")
end

function CreateFrame(kind, _, parent, template)
	local w = newWidget(kind, parent)
	w.template = template
	if template == "UICheckButtonTemplate" then
		w.Text = newWidget("FontString", w)
	elseif template == "WowStyle1DropdownTemplate" then
		if M.noDropdown then error("unknown template") end
		function w:SetupMenu(fn)
			self.menu = fn
		end
	end
	return w
end
UIParent = newWidget("Frame")
GameTooltip = newWidget("GameTooltip")

-- Minimap: 140 wide, centered at (500, 400), scale 1.
Minimap = newWidget("Frame")
function Minimap:GetWidth() return 140 end
function Minimap:GetCenter() return 500, 400 end
function Minimap:GetEffectiveScale() return 1 end
function Minimap:GetFrameLevel() return 2 end
M.cursor = { 0, 0 }
function GetCursorPosition() return M.cursor[1], M.cursor[2] end
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- Popups: StaticPopup_Show records the dialog; tests run its OnAccept.
StaticPopupDialogs = {}
YES, NO = "Yes", "No"
function StaticPopup_Show(name, text) M.popup = { name = name, text = text, dialog = StaticPopupDialogs[name] } end
function date(fmt, t) return os.date("!" .. fmt, t) end

function CreateSettingsButtonInitializer(name, buttonText, click)
	return { name = name, buttonText = buttonText, click = click }
end

-- ScrollBox helpers.
function CreateScrollBoxListLinearView()
	local view = {}
	function view:SetElementExtent() end
	function view:SetElementInitializer(_, fn) self.initializer = fn end
	return view
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, _, view) box.view = view end }
function CreateDataProvider(list) return { list = list } end
ScrollBoxConstants = { RetainScrollPosition = true }

-- hooksecurefunc(table, name, fn) / hooksecurefunc(name, fn): post-hook.
function hooksecurefunc(t, name, fn)
	if type(t) == "string" then t, name, fn = _G, t, name end
	local orig = t[name]
	t[name] = function(...)
		local r = { orig(...) }
		fn(...)
		return unpack(r)
	end
end

-- Settings API: records registrations; setting:SetValue writes the saved
-- table and runs the value-changed callbacks like the real panel.
function M.newSettings()
	local s = { categories = {}, settings = {}, callbacks = {}, controls = {}, opened = nil }
	s.VarType = { Boolean = "boolean", Number = "number", String = "string" }
	s.initializers = {}
	function s.RegisterVerticalLayoutCategory(name)
		local category = { name = name, GetID = function() return "cat:" .. name end }
		s.categories[#s.categories + 1] = category
		return category, { AddInitializer = function(_, init) s.initializers[#s.initializers + 1] = init end }
	end
	function s.RegisterCanvasLayoutSubcategory(_, frame, name)
		s.canvas = { frame = frame, name = name }
	end
	function s.RegisterAddOnSetting(_, variable, key, tbl, varType, label, default)
		local setting = { variable = variable, key = key, varType = varType, label = label, default = default }
		function setting:GetValue() return tbl[key] end
		function setting:SetValue(v)
			tbl[key] = v
			for _, cb in ipairs(s.callbacks[variable] or {}) do cb(nil, self, v) end
		end
		s.settings[key] = setting
		return setting
	end
	function s.SetOnValueChangedCallback(variable, cb)
		s.callbacks[variable] = s.callbacks[variable] or {}
		table.insert(s.callbacks[variable], cb)
	end
	function s.CreateCheckbox(_, setting) s.controls[#s.controls + 1] = { kind = "checkbox", setting = setting } end
	function s.CreateDropdown(_, setting, options)
		s.controls[#s.controls + 1] = { kind = "dropdown", setting = setting, options = options }
	end
	function s.CreateControlTextContainer()
		local data = {}
		return {
			Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end,
			GetData = function() return data end,
		}
	end
	function s.RegisterAddOnCategory(category) s.registered = category end
	function s.OpenToCategory(id) s.opened = id end
	return s
end
function geterrorhandler() return function(err) M.errors[#M.errors + 1] = err end end

function strjoin(sep, ...) return table.concat({ ... }, sep) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function tostringall(...)
	local t = { ... }
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	return unpack(t, 1, select("#", ...))
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function WrapTextInColorCode(text, color) return "|c" .. color .. text .. "|r" end

function GetBuildInfo() return "1.60.0", "99999", "Nov 4 2026", 16000 end
function UnitName() return "Tester" end
function strsplit(sep, text)
	local parts = {}
	for part in (text .. sep):gmatch("(.-)" .. sep) do parts[#parts + 1] = part end
	return unpack(parts)
end
function GetNormalizedRealmName() return "StubRealm" end
function InCombatLockdown() return M.combat end
function IsShiftKeyDown() return M.shift end
function UnitClass() return M.classToken, M.classToken end

C_AddOns = {
	GetAddOnMetadata = function(_, field)
		if field == "Version" then return "0.1.0" end
	end,
	IsAddOnLoaded = function() return false end,
}

M.spellNames = { [2963] = "Bolt of Linen Cloth", [990001] = "Feathered Jerkin" }
C_Spell = {
	GetSpellName = function(id) return M.spellNames[id] end,
	GetSpellLink = function(id) return "spell:" .. id end,
}
-- Modified clicks: M.modifier is nil, "CHATLINK" or "DRESSUP"; links land in M.linked.
function IsModifiedClick(action)
	if action then return M.modifier == action end
	return M.modifier ~= nil
end
function HandleModifiedItemClick(link)
	M.linked[#M.linked + 1] = link
	return true
end
function ChatEdit_InsertLink(link)
	M.linked[#M.linked + 1] = link
	return true
end
-- Item names: a few fixed ones plus M.itemNames set by tests.
M.itemNames = {}
C_Item = {
	GetItemNameByID = function(id)
		if id == 990102 then return "Feathered Boots" end
		return M.itemNames[id]
	end,
	GetItemIconByID = function(id) return 100000 + id end,
	GetItemInfo = function(id)
		if M.uncachedItems[id] then return nil end
		return "item", "item:" .. id
	end,
	RequestLoadItemDataByID = function(id) M.itemLoads[#M.itemLoads + 1] = id end,
}

LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", PRIEST = "Priest" }
C_ClassColor = {
	GetClassColor = function(token)
		if token == "MAGE" then
			return { WrapTextInColorCode = function(_, text) return "|cff3fc7eb" .. text .. "|r" end }
		end
	end,
}

Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
TooltipDataProcessor = {
	AddTooltipPostCall = function(kind, fn)
		tooltipPostCalls[kind] = tooltipPostCalls[kind] or {}
		table.insert(tooltipPostCalls[kind], fn)
	end,
}


C_Timer = { After = function(delay, fn) M.timers[#M.timers + 1] = { at = M.now + delay, fn = fn } end }
function GetTime() return M.now end

SOUNDKIT = { IG_QUEST_LIST_COMPLETE = 878 }
function PlaySound(kit, channel) M.sounds[#M.sounds + 1] = { kit = kit, channel = channel } end
RaidWarningFrame = {}
function RaidNotice_AddMessage(_, text) M.notices[#M.notices + 1] = text end
function GetServerTime() return 1800000000 end
function UnitFactionGroup() return "Horde" end

-- Professions: GetProfessions returns indices into M.professions (5 slots).
function GetProfessions()
	local p = M.professions
	return p[1] and 1, p[2] and 2, p[3] and 3, p[4] and 4, p[5] and 5
end
function GetProfessionInfo(index)
	local p = M.professions[index]
	return "Prof", 0, p.rank, p.maxRank, 0, 0, p.skillLine
end

C_TradeSkillUI = {
	IsTradeSkillReady = function() return M.tradeSkill ~= nil end,
	IsTradeSkillLinked = function() return M.tradeSkill and M.tradeSkill.linked or false end,
	IsTradeSkillGuild = function() return false end,
	IsTradeSkillGuildMember = function() return false end,
	IsNPCCrafting = function() return false end,
	GetBaseProfessionInfo = function()
		local t = M.tradeSkill
		return { professionID = t.profID, skillLevel = t.skillLevel, maxSkillLevel = 300 }
	end,
	GetProfessionInfoBySkillLineID = function(id)
		-- retail-style child tier lines 2937-2948 map to their parent
		local parents = { [2945] = 165, [2948] = 197 }
		return { professionID = id, parentProfessionID = parents[id] or 0 }
	end,
	GetRecipeInfo = function(id)
		local learned = M.tradeSkill.recipes[id]
		if learned == nil then return nil end
		return { recipeID = id, learned = learned, name = "Recipe " .. id }
	end,
	GetFilteredRecipeIDs = function()
		local ids = {}
		for id in pairs(M.tradeSkill.recipes) do ids[#ids + 1] = id end
		return ids
	end,
}
C_TradeSkillUI.GetAllRecipeIDs = C_TradeSkillUI.GetFilteredRecipeIDs

C_Container = {
	GetContainerNumSlots = function(bag) return M.containers[bag] and 16 or 0 end,
	GetContainerItemID = function(bag, slot)
		local item = M.containers[bag] and M.containers[bag][slot]
		return item and item[1]
	end,
	GetContainerItemInfo = function(bag, slot)
		local item = M.containers[bag] and M.containers[bag][slot]
		if not item then return nil end
		return { itemID = item[1], stackCount = item[2] }
	end,
}
C_Bank = {
	FetchPurchasedBankTabIDs = function(bankType)
		if M.noBankAPI then error("no API") end
		return M.bankTabs[bankType] or {}
	end,
	CanViewBank = function(bankType) return bankType ~= 2 or M.accountBankViewable end,
}
Enum.BankType = { Character = 0, Guild = 1, Account = 2 }

return M
