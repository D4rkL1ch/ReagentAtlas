local addonName, ns = ...

local Valuation = ns:RegisterModule("Valuation", {})

-- All tuning knobs in one place (SPEC.md > Value tier). Expect a tuning pass
-- a few weeks after launch.
Valuation.WEIGHTS = {
	skillCap = 300,       -- skill at which the skill signal maxes out
	skillPoints = 40,     -- points for a recipe at skillCap
	perRecipe = 2,        -- points per recipe using the item...
	maxRecipes = 10,      -- ...counting at most this many
	rareOutput = 10,      -- best output is rare (quality 3)
	epicOutput = 20,      -- best output is epic or better (quality 4+)
	multiProfession = 5,  -- used in 2+ professions
	spellReagent = 10,
}

-- Lower score bound of each tier; index = tier number.
Valuation.TIER_MIN = { 0, 15, 40, 70 }

Valuation.TIER_VENDOR = 1
Valuation.TIER_USEFUL = 2
Valuation.TIER_VALUABLE = 3
Valuation.TIER_KEEP = 4

Valuation.TIERS = {
	{ name = "Vendor",   color = "ff9d9d9d" },
	{ name = "Useful",   color = "ffffffff" },
	{ name = "Valuable", color = "ff4da6ff" },
	{ name = "Keep!",    color = "ffff8000" },
}

function Valuation:TierForScore(score)
	local tier = 1
	for i = 2, #self.TIER_MIN do
		if score >= self.TIER_MIN[i] then
			tier = i
		end
	end
	return tier
end

-- Static data never changes in a session, so results are cached per item.
local cache = {}

local function Analyze(itemID)
	local entry = ns.Reagents and ns.Reagents[itemID]
	if not entry then return nil end

	local recipes = ns.Recipes
	local W = Valuation.WEIGHTS

	local profCounts, profOrder = {}, {}
	local topSkill, topProf, bestQ = 0, nil, 0
	local count = 0
	for _, recipeID in ipairs(entry.r) do
		local recipe = recipes[recipeID]
		if recipe then
			count = count + 1
			if not profCounts[recipe.prof] then
				profCounts[recipe.prof] = 0
				profOrder[#profOrder + 1] = recipe.prof
			end
			profCounts[recipe.prof] = profCounts[recipe.prof] + 1
			if recipe.skill > topSkill or not topProf then
				topSkill, topProf = recipe.skill, recipe.prof
			end
			if (recipe.outQ or 0) > bestQ then
				bestQ = recipe.outQ
			end
		end
	end

	local spell = entry.spell
	if count == 0 and not spell then return nil end

	-- Professions with the most recipes first; ties keep data order (skill desc).
	local rank = {}
	for i, prof in ipairs(profOrder) do rank[prof] = i end
	table.sort(profOrder, function(a, b)
		if profCounts[a] ~= profCounts[b] then
			return profCounts[a] > profCounts[b]
		end
		return rank[a] < rank[b]
	end)

	local score = math.min(topSkill, W.skillCap) / W.skillCap * W.skillPoints
		+ math.min(count, W.maxRecipes) * W.perRecipe
	if bestQ >= 4 then
		score = score + W.epicOutput
	elseif bestQ == 3 then
		score = score + W.rareOutput
	end
	if #profOrder >= 2 then
		score = score + W.multiProfession
	end
	if spell then
		score = score + W.spellReagent
	end

	return {
		itemID = itemID,
		score = score,
		tier = Valuation:TierForScore(score),
		recipeCount = count,
		professions = profOrder,  -- skill line IDs, most recipes first
		profCounts = profCounts,
		topSkill = topSkill,
		topProf = topProf,
		bestQuality = bestQ,
		spellClasses = spell,     -- class tokens or nil
	}
end

-- Returns the valuation table for an item, or nil if no recipe or spell uses it.
-- Callers must treat the result as read-only.
function Valuation:GetInfo(itemID)
	if not itemID then return nil end
	local info = cache[itemID]
	if info == nil then
		info = Analyze(itemID) or false
		cache[itemID] = info
	end
	return info or nil
end

function Valuation:ClearCache()
	wipe(cache)
end

function Valuation:GetTierName(tier)
	return self.TIERS[tier].name
end

function Valuation:ColorTier(tier, text)
	return WrapTextInColorCode(text or self.TIERS[tier].name, self.TIERS[tier].color)
end
