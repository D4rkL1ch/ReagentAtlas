---@diagnostic disable: undefined-global
-- Gathering tracking reminder: Find Herbs / Find Minerals left off.
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

local HERBS = { name = "Find Herbs", spellID = 2383 }
local MINERALS = { name = "Find Minerals", spellID = 2580 }
local TREASURE = { name = "Find Treasure", spellID = 2481 }

local function track(...)
	stubs.tracking = {}
	for i, entry in ipairs({ ... }) do
		stubs.tracking[i] = { name = entry.name, spellID = entry.spellID, active = entry.active }
	end
end

local function on(entry)
	return { name = entry.name, spellID = entry.spellID, active = true }
end

local function boot(savedVars)
	local ns = T.boot(savedVars or {}, T.useFixture)
	stubs.notices, stubs.printed = {}, {}
	return ns
end

local function login()
	stubs.fire("PLAYER_ENTERING_WORLD", true, false)
	stubs.runTimers()
end

test("reminder: herbalist with tracking off is reminded after login", function()
	track(HERBS, TREASURE)
	boot()
	login()
	eq(#stubs.notices, 1, "notices")
	eq(stubs.notices[1], "Find Herbs is off")
	contains(stubs.printed[#stubs.printed], "tracking menu")
end)

test("reminder: no reminder while gathering tracking is on", function()
	track(on(HERBS))
	boot()
	login()
	eq(#stubs.notices, 0, "notices")
end)

test("reminder: herbalist-miner is fine with either one on (one tracking at a time)", function()
	track(HERBS, on(MINERALS))
	boot()
	login()
	eq(#stubs.notices, 0, "notices")
end)

test("reminder: herbalist-miner with both off names both", function()
	track(MINERALS, HERBS)
	local ns = boot()
	eq(ns.GatherReminder:GetReminder(), "Find Herbs / Find Minerals are off")
end)

test("reminder: characters without gathering tracking never get one", function()
	track(on(TREASURE))
	boot()
	login()
	eq(#stubs.notices, 0, "notices")
end)

test("reminder: setting off silences it", function()
	track(HERBS)
	boot({ settings = { gatherReminder = false } })
	login()
	eq(#stubs.notices, 0, "notices")
end)

test("reminder: waits for combat to end", function()
	track(HERBS)
	boot()
	stubs.combat = true
	login()
	eq(#stubs.notices, 0, "in combat")
	stubs.combat = false
	stubs.fire("PLAYER_REGEN_ENABLED")
	stubs.runTimers()
	eq(#stubs.notices, 1, "after combat")
end)

test("reminder: after resurrecting, not while dead, at most once a minute", function()
	track(HERBS)
	boot()
	stubs.dead = true
	stubs.fire("PLAYER_ALIVE") -- releasing the spirit fires it too
	stubs.runTimers()
	eq(#stubs.notices, 0, "ghost")
	stubs.dead = false
	stubs.fire("PLAYER_UNGHOST")
	stubs.fire("PLAYER_ALIVE")
	stubs.runTimers()
	eq(#stubs.notices, 1, "resurrected")
	stubs.fire("PLAYER_ALIVE")
	stubs.runTimers()
	eq(#stubs.notices, 1, "within a minute")
	stubs.runTimers(61)
	stubs.fire("PLAYER_ALIVE")
	stubs.runTimers()
	eq(#stubs.notices, 2, "a minute later")
end)

test("reminder: quiet inside instances and on flights, checks on leaving an instance", function()
	track(HERBS)
	boot()
	stubs.instance = true
	stubs.fire("PLAYER_ENTERING_WORLD", false, false)
	stubs.fire("PLAYER_ALIVE")
	stubs.runTimers()
	eq(#stubs.notices, 0, "in instance")
	stubs.instance = false
	stubs.taxi = true
	stubs.fire("PLAYER_ENTERING_WORLD", false, false)
	stubs.runTimers()
	eq(#stubs.notices, 0, "on taxi")
	stubs.taxi = false
	stubs.instance = true
	stubs.fire("PLAYER_ENTERING_WORLD", false, false)
	stubs.instance = false
	stubs.fire("PLAYER_ENTERING_WORLD", false, false)
	stubs.runTimers()
	eq(#stubs.notices, 1, "left instance")
end)

test("reminder: /ratlas tracking lists the tracking types", function()
	track(on(TREASURE), HERBS)
	boot()
	stubs.slash("/ratlas", "tracking")
	local text = table.concat(stubs.printed, "\n")
	contains(text, "Find Treasure (spell 2481) - on")
	contains(text, "Find Herbs (spell 2383) - gathering")
	contains(text, "Find Herbs is off")
end)

test("reminder: turning gathering tracking off reminds a few seconds later", function()
	track(on(MINERALS))
	boot()
	track(MINERALS)
	stubs.fire("MINIMAP_UPDATE_TRACKING")
	stubs.runTimers(1)
	eq(#stubs.notices, 0, "not instantly")
	stubs.runTimers()
	eq(#stubs.notices, 1, "after the delay")
	eq(stubs.notices[1], "Find Minerals is off")
end)

test("reminder: switching herbs to minerals doesn't remind", function()
	track(on(HERBS), MINERALS)
	boot()
	track(HERBS, MINERALS) -- passes through "off"
	stubs.fire("MINIMAP_UPDATE_TRACKING")
	track(HERBS, on(MINERALS))
	stubs.fire("MINIMAP_UPDATE_TRACKING")
	stubs.runTimers()
	eq(#stubs.notices, 0, "notices")
end)

test("reminder: other tracking changes don't remind", function()
	track(MINERALS, TREASURE)
	boot()
	track(MINERALS, on(TREASURE))
	stubs.fire("MINIMAP_UPDATE_TRACKING")
	stubs.runTimers()
	eq(#stubs.notices, 0, "was already off before, not a switch-off")
end)

test("reminder: ordinary loading screens don't check", function()
	track(HERBS)
	boot()
	stubs.fire("PLAYER_ENTERING_WORLD", false, false)
	stubs.runTimers()
	eq(#stubs.notices, 0, "notices")
end)
