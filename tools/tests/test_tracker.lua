---@diagnostic disable: undefined-global
-- Tracking list: goals, alerts, rows and the window.
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

local FEATHER, ARCANITE, NEXUS, DYE = 17056, 12360, 20725, 2604
local RECIPE = 880001 -- 10 Arcanite Bar, 1 Nexus Crystal, 2 Red Dye

local function boot(savedVars)
	stubs.itemNames[FEATHER] = "Light Feather"
	stubs.itemNames[ARCANITE] = "Arcanite Bar"
	stubs.itemNames[NEXUS] = "Nexus Crystal"
	stubs.itemNames[DYE] = "Red Dye"
	stubs.spellNames[RECIPE] = "Arcanite Reaper"
	return T.boot(savedVars or { version = 1 }, T.useFixture)
end

-- Boots, passes the login delay and settles the counts.
local function settledBoot(savedVars)
	local ns = boot(savedVars)
	stubs.runTimers()
	stubs.notices, stubs.sounds, stubs.printed = {}, {}, {}
	return ns
end

local function setBags(items)
	local slots = {}
	for itemID, count in pairs(items) do slots[#slots + 1] = { itemID, count } end
	stubs.containers[0] = slots
	stubs.fire("BAG_UPDATE_DELAYED")
end

local function settle() stubs.runTimers() end

local function dump(rows)
	local out = {}
	for i, row in ipairs(rows) do
		if row.type == "reagent" then
			out[i] = ("%s %d/%d"):format(row.name, row.have, row.need)
		else
			out[i] = row.text or row.name
		end
	end
	return table.concat(out, "\n")
end

-- Model ---------------------------------------------------------------------

test("a reagent can be tracked without a goal and never alerts", function()
	local ns = settledBoot()
	local entry = ns.Tracker:Add("item", FEATHER)
	eq(entry.need, nil, "no goal")
	setBags({ [FEATHER] = 500 })
	settle()
	eq(ns.Tracker:GetStatus(entry).have, 500, "count shown")
	eq(ns.Tracker:GetStatus(entry).met, false, "nothing to meet")
	eq(#stubs.notices, 0, "no alert")
end)

test("adding is idempotent, unknown IDs are refused, untracking removes", function()
	local ns = settledBoot()
	local entry = ns.Tracker:Add("recipe", RECIPE)
	eq(ns.Tracker:Add("recipe", RECIPE), entry, "same entry")
	eq(#ns.Tracker:GetEntries(), 1, "one entry")
	eq(ns.Tracker:Add("recipe", 12345), nil, "unknown recipe")
	eq(ns.Tracker:Add("item", 12345), nil, "unknown reagent")
	eq(ns.Tracker:Toggle("recipe", RECIPE), false, "toggled off")
	eq(#ns.Tracker:GetEntries(), 0, "removed")
	eq(ns.Tracker:Toggle("recipe", RECIPE), true, "toggled on")
end)

test("a recipe counts required and owned per reagent, scaled by crafts", function()
	local ns = settledBoot()
	setBags({ [ARCANITE] = 12, [DYE] = 1 })
	settle()
	local entry = ns.Tracker:Add("recipe", RECIPE)
	local status = ns.Tracker:GetStatus(entry)
	eq(#status.reagents, 3, "all reagents")
	local a = status.reagents[1]
	eq(a.itemID, DYE, "sorted")
	eq(a.have .. "/" .. a.need, "1/2", "dye")
	ns.Tracker:SetNeed(entry, 2)
	eq(ns.Tracker:GetStatus(entry).reagents[1].need, 4, "two crafts")
end)

test("counts cover the whole account", function()
	local ns = settledBoot({
		version = 1,
		chars = { ["Brewdin-StubRealm"] = { profs = {}, bags = { [FEATHER] = 3 }, bank = { [FEATHER] = 4 } } },
		account = { bank = { [FEATHER] = 5 } },
	})
	setBags({ [FEATHER] = 1 })
	settle()
	eq(ns.Tracker:GetStatus(ns.Tracker:Add("item", FEATHER)).have, 13, "alt + warband + mine")
end)

test("SetNeed: empty clears a reagent goal, puts a recipe back to one craft", function()
	local ns = settledBoot()
	local item, recipe = ns.Tracker:Add("item", FEATHER), ns.Tracker:Add("recipe", RECIPE)
	ns.Tracker:SetNeed(item, 20)
	eq(item.need, 20, "set")
	ns.Tracker:SetNeed(item, nil)
	eq(item.need, nil, "cleared")
	ns.Tracker:SetNeed(item, 0)
	eq(item.need, nil, "zero clears")
	ns.Tracker:SetNeed(recipe, 3)
	ns.Tracker:SetNeed(recipe, nil)
	eq(recipe.need, 1, "one craft")
end)

-- Alerts --------------------------------------------------------------------

test("reaching a goal alerts once, with text, chat line and sound", function()
	local ns = settledBoot()
	ns.Tracker:SetNeed(ns.Tracker:Add("item", FEATHER), 20)
	setBags({ [FEATHER] = 19 })
	settle()
	eq(#stubs.notices, 0, "not yet")
	setBags({ [FEATHER] = 20 })
	settle()
	eq(stubs.notices[1], "You have enough Light Feather (20)", "on screen")
	contains(table.concat(stubs.printed, "\n"), "You have enough Light Feather (20)", "chat")
	eq(#stubs.sounds, 1, "sound")
	eq(stubs.sounds[1].kit, 878, "quest complete sound")
	eq(stubs.sounds[1].channel, "Master", "heard with effects off")
	setBags({ [FEATHER] = 25 })
	settle()
	eq(#stubs.sounds, 1, "no repeat while met")
end)

test("a recipe alerts when its last reagent arrives", function()
	local ns = settledBoot()
	ns.Tracker:Add("recipe", RECIPE)
	setBags({ [ARCANITE] = 10, [NEXUS] = 1 })
	settle()
	eq(#stubs.notices, 0, "dye missing")
	setBags({ [ARCANITE] = 10, [NEXUS] = 1, [DYE] = 2 })
	settle()
	eq(stubs.notices[1], "You have the reagents for Arcanite Reaper", "alert")
end)

test("the alert names the number of crafts", function()
	local ns = settledBoot()
	ns.Tracker:SetNeed(ns.Tracker:Add("recipe", RECIPE), 2)
	setBags({ [ARCANITE] = 20, [NEXUS] = 2, [DYE] = 4 })
	settle()
	eq(stubs.notices[1], "You have the reagents for Arcanite Reaper x2", "alert")
end)

test("spending below the goal re-arms it", function()
	local ns = settledBoot()
	ns.Tracker:SetNeed(ns.Tracker:Add("item", FEATHER), 20)
	setBags({ [FEATHER] = 20 })
	settle()
	setBags({ [FEATHER] = 5 })
	settle()
	eq(#stubs.sounds, 1, "no alert on the way down")
	setBags({ [FEATHER] = 20 })
	settle()
	eq(#stubs.sounds, 2, "alerts again")
end)

test("a goal you already meet is silent, setting it yourself is not news", function()
	local ns = settledBoot()
	setBags({ [FEATHER] = 30 })
	settle()
	ns.Tracker:SetNeed(ns.Tracker:Add("item", FEATHER), 20)
	settle()
	setBags({ [FEATHER] = 31 })
	settle()
	eq(#stubs.sounds, 0, "silent")
end)

test("raising a met goal arms it again", function()
	local ns = settledBoot()
	setBags({ [FEATHER] = 30 })
	settle()
	local entry = ns.Tracker:Add("item", FEATHER)
	ns.Tracker:SetNeed(entry, 20)
	ns.Tracker:SetNeed(entry, 40)
	setBags({ [FEATHER] = 40 })
	settle()
	eq(#stubs.sounds, 1, "alerts at the new goal")
end)

test("a met goal doesn't alert again after a relog", function()
	local saved = {
		version = 1,
		chars = { ["Tester-StubRealm"] = { profs = {}, bags = {}, bank = { [FEATHER] = 20 } } },
		tracked = { { kind = "item", id = FEATHER, need = 20, done = true } },
	}
	settledBoot(saved)
	eq(#stubs.sounds, 0, "nothing new")
end)

test("bags that read empty at login don't re-arm a met goal", function()
	local saved = {
		version = 1,
		chars = { ["Tester-StubRealm"] = { profs = {}, bags = { [FEATHER] = 20 }, bank = {} } },
		tracked = { { kind = "item", id = FEATHER, need = 20, done = true } },
	}
	-- The login scan finds nothing, and stays that way past the settle delay.
	boot(saved)
	stubs.runTimers(1)
	stubs.containers[0] = { { FEATHER, 20 } }
	stubs.fire("BAG_UPDATE_DELAYED")
	stubs.runTimers()
	eq(saved.tracked[1].done, true, "still met")
	eq(#stubs.sounds, 0, "no alert")
end)

test("moving items between bags and bank neither alerts nor re-arms", function()
	local ns = settledBoot()
	stubs.containers[6] = { { FEATHER, 10 } }
	stubs.fire("BANKFRAME_OPENED")
	settle()
	setBags({ [FEATHER] = 5 })
	settle()
	ns.Tracker:SetNeed(ns.Tracker:Add("item", FEATHER), 20)

	-- Withdraw: for a moment the bags have the 10 and the cached bank still does.
	stubs.containers[6] = {}
	setBags({ [FEATHER] = 15 })
	settle()
	eq(ns.Inventory:GetCounts(FEATHER), 15, "bank scanned")
	eq(#stubs.sounds, 0, "no false alert from the double count")
end)

test("several goals met at once make one sound and one screen message", function()
	local ns = settledBoot()
	ns.Tracker:SetNeed(ns.Tracker:Add("item", FEATHER), 1)
	ns.Tracker:SetNeed(ns.Tracker:Add("item", DYE), 1)
	setBags({ [FEATHER] = 1, [DYE] = 1 })
	settle()
	eq(#stubs.sounds, 1, "one sound")
	eq(stubs.notices[1], "2 tracked goals met", "summary")
	eq(#stubs.notices, 1, "one message")
	local chat = table.concat(stubs.printed, "\n")
	contains(chat, "Light Feather", "chat names each")
	contains(chat, "Red Dye", "chat names each")
end)

test("the sound follows its setting, the message stays", function()
	local ns = settledBoot()
	Settings.settings.trackerSound:SetValue(false)
	ns.Tracker:SetNeed(ns.Tracker:Add("item", FEATHER), 1)
	setBags({ [FEATHER] = 1 })
	settle()
	eq(#stubs.sounds, 0, "silent")
	eq(#stubs.notices, 1, "still shown")
end)

test("no raid warning frame: falls back to the errors frame", function()
	local ns = settledBoot()
	local notice = _G.RaidNotice_AddMessage
	_G.RaidNotice_AddMessage = nil
	local shown
	_G.UIErrorsFrame = { AddMessage = function(_, text) shown = text end }
	ns.Tracker:SetNeed(ns.Tracker:Add("item", FEATHER), 1)
	setBags({ [FEATHER] = 1 })
	settle()
	_G.RaidNotice_AddMessage, _G.UIErrorsFrame = notice, nil
	eq(shown, "You have enough Light Feather (1)", "shown")
end)

test("a failing sound doesn't break the check", function()
	local ns = settledBoot()
	local play = _G.PlaySound
	_G.PlaySound = function() error("bad kit") end
	ns.Tracker:SetNeed(ns.Tracker:Add("item", FEATHER), 1)
	setBags({ [FEATHER] = 1 })
	settle()
	_G.PlaySound = play
	eq(#stubs.notices, 1, "still shown")
	eq(ns.Tracker:Find("item", FEATHER).done, true, "marked")
end)

-- Rows ----------------------------------------------------------------------

test("rows: unknown recipe shows reagents, then where to get it", function()
	local ns = settledBoot()
	ns.RecipeSources = { [RECIPE] = { i = 9001, dn = 12, dz = { "Stratholme" }, dzn = 1 } }
	ns.SourceNPCs = {}
	stubs.itemNames[9001] = "Plans: Arcanite Reaper"
	setBags({ [ARCANITE] = 3 })
	settle()
	ns.Tracker:Add("recipe", RECIPE)
	eq(dump(ns.Tracker:GetRows()), table.concat({
		"Arcanite Reaper",
		"Red Dye 0/2",
		"Arcanite Bar 3/10",
		"Nexus Crystal 0/1",
		"Learned from Plans: Arcanite Reaper",
		"Drop: 12 creatures in Stratholme",
		ns.Sources.UNCONFIRMED_NOTE,
	}, "\n"), "rows")
end)

test("rows: a known recipe says who knows it instead of where it drops", function()
	local ns = settledBoot({
		version = 1,
		chars = { ["Brewdin-StubRealm"] = { profs = { [164] = { rank = 300, known = { [RECIPE] = true } } }, bags = {}, bank = {} } },
	})
	ns.RecipeSources = { [RECIPE] = { i = 9001, dn = 12, dz = { "Stratholme" }, dzn = 1 } }
	ns.SourceNPCs = {}
	ns.Tracker:Add("recipe", RECIPE)
	local rows = ns.Tracker:GetRows()
	local last = rows[#rows]
	eq(last.text, "Known by Brewdin", "who")
	eq(last.known, "alt", "colored as an alt")
	assert(not dump(rows):find("Stratholme", 1, true), "no source")
end)

test("rows: a collapsed recipe is one row, the note goes with its source", function()
	local ns = settledBoot()
	ns.RecipeSources = { [RECIPE] = { i = 9001, dn = 12, dz = { "Stratholme" }, dzn = 1 } }
	ns.SourceNPCs = {}
	local entry = ns.Tracker:Add("recipe", RECIPE)
	ns.Tracker:SetCollapsed(entry, true)
	eq(#ns.Tracker:GetRows(), 1, "one row")
end)

test("rows: a recipe gone from the data stays listed and removable", function()
	local ns = settledBoot({ version = 1, tracked = { { kind = "recipe", id = 777, need = 1 } } })
	local rows = ns.Tracker:GetRows()
	eq(#rows, 1, "one row")
	eq(rows[1].name, "Recipe #777", "fallback name")
	eq(rows[1].status.met, false, "never met")
	ns.Tracker:Check()
	eq(#stubs.notices, 0, "no alert")
	ns.Tracker:Remove("recipe", 777)
	eq(#ns.Tracker:GetEntries(), 0, "removed")
end)

-- Window --------------------------------------------------------------------

local function findWindow()
	for _, w in ipairs(stubs.allWidgets()) do
		if w.title == "Tracking list" then return w end
	end
end

local function listOf(window)
	local function search(parent)
		for _, w in ipairs(stubs.allWidgets()) do
			if w.parent == parent then
				if w.template == "WowScrollBoxList" then return w end
				local found = w.kind == "Frame" and search(w)
				if found then return found end
			end
		end
	end
	return search(window)
end

local function needBox()
	for _, w in ipairs(stubs.allWidgets()) do
		if w.kind == "EditBox" and w.template == "InputBoxTemplate" then return w end
	end
end

test("window: rows render for every type, goals are set through the footer", function()
	local ns = settledBoot()
	ns.RecipeSources = { [RECIPE] = { i = 9001, dn = 12, dz = { "Stratholme" }, dzn = 1 } }
	ns.SourceNPCs = {}
	setBags({ [FEATHER] = 7 })
	settle()
	ns.Tracker:Add("item", FEATHER)
	ns.Tracker:Add("recipe", RECIPE)
	ns.TrackerUI:Open()
	local window = findWindow()
	local list = listOf(window)
	local row = list.rows[1]
	eq(row.Count.Label.text, "|cffe8e2d07 / —|r", "count without a goal")

	row.Count.scripts.OnClick(row.Count)
	local box = needBox()
	eq(box.shown, true, "box open")
	box:SetText("12")
	box.scripts.OnEnterPressed(box)
	eq(box.shown, false, "box closed")
	eq(ns.Tracker:Find("item", FEATHER).need, 12, "goal saved")
	contains(list.rows[1].Count.Label.text, "7 / 12", "row updated")
end)

test("window: Esc leaves the goal alone, empty clears it", function()
	local ns = settledBoot()
	local entry = ns.Tracker:Add("item", FEATHER)
	ns.Tracker:SetNeed(entry, 5)
	ns.TrackerUI:Open()
	local row = listOf(findWindow()).rows[1]
	row.Count.scripts.OnClick(row.Count)
	local box = needBox()
	eq(box:GetText(), "5", "current goal")
	box:SetText("99")
	box.scripts.OnEscapePressed(box)
	eq(entry.need, 5, "kept")
	row.Count.scripts.OnClick(row.Count)
	box:SetText("")
	box.scripts.OnEnterPressed(box)
	eq(entry.need, nil, "cleared")
end)

test("window: removing the entry being edited closes the box", function()
	local ns = settledBoot()
	ns.Tracker:Add("item", FEATHER)
	ns.TrackerUI:Open()
	local row = listOf(findWindow()).rows[1]
	row.Count.scripts.OnClick(row.Count)
	row.Remove.scripts.OnClick(row.Remove)
	eq(needBox().shown, false, "closed")
	eq(#ns.Tracker:GetEntries(), 0, "removed")
end)

test("window: a plain click folds a recipe, a modified click links instead", function()
	local ns = settledBoot()
	local entry = ns.Tracker:Add("recipe", RECIPE)
	ns.TrackerUI:Open()
	local row = listOf(findWindow()).rows[1]
	row.scripts.OnClick(row)
	eq(entry.collapsed, true, "folded")
	row.scripts.OnClick(row)
	eq(entry.collapsed, nil, "unfolded")
	stubs.modifier = "CHATLINK"
	row.scripts.OnClick(row)
	eq(entry.collapsed, nil, "not folded")
	eq(stubs.linked[1], "item:880101", "crafted item linked")
end)

test("window: stays open across a reload, position saved", function()
	local saved = { version = 1 }
	settledBoot(saved)
	stubs.slash("/ratlas", "track")
	local window = findWindow()
	eq(saved.ui.trackerShown, true, "saved on first open")
	window:Hide()
	eq(saved.ui.trackerShown, false, "closed")
	stubs.slash("/ratlas", "track")
	eq(saved.ui.trackerShown, true, "open")
	window:ClearAllPoints()
	window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -20)
	window.scripts.OnDragStop(window)
	eq(saved.ui.trackerPoint[3], 10, "position")

	stubs.reset()
	boot(saved)
	window = findWindow()
	assert(window and window.shown, "reopened")
	eq(window:GetPoint(1), "TOPLEFT", "restored")
end)

test("window: empty state", function()
	local ns = settledBoot()
	ns.TrackerUI:Open()
	local found = false
	for _, w in ipairs(stubs.allWidgets()) do
		if w.text and w.text:find("Nothing tracked yet", 1, true) then found = w.shown end
	end
	eq(found, true, "shown")
end)

-- Browser, minimap, settings ------------------------------------------------

test("browser: Track on a reagent and + on a recipe add to the list and open it", function()
	local ns = settledBoot()
	ns.Browser:Open()
	ns.Browser:Select(ARCANITE)
	local track, rowTrack
	for _, w in ipairs(stubs.allWidgets()) do
		if w.template == "UIPanelButtonTemplate" and (w.text == "Track") then track = w end
		if w.Track and w.recipeID == RECIPE then rowTrack = w.Track end
	end
	assert(track and rowTrack, "buttons exist")
	track.scripts.OnClick(track)
	eq(ns.Tracker:Find("item", ARCANITE) ~= nil, true, "reagent tracked")
	eq(track.text, "Untrack", "button flips")
	eq(ns.TrackerUI:IsShown(), true, "list opened")
	rowTrack.scripts.OnClick(rowTrack)
	eq(ns.Tracker:Find("recipe", RECIPE) ~= nil, true, "recipe tracked")
	rowTrack.scripts.OnClick(rowTrack)
	eq(ns.Tracker:Find("recipe", RECIPE), nil, "recipe untracked")
end)

test("browser: tracking a recipe doesn't rebuild the list under the cursor", function()
	local ns = settledBoot()
	ns.Browser:Open()
	ns.Browser:Select(ARCANITE)
	local rowTrack, list
	for _, w in ipairs(stubs.allWidgets()) do
		if w.Track and w.recipeID == RECIPE then rowTrack, list = w.Track, w.parent end
	end
	local provider = list.provider
	rowTrack.scripts.OnClick(rowTrack)
	settle()
	eq(list.provider, provider, "same data provider")
end)

test("minimap: shift-click toggles the tracking list", function()
	local ns = settledBoot()
	local button
	for _, w in ipairs(stubs.allWidgets()) do
		if w.kind == "Button" and w.parent == Minimap then button = w end
	end
	stubs.shift = true
	button.scripts.OnClick(button, "LeftButton")
	eq(ns.TrackerUI:IsShown(), true, "opened")
	eq(ns.Browser:IsShown(), false, "browser left alone")
end)

test("the sound defaults on for existing saved data", function()
	local ns = settledBoot({ version = 1, settings = { tooltip = false } })
	eq(ns.db.settings.trackerSound, true, "default")
	eq(#ns.db.tracked, 0, "empty list")
end)
