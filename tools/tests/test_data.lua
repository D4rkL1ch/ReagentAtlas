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

test("recipe sources are consistent and render", function()
	local ns = T.boot(nil)
	if not ns.RecipeSources then return end
	local named = 0
	for recipeID, src in pairs(ns.RecipeSources) do
		eq(ns.Recipes[recipeID] ~= nil, true, "recipe exists " .. recipeID)
		eq(type(src.i), "number", "recipe item of " .. recipeID)
		for _, list in ipairs({ src.v or {}, src.d or {} }) do
			for _, npcID in ipairs(list) do
				eq(ns.SourceNPCs[npcID] ~= nil, true, "NPC exists " .. npcID)
			end
		end
		if src.v or src.q or src.d or src.dn or src.o then named = named + 1 end
	end
	eq(named > 0, true, "has named sources")
	for recipeID in pairs(ns.Recipes) do
		eq(type(ns.Sources:GetTag(recipeID)), "string", "tag for " .. recipeID)
		eq(type(ns.Sources:GetDetailLines(recipeID)), "table", "lines for " .. recipeID)
	end
end)

test("real data: known recipe sources", function()
	local ns = T.boot(nil)
	if ns.DATA_BUILD == "sample" then return end
	eq(ns.Sources:GetTag(2152), "Trainer (likely)", "Light Armor Kit has no recipe item")
	-- Mystery Stew: Alliance vendors only, plus a neutral one with no location.
	local src = ns.RecipeSources[15865]
	eq(src.i, 12233, "Recipe: Mystery Stew")
	eq(ns.SourceNPCs[src.v[1]][1], "Helenia Olden", "first vendor")
	eq(ns.SourceNPCs[src.v[1]][2], "Dustwallow Marsh", "first vendor's zone")
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
	eq(V:GetInfo(12363).tier, V.TIER_KEEP, "Arcane Crystal: few recipes, feeds Arcanite's")
	eq(V:GetInfo(13468).tier, V.TIER_KEEP, "Black Lotus")
	eq(V:GetInfo(2770).tier, V.TIER_VENDOR, "Copper Ore: long chain, none of it high-end")
	eq(V:GetInfo(2589).tier <= V.TIER_USEFUL, true, "Linen Cloth at most Useful")
	eq(V:GetInfo(2604).tier <= V.TIER_USEFUL, true, "Red Dye (vendor) at most Useful")
	eq(V:GetInfo(6948), nil, "Hearthstone is not a reagent")
end)

test("output counts and conversion flags are well formed", function()
	local ns = T.boot(nil)
	for recipeID, recipe in pairs(ns.Recipes) do
		if recipe.n then
			eq(recipe.n > 1, true, "n of " .. recipeID)
			eq(recipe.out ~= nil, true, "output of " .. recipeID)
		end
		if recipe.conv then
			local kinds = 0
			for _ in pairs(recipe.reagents) do kinds = kinds + 1 end
			eq(kinds, 1, "conversion " .. recipeID .. " has one input")
		end
	end
end)
