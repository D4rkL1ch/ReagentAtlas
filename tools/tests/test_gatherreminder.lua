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
	stubs.runTimers(10) -- not unbounded: an owed reminder retries while blocked
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
test("reminder: after resurrecting, not while dead, at most once a minute", function()
	track(HERBS)
	boot()
	stubs.dead = true
	stubs.fire("PLAYER_ALIVE") -- releasing the spirit fires it too
	stubs.runTimers(30)
	eq(#stubs.notices, 0, "ghost")
	stubs.dead = false
	stubs.fire("PLAYER_UNGHOST")
	stubs.fire("PLAYER_ALIVE")
	stubs.runTimers(10)
	eq(#stubs.notices, 1, "resurrected")
	stubs.fire("PLAYER_ALIVE")
	stubs.runTimers(10)
	eq(#stubs.notices, 1, "within a minute")
	stubs.runTimers(60)
	eq(#stubs.notices, 2, "owed reminder comes once the minute is up")
	stubs.runTimers()
	eq(#stubs.notices, 2, "and only once")
end)

test("reminder: plays a sound unless turned off", function()
	track(HERBS)
	boot()
	stubs.sounds = {}
	login()
	eq(#stubs.sounds, 1, "sound")
	eq(stubs.sounds[1].kit, 8959, "raid warning")
	track(HERBS)
	boot({ settings = { gatherSound = false } })
	stubs.sounds = {}
	login()
	eq(#stubs.notices, 1, "still reminds")
	eq(#stubs.sounds, 0, "silent")
end)

test("reminder: resurrected in combat reminds after combat", function()
	track(on(HERBS))
	boot()
	stubs.combat = true
	stubs.dead = true
	track(HERBS) -- dying clears tracking
	stubs.fire("PLAYER_DEAD")
	stubs.fire("MINIMAP_UPDATE_TRACKING")
	stubs.runTimers(20)
	stubs.dead = false
	stubs.fire("PLAYER_ALIVE") -- battle resurrection, still in combat
	stubs.runTimers(20)
	eq(#stubs.notices, 0, "in combat")
	stubs.combat = false
	stubs.runTimers(10) -- no PLAYER_REGEN_ENABLED needed; the retry picks it up
	eq(#stubs.notices, 1, "after combat")
end)

test("reminder: owed through death even if no resurrect event comes", function()
	track(on(MINERALS))
	boot()
	stubs.dead = true
	track(MINERALS)
	stubs.fire("MINIMAP_UPDATE_TRACKING")
	stubs.fire("PLAYER_DEAD")
	stubs.runTimers(60)
	eq(#stubs.notices, 0, "dead")
	stubs.dead = false
	stubs.runTimers(10)
	eq(#stubs.notices, 1, "alive again")
end)

test("reminder: shows in dungeons and raids, not in battlegrounds", function()
	track(HERBS)
	boot()
	stubs.instance = true
	stubs.fire("PLAYER_ENTERING_WORLD", false, false)
	stubs.runTimers(10)
	eq(#stubs.notices, 1, "entering a dungeon")
	stubs.runTimers(120)
	stubs.dead = true
	stubs.fire("PLAYER_DEAD")
	stubs.runTimers(10)
	stubs.dead = false
	stubs.fire("PLAYER_ALIVE")
	stubs.runTimers(10)
	eq(#stubs.notices, 2, "resurrected in a dungeon")
	stubs.runTimers(120)
	stubs.instanceType = "raid"
	stubs.fire("PLAYER_ALIVE")
	stubs.runTimers(10)
	eq(#stubs.notices, 3, "raid")
	stubs.runTimers(120)
	stubs.instanceType = "pvp"
	stubs.fire("PLAYER_ALIVE")
	stubs.runTimers(120)
	eq(#stubs.notices, 3, "battleground")
	stubs.instance, stubs.instanceType = false, nil
	stubs.fire("PLAYER_ENTERING_WORLD", false, false)
	stubs.runTimers(10)
	eq(#stubs.notices, 4, "left the battleground")
end)

test("reminder: waits for a flight to land", function()
	track(HERBS)
	boot()
	stubs.taxi = true
	stubs.fire("PLAYER_ALIVE")
	stubs.runTimers(120)
	eq(#stubs.notices, 0, "flying")
	stubs.taxi = false
	stubs.runTimers(10)
	eq(#stubs.notices, 1, "landed")
end)

test("reminder: tracking list that loads late after login still reminds", function()
	track()
	boot()
	login()
	stubs.runTimers(20)
	eq(#stubs.notices, 0, "nothing loaded")
	track(HERBS)
	stubs.fire("MINIMAP_UPDATE_TRACKING")
	stubs.runTimers(10)
	eq(#stubs.notices, 1, "loaded")
end)

test("reminder: turning tracking on before the check cancels it", function()
	track(HERBS)
	boot()
	stubs.combat = true
	login()
	stubs.runTimers(30)
	track(on(HERBS))
	stubs.combat = false
	stubs.runTimers()
	eq(#stubs.notices, 0, "notices")
end)
