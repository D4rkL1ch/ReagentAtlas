---@diagnostic disable: undefined-global
-- Sanity checks on whatever Data/*.lua currently holds (real or sample).
local T = ...
local test, eq, stubs = T.test, T.eq, T.stubs

test("generated data is consistent", function()
	local ns = T.boot(nil)
	eq(type(ns.DATA_BUILD), "string", "DATA_BUILD")
	eq(type(ns.MAX_SKILL), "number", "MAX_SKILL")
	local reagents = 0
	for itemID, entry in pairs(ns.Reagents) do
		reagents = reagents + 1
		eq(type(entry.r), "table", "r of " .. itemID)
		local prevSkill = math.huge
		for _, recipeID in ipairs(entry.r) do
			local recipe = ns.Recipes[recipeID]
			eq(recipe ~= nil, true, ("recipe %d of item %d exists"):format(recipeID, itemID))
			eq(recipe.reagents[itemID] ~= nil, true, ("recipe %d uses item %d"):format(recipeID, itemID))
			eq(recipe.skill <= prevSkill, true, ("item %d recipes sorted by skill"):format(itemID))
			eq(ns.ProfessionNames[recipe.prof] ~= nil, true, "profession name for " .. recipe.prof)
			prevSkill = recipe.skill
		end
	end
	eq(reagents > 0, true, "has reagents")
end)

test("every reagent renders both tooltip views", function()
	local ns = T.boot(nil)
	local tt = stubs.newTooltip()
	for itemID in pairs(ns.Reagents) do
		stubs.shift = false
		tt:SetItem(itemID)
		eq(#tt.lines > 1, true, "collapsed lines for " .. itemID)
		stubs.shift = true
		tt:SetItem(itemID)
		eq(#tt.lines > 1, true, "Shift lines for " .. itemID)
	end
end)

test("real data: anchor items land in sensible tiers", function()
	local ns = T.boot(nil)
	if ns.DATA_BUILD == "sample" then return end
	local V = ns.Valuation
	eq(V:GetInfo(12360).tier, V.TIER_KEEP, "Arcanite Bar")
	eq(V:GetInfo(20725).tier, V.TIER_KEEP, "Nexus Crystal")
	eq(V:GetInfo(2589).tier <= V.TIER_USEFUL, true, "Linen Cloth at most Useful")
	eq(V:GetInfo(2604).tier <= V.TIER_USEFUL, true, "Red Dye (vendor) at most Useful")
	eq(V:GetInfo(6948), nil, "Hearthstone is not a reagent")
end)
