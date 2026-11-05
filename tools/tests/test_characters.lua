---@diagnostic disable: undefined-global
-- Phase 3: professions, inventory, alt-aware tooltip.
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

local ME = "Tester-StubRealm"

-- Saved data with two alts: Brewdin (same realm, Tailoring) and Frostia
-- (other realm, owns feathers in the bank).
local function altData()
	return {
		version = 1,
		chars = {
			["Brewdin-StubRealm"] = {
				class = "PRIEST",
				profs = { [197] = { rank = 225, known = { [990004] = true, [990005] = true } } },
				bags = { [17056] = 20 },
				bank = {},
			},
			["Frostia-OtherRealm"] = {
				class = "MAGE",
				profs = { [202] = { rank = 200, known = { [990006] = true } } },
				bags = {},
				bank = { [17056] = 5 },
			},
		},
		account = { bank = { [17056] = 3 } },
	}
end

local function boot(savedVars)
	return T.boot(savedVars or altData(), T.useFixture)
end

-- Open "our" Leatherworking window and let the debounced scan run.
local function openLeatherworking(recipes)
	stubs.tradeSkill = { profID = 165, skillLevel = 290, recipes = recipes }
	stubs.fire("TRADE_SKILL_SHOW")
	stubs.runTimers()
end

-- Professions ---------------------------------------------------------------

test("character record is created at login", function()
	local ns = boot()
	local char = ns.db.chars[ME]
	eq(type(char), "table", "record")
	eq(char.class, "WARRIOR", "class")
	eq(char.faction, "Horde", "faction")
	eq(char.lastSeen, 1800000000, "lastSeen")
end)

test("profession ranks recorded at login, child skill lines folded", function()
	stubs.professions = { { skillLine = 2945, rank = 290, maxRank = 300 }, nil, { skillLine = 129, rank = 150, maxRank = 300 } }
	local ns = boot()
	local profs = ns.db.chars[ME].profs
	eq(profs[165].rank, 290, "Leatherworking via child line 2945")
	eq(profs[129].rank, 150, "First Aid in slot 3")
	eq(profs[2945], nil, "child line not stored")
end)

test("unlearned profession is dropped, empty list never prunes", function()
	stubs.professions = { { skillLine = 165, rank = 290, maxRank = 300 }, { skillLine = 197, rank = 100, maxRank = 150 } }
	local ns = boot()
	ns.db.chars[ME].profs[197].known[990004] = true
	stubs.professions = { { skillLine = 165, rank = 291, maxRank = 300 } }
	stubs.fire("SKILL_LINES_CHANGED")
	eq(ns.db.chars[ME].profs[197], nil, "Tailoring dropped")
	eq(ns.db.chars[ME].profs[165].rank, 291, "rank updated")
	stubs.professions = {}
	stubs.fire("SKILL_LINES_CHANGED")
	eq(ns.db.chars[ME].profs[165] ~= nil, true, "kept on empty list")
end)

test("own profession window records learned recipes", function()
	local ns = boot()
	openLeatherworking({ [990001] = true, [990002] = false, [990003] = true })
	local prof = ns.db.chars[ME].profs[165]
	eq(prof.known[990001], true, "learned")
	eq(prof.known[990002], nil, "not learned")
	eq(prof.known[990003], true, "learned")
	eq(prof.rank, 290, "rank from window")
end)

test("full recipe list replaces, so forgotten recipes disappear", function()
	local ns = boot()
	openLeatherworking({ [990001] = true, [990003] = true })
	openLeatherworking({ [990001] = true, [990003] = false })
	eq(ns.db.chars[ME].profs[165].known[990003], nil, "removed")
end)

test("filtered recipe list only adds", function()
	local ns = boot()
	openLeatherworking({ [990001] = true })
	local getAll = C_TradeSkillUI.GetAllRecipeIDs
	C_TradeSkillUI.GetAllRecipeIDs = nil
	openLeatherworking({ [990003] = true })
	C_TradeSkillUI.GetAllRecipeIDs = getAll
	local known = ns.db.chars[ME].profs[165].known
	eq(known[990001], true, "kept")
	eq(known[990003], true, "added")
end)

test("linked profession windows are ignored", function()
	local ns = boot()
	stubs.tradeSkill = { profID = 165, skillLevel = 300, recipes = { [990001] = true }, linked = true }
	stubs.fire("TRADE_SKILL_SHOW")
	stubs.runTimers()
	eq(ns.db.chars[ME].profs[165], nil, "nothing recorded")
end)

test("list updates are debounced into one scan", function()
	local ns = boot()
	stubs.runTimers() -- login timers
	stubs.tradeSkill = { profID = 165, skillLevel = 290, recipes = { [990001] = true } }
	stubs.fire("TRADE_SKILL_LIST_UPDATE")
	stubs.fire("TRADE_SKILL_LIST_UPDATE")
	stubs.fire("TRADE_SKILL_LIST_UPDATE")
	eq(#stubs.timers, 1, "one timer")
	stubs.runTimers()
	eq(ns.db.chars[ME].profs[165].known[990001], true, "scanned")
end)

test("learning a recipe records it without the window", function()
	local ns = boot()
	stubs.fire("NEW_RECIPE_LEARNED", 990002)
	eq(ns.db.chars[ME].profs[165].known[990002], true, "known")
	stubs.fire("NEW_RECIPE_LEARNED", 123456) -- not in data: ignored
end)

test("GetKnownBy reports you and sorted alts, and refreshes", function()
	local ns = boot()
	local isMe, alts = ns.Professions:GetKnownBy(990004)
	eq(isMe, false, "not me")
	eq(#alts, 1, "one alt")
	eq(alts[1], "Brewdin-StubRealm", "alt")
	stubs.fire("NEW_RECIPE_LEARNED", 990004)
	isMe, alts = ns.Professions:GetKnownBy(990004)
	eq(isMe, true, "now me")
	eq(#alts, 1, "alt still listed")
	isMe, alts = ns.Professions:GetKnownBy(990007)
	eq(isMe, false, "unknown recipe")
	eq(#alts, 0, "no alts")
end)

test("/ratlas diff lists learned recipes missing from the data", function()
	boot()
	stubs.printed = {}
	stubs.slash("/ratlas", "diff")
	contains(table.concat(stubs.printed, "\n"), "no differences found", "nothing yet")
	openLeatherworking({ [990001] = true, [555555] = true })
	stubs.printed = {}
	stubs.slash("/ratlas", "diff")
	local out = table.concat(stubs.printed, "\n")
	contains(out, "1 learned recipes are missing", "count")
	contains(out, "Recipe 555555 (555555)", "name")
end)

test("/ratlas forget removes another character", function()
	local ns = boot()
	stubs.slash("/ratlas", "forget Frostia-OtherRealm")
	eq(ns.db.chars["Frostia-OtherRealm"], nil, "removed")
	local isMe, alts = ns.Professions:GetKnownBy(990006)
	eq(#alts, 0, "index refreshed")
	stubs.printed = {}
	stubs.slash("/ratlas", "forget " .. ME)
	contains(table.concat(stubs.printed, "\n"), "can't forget", "self protected")
	eq(ns.db.chars[ME] ~= nil, true, "self kept")
end)

-- Inventory -----------------------------------------------------------------

test("bags count only reagents, stacks summed across bags", function()
	stubs.containers = {
		[0] = { { 17056, 10 }, { 6948, 1 }, nil, { 17056, 5 } },
		[5] = { { 2589, 20 } },
	}
	local ns = boot()
	local bags = ns.db.chars[ME].bags
	eq(bags[17056], 15, "feathers")
	eq(bags[2589], 20, "linen in reagent bag")
	eq(bags[6948], nil, "hearthstone skipped")
end)

test("bags rescan on BAG_UPDATE_DELAYED", function()
	local ns = boot()
	stubs.containers = { [1] = { { 2589, 7 } } }
	stubs.fire("BAG_UPDATE_DELAYED")
	eq(ns.db.chars[ME].bags[2589], 7, "updated")
end)

test("bank is scanned only while open, warband bank too", function()
	local ns = boot()
	stubs.containers = { [6] = { { 2589, 40 } }, [15] = { { 17056, 9 } }, [9] = { { 2589, 99 } } }
	stubs.fire("BAG_UPDATE_DELAYED")
	stubs.runTimers()
	eq(ns.db.chars[ME].bank[2589], nil, "closed bank not read")
	stubs.fire("BANKFRAME_OPENED")
	stubs.runTimers()
	eq(ns.db.chars[ME].bank[2589], 40, "purchased tab only (tab 9 not purchased)")
	eq(ns.db.account.bank[17056], 9, "warband bank")
	stubs.fire("BANKFRAME_CLOSED")
	stubs.containers[6] = {}
	stubs.fire("PLAYERBANKSLOTS_CHANGED", 1)
	stubs.runTimers()
	eq(ns.db.chars[ME].bank[2589], 40, "kept after closing")
end)

test("warband bank left alone when it can't be viewed", function()
	stubs.accountBankViewable = false
	local ns = boot()
	stubs.fire("BANKFRAME_OPENED")
	stubs.runTimers()
	eq(ns.db.account.bank[17056], 3, "previous warband counts kept")
end)

test("bank falls back to all tab IDs without C_Bank", function()
	stubs.noBankAPI = true
	stubs.containers = { [14] = { { 2589, 2 } } }
	local ns = boot()
	stubs.fire("BANKFRAME_OPENED")
	stubs.runTimers()
	eq(ns.db.chars[ME].bank[2589], 2, "tab 14 read")
end)

test("GetCounts: you first, then by count; warband separate", function()
	stubs.containers = { [0] = { { 17056, 2 } } }
	local ns = boot()
	local total, holders, warband = ns.Inventory:GetCounts(17056)
	eq(total, 2 + 20 + 5 + 3, "total")
	eq(warband, 3, "warband")
	eq(#holders, 3, "holders")
	eq(holders[1].key, ME, "you first")
	eq(holders[2].key, "Brewdin-StubRealm", "then most")
	eq(holders[3].bank, 5, "bank count")
	eq(ns.Inventory:GetCounts(2589), 0, "none owned")
end)

-- Tooltip -------------------------------------------------------------------

test("collapsed tooltip shows alt crafting and owned totals", function()
	boot()
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	local text = tt:Text()
	contains(text, "\nYour alts can craft 3 (Brewdin, Frostia-OtherRealm)\n", "alts line")
	contains(text, "\nOwned: 28 across 2 characters + warband bank\n", "owned line")
	contains(table.concat(tt.lines, "\n"), "|cff66b3ffYour alts can craft", "blue")
end)

test("collapsed tooltip: you can craft, you listed first", function()
	stubs.containers = { [0] = { { 17056, 1 } } }
	boot()
	stubs.fire("NEW_RECIPE_LEARNED", 990001)
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	contains(tt:Text(), "\nYou can craft 4 (you, Brewdin, Frostia-OtherRealm)\n", "craft line")
	contains(table.concat(tt.lines, "\n"), "|cff1eff00You can craft", "green")
end)

test("mockup order of collapsed lines", function()
	boot()
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	eq(tt:Text(), table.concat({
		" ",
		"Reagent Atlas: Valuable",
		"Used in 7 recipes · Leatherworking, Tailoring...",
		"Highest: Leatherworking 285",
		"Your alts can craft 3 (Brewdin, Frostia-OtherRealm)",
		"Spell reagent for Mage, Priest",
		"Owned: 28 across 2 characters + warband bank",
		"Hold Shift for all recipes",
	}, "\n"))
end)

test("name lists are capped", function()
	local saved = altData()
	for _, name in ipairs({ "Aa", "Bb", "Cc" }) do
		saved.chars[name .. "-StubRealm"] = { profs = { [165] = { known = { [990001] = true } } }, bags = {}, bank = {} }
	end
	boot(saved)
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	contains(tt:Text(), "Your alts can craft 4 (Aa, Bb, Brewdin +2)", "capped")
end)

test("Shift view colors recipes by who knows them and lists owners", function()
	stubs.containers = { [0] = { { 17056, 2 } } }
	boot()
	stubs.fire("NEW_RECIPE_LEARNED", 990001)
	stubs.shift = true
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	eq(tt:Text(), table.concat({
		" ",
		"Reagent Atlas: Valuable",
		"Leatherworking",
		"[v] Feathered Jerkin (285) | you",
		"· Feathered Boots (250)",
		"· Recipe #990003 (210)",
		"Tailoring",
		"[v] Recipe #990004 (225) | Brewdin",
		"[v] Recipe #990005 (180) | Brewdin",
		"Engineering",
		"[v] Recipe #990006 (200) | Frostia-OtherRealm",
		"· Recipe #990007 (150)",
		"Spell reagent for Mage, Priest",
		" ",
		"You | Bags 2",
		"Brewdin | Bags 20",
		"Frostia-OtherRealm | Bank 5",
		"Warband bank | 3",
	}, "\n"))
	local raw = table.concat(tt.lines, "\n")
	contains(raw, "|cff1eff00|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t Feathered Jerkin", "own recipe green with check")
	contains(raw, "|cff66b3ff|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t Recipe #990004", "alt recipe blue")
end)

test("no character data adds no craft or owned lines", function()
	T.boot(nil, T.useFixture)
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	eq(tt:Text():find("craft", 1, true), nil, "no craft line")
	eq(tt:Text():find("Owned", 1, true), nil, "no owned line")
end)
