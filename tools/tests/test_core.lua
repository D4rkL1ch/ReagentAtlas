---@diagnostic disable: undefined-global
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

test("fresh install creates DB with defaults", function()
	local ns = T.boot(nil)
	local db = _G.ReagentAtlasDB
	eq(type(db), "table", "ReagentAtlasDB")
	eq(db, ns.db, "ns.db")
	eq(db.version, 1, "version")
	eq(db.settings.tooltip, true, "settings.tooltip")
	eq(db.settings.markerMinTier, 3, "settings.markerMinTier")
	eq(type(db.chars), "table", "chars")
	eq(type(db.ui), "table", "ui")
end)

test("existing settings are kept", function()
	T.boot({ version = 1, settings = { tooltip = false } })
	eq(_G.ReagentAtlasDB.settings.tooltip, false, "tooltip")
	eq(_G.ReagentAtlasDB.settings.markers, true, "markers default filled")
end)

test("unversioned DB is migrated to current version", function()
	T.boot({ chars = { ["A-B"] = {} } })
	eq(_G.ReagentAtlasDB.version, 1, "version")
	eq(type(_G.ReagentAtlasDB.chars["A-B"]), "table", "chars kept")
end)

test("newer DB version is left alone", function()
	T.boot({ version = 99 })
	eq(_G.ReagentAtlasDB.version, 99, "version")
end)

test("modules get OnInit then OnLogin, errors are isolated", function()
	_G.ReagentAtlasDB = nil
	local ns = T.loadAddon()
	local calls = {}
	ns:RegisterModule("Broken", { OnInit = function() error("boom") end })
	ns:RegisterModule("Good", {
		OnInit = function(self) calls[#calls + 1] = "init:" .. self.name .. ":" .. tostring(ns.db ~= nil) end,
		OnLogin = function() calls[#calls + 1] = "login" end,
	})
	stubs.fire("ADDON_LOADED", "ReagentAtlas")
	stubs.fire("ADDON_LOADED", "ReagentAtlas") -- second fire must not re-init
	stubs.fire("PLAYER_LOGIN")
	eq(#calls, 2, "call count")
	eq(calls[1], "init:Good:true", "first call")
	eq(calls[2], "login", "second call")
	eq(#stubs.errors, 1, "errors reported")
	eq(ns.Good ~= nil, true, "ns.Good")
end)

test("duplicate module name is rejected", function()
	local ns = T.loadAddon()
	ns:RegisterModule("X", {})
	eq(pcall(ns.RegisterModule, ns, "X", {}), false, "second register")
end)

test("unregistering during dispatch does not skip other handlers", function()
	local ns = T.loadAddon()
	local hits = 0
	local function first(event) ns:UnregisterEvent(event, first) end
	ns:RegisterEvent("TEST_EVENT", first)
	ns:RegisterEvent("TEST_EVENT", function() hits = hits + 1 end)
	stubs.fire("TEST_EVENT")
	stubs.fire("TEST_EVENT")
	eq(hits, 2, "second handler hits")
end)

test("char key is Name-Realm", function()
	local ns = T.boot(nil)
	eq(ns:GetCharKey(), "Tester-StubRealm", "key")
end)

test("/ratlas prints version, interface and Auctionator status", function()
	T.boot(nil)
	stubs.printed = {}
	stubs.slash("/ratlas", "")
	local out = table.concat(stubs.printed, "\n")
	contains(out, "v0.1.0", "version")
	contains(out, "interface 16000", "interface")
	contains(out, "recipe data: build", "data build")
	contains(out, "Auctionator API v1: not loaded", "auctionator status")

	stubs.printed = {}
	_G.Auctionator = { API = { v1 = {} } }
	stubs.slash("/ratlas", "version")
	contains(table.concat(stubs.printed, "\n"), "Auctionator API v1: found", "found")
end)

test("unknown command gives a hint", function()
	T.boot(nil)
	stubs.slash("/ratlas", "nope")
	contains(table.concat(stubs.printed, "\n"), "unknown command 'nope'", "hint")
end)

test("data build matching the client prints nothing", function()
	T.boot(nil, function(ns) ns.DATA_BUILD = "99999" end)
	eq(#stubs.printed, 0, "printed lines")
end)

test("data build mismatch warns once per client build", function()
	T.boot(nil, function(ns) ns.DATA_BUILD = "11111" end)
	contains(table.concat(stubs.printed, "\n"), "recipe data is from build 11111, client is 99999", "warning")
	eq(_G.ReagentAtlasDB.warnedBuild, "99999", "remembered")

	local saved = _G.ReagentAtlasDB
	stubs.reset()
	T.boot(saved, function(ns) ns.DATA_BUILD = "11111" end)
	eq(#stubs.printed, 0, "no second warning")
end)

test("sample data announces itself", function()
	T.boot(nil, function(ns) ns.DATA_BUILD = "sample" end)
	contains(table.concat(stubs.printed, "\n"), "sample recipe data", "notice")
end)
