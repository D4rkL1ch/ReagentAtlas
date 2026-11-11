local addonName, ns = ...

local Pricing = ns:RegisterModule("Pricing", {})

local MAX_AGE_DAYS = 7 -- older Auctionator prices are ignored (SPEC.md > Auctionator bridge)
local AH_CUT = 0.05    -- share of a sale the auction house keeps
local AGE_CACHE_SECONDS = 60

-- Set when an Auctionator call errors; the bridge stays off for the session.
local brokenReason

local function API()
	local a = Auctionator
	return type(a) == "table" and type(a.API) == "table" and type(a.API.v1) == "table" and a.API.v1 or nil
end

local function Disable(err)
	if brokenReason then return end
	brokenReason = tostring(err)
	ns:Print("Auctionator prices disabled for this session after an error: " .. brokenReason)
end

-- Calls Auctionator.API.v1[name](addonName, ...) in pcall. Returns ok, result.
local function Call(name, ...)
	local api = API()
	local fn = api and api[name]
	if type(fn) ~= "function" then return false end
	local ok, result = pcall(fn, addonName, ...)
	if not ok then
		Disable(result)
		return false
	end
	return true, result
end

function Pricing:IsEnabled()
	return not brokenReason and ns.db.settings.useAuctionator and API() ~= nil
end

-- Days since an item was last seen on the AH, or nil. Auctionator sorts the
-- item's whole price history to work this out, and a list asks about hundreds
-- of items on every refresh, so answers are kept for a while. Age counts in
-- days: only a scan changes it sooner, and a scan clears these.
local ages = {} -- itemID -> days, false if Auctionator has no answer
local agesSince = 0

local function GetAge(itemID)
	local now = GetTime()
	if now - agesSince > AGE_CACHE_SECONDS then
		wipe(ages)
		agesSince = now
	end
	local age = ages[itemID]
	if age == nil then
		local _, result = Call("GetAuctionAgeByItemID", itemID)
		age = type(result) == "number" and result or false
		ages[itemID] = age
	end
	return age or nil
end

-- Auction price in copper and its age in days (nil if Auctionator doesn't
-- say), or nil when there is no fresh price.
function Pricing:GetPrice(itemID)
	if not itemID or not self:IsEnabled() then return nil end
	local ok, price = Call("GetAuctionPriceByItemID", itemID)
	if not ok or type(price) ~= "number" or price <= 0 then return nil end
	local age = GetAge(itemID)
	if brokenReason or (age and age > MAX_AGE_DAYS) then return nil end
	return price, age
end

-- AH price of an item, through a table shared across one pass over the
-- recipes: a list asks about the same reagents many times.
local function Lookup(itemID, cache)
	local price = cache[itemID]
	if price == nil then
		price = Pricing:GetPrice(itemID) or false
		cache[itemID] = price
	end
	return price or nil
end

-- What one item of a reagent costs: the vendor if it sells it, or the AH if
-- that's cheaper; nil without either price.
local function ReagentCost(itemID, cache)
	local reagent = ns.Reagents[itemID]
	local vendor = reagent and reagent.buy
	local ah = Lookup(itemID, cache)
	if vendor and ah then return math.min(vendor, ah) end
	return vendor or ah
end

-- Cheapest first; options without a price last, most owned first, then in
-- the crate's own order.
local function ByCost(a, b)
	if (a.cost ~= nil) ~= (b.cost ~= nil) then return a.cost ~= nil end
	if a.cost and a.cost ~= b.cost then return a.cost < b.cost end
	if not a.cost and a.have ~= b.have then return a.have > b.have end
	return a.order < b.order
end

-- Ways to fill a Waylaid Crate (any one bundle), cheapest first, or nil if
-- the item isn't one. Each option:
--   itemID, count  the bundle
--   cost    copper to buy the whole bundle; nil without a fresh price
--   vendor  true when the cost is the vendor price
--   age     days since Auctionator saw the AH price used, when known
--   have    owned across the account
--   order   position in the crate's own list
function Pricing:GetCrateOptions(crateID)
	local bundles = ns.Crates and ns.Crates[crateID]
	if not bundles then return nil end
	local options = {}
	for i, bundle in ipairs(bundles) do
		local itemID, count = bundle[1], bundle[2]
		local reagent = ns.Reagents[itemID]
		local vendor = reagent and reagent.buy
		local ah, age = self:GetPrice(itemID)
		local option = { itemID = itemID, count = count, have = ns.Inventory:GetTotal(itemID), order = i }
		if vendor and not (ah and ah < vendor) then
			option.cost, option.vendor = vendor * count, true
		elseif ah then
			option.cost, option.age = ah * count, age
		end
		options[i] = option
	end
	table.sort(options, ByCost)
	return options
end

-- Value of one craft, in copper:
--   cost      all reagents, nil unless every one has a price
--   unpriced  how many reagents have none
--   sale      what the output lists for on the AH, for all items a craft makes
--   profit    sale less the AH cut less cost; nil unless both are known
-- Listing deposits aren't included. cache is optional, see Lookup.
function Pricing:GetCraftValue(recipeID, cache)
	cache = cache or {}
	local recipe = ns.Recipes[recipeID]
	local cost, unpriced = 0, 0
	for itemID, count in pairs(recipe.reagents) do
		local price = ReagentCost(itemID, cache)
		if price then
			cost = cost + price * count
		else
			unpriced = unpriced + 1
		end
	end
	local value = { cost = unpriced == 0 and cost or nil, unpriced = unpriced }
	local price = recipe.out and Lookup(recipe.out, cache)
	if price then
		value.sale = price * (recipe.n or 1)
		if value.cost then
			value.profit = math.floor(value.sale * (1 - AH_CUT)) - value.cost
		end
	end
	return value
end

-- "12g 40s" with coin icons; plain text if the client lacks the helper.
function Pricing:FormatMoney(copper)
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		local ok, text = pcall(C_CurrencyInfo.GetCoinTextureString, copper)
		if ok and type(text) == "string" then return text end
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end

-- One line for /ratlas version.
function Pricing:StatusText()
	if brokenReason then
		return "|cffff5555off after an error|r (" .. brokenReason .. ")"
	elseif API() then
		return ns.db.settings.useAuctionator and "Auctionator API v1" or "Auctionator found, turned off in settings"
	elseif C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Auctionator") then
		return "|cffff5555Auctionator is loaded but has no API v1|r"
	end
	return "none (Auctionator not loaded)"
end

function Pricing:OnLogin()
	-- Optional: newer Auctionator versions notify after a scan. The message
	-- lets UI refresh (bag markers, browser).
	Call("RegisterForDBUpdate", function()
		wipe(ages)
		ns:Fire("PRICES_CHANGED")
	end)
end
