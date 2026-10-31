---@diagnostic disable: undefined-global
local T = ...
local test, eq, near = T.test, T.eq, T.near

local function boot()
	return T.boot(nil, T.useFixture)
end

-- Expected demand points for n recipes (weights: 15 points, full at 40).
local function demand(n)
	return math.min(math.log(1 + n) / math.log(41), 1) * 15
end

test("tier boundaries", function()
	local V = boot().Valuation
	eq(V:TierForScore(0), 1, "0")
	eq(V:TierForScore(14.99), 1, "14.99")
	eq(V:TierForScore(15), 2, "15")
	eq(V:TierForScore(39.99), 2, "39.99")
	eq(V:TierForScore(40), 3, "40")
	eq(V:TierForScore(69.99), 3, "69.99")
	eq(V:TierForScore(70), 4, "70")
	eq(V:TierForScore(250), 4, "250")
end)

test("Light Feather scores per the heuristic", function()
	local info = boot().Valuation:GetInfo(17056)
	-- skill 285/300*35, 7 recipes, best output uncommon = 0, 3 professions = 5,
	-- own quality common = 0; being a spell reagent only sets a floor
	near(info.score, 285 / 300 * 35 + demand(7) + 5, "score")
	eq(info.tier, 3, "tier")
	eq(info.recipeCount, 7, "recipeCount")
	eq(info.topSkill, 285, "topSkill")
	eq(info.topProf, 165, "topProf")
	eq(info.spellClasses[2], "PRIEST", "spell classes")
	eq(info.vendor, false, "vendor")
	eq(info.sellPrice, 4, "sell price")
end)

test("professions ordered by recipe count, ties by highest skill", function()
	local profs = boot().Valuation:GetInfo(17056).professions
	eq(#profs, 3, "count")
	eq(profs[1], 165, "Leatherworking (3)")
	eq(profs[2], 197, "Tailoring (2, top 225)")
	eq(profs[3], 202, "Engineering (2, top 200)")
end)

test("low skill reagent is Vendor", function()
	local info = boot().Valuation:GetInfo(2589)
	near(info.score, 1 / 300 * 35 + demand(2) + 5, "score")
	eq(info.tier, 1, "tier")
end)

test("epic and rare outputs add their bonus", function()
	local V = boot().Valuation
	-- 12360 is also uncommon itself (+10)
	near(V:GetInfo(12360).score, 35 + demand(1) + 10 + 10, "epic")
	near(V:GetInfo(12359).score, 260 / 300 * 35 + demand(1) + 5, "rare")
end)

test("own quality counts, epic and above capped at the epic bonus", function()
	local ns = boot()
	near(ns.Valuation:GetInfo(20725).score, 35 + demand(1) + 10 + 20, "epic reagent")
	ns.Reagents[20725].q = 5
	ns.Valuation:ClearCache()
	near(ns.Valuation:GetInfo(20725).score, 35 + demand(1) + 10 + 20, "legendary reagent")
end)

test("vendor-sold reagents are capped at Useful", function()
	local info = boot().Valuation:GetInfo(2604)
	-- 300 skill, 2 recipes, epic output, 1 profession: Valuable by score...
	near(info.score, 35 + demand(2) + 10, "score")
	-- ...but anyone can buy it
	eq(info.tier, 2, "tier")
	eq(info.vendor, true, "vendor flag")
end)

test("spell reagents are at least Useful", function()
	local ns = boot()
	local info = ns.Valuation:GetInfo(17020)
	eq(info.recipeCount, 0, "recipes")
	near(info.score, 0, "score")
	eq(info.tier, 2, "spell-only tier")
	-- a low-scoring recipe reagent that is also a spell reagent
	ns.Reagents[2589].spell = { "ROGUE" }
	ns.Valuation:ClearCache()
	eq(ns.Valuation:GetInfo(2589).tier, 2, "Linen as spell reagent")
end)

test("items no recipe uses return nil", function()
	local V = boot().Valuation
	eq(V:GetInfo(6948), nil, "hearthstone")
	eq(V:GetInfo(nil), nil, "nil id")
end)

test("demand grows on a log scale and caps at demandFull", function()
	local ns = boot()
	local function addItem(itemID, n)
		local r = {}
		for i = 1, n do
			local id = itemID * 1000 + i
			ns.Recipes[id] = { prof = 197, skill = 0, reagents = { [itemID] = 1 } }
			r[i] = id
		end
		ns.Reagents[itemID] = { r = r, q = 1 }
	end
	addItem(5001, 10)
	addItem(5002, 40)
	addItem(5003, 200)
	near(ns.Valuation:GetInfo(5001).score, demand(10), "10 recipes")
	near(ns.Valuation:GetInfo(5002).score, 15, "40 recipes")
	near(ns.Valuation:GetInfo(5003).score, 15, "200 recipes")
end)

test("skill scales against MAX_SKILL from the data", function()
	local ns = boot()
	ns.MAX_SKILL = 600
	near(ns.Valuation:GetInfo(12359).score, 260 / 600 * 35 + demand(1) + 5, "half-height cap")
	ns.Valuation:ClearCache()
	ns.MAX_SKILL = nil -- older data without the constant falls back to 300
	near(ns.Valuation:GetInfo(12359).score, 260 / 300 * 35 + demand(1) + 5, "fallback")
end)
