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
	eq(V:GetInfo(2770).tier, V.TIER_COMMON, "Copper Ore: low score, lifted as a material")
	eq(V:GetInfo(2589).tier <= V.TIER_USEFUL, true, "Linen Cloth at most Useful")
	eq(V:GetInfo(2604).tier <= V.TIER_COMMON, true, "Red Dye (vendor) at most Common")
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

-- Duplicate and dead entries ---------------------------------------------------

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

local function noRepeats(list, msg)
	local seen = {}
	for _, v in ipairs(list) do
		eq(seen[v], nil, ("%s: %s repeated"):format(msg, tostring(v)))
		seen[v] = true
	end
end

test("data files assign every key once", function()
	-- Lua keeps the last of two assignments, so repeats only show in the text.
	for _, file in ipairs({ "Recipes", "Reagents", "Crates", "Sources" }) do
		local seen = {}
		for line in io.lines(T.repoRoot .. "/Data/" .. file .. ".lua") do
			local var, id = line:match("^(%a+)%[(%d+)%] = ")
			if var then
				local key = var .. "[" .. id .. "]"
				eq(seen[key], nil, file .. ".lua assigns " .. key .. " twice")
				seen[key] = true
				local reagents = line:match("reagents = (%b{})")
				if reagents then
					local inRecipe = {}
					for item in reagents:gmatch("%[(%d+)%]") do
						eq(inRecipe[item], nil, key .. " lists reagent " .. item .. " twice")
						inRecipe[item] = true
					end
				end
			end
		end
	end
end)

test("data lists have no repeats and no dead entries", function()
	local ns = T.boot(nil)
	local usedBy = {}
	for recipeID, recipe in pairs(ns.Recipes) do
		eq(next(recipe.reagents) ~= nil, true, "recipe " .. recipeID .. " has reagents")
		for itemID in pairs(recipe.reagents) do
			eq(ns.Reagents[itemID] ~= nil, true, ("reagent %d of recipe %d exists"):format(itemID, recipeID))
			usedBy[itemID] = (usedBy[itemID] or 0) + 1
		end
	end

	local inCrate = {}
	for crateID, bundles in pairs(ns.Crates or {}) do
		local items = {}
		for i, bundle in ipairs(bundles) do
			items[i] = bundle[1]
			inCrate[bundle[1]] = true
			eq(ns.Reagents[bundle[1]] ~= nil, true, ("crate %d item %d is a reagent"):format(crateID, bundle[1]))
		end
		noRepeats(items, "crate " .. crateID)
	end

	for _, itemID in ipairs(sortedKeys(ns.Reagents)) do
		local entry = ns.Reagents[itemID]
		noRepeats(entry.r, "recipes of item " .. itemID)
		eq(#entry.r, usedBy[itemID] or 0, "item " .. itemID .. " lists every recipe that uses it")
		if entry.spell then noRepeats(entry.spell, "classes of item " .. itemID) end
		eq(#entry.r > 0 or entry.spell ~= nil or entry.vendor or inCrate[itemID] or false, true,
			"item " .. itemID .. " is used by something")
	end

	-- Same profession, output, count and reagents is a copy the build should drop.
	-- Enchants have no output item, so equal reagents there are different enchants.
	local seen = {}
	for _, recipeID in ipairs(sortedKeys(ns.Recipes)) do
		local recipe = ns.Recipes[recipeID]
		if recipe.out then
			local parts = { recipe.prof, recipe.out, recipe.n or 1 }
			for _, itemID in ipairs(sortedKeys(recipe.reagents)) do
				parts[#parts + 1] = itemID .. "x" .. recipe.reagents[itemID]
			end
			local key = table.concat(parts, ":")
			eq(seen[key], nil, ("recipe %d copies recipe %s"):format(recipeID, tostring(seen[key])))
			seen[key] = recipeID
		end
	end

	if ns.RecipeSources then
		local npcUsed = {}
		for recipeID, src in pairs(ns.RecipeSources) do
			for _, field in ipairs({ "v", "d", "dz", "q" }) do
				if src[field] then noRepeats(src[field], ("%s of recipe %d"):format(field, recipeID)) end
			end
			for _, npcID in ipairs(src.v or {}) do npcUsed[npcID] = true end
			for _, npcID in ipairs(src.d or {}) do npcUsed[npcID] = true end
		end
		for npcID in pairs(ns.SourceNPCs) do
			eq(npcUsed[npcID], true, "NPC " .. npcID .. " is named by a source")
		end
	end
end)

test("real data: hand-kept lists have no repeats and no dead rows", function()
	local ns = T.boot(nil)
	if ns.DATA_BUILD == "sample" then return end
	local function rows(name)
		local result, header = {}, nil
		for line in io.lines(T.repoRoot .. "/tools/" .. name) do
			local cells = {}
			for cell in (line .. ","):gmatch("([^,]*),") do cells[#cells + 1] = cell end
			if not header then
				header = cells
			elseif line ~= "" then
				local row = {}
				for i, col in ipairs(header) do row[col] = cells[i] end
				result[#result + 1] = row
			end
		end
		return result
	end
	local function unique(name, ...)
		local cols, seen = { ... }, {}
		for _, row in ipairs(rows(name)) do
			local parts = {}
			for i, col in ipairs(cols) do parts[i] = row[col] end
			local key = table.concat(parts, ",")
			eq(seen[key], nil, name .. " repeats " .. key)
			seen[key] = true
		end
	end
	unique("vendor_reagents.csv", "itemID")
	unique("spell_reagents.csv", "itemID", "class")
	unique("crate_bundles.csv", "crateID", "itemID")

	for _, row in ipairs(rows("vendor_reagents.csv")) do
		local entry = ns.Reagents[tonumber(row.itemID)]
		eq(entry ~= nil and entry.vendor, true, "vendor_reagents.csv row " .. row.itemID .. " is a vendor reagent")
	end
	for _, row in ipairs(rows("spell_reagents.csv")) do
		local entry = ns.Reagents[tonumber(row.itemID)]
		local class, remove = row.class:gsub("^%-", "")
		local has = false
		for _, c in ipairs(entry and entry.spell or {}) do
			if c == class then has = true end
		end
		eq(has, remove == 0, "spell_reagents.csv row " .. row.itemID .. "," .. row.class .. " is applied")
	end
end)
