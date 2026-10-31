-- Minimal WoW API stubs for offline tests. Extend as modules need more.

local M = {}

local frames = {}

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

function M.reset()
	frames = {}
	M.printed = {}
	M.errors = {}
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

function GetBuildInfo() return "1.60.0", "99999", "Nov 4 2026", 16000 end
function UnitName() return "Tester" end
function GetNormalizedRealmName() return "StubRealm" end
function InCombatLockdown() return false end

C_AddOns = {
	GetAddOnMetadata = function(_, field)
		if field == "Version" then return "0.1.0" end
	end,
	IsAddOnLoaded = function() return false end,
}

return M
