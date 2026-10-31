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
		"Reagent Atlas: Valuable",
		"Used in 7 recipes · Leatherworking, Tailoring...",
		"Highest: Leatherworking 285",
		"Spell reagent: Mage, Priest",
		"Hold Shift for all recipes",
	}, "\n"))
	contains(tt.lines[2], "|cff4da6ff", "tier colored blue")
end)

test("Shift view groups recipes by profession, skill desc", function()
	boot()
	stubs.shift = true
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	eq(tt:Text(), table.concat({
		" ",
		"Reagent Atlas: Valuable",
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
		"Spell reagent: Mage, Priest",
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
	eq(tt:Text(), " \nReagent Atlas: Vendor\nSpell reagent: Mage")
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

test("pressing Shift refreshes a shown tooltip", function()
	boot()
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	contains(tt:Text(), "Hold Shift", "collapsed first")
	stubs.shift = true
	stubs.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	contains(tt:Text(), "Feathered Jerkin (285)", "expanded after Shift")
	stubs.shift = false
	stubs.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
	contains(tt:Text(), "Feathered Jerkin", "Ctrl does not refresh")
	stubs.fire("MODIFIER_STATE_CHANGED", "RSHIFT", 0)
	contains(tt:Text(), "Hold Shift", "collapsed after release")
end)

test("hidden tooltips are not refreshed", function()
	boot()
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	tt:Hide()
	local refreshed = false
	tt.RefreshData = function() refreshed = true end
	stubs.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	eq(refreshed, false, "refreshed")
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
