---@diagnostic disable: undefined-global
-- Phase 4: Auctionator bridge and price-adjusted tiers.
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

-- Installs a fake Auctionator. prices/ages: [itemID] = copper / days.
-- Records the caller IDs it was given.
local function fakeAuctionator(prices, ages)
	local api = { callers = {} }
	function api.GetAuctionPriceByItemID(caller, itemID)
		api.callers[#api.callers + 1] = caller
		return prices[itemID]
	end
	function api.GetAuctionAgeByItemID(caller, itemID)
		api.callers[#api.callers + 1] = caller
		return ages and ages[itemID]
	end
	function api.RegisterForDBUpdate(caller, callback)
		api.callers[#api.callers + 1] = caller
		api.onUpdate = callback
	end
	_G.Auctionator = { API = { v1 = api } }
	return api
end

local function boot(savedVars)
	return T.boot(savedVars, T.useFixture)
end

local function tooltipFor(ns, itemID)
	local tt = stubs.newTooltip()
	ns.Tooltip:AddItemLines(tt, itemID, false)
	return tt:Text()
end

-- AdjustTier with synthetic info, independent of the score weights.
local function info(tier, sell, vendor)
	return { tier = tier, sellPrice = sell, vendor = vendor or false }
end

test("no Auctionator: no price, data tier unchanged", function()
	local ns = boot(nil)
	eq(ns.Pricing:GetPrice(12359), nil, "price")
	local tier, price = ns.Valuation:GetTier(12359)
	eq(tier, ns.Valuation:GetInfo(12359).tier, "tier")
	eq(price, nil, "price from GetTier")
	local text = tooltipFor(ns, 12359)
	eq(text:find("AH", 1, true), nil, "no AH text")
	eq(#stubs.errors, 0, "no errors")
end)

test("Auctionator without API v1 or functions is treated as absent", function()
	local ns = boot(nil)
	_G.Auctionator = {}
	eq(ns.Pricing:GetPrice(12359), nil, "no API table")
	_G.Auctionator = { API = { v1 = {} } }
	eq(ns.Pricing:GetPrice(12359), nil, "no functions")
	eq(#stubs.errors, 0, "no errors")
end)

test("fresh price is returned with its age; caller ID is the addon name", function()
	local api = fakeAuctionator({ [12359] = 15000 }, { [12359] = 2 })
	local ns = boot(nil)
	local price, age = ns.Pricing:GetPrice(12359)
	eq(price, 15000, "price")
	eq(age, 2, "age")
	for _, caller in ipairs(api.callers) do eq(caller, "ReagentAtlas", "caller") end
end)

test("prices older than 7 days, zero or non-numeric are ignored", function()
	fakeAuctionator({ [12359] = 15000, [12360] = 0, [2589] = "lots" }, { [12359] = 8 })
	local ns = boot(nil)
	eq(ns.Pricing:GetPrice(12359), nil, "stale")
	eq(ns.Pricing:GetPrice(12360), nil, "zero")
	eq(ns.Pricing:GetPrice(2589), nil, "string")
end)

test("missing age function still gives a price", function()
	local api = fakeAuctionator({ [12359] = 15000 })
	api.GetAuctionAgeByItemID = nil
	local ns = boot(nil)
	local price, age = ns.Pricing:GetPrice(12359)
	eq(price, 15000, "price")
	eq(age, nil, "age")
end)

test("useAuctionator = false turns prices off", function()
	fakeAuctionator({ [12359] = 15000 })
	local ns = boot({ version = 1, settings = { useAuctionator = false } })
	eq(ns.Pricing:GetPrice(12359), nil, "price")
	stubs.slash("/ratlas", "version")
	contains(table.concat(stubs.printed, "\n"), "turned off in settings", "status")
end)

test("an Auctionator error disables the bridge for the session, once", function()
	local api = fakeAuctionator({ [12359] = 15000 })
	local ns = boot(nil)
	api.GetAuctionPriceByItemID = function() error("boom") end
	stubs.printed = {}
	eq(ns.Pricing:GetPrice(12359), nil, "first call")
	api.GetAuctionPriceByItemID = function() return 15000 end
	eq(ns.Pricing:GetPrice(12359), nil, "stays off")
	local out = table.concat(stubs.printed, "\n")
	contains(out, "disabled for this session", "notice")
	eq(select(2, out:gsub("disabled for this session", "")), 1, "printed once")
	-- The tooltip still renders without a price.
	contains(tooltipFor(ns, 12359), "Reagent Atlas:", "tooltip")
	stubs.printed = {}
	stubs.slash("/ratlas", "version")
	contains(table.concat(stubs.printed, "\n"), "off after an error", "status")
	eq(#stubs.errors, 0, "no Lua errors")
end)

test("DB update callback fires PRICES_CHANGED", function()
	local api = fakeAuctionator({})
	local ns = boot(nil)
	local fired = 0
	ns:RegisterMessage("PRICES_CHANGED", function() fired = fired + 1 end)
	assert(api.onUpdate, "registered")
	api.onUpdate()
	eq(fired, 1, "fired")
end)

test("AdjustTier: raise one step at 5x vendor price and at least 1g", function()
	local ns = boot(nil)
	local V = ns.Valuation
	eq(V:AdjustTier(info(2, 1000), 5000), 2, "5x but under 1g")
	eq(V:AdjustTier(info(2, 1000), 10000), 3, "10x and 1g")
	eq(V:AdjustTier(info(2, 2500), 10000), 2, "1g but only 4x")
	eq(V:AdjustTier(info(5, 100), 99999), 5, "Keep! stays Keep!")
	eq(V:AdjustTier(info(4, 100), 99999), 5, "Valuable -> Keep!")
	eq(V:AdjustTier(info(1, 100), 20000), 2, "Vendor -> Common")
end)

test("AdjustTier: below vendor price caps at Common", function()
	local V = boot(nil).Valuation
	eq(V:AdjustTier(info(5, 1000), 999), 2, "Keep! -> Common")
	eq(V:AdjustTier(info(1, 1000), 999), 1, "Vendor stays Vendor")
end)

test("AdjustTier: vendor-sold reagents stay capped; no sell price means no change", function()
	local V = boot(nil).Valuation
	eq(V:AdjustTier(info(2, 100, true), 50000), 2, "vendor item")
	eq(V:AdjustTier(info(2, nil), 50000), 2, "no sell price")
	eq(V:AdjustTier(info(2, 0), 50000), 2, "zero sell price")
	eq(V:AdjustTier(info(3, 100), nil), 3, "no price")
end)

test("tooltip shows the adjusted tier, the price and its age", function()
	fakeAuctionator({ [12359] = 123456 }, { [12359] = 3 })
	local ns = boot(nil)
	local base = ns.Valuation:GetInfo(12359).tier
	local tier = ns.Valuation:GetTier(12359)
	eq(tier, math.min(base + 1, 4), "raised")
	local text = tooltipFor(ns, 12359)
	contains(text, "Reagent Atlas: " .. ns.Valuation:GetTierName(tier) .. " · AH 12g 34s 56c (3 days old)", "tier line")
end)

test("price seen today shows no age", function()
	fakeAuctionator({ [12359] = 700 }, { [12359] = 0 })
	local ns = boot(nil)
	local text = tooltipFor(ns, 12359)
	contains(text, "· AH 7s\n", "price without age")
end)

test("FormatMoney text fallback", function()
	local P = boot(nil).Pricing
	eq(P:FormatMoney(0), "0c", "zero")
	eq(P:FormatMoney(5), "5c", "copper")
	eq(P:FormatMoney(10000), "1g", "gold")
	eq(P:FormatMoney(10203), "1g 2s 3c", "mixed")
end)

-- Waylaid Crates ------------------------------------------------------------

local CRATE = 800001

-- Fixture data plus one crate: 20x A, 10x B, 5x C (vendor-sold), 4x D.
local function bootCrate()
	local ns = T.boot(nil, function(ns)
		T.useFixture(ns)
		ns.Crates = { [CRATE] = { { 700001, 20 }, { 700002, 10 }, { 700003, 5 }, { 700004, 4 } } }
		ns.Reagents[700003] = { r = {}, q = 1, sell = 10, vendor = true, buy = 50 }
	end)
	stubs.itemNames[700001], stubs.itemNames[700002] = "Herb A", "Herb B"
	stubs.itemNames[700003], stubs.itemNames[700004] = "Thread C", "Shard D"
	return ns
end

local function crateTooltip(ns, expanded)
	local tt = stubs.newTooltip()
	eq(ns.Tooltip:AddItemLines(tt, CRATE, expanded), true, "crate annotated")
	return tt:Text()
end

test("crate options: cheapest first, vendor price when lower, unpriced last", function()
	fakeAuctionator({ [700001] = 100, [700002] = 150, [700003] = 80 }, { [700002] = 2 })
	local ns = bootCrate()
	ns.db.account.bank = { [700004] = 9 }
	local options = ns.Pricing:GetCrateOptions(CRATE)
	eq(#options, 4, "all bundles")
	eq(options[1].itemID, 700003, "vendor 5x50 = 250 first")
	eq(options[1].cost, 250, "vendor cost")
	eq(options[1].vendor, true, "vendor flag")
	eq(options[2].itemID, 700002, "10x150 = 1500")
	eq(options[2].age, 2, "age kept")
	eq(options[3].itemID, 700001, "20x100 = 2000")
	eq(options[4].itemID, 700004, "no price last")
	eq(options[4].cost, nil, "unpriced")
	eq(options[4].have, 9, "owned count")
	eq(ns.Pricing:GetCrateOptions(12359), nil, "not a crate")
end)

test("crate options: AH cheaper than vendor wins; stale prices are unpriced", function()
	fakeAuctionator({ [700003] = 20, [700001] = 5 }, { [700001] = 9 })
	local ns = bootCrate()
	local options = ns.Pricing:GetCrateOptions(CRATE)
	eq(options[1].itemID, 700003, "AH 5x20")
	eq(options[1].cost, 100, "AH cost")
	eq(options[1].vendor, nil, "not vendor")
	eq(options[2].cost, nil, "stale price ignored")
end)

test("crate tooltip: top 3 collapsed, all with Shift", function()
	fakeAuctionator({ [700001] = 100, [700002] = 150 }, { [700002] = 2 })
	local ns = bootCrate()
	ns.db.account.bank = { [700001] = 32 }
	local text = crateTooltip(ns, false)
	contains(text, "Reagent Atlas: Fill with any one, cheapest first", "header")
	contains(text, "5x Thread C | 2s 50c", "vendor first, no note collapsed")
	contains(text, "10x Herb B | 15s\n", "no age collapsed")
	contains(text, "20x Herb A (have 32) | 20s", "owned count")
	contains(text, "1 more · Hold Shift for all", "more hint")
	eq(text:find("Shard D", 1, true), nil, "4th hidden")
	text = crateTooltip(ns, true)
	contains(text, "5x Thread C | 2s 50c (vendor)", "vendor note")
	contains(text, "10x Herb B | 15s (2 days old)", "age")
	contains(text, "4x Shard D | no price", "unpriced")
	eq(text:find("Hold Shift", 1, true), nil, "no hint expanded")
	eq(#stubs.errors, 0, "no errors")
end)

test("crate tooltip without Auctionator: vendor prices only, with a note", function()
	local ns = bootCrate()
	local text = crateTooltip(ns, true)
	contains(text, "5x Thread C | 2s 50c (vendor)", "vendor priced")
	contains(text, "20x Herb A | no price", "no AH price")
	contains(text, "Auction prices need Auctionator", "note")
end)

test("real data: every crate renders and its reagents have names in the data", function()
	local ns = T.boot(nil)
	local crates = 0
	for crateID, bundles in pairs(ns.Crates) do
		crates = crates + 1
		eq(#bundles >= 2, true, "bundles of " .. crateID)
		local tt = stubs.newTooltip()
		eq(ns.Tooltip:AddItemLines(tt, crateID, true), true, "renders " .. crateID)
	end
	if ns.DATA_BUILD ~= "sample" then eq(crates, 30, "crate count") end
	eq(#stubs.errors, 0, "no errors")
end)
