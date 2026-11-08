local addonName, ns = ...

-- Namespace basics ----------------------------------------------------------

ns.name = addonName
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "dev"
ns.DB_VERSION = 2

local CHAT_PREFIX = "|cff33ff99Reagent Atlas|r: "

function ns:Print(...)
	print(CHAT_PREFIX .. strjoin(" ", tostringall(...)))
end

-- Raid-warning style message (the errors frame if there is none) and an
-- optional sound kit. Master channel: it still plays with sound effects off.
-- A kit the client doesn't know must not break the caller.
function ns:ShowAlert(text, color, sound)
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, color)
	elseif UIErrorsFrame then
		UIErrorsFrame:AddMessage(text, color.r, color.g, color.b)
	end
	self:PlayAlertSound(sound)
end

function ns:PlayAlertSound(sound)
	if sound and PlaySound then
		pcall(PlaySound, sound, "Master")
	end
end

-- Event dispatcher ----------------------------------------------------------
-- Several handlers may listen to the same event; each receives (event, ...).

local eventFrame = CreateFrame("Frame")
local handlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		list[i](event, ...)
	end
end)

function ns:RegisterEvent(event, handler)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		eventFrame:RegisterEvent(event)
	end
	list[#list + 1] = handler
end

function ns:UnregisterEvent(event, handler)
	local old = handlers[event]
	if not old then return end
	-- Build a new list so a dispatch loop in progress keeps iterating the old one.
	local list = {}
	for i = 1, #old do
		if old[i] ~= handler then
			list[#list + 1] = old[i]
		end
	end
	handlers[event] = list
	if #list == 0 then
		handlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

-- Addon-internal messages (e.g. "CHAR_DATA_CHANGED"). Kept apart from game
-- events because RegisterEvent errors on names the client doesn't know.
local messageHandlers = {}

function ns:RegisterMessage(message, handler)
	local list = messageHandlers[message]
	if not list then
		list = {}
		messageHandlers[message] = list
	end
	list[#list + 1] = handler
end

function ns:Fire(message, ...)
	local list = messageHandlers[message]
	if not list then return end
	for i = 1, #list do
		list[i](message, ...)
	end
end

-- CHAR_DATA_CHANGED carries this when only item counts changed, so listeners
-- that depend on recipes can skip the work. Without it, anything may have.
ns.INVENTORY_ONLY = "inventory"

-- True if two flat tables hold the same keys and values. Scans use it to stay
-- quiet when nothing changed: most events that trigger one change nothing.
function ns.SameTable(a, b)
	for k, v in pairs(a) do
		if b[k] ~= v then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

-- Module registry -----------------------------------------------------------
-- Modules call ns:RegisterModule("Name", mod) at file load. OnInit runs after
-- ADDON_LOADED (SavedVariables ready), OnLogin after PLAYER_LOGIN.

local modules = {}

function ns:RegisterModule(name, mod)
	assert(type(name) == "string" and type(mod) == "table", "RegisterModule(name, table)")
	assert(not ns[name], "module name already in use: " .. name)
	mod.name = name
	ns[name] = mod
	modules[#modules + 1] = mod
	return mod
end

local function CallModules(method)
	for i = 1, #modules do
		local mod = modules[i]
		if mod[method] then
			local ok, err = pcall(mod[method], mod)
			if not ok then
				geterrorhandler()(("%s %s.%s: %s"):format(addonName, mod.name, method, tostring(err)))
			end
		end
	end
end

-- SavedVariables ------------------------------------------------------------

local DEFAULT_SETTINGS = {
	tooltip = true,
	markers = true,
	useAuctionator = true,
	markerMinTier = 4, -- Valuable
	minimapIcon = true,
	trackerSound = true,
	lootAlerts = true,
	lootSound = true,
	lootMinTier = 5, -- Keep!
}

-- Fill missing keys from defaults without overwriting user values.
local function ApplyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			target[k] = v
		end
	end
end

-- Migrations keyed by the version they upgrade *from*. Each step must leave
-- the DB valid for version + 1.
local migrations = {
	-- Four value tiers became five: Common went in below Useful, so the old
	-- Valuable (3) and Keep! (4) moved up one. Vendor and Useful/Common (2) stay.
	[1] = function(db)
		local function Shift(tbl, key)
			if tbl and type(tbl[key]) == "number" and tbl[key] >= 3 then
				tbl[key] = tbl[key] + 1
			end
		end
		Shift(db.settings, "markerMinTier")
		Shift(db.ui and db.ui.filters, "minTier")
	end,
}

local function MigrateDB(db)
	local from = db.version or 0
	if from > ns.DB_VERSION then
		ns:Print(("saved data is from a newer version (%d > %d); it will be left as is."):format(from, ns.DB_VERSION))
		return
	end
	while from < ns.DB_VERSION do
		local step = migrations[from]
		if step then
			step(db)
		end
		from = from + 1
	end
	db.version = ns.DB_VERSION
end

local function InitDB()
	if type(ReagentAtlasDB) ~= "table" then
		ReagentAtlasDB = { version = ns.DB_VERSION }
	end
	local db = ReagentAtlasDB
	MigrateDB(db)
	db.settings = db.settings or {}
	ApplyDefaults(db.settings, DEFAULT_SETTINGS)
	db.ui = db.ui or {}
	db.chars = db.chars or {}
	db.account = db.account or {}   -- account-wide data, e.g. the warband bank
	db.tracked = db.tracked or {}   -- tracking list, see Modules/Tracker.lua
	db.seenVendors = db.seenVendors or {} -- recipe vendors seen, see Modules/Sources.lua
	ns.db = db
end

-- Characters ----------------------------------------------------------------

-- "Name-Realm" key used in ReagentAtlasDB.chars. Realm may be nil very early
-- in the loading process, so only call this from PLAYER_LOGIN onwards. Cached
-- once known: lookups ask for it for every recipe in a list.
local charKey

function ns:GetCharKey()
	if charKey then return charKey end
	local name = UnitName("player")
	local realm = GetNormalizedRealmName()
	if not name or not realm then return nil end
	charKey = name .. "-" .. realm
	return charKey
end

-- The current character's record in ReagentAtlasDB.chars, created on first
-- use. Returns nil before the character key is known.
function ns:GetCharData()
	local key = self:GetCharKey()
	if not key then return nil end
	local char = self.db.chars[key]
	if not char then
		char = { profs = {}, bags = {}, bank = {} }
		self.db.chars[key] = char
	end
	local _, class = UnitClass("player")
	char.class = class
	char.faction = UnitFactionGroup("player")
	char.lastSeen = GetServerTime()
	return char, key
end

-- Character name for display: "Name" on the current realm, else "Name-Realm".
function ns:CharDisplayName(key)
	local name, realm = key:match("^(.-)%-(.+)$")
	if not name then return key end
	if realm == GetNormalizedRealmName() then
		return name
	end
	return key
end

-- Diagnostics ---------------------------------------------------------------

-- Status lines for /ratlas version and the settings panel.
function ns:GetStatusLines()
	local gameVersion, build, _, tocVersion = GetBuildInfo()
	local lines = {
		("v%s"):format(self.version),
		("client %s (build %s), interface %s"):format(tostring(gameVersion), tostring(build), tostring(tocVersion)),
		("recipe data: build %s"):format(tostring(self.DATA_BUILD)),
	}
	if self.Pricing then
		lines[#lines + 1] = "prices: " .. self.Pricing:StatusText()
	end
	return lines
end

local function PrintStatus()
	for _, line in ipairs(ns:GetStatusLines()) do
		ns:Print(line)
	end
end

-- Slash command -------------------------------------------------------------

local commands = {}
local commandHelp = {}

-- Modules add subcommands here; fn receives the rest of the line.
function ns:RegisterCommand(name, usage, fn)
	commands[name] = fn
	commandHelp[#commandHelp + 1] = usage
end

commands[""] = function()
	if ns.Browser then ns.Browser:Toggle() else PrintStatus() end
end
commands.version = PrintStatus

commands.help = function()
	ns:Print("commands:")
	print("  /ratlas - open or close the reagent browser (also on the minimap)")
	print("  /ratlas version - version, client and price source")
	for _, usage in ipairs(commandHelp) do
		print("  /ratlas " .. usage)
	end
	print("  /ratlas help - this list")
end

-- Removes a character's saved data. Shared by /ratlas forget and the settings
-- panel. Returns true, or false and why not ("current" or "unknown").
function ns:ForgetCharacter(key)
	if key == self:GetCharKey() then return false, "current" end
	if not self.db.chars[key] then return false, "unknown" end
	self.db.chars[key] = nil
	self:Fire("CHAR_DATA_CHANGED")
	return true
end

ns:RegisterCommand("forget", "forget Name-Realm - remove a deleted character's data", function(arg)
	local key = strtrim(arg or "")
	if key == "" then
		ns:Print("usage: /ratlas forget Name-Realm")
		return
	end
	local ok, reason = ns:ForgetCharacter(key)
	if ok then
		ns:Print(("forgot %s."):format(key))
	elseif reason == "current" then
		ns:Print("can't forget the character you're logged in on.")
	else
		ns:Print(("no data for '%s'. Keys are case-sensitive, e.g. Thrall-Stormrage."):format(key))
	end
end)

SLASH_REAGENTATLAS1 = "/ratlas"
SlashCmdList.REAGENTATLAS = function(msg)
	local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	local fn = commands[cmd:lower()]
	if fn then
		fn(rest)
	else
		ns:Print(("unknown command '%s'. Type /ratlas help."):format(cmd))
	end
end

-- Lifecycle -----------------------------------------------------------------

local function OnAddonLoaded(event, loadedName)
	if loadedName ~= addonName then return end
	ns:UnregisterEvent(event, OnAddonLoaded)
	InitDB()
	CallModules("OnInit")
end

-- Warn once per client build when the recipe data was generated for another
-- build (SPEC.md > Data sourcing, step 5). Sample data warns every session.
local function CheckDataBuild()
	local dataBuild = ns.DATA_BUILD
	local _, clientBuild = GetBuildInfo()
	if dataBuild == "sample" then
		ns:Print("using sample recipe data (development build).")
	elseif dataBuild and tostring(dataBuild) ~= tostring(clientBuild) and ns.db.warnedBuild ~= clientBuild then
		ns:Print(("recipe data is from build %s, client is %s. Recipes may be out of date."):format(
			tostring(dataBuild), tostring(clientBuild)))
		ns.db.warnedBuild = clientBuild
	end
end

local function OnPlayerLogin(event)
	ns:UnregisterEvent(event, OnPlayerLogin)
	CheckDataBuild()
	CallModules("OnLogin")
end

ns:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
ns:RegisterEvent("PLAYER_LOGIN", OnPlayerLogin)
