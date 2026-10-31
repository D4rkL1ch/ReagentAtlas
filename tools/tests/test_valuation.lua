---@diagnostic disable: undefined-global
local T = ...
local test, eq, near = T.test, T.eq, T.near

local function boot()
	return T.boot(nil, T.useFixture)
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

test("Light Feather scores per the spec heuristic", function()
	local info = boot().Valuation:GetInfo(17056)
	-- skill 285/300*40 = 38, 7 recipes = 14, best quality uncommon = 0,
	-- 3 professions = 5, spell reagent = 10
	near(info.score, 67, "score")
	eq(info.tier, 3, "tier")
	eq(info.recipeCount, 7, "recipeCount")
	eq(info.topSkill, 285, "topSkill")
	eq(info.topProf, 165, "topProf")
	eq(info.spellClasses[2], "PRIEST", "spell classes")
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
	-- 1/300*40 + 2*2 + 5 (two professions)
	near(info.score, 40 / 300 + 4 + 5, "score")
	eq(info.tier, 1, "tier")
end)

test("epic and rare outputs add their bonus", function()
	local V = boot().Valuation
	near(V:GetInfo(12360).score, 40 + 2 + 20, "epic")
	near(V:GetInfo(12359).score, 260 / 300 * 40 + 2 + 10, "rare")
end)

test("spell-only reagent gets an entry", function()
	local info = boot().Valuation:GetInfo(17020)
	eq(info.recipeCount, 0, "recipes")
	near(info.score, 10, "score")
	eq(info.tier, 1, "tier")
end)

test("items no recipe uses return nil", function()
	local V = boot().Valuation
	eq(V:GetInfo(6948), nil, "hearthstone")
	eq(V:GetInfo(nil), nil, "nil id")
end)

test("recipe count caps at 10", function()
	local ns = boot()
	local r = {}
	for i = 1, 15 do
		ns.Recipes[700000 + i] = { prof = 197, skill = 0, reagents = { [5000] = 1 } }
		r[i] = 700000 + i
	end
	ns.Reagents[5000] = { r = r }
	near(ns.Valuation:GetInfo(5000).score, 20, "score")
end)
