---@diagnostic disable: undefined-global
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

local function boot(savedVars)
	return T.boot(savedVars, T.useFixture)
end

test("collapsed tooltip matches the mockup layout", function()
	boot()
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	eq(tt.lines[1], " ", "spacer")
	eq(tt:Text(), table.concat({
		" ",
		"Reagent Atlas: Useful",
		"Used in 7 recipes · Leatherworking, Tailoring...",
		"Highest: Leatherworking 285",
		"Spell reagent for Mage, Priest",
		"Hold Shift for all recipes",
	}, "\n"))
	contains(tt.lines[2], "|cff1eff00", "tier colored green")
end)

test("Shift view groups recipes by profession, skill desc", function()
	boot()
	stubs.shift = true
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	eq(tt:Text(), table.concat({
		" ",
		"Reagent Atlas: Useful",
		"Leatherworking",
		"· Feathered Jerkin (285)",
		"· Feathered Boots (250)",     -- name from output item
		"· Recipe #990003 (210)",      -- no name available
		"Tailoring",
		"· Recipe #990004 (225)",
		"· Recipe #990005 (180)",
		"Engineering",
		"· Recipe #990006 (200)",
		"· Recipe #990007 (150)",
		"Spell reagent for Mage, Priest",
	}, "\n"))
end)

test("single recipe uses singular and two professions no ellipsis", function()
	local ns = boot()
	ns.Recipes[600001] = { prof = 165, skill = 50, reagents = { [6000] = 1 } }
	ns.Recipes[600002] = { prof = 197, skill = 40, reagents = { [6001] = 1 } }
	ns.Recipes[600003] = { prof = 165, skill = 30, reagents = { [6001] = 1 } }
	ns.Reagents[6000] = { r = { 600001 } }
	ns.Reagents[6001] = { r = { 600002, 600003 } }
	local tt = stubs.newTooltip()
	tt:SetItem(6000)
	contains(tt:Text(), "Used in 1 recipe · Leatherworking\n", "singular")
	tt:SetItem(6001)
	-- tie on count: Tailoring has the higher-skill recipe, so it comes first
	contains(tt:Text(), "Used in 2 recipes · Tailoring, Leatherworking\n", "no ellipsis")
end)

test("spell-only reagent has no recipe lines or Shift hint", function()
	boot()
	local tt = stubs.newTooltip()
	tt:SetItem(17020)
	eq(tt:Text(), " \nReagent Atlas: Common\nSpell reagent for Mage\nSold by vendors")
end)

test("spell reagent line names classes in class colors", function()
	boot()
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	local line
	for _, l in ipairs(tt.lines) do
		if l:find("Spell reagent", 1, true) then line = l end
	end
	contains(line, "|cff3fc7ebMage|r", "Mage in class color")
	contains(line, "Priest", "Priest named")
end)

test("spell reagent for your own class says so", function()
	boot()
	stubs.classToken = "PRIEST"
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	contains(tt:Text(), "\nSpell reagent for your class\n", "own class")
	eq(tt:Text():find("Mage", 1, true), nil, "other classes not listed")
	contains(table.concat(tt.lines, "\n"), "|cff1eff00Spell reagent for your class", "green")
end)

test("vendor-sold reagent says so in both views", function()
	boot()
	local tt = stubs.newTooltip()
	tt:SetItem(2604)
	eq(tt:Text(), table.concat({
		" ",
		"Reagent Atlas: Common",
		"Used in 2 recipes · Blacksmithing",
		"Highest: Blacksmithing 300",
		"Sold by vendors",
		"Hold Shift for all recipes",
	}, "\n"))
	stubs.shift = true
	tt:SetItem(2604)
	local lines = tt:Text()
	eq(lines:sub(-#"Sold by vendors"), "Sold by vendors", "last line of Shift view")
end)

test("unknown items get no lines", function()
	boot()
	local tt = stubs.newTooltip()
	tt:SetItem(6948)
	eq(#tt.lines, 0, "lines")
end)

test("tooltip setting off adds nothing", function()
	boot({ version = 1, settings = { tooltip = false } })
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	eq(#tt.lines, 0, "lines")
end)

test("Shift is read when the tooltip is built", function()
	boot()
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	contains(tt:Text(), "Hold Shift", "collapsed without Shift")
	stubs.shift = true
	tt:SetItem(17056) -- the next hover, or a bag button's UpdateTooltip
	contains(tt:Text(), "Feathered Jerkin (285)", "expanded with Shift")
	stubs.shift = false
end)

-- RefreshData from addon code taints GameTooltip for the session (unit
-- frames, nameplates and Settings then error on secret values).
test("pressing Shift never refreshes tooltips from addon code", function()
	boot()
	local item, unit = stubs.newTooltip(), stubs.newTooltip()
	item:SetItem(17056)
	unit:SetItem(17056)
	unit:SetUnit("party1")
	local refreshed = 0
	item.RefreshData = function() refreshed = refreshed + 1 end
	unit.RefreshData = item.RefreshData
	stubs.shift = true
	stubs.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	stubs.combat = true
	stubs.fire("MODIFIER_STATE_CHANGED", "RSHIFT", 0)
	stubs.shift, stubs.combat = false, false
	eq(refreshed, 0, "refreshed")
	eq(unit:Text(), "party1", "unit tooltip untouched")
end)

test("Shift view caps long recipe lists", function()
	local ns = boot()
	local r = {}
	for i = 1, 45 do
		ns.Recipes[700000 + i] = { prof = 197, skill = 100 - i, reagents = { [5000] = 1 } }
		r[i] = 700000 + i
	end
	ns.Reagents[5000] = { r = r }
	stubs.shift = true
	local tt = stubs.newTooltip()
	tt:SetItem(5000)
	contains(tt:Text(), "...and 15 more", "overflow line")
	eq(#tt.lines, 1 + 1 + 1 + 30 + 1, "spacer, tier, header, 30 recipes, overflow")
end)

-- Crafted items and recipe items --------------------------------------------

-- The player has Tailoring 200 and knows nothing; Brewdin has Tailoring 225 and
-- knows 990004; Frostia has Leatherworking 290.
local PATTERN = 9004 -- teaches 990004 (Tailoring)
local LW_PATTERN = 9001 -- teaches 990001 (Leatherworking)
local BS_PATTERN = 9002 -- teaches 880002 (Blacksmithing)

local function craftingChars()
	return {
		version = 1,
		chars = {
			["Tester-StubRealm"] = { class = "MAGE", profs = { [197] = { rank = 200, known = {} } }, bags = {}, bank = {} },
			["Brewdin-StubRealm"] = { class = "PRIEST", profs = { [197] = { rank = 225, known = { [990004] = true } } }, bags = { [17056] = 2 }, bank = {} },
			["Frostia-StubRealm"] = { class = "MAGE", profs = { [165] = { rank = 290, known = {} } }, bags = {}, bank = {} },
		},
	}
end

local function bootCrafting()
	local ns = boot(craftingChars())
	ns.RecipeSources = {
		[990004] = { i = PATTERN },
		[990001] = { i = LW_PATTERN, v = { 1 } },
		[880002] = { i = BS_PATTERN },
	}
	ns.SourceNPCs = { [1] = { "Some Vendor", "Elwynn Forest", "AH" } }
	return ns
end

local function tooltipFor(itemID)
	local tt = stubs.newTooltip()
	tt:SetItem(itemID)
	return tt
end

test("a recipe item says what it teaches, who knows it and who could learn it", function()
	bootCrafting()
	eq(tooltipFor(PATTERN):Text(), table.concat({
		" ",
		"Reagent Atlas: Teaches Recipe #990004",
		"Known by Brewdin",
		"Could learn: you (200/225)",
		"Hold Shift for reagents",
	}, "\n"))
end)

test("a recipe item nobody can use says so", function()
	bootCrafting()
	local text = tooltipFor(BS_PATTERN):Text()
	contains(text, "None of your characters has Blacksmithing", "no one has it")
end)

test("could learn lists an alt in blue when you can't", function()
	bootCrafting()
	local tt = tooltipFor(LW_PATTERN)
	contains(tt:Text(), "Could learn: Frostia (290)", "alt")
	assert(not tt:Text():find("you (", 1, true), "not you")
end)

test("Shift on a recipe item adds the reagents against what you own", function()
	bootCrafting()
	stubs.shift = true
	stubs.itemNames[17056] = "Light Feather"
	local text = tooltipFor(PATTERN):Text()
	contains(text, "Light Feather", "reagent")
	contains(text, "2 / 3", "have / need")
	assert(not text:find("Hold Shift", 1, true), "no hint in the Shift view")
	stubs.shift = false
end)

test("a crafted item shows its profession and who can make it", function()
	bootCrafting()
	local text = tooltipFor(990104):Text()
	contains(text, "Reagent Atlas: Crafted with Tailoring 225", "profession")
	contains(text, "Known by Brewdin", "who")
	contains(text, "Hold Shift for reagents", "hint")
end)

test("a crafted item nobody knows shows where to get the recipe", function()
	local ns = bootCrafting()
	local collapsed = tooltipFor(990101):Text()
	contains(collapsed, "None of your characters knows this", "nobody")
	contains(collapsed, "Vendor", "source tag")
	contains(collapsed, ns.Sources.UNCONFIRMED_NOTE, "flagged unconfirmed")
	stubs.shift = true
	contains(tooltipFor(990101):Text(), "Some Vendor", "full source")
	stubs.shift = false
end)

test("an item that is crafted and a reagent gets both sections and one hint", function()
	local ns = bootCrafting()
	ns.Recipes[770001] = { prof = 164, skill = 200, out = 17056, outQ = 1, reagents = { [2604] = 1 } }
	local text = tooltipFor(17056):Text()
	contains(text, "Crafted with Blacksmithing 200", "crafted")
	contains(text, "Used in 7 recipes", "reagent")
	local _, hints = text:gsub("Hold Shift", "")
	eq(hints, 1, "one hint")
end)

test("items that are none of these stay untouched, and the setting covers all of it", function()
	local ns = bootCrafting()
	eq(#tooltipFor(424242).lines, 0, "unrelated item")
	ns.db.settings.tooltip = false
	eq(#tooltipFor(PATTERN).lines, 0, "tooltip setting off")
	eq(#tooltipFor(990104).lines, 0, "tooltip setting off")
end)

test("every recipe item and crafted item in the generated data renders", function()
	local ns = T.boot(nil)
	local count = 0
	for _, recipe in pairs(ns.Recipes) do
		if recipe.out then
			tooltipFor(recipe.out)
			count = count + 1
		end
	end
	for _, source in pairs(ns.RecipeSources or {}) do
		if source.i then
			stubs.shift = true
			tooltipFor(source.i)
			stubs.shift = false
		end
	end
	assert(count > 0, "recipes")
	eq(#stubs.errors, 0, "no errors")
end)
