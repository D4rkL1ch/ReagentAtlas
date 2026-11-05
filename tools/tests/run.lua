---@diagnostic disable: undefined-global
-- Offline tests with stubbed WoW APIs. Not shipped.
-- Run: tools\tests\run.ps1   (uses the LuaLS binary as the Lua interpreter)
--
-- The interpreter is newer than WoW's Lua 5.1, so this catches logic errors,
-- not 5.1 syntax issues; LuaLS diagnostics (runtime 5.1) cover those.

local repoRoot = assert(arg and arg[1], "usage: run.lua <repoRoot>")
local testDir = repoRoot .. "/tools/tests/"
local stubs = dofile(testDir .. "wowstubs.lua")

local T = { stubs = stubs }
local failures, passed = 0, 0

function T.test(name, fn)
	stubs.reset()
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failures = failures + 1
		io.write("FAIL ", name, "\n  ", tostring(err), "\n")
	end
end

function T.eq(actual, expected, msg)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(msg or "value", tostring(expected), tostring(actual)), 2)
	end
end

function T.near(actual, expected, msg)
	if math.abs(actual - expected) > 1e-6 then
		error(("%s: expected %s, got %s"):format(msg or "value", tostring(expected), tostring(actual)), 2)
	end
end

function T.contains(haystack, needle, msg)
	if not haystack:find(needle, 1, true) then
		error(("%s: '%s' not found in:\n%s"):format(msg or "text", needle, haystack), 2)
	end
end

-- Load every file listed in the TOC, in order, sharing one namespace table.
function T.loadAddon()
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

-- Load the addon and run it through ADDON_LOADED and PLAYER_LOGIN. `setup`
-- runs between loading files and the events, e.g. to swap in fixture data.
function T.boot(savedVars, setup)
	_G.ReagentAtlasDB = savedVars
	local ns = T.loadAddon()
	if setup then setup(ns) end
	stubs.fire("ADDON_LOADED", "SomeOtherAddon")
	stubs.fire("ADDON_LOADED", "ReagentAtlas")
	stubs.fire("PLAYER_LOGIN")
	return ns
end

-- Fixture data independent of whatever Data/*.lua currently holds.
function T.useFixture(ns)
	local fx = dofile(testDir .. "fixture.lua")
	ns.Recipes, ns.Reagents, ns.ProfessionNames = fx.Recipes, fx.Reagents, fx.ProfessionNames
	ns.MAX_SKILL = fx.MAX_SKILL
	ns.DATA_BUILD = "99999"
	-- No sources by default, so layout tests stay independent of them.
	ns.RecipeSources, ns.SourceNPCs = nil, nil
end

for _, file in ipairs({ "test_core.lua", "test_valuation.lua", "test_tooltip.lua", "test_characters.lua", "test_pricing.lua", "test_ui.lua", "test_sources.lua", "test_tracker.lua", "test_data.lua" }) do
	assert(loadfile(testDir .. file))(T)
end

io.write(("%d passed, %d failed\n"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
