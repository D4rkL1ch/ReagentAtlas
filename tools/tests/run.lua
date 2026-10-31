-- Offline smoke tests with stubbed WoW APIs. Not shipped.
-- Run: tools\tests\run.ps1   (uses the LuaLS binary as the Lua interpreter)
--
-- The interpreter is newer than WoW's Lua 5.1, so this catches logic errors,
-- not 5.1 syntax issues; LuaLS diagnostics (runtime 5.1) cover those.

local repoRoot = assert(arg and arg[1], "usage: run.lua <repoRoot>")
local stubs = dofile(repoRoot .. "/tools/tests/wowstubs.lua")

local failures, passed = 0, 0
local function test(name, fn)
	stubs.reset()
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failures = failures + 1
		io.write("FAIL ", name, "\n  ", tostring(err), "\n")
	end
end

local function eq(actual, expected, msg)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(msg or "value", tostring(expected), tostring(actual)), 2)
	end
end

-- Load every file listed in the TOC, in order, sharing one namespace table.
local function loadAddon()
	local ns = {}
	for line in io.lines(repoRoot .. "/ReagentAtlas.toc") do
		local file = line:match("^%s*([^#%s][^\r\n]-)%s*$")
		if file then
			local chunk = assert(loadfile(repoRoot .. "/" .. file:gsub("\\", "/")))
			chunk("ReagentAtlas", ns)
		end
	end
	return ns
end

local function boot(savedVars)
	_G.ReagentAtlasDB = savedVars
	local ns = loadAddon()
	stubs.fire("ADDON_LOADED", "SomeOtherAddon")
	stubs.fire("ADDON_LOADED", "ReagentAtlas")
	stubs.fire("PLAYER_LOGIN")
	return ns
end

test("fresh install creates DB with defaults", function()
	local ns = boot(nil)
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
	boot({ version = 1, settings = { tooltip = false } })
	eq(_G.ReagentAtlasDB.settings.tooltip, false, "tooltip")
	eq(_G.ReagentAtlasDB.settings.markers, true, "markers default filled")
end)

test("unversioned DB is migrated to current version", function()
	boot({ chars = { ["A-B"] = {} } })
	eq(_G.ReagentAtlasDB.version, 1, "version")
	eq(type(_G.ReagentAtlasDB.chars["A-B"]), "table", "chars kept")
end)

test("newer DB version is left alone", function()
	boot({ version = 99 })
	eq(_G.ReagentAtlasDB.version, 99, "version")
end)

test("modules get OnInit then OnLogin, errors are isolated", function()
	_G.ReagentAtlasDB = nil
	local ns = loadAddon()
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
	local ns = loadAddon()
	ns:RegisterModule("X", {})
	eq(pcall(ns.RegisterModule, ns, "X", {}), false, "second register")
end)

test("unregistering during dispatch does not skip other handlers", function()
	local ns = loadAddon()
	local hits = 0
	local function first(event) ns:UnregisterEvent(event, first) end
	ns:RegisterEvent("TEST_EVENT", first)
	ns:RegisterEvent("TEST_EVENT", function() hits = hits + 1 end)
	stubs.fire("TEST_EVENT")
	stubs.fire("TEST_EVENT")
	eq(hits, 2, "second handler hits")
end)

test("char key is Name-Realm", function()
	local ns = boot(nil)
	eq(ns:GetCharKey(), "Tester-StubRealm", "key")
end)

test("/ratlas prints version, interface and Auctionator status", function()
	boot(nil)
	stubs.slash("/ratlas", "")
	local out = table.concat(stubs.printed, "\n")
	eq(out:find("v0.1.0", 1, true) ~= nil, true, "version in output:\n" .. out)
	eq(out:find("interface 16000", 1, true) ~= nil, true, "interface in output")
	eq(out:find("Auctionator API v1: not loaded", 1, true) ~= nil, true, "auctionator status")

	stubs.printed = {}
	_G.Auctionator = { API = { v1 = {} } }
	stubs.slash("/ratlas", "version")
	eq(table.concat(stubs.printed, "\n"):find("Auctionator API v1: found", 1, true) ~= nil, true, "found")
end)

test("unknown command gives a hint", function()
	boot(nil)
	stubs.slash("/ratlas", "nope")
	eq(table.concat(stubs.printed, "\n"):find("unknown command 'nope'", 1, true) ~= nil, true, "hint")
end)

io.write(("%d passed, %d failed\n"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
