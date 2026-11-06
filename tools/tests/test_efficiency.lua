---@diagnostic disable: undefined-global
-- Work is only done when something changed, and shortcuts agree with the long
-- way round.
local T = ...
local test, eq, stubs = T.test, T.eq, T.stubs

local ME = "Tester-StubRealm"
local FEATHER, LINEN = 17056, 2589

local function altData()
	return {
		version = 1,
		chars = {
			["Brewdin-StubRealm"] = {
				class = "PRIEST",
				profs = { [197] = { rank = 225, known = { [990004] = true } } },
				bags = { [FEATHER] = 20 },
				bank = {},
			},
			["Frostia-OtherRealm"] = { class = "MAGE", profs = {}, bags = {}, bank = { [FEATHER] = 5 } },
		},
		account = { bank = { [FEATHER] = 3 } },
	}
end

local function boot(savedVars)
	return T.boot(savedVars or altData(), T.useFixture)
end

local function countChanges(ns)
	local fired = { total = 0, inventory = 0 }
	ns:RegisterMessage("CHAR_DATA_CHANGED", function(_, what)
		fired.total = fired.total + 1
		if what == ns.INVENTORY_ONLY then fired.inventory = fired.inventory + 1 end
	end)
	return fired
end

local function fakeAuctionator(prices, ages)
	local api = { ageCalls = 0 }
	function api.GetAuctionPriceByItemID(_, itemID) return prices[itemID] end
	function api.GetAuctionAgeByItemID(_, itemID)
		api.ageCalls = api.ageCalls + 1
		return ages[itemID]
	end
	function api.RegisterForDBUpdate(_, callback) api.onUpdate = callback end
	_G.Auctionator = { API = { v1 = api } }
	return api
end

-- Scans ---------------------------------------------------------------------

test("a bag update that changes no reagent counts announces nothing", function()
	stubs.containers = { [0] = { { LINEN, 7 }, { 6948, 1 } } }
	local ns = boot()
	local fired = countChanges(ns)
	stubs.containers = { [0] = { { 6949, 1 } }, [1] = { { LINEN, 7 } } }
	stubs.fire("BAG_UPDATE_DELAYED")
	eq(fired.total, 0, "moved the linen, swapped a non-reagent")
	stubs.containers[1] = { { LINEN, 8 } }
	stubs.fire("BAG_UPDATE_DELAYED")
	eq(fired.total, 1, "a new count is a change")
	eq(fired.inventory, 1, "marked as inventory only")
	eq(ns.db.chars[ME].bags[LINEN], 8, "stored")
end)

test("a bank scan announces only a change, the warband bank included", function()
	local ns = boot()
	stubs.containers = { [6] = { { LINEN, 4 } }, [15] = { { FEATHER, 3 } } }
	stubs.fire("BANKFRAME_OPENED")
	stubs.runTimers()
	eq(ns.db.chars[ME].bank[LINEN], 4, "scanned")
	local fired = countChanges(ns)
	stubs.fire("PLAYERBANKSLOTS_CHANGED")
	stubs.runTimers()
	eq(fired.total, 0, "same counts")
	stubs.containers[15] = { { FEATHER, 4 } }
	stubs.fire("PLAYERBANKSLOTS_CHANGED")
	stubs.runTimers()
	eq(fired.total, 1, "warband bank changed")
	eq(ns.db.account.bank[FEATHER], 4, "stored")
end)

test("inventory changes keep the known-recipe index, others replace it", function()
	local ns = boot()
	ns.Professions:GetKnownBy(990004)
	ns.db.chars["Brewdin-StubRealm"].profs[197].known[990004] = nil
	ns:Fire("CHAR_DATA_CHANGED", ns.INVENTORY_ONLY)
	eq(#select(2, ns.Professions:GetKnownBy(990004)), 1, "index kept")
	ns:Fire("CHAR_DATA_CHANGED")
	eq(#select(2, ns.Professions:GetKnownBy(990004)), 0, "index rebuilt")
end)

test("skill events announce only a changed rank or profession", function()
	stubs.professions = { { skillLine = 165, rank = 100, maxRank = 150 } }
	local ns = boot()
	local fired = countChanges(ns)
	stubs.fire("SKILL_LINES_CHANGED")
	eq(fired.total, 0, "a weapon skill went up")
	stubs.professions[1].rank = 101
	stubs.fire("SKILL_LINES_CHANGED")
	eq(fired.total, 1, "a profession skill went up")
	stubs.professions = { { skillLine = 197, rank = 1, maxRank = 75 } }
	stubs.fire("SKILL_LINES_CHANGED")
	eq(fired.total, 2, "swapped profession")
	eq(ns.db.chars[ME].profs[165], nil, "old one pruned")
end)

local function openLeatherworking(recipes)
	stubs.tradeSkill = { profID = 165, skillLevel = 290, recipes = recipes }
	stubs.fire("TRADE_SKILL_SHOW")
	stubs.runTimers()
end

test("a recipe rescan announces only a change", function()
	local ns = boot()
	openLeatherworking({ [990001] = true })
	local fired = countChanges(ns)
	stubs.fire("TRADE_SKILL_LIST_UPDATE")
	stubs.runTimers()
	eq(fired.total, 0, "same recipes and rank")
	openLeatherworking({ [990001] = true, [990002] = true })
	eq(fired.total, 1, "learned one")
	eq(ns.db.chars[ME].profs[165].known[990002], true, "stored")
end)

test("a filtered recipe list still only adds", function()
	local ns = boot()
	openLeatherworking({ [990001] = true })
	local getAll = C_TradeSkillUI.GetAllRecipeIDs
	C_TradeSkillUI.GetAllRecipeIDs = nil
	local fired = countChanges(ns)
	openLeatherworking({ [990002] = true })
	C_TradeSkillUI.GetAllRecipeIDs = getAll
	eq(fired.total, 1, "added one")
	eq(ns.db.chars[ME].profs[165].known[990001], true, "kept")
	eq(ns.db.chars[ME].profs[165].known[990002], true, "new")
end)

test("bags are read without the ID-only call too", function()
	local getID = C_Container.GetContainerItemID
	C_Container.GetContainerItemID = nil
	stubs.containers = { [0] = { { LINEN, 7 } } }
	local ok, ns = pcall(boot)
	C_Container.GetContainerItemID = getID
	eq(ok, true, "booted")
	eq(ns.db.chars[ME].bags[LINEN], 7, "counted")
end)

-- Shortcuts agree -----------------------------------------------------------

test("GetTotal matches GetCounts across characters and the warband bank", function()
	stubs.containers = { [0] = { { FEATHER, 2 } } }
	local ns = boot()
	eq(ns.Inventory:GetTotal(FEATHER), 30, "bags, alts, bank, warband")
	eq(ns.Inventory:GetTotal(FEATHER), (ns.Inventory:GetCounts(FEATHER)), "same as the long way")
	eq(ns.Inventory:GetTotal(LINEN), 0, "none")
end)

test("HasReagents agrees with the recipe's status", function()
	stubs.containers = { [0] = { { FEATHER, 200 }, { LINEN, 200 } } }
	local ns = boot()
	local met = 0
	for recipeID in pairs(ns.Recipes) do
		local status = ns.Tracker:GetStatus({ kind = "recipe", id = recipeID, need = 1 })
		eq(ns.Tracker:HasReagents(recipeID), status.met, "recipe " .. recipeID)
		if status.met then met = met + 1 end
	end
	eq(met > 0, true, "some recipe is ready")
	eq(ns.Tracker:HasReagents(123456), false, "unknown recipe")
end)

-- Tracker -------------------------------------------------------------------

test("with nothing tracked, data changes queue no tracker work", function()
	local ns = boot()
	stubs.runTimers()
	local redraws = 0
	ns:RegisterMessage("TRACKER_CHANGED", function() redraws = redraws + 1 end)
	ns:Fire("CHAR_DATA_CHANGED")
	stubs.runTimers()
	eq(redraws, 0, "no redraw")
end)

-- Item data -----------------------------------------------------------------

test("the tracking list ignores item data it didn't ask for", function()
	local ns = boot()
	ns.TrackerUI:Open()
	stubs.runTimers()
	local refreshes = 0
	local getRows = ns.Tracker.GetRows
	ns.Tracker.GetRows = function(...)
		refreshes = refreshes + 1
		return getRows(...)
	end
	stubs.fire("ITEM_DATA_LOAD_RESULT", 777777, true)
	stubs.runTimers()
	eq(refreshes, 0, "someone else's item")
	ns.Browser:GetItemName(888888)
	stubs.fire("ITEM_DATA_LOAD_RESULT", 888888, true)
	stubs.runTimers()
	eq(refreshes, 1, "our item")
end)

test("a burst of item data rebuilds the browser once a second", function()
	local ns = boot()
	ns.Browser:Open()
	local builds = 0
	local build = ns.Browser.BuildRows
	ns.Browser.BuildRows = function(...)
		builds = builds + 1
		return build(...)
	end
	ns.Browser:GetItemName(888888)
	for _ = 1, 15 do
		stubs.fire("ITEM_DATA_LOAD_RESULT", 888888, true)
		stubs.runTimers(0.1)
	end
	stubs.runTimers()
	eq(builds, 2, "1.5 seconds of arrivals")
end)

-- Prices --------------------------------------------------------------------

test("an item's age is asked once while the price stays live", function()
	local prices = { [12359] = 70000 }
	local api = fakeAuctionator(prices, { [12359] = 2 })
	local P = boot().Pricing
	eq(select(2, P:GetPrice(12359)), 2, "age")
	prices[12359] = 80000
	local price, age = P:GetPrice(12359)
	eq(price, 80000, "new price")
	eq(age, 2, "same age")
	eq(api.ageCalls, 1, "asked once")
end)

test("a missing age is remembered too", function()
	local api = fakeAuctionator({ [12359] = 70000 }, {})
	local P = boot().Pricing
	P:GetPrice(12359)
	eq(select(2, P:GetPrice(12359)), nil, "no age")
	eq(api.ageCalls, 1, "asked once")
end)

test("ages are asked again after a scan, or after a minute", function()
	local ages = { [12359] = 2 }
	local api = fakeAuctionator({ [12359] = 70000 }, ages)
	local P = boot().Pricing
	P:GetPrice(12359)
	ages[12359] = 0
	api.onUpdate()
	eq(select(2, P:GetPrice(12359)), 0, "scan")
	ages[12359] = 1
	stubs.now = stubs.now + 61
	eq(select(2, P:GetPrice(12359)), 1, "a minute on")
end)

test("a price that a scan shows is stale is dropped", function()
	local ages = { [12359] = 2 }
	local api = fakeAuctionator({ [12359] = 70000 }, ages)
	local P = boot().Pricing
	eq(P:GetPrice(12359), 70000, "fresh")
	ages[12359] = 8
	api.onUpdate()
	eq(P:GetPrice(12359), nil, "stale")
end)

test("an age call that errors still turns the bridge off", function()
	local api = fakeAuctionator({ [12359] = 70000 }, {})
	api.GetAuctionAgeByItemID = function() error("boom") end
	local P = boot().Pricing
	eq(P:GetPrice(12359), nil, "no price")
	eq(P:IsEnabled(), false, "off")
end)

-- Bag pips ------------------------------------------------------------------

test("a pip is repainted only when its tier changes", function()
	local bag = stubs.newBagFrame(0, { true })
	_G.ContainerFrameContainer = { ContainerFrames = { bag } }
	stubs.containers[0] = { { 12360, 2 } }
	local ns = boot()
	ns.BagMarkers:UpdateFrame(bag)
	local fill = bag.buttons[1].ReagentAtlasPip.fill
	local painted = 0
	local paint = fill.SetColorTexture
	fill.SetColorTexture = function(...)
		painted = painted + 1
		return paint(...)
	end
	ns.BagMarkers:UpdateFrame(bag)
	eq(painted, 0, "same tier")
	local tier = ns.Valuation.GetTier
	ns.Valuation.GetTier = function() return 4 end
	ns.BagMarkers:UpdateFrame(bag)
	ns.Valuation.GetTier = tier
	eq(painted, 1, "new tier")
end)
