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
			out[i] = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
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
	SlashCmdList = {}
	Auctionator = nil
	ReagentAtlasDB = nil
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

return M
