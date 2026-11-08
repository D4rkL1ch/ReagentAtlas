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
