local addonName, ns = ...

-- Namespace basics ----------------------------------------------------------

ns.name = addonName
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "dev"
ns.DB_VERSION = 1

local CHAT_PREFIX = "|cff33ff99Reagent Atlas|r: "

function ns:Print(...)
	print(CHAT_PREFIX .. strjoin(" ", tostringall(...)))
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
	markerMinTier = 3,
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
	-- [1] = function(db) ... end,
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
	ns.db = db
end

-- Current character ---------------------------------------------------------

-- "Name-Realm" key used in ReagentAtlasDB.chars. Realm may be nil very early
-- in the loading process, so only call this from PLAYER_LOGIN onwards.
function ns:GetCharKey()
	local name = UnitName("player")
	local realm = GetNormalizedRealmName()
	if not name or not realm then return nil end
	return name .. "-" .. realm
end

-- Diagnostics ---------------------------------------------------------------

local function HasAuctionatorAPI()
	return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil
end

local function PrintStatus()
	local gameVersion, build, _, tocVersion = GetBuildInfo()
	ns:Print(("v%s"):format(ns.version))
	ns:Print(("client %s (build %s), interface %s"):format(
		tostring(gameVersion), tostring(build), tostring(tocVersion)))
	ns:Print(("recipe data: build %s"):format(tostring(ns.DATA_BUILD)))

	local auctionatorLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Auctionator")
	if HasAuctionatorAPI() then
		ns:Print("Auctionator API v1: found")
	elseif auctionatorLoaded then
		ns:Print("Auctionator API v1: |cffff5555missing|r (Auctionator is loaded)")
	else
		ns:Print("Auctionator API v1: not loaded")
	end
end

-- Slash command -------------------------------------------------------------

local commands = {}

commands[""] = PrintStatus
commands.version = PrintStatus

commands.help = function()
	ns:Print("commands:")
	print("  /ratlas - version and client info")
	print("  /ratlas help - this list")
end

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
