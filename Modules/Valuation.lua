local addonName, ns = ...

local Valuation = ns:RegisterModule("Valuation", {})

-- All tuning knobs in one place (SPEC.md > Value tier). Calibrated against the
-- Forever 1.60.1 data; expect a tuning pass a few weeks after launch.
Valuation.WEIGHTS = {
	skillPoints = 35,     -- highest recipe skill, scaled against ns.MAX_SKILL
	demandPoints = 15,    -- recipes using it directly or via its chain, whichever is more, log scale...
	demandFull = 40,      -- ...reaching full points at this many recipes
	chainPoints = 20,     -- high-end recipes it feeds through its crafting chain, log scale...
	chainFull = 100,      -- ...reaching full points at this many recipes
	rareOutput = 5,       -- best output is rare (quality 3)
	epicOutput = 10,      -- best output is epic or better (quality 4+)
	multiProfession = 5,  -- used in 2+ professions
	ownQuality = { [2] = 10, [3] = 15, [4] = 20 }, -- the reagent's own quality (4 = epic and up)
	spellMinTier = 2,     -- spell reagents are at least Common
	vendorMaxTier = 2,    -- vendor-sold reagents are capped at Common
	priceRaiseFactor = 5, -- a fresh AH price this many times the vendor price...
	priceRaiseMin = 10000, -- ...and at least this much (copper) raises the tier one step
	priceCapTier = 2,     -- an AH price below the vendor price caps the tier at Common
}

local DEFAULT_MAX_SKILL = 300

-- Lower score bound of each tier; index = tier number.
Valuation.TIER_MIN = { 0, 15, 35, 55, 75 }

Valuation.TIER_VENDOR = 1
Valuation.TIER_COMMON = 2
Valuation.TIER_USEFUL = 3
Valuation.TIER_VALUABLE = 4
Valuation.TIER_KEEP = 5

-- Colours follow item quality: poor, common, uncommon, rare (lightened), legendary.
Valuation.TIERS = {
	{ name = "Vendor",   color = "ff9d9d9d" },
	{ name = "Common",   color = "ffffffff" },
	{ name = "Useful",   color = "ff1eff00" },
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
	local quality = entry.q or 1

	-- Professions with the most recipes first; ties keep data order (skill desc).
	local rank = {}
	for i, prof in ipairs(profOrder) do rank[prof] = i end
	table.sort(profOrder, function(a, b)
		if profCounts[a] ~= profCounts[b] then
			return profCounts[a] > profCounts[b]
		end
		return rank[a] < rank[b]
	end)

	local maxSkill = ns.MAX_SKILL or DEFAULT_MAX_SKILL
	if maxSkill <= 0 then maxSkill = DEFAULT_MAX_SKILL end

	local deep = entry.deep or 0 -- high-end recipes reached through the crafting chain
	local score = 0
	if count > 0 then
		score = math.min(topSkill / maxSkill, 1) * W.skillPoints
			+ math.min(math.log(1 + math.max(count, deep)) / math.log(1 + W.demandFull), 1) * W.demandPoints
			+ math.min(math.log(1 + deep) / math.log(1 + W.chainFull), 1) * W.chainPoints
		if bestQ >= 4 then
			score = score + W.epicOutput
		elseif bestQ == 3 then
			score = score + W.rareOutput
		end
		if #profOrder >= 2 then
			score = score + W.multiProfession
		end
	end
	score = score + (W.ownQuality[math.min(quality, 4)] or 0)

	local tier = Valuation:TierForScore(score)
	if spell and tier < W.spellMinTier then
		tier = W.spellMinTier
	end
	if entry.vendor and tier > W.vendorMaxTier then
		tier = W.vendorMaxTier
	end

	return {
		itemID = itemID,
		score = score,
		tier = tier,
		quality = quality,
		vendor = entry.vendor or false, -- also sold by NPC vendors
		sellPrice = entry.sell,         -- vendor sell price in copper, or nil
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

-- The data tier adjusted by an auction price (copper, or nil). Vendor-sold
-- reagents stay capped: their AH price only reflects the vendor markup.
function Valuation:AdjustTier(info, price)
	local tier = info.tier
	local sell = info.sellPrice
	if not price or not sell or sell <= 0 then return tier end
	local W = self.WEIGHTS
	if price < sell then
		return math.min(tier, W.priceCapTier)
	end
	if price >= sell * W.priceRaiseFactor and price >= W.priceRaiseMin then
		tier = math.min(tier + 1, self.TIER_KEEP)
		if info.vendor then
			tier = math.min(tier, W.vendorMaxTier)
		end
	end
	return tier
end

-- Final tier of an item, plus the auction price (copper) and its age in days
-- that went into it. Returns nil for items no recipe or spell uses.
function Valuation:GetTier(itemID)
	local info = self:GetInfo(itemID)
	if not info then return nil end
	local price, age = ns.Pricing:GetPrice(itemID)
	return self:AdjustTier(info, price), price, age
end

function Valuation:GetTierName(tier)
	return self.TIERS[tier].name
end

function Valuation:ColorTier(tier, text)
	return WrapTextInColorCode(text or self.TIERS[tier].name, self.TIERS[tier].color)
end
