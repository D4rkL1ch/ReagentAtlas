local addonName, ns = ...

local Pricing = ns:RegisterModule("Pricing", {})

local MAX_AGE_DAYS = 7 -- older Auctionator prices are ignored (SPEC.md > Auctionator bridge)

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

-- Auction price in copper and its age in days (nil if Auctionator doesn't
-- say), or nil when there is no fresh price.
function Pricing:GetPrice(itemID)
	if not itemID or not self:IsEnabled() then return nil end
	local ok, price = Call("GetAuctionPriceByItemID", itemID)
	if not ok or type(price) ~= "number" or price <= 0 then return nil end
	local age
	ok, age = Call("GetAuctionAgeByItemID", itemID)
	if brokenReason then return nil end
	if type(age) ~= "number" then
		age = nil
	elseif age > MAX_AGE_DAYS then
		return nil
	end
	return price, age
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
	-- Optional: newer Auctionator versions notify after a scan. Nothing is
	-- cached here; the message lets UI refresh (bag markers, browser).
	Call("RegisterForDBUpdate", function()
		ns:Fire("PRICES_CHANGED")
	end)
end
