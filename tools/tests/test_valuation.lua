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
	eq(V:TierForScore(34.99), 2, "34.99")
	eq(V:TierForScore(35), 3, "35")
	eq(V:TierForScore(54.99), 3, "54.99")
	eq(V:TierForScore(55), 4, "55")
	eq(V:TierForScore(74.99), 4, "74.99")
	eq(V:TierForScore(75), 5, "75")
	eq(V:TierForScore(250), 5, "250")
	eq(#V.TIERS, #V.TIER_MIN, "a name per tier")
	eq(V.TIER_KEEP, #V.TIERS, "Keep! is the top tier")
end)

test("the crafting chain adds points on a log scale, capped", function()
	local ns = T.boot(nil, function(ns)
		T.useFixture(ns)
		ns.Reagents[12359].deep = 9
		ns.Reagents[12360].deep = 500
	end)
	local V = ns.Valuation
	local plain = T.boot(nil, T.useFixture).Valuation
	-- Both have 1 direct recipe; the chain replaces that count in demand too.
	near(V:GetInfo(12359).score - plain:GetInfo(12359).score,
		demand(9) - demand(1) + math.log(10) / math.log(101) * 20, "partial")
	near(V:GetInfo(12360).score - plain:GetInfo(12360).score, 15 - demand(1) + 20, "capped")
end)

test("a chain shorter than the direct recipe count leaves demand alone", function()
	local ns = T.boot(nil, function(ns)
		T.useFixture(ns)
		ns.Reagents[17056].deep = 3
	end)
	near(ns.Valuation:GetInfo(17056).score,
		285 / 300 * 35 + demand(7) + math.log(4) / math.log(101) * 20 + 5, "score")
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

test("vendor-sold reagents are capped at Common", function()
	local info = boot().Valuation:GetInfo(2604)
	-- 300 skill, 2 recipes, epic output, 1 profession: Valuable by score...
	near(info.score, 35 + demand(2) + 10, "score")
	-- ...but anyone can buy it
	eq(info.tier, 2, "tier")
	eq(info.vendor, true, "vendor flag")
end)

test("spell reagents are at least Common", function()
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

test("real data: crate reagents and smelted/cured materials are at least Common", function()
	local ns = T.boot(nil)
	if ns.DATA_BUILD == "sample" then return end
	local V = ns.Valuation
	eq(V:GetInfo(2770).tier, V.TIER_COMMON, "Copper Ore: smelted into Copper Bar")
	eq(V:GetInfo(2771).tier, V.TIER_COMMON, "Tin Ore: fills a crate")
	eq(V:GetInfo(783).tier, V.TIER_COMMON, "Light Hide: cured into Cured Light Hide")
	eq(V:GetInfo(2672).tier, V.TIER_VENDOR, "Stringy Wolf Meat stays Vendor")
end)
