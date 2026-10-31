---@diagnostic disable: undefined-global, lowercase-global, undefined-field
-- Minimal WoW API stubs for offline tests. Extend as modules need more.

local M = {}

local frames = {}
local tooltipPostCalls = {}

local function newFrame()
	local f = { events = {}, scripts = {} }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:UnregisterEvent(e) self.events[e] = nil end
	function f:SetScript(name, fn) self.scripts[name] = fn end
	frames[#frames + 1] = f
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
		for _, fn in ipairs(tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do
			fn(self, { id = itemID })
		end
	end
	function tt:RefreshData() self:SetItem(self.itemID) end
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
	-- Character state, changed by tests.
	M.professions = {}       -- array of { skillLine, rank, maxRank } in GetProfessions order
	M.tradeSkill = nil       -- open window: { profID, skillLevel, recipes = { [id] = learned }, linked, filteredOnly }
	M.containers = {}        -- [bagID] = array of { itemID, count } (nil = empty slot)
	M.bankTabs = { [0] = { 6, 7 }, [2] = { 15 } }
	M.accountBankViewable = true
	M.noBankAPI = false
	SlashCmdList = {}
	Auctionator = nil
	ReagentAtlasDB = nil
end

-- Run pending C_Timer callbacks (including ones they schedule).
function M.runTimers()
	while #M.timers > 0 do
		local fn = table.remove(M.timers, 1)
		fn()
	end
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

function CreateFrame() return newFrame() end
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
function GetNormalizedRealmName() return "StubRealm" end
function InCombatLockdown() return false end
function IsShiftKeyDown() return M.shift end
function UnitClass() return M.classToken, M.classToken end

C_AddOns = {
	GetAddOnMetadata = function(_, field)
		if field == "Version" then return "0.1.0" end
	end,
	IsAddOnLoaded = function() return false end,
}

M.spellNames = { [2963] = "Bolt of Linen Cloth", [990001] = "Feathered Jerkin" }
C_Spell = { GetSpellName = function(id) return M.spellNames[id] end }
C_Item = { GetItemNameByID = function(id) if id == 990102 then return "Feathered Boots" end end }

LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", PRIEST = "Priest" }
C_ClassColor = {
	GetClassColor = function(token)
		if token == "MAGE" then
			return { WrapTextInColorCode = function(_, text) return "|cff3fc7eb" .. text .. "|r" end }
		end
	end,
}

Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = {
	AddTooltipPostCall = function(kind, fn)
		tooltipPostCalls[kind] = tooltipPostCalls[kind] or {}
		table.insert(tooltipPostCalls[kind], fn)
	end,
}


C_Timer = { After = function(_, fn) M.timers[#M.timers + 1] = fn end }
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
