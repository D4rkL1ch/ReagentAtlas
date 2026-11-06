local addonName, ns = ...

local Inventory = ns:RegisterModule("Inventory", {})

local BANK_SCAN_DELAY = 0.2 -- seconds; slot events arrive in bursts

-- Backpack, bags 1-4 and the reagent bag (Enum.BagIndex 0-5 in Forever).
local BAG_IDS = { 0, 1, 2, 3, 4, 5 }
-- Fallback bank tab bag IDs if C_Bank can't list the purchased tabs.
local CHARACTER_BANK_TABS = { 6, 7, 8, 9, 10, 11, 12, 13, 14 }
local ACCOUNT_BANK_TABS = { 15, 16, 17, 18, 19, 20, 21, 22, 23 }

-- The item in a slot, or nil. GetContainerItemInfo builds a table per call, so
-- it's only used where the client lacks the ID-only call.
function Inventory:GetSlotItem(bag, slot)
	if C_Container.GetContainerItemID then
		return C_Container.GetContainerItemID(bag, slot)
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	return info and info.itemID
end

-- Counts of reagents (items in ns.Reagents) in the given containers. Other
-- items are skipped to keep the saved file small.
local function CountContainers(bagIDs)
	local counts = {}
	for _, bag in ipairs(bagIDs) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local itemID = Inventory:GetSlotItem(bag, slot)
			if itemID and ns.Reagents[itemID] then
				local info = C_Container.GetContainerItemInfo(bag, slot)
				counts[itemID] = (counts[itemID] or 0) + (info and info.stackCount or 1)
			end
		end
	end
	return counts
end

local function BankTabIDs(bankTypeName, fallback)
	local bankType = Enum.BankType and Enum.BankType[bankTypeName]
	if bankType and C_Bank and C_Bank.FetchPurchasedBankTabIDs then
		local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, bankType)
		if ok and type(ids) == "table" then return ids end
	end
	return fallback
end

local function CanViewAccountBank()
	if not (Enum.BankType and C_Bank and C_Bank.CanViewBank) then return false end
	local ok, canView = pcall(C_Bank.CanViewBank, Enum.BankType.Account)
	return ok and canView
end

-- Scanning ------------------------------------------------------------------

-- Stores a scan and returns whether it differs: moving items around or looting
-- something that isn't a reagent shouldn't rebuild every open list.
local function Store(owner, field, counts)
	if owner[field] and ns.SameTable(owner[field], counts) then return false end
	owner[field] = counts
	return true
end

function Inventory:ScanBags()
	local char = ns:GetCharData()
	if not char then return end
	if Store(char, "bags", CountContainers(BAG_IDS)) then
		ns:Fire("CHAR_DATA_CHANGED", ns.INVENTORY_ONLY)
	end
end

local bankOpen = false

-- The bank is only readable while the bank frame is open; the counts are
-- kept until the next visit.
function Inventory:ScanBank()
	if not bankOpen then return end
	local char = ns:GetCharData()
	if not char then return end
	local changed = Store(char, "bank", CountContainers(BankTabIDs("Character", CHARACTER_BANK_TABS)))
	if CanViewAccountBank() then
		changed = Store(ns.db.account, "bank", CountContainers(BankTabIDs("Account", ACCOUNT_BANK_TABS))) or changed
	end
	if changed then ns:Fire("CHAR_DATA_CHANGED", ns.INVENTORY_ONLY) end
end

local bankScanQueued = false
local function QueueBankScan()
	if not bankOpen or bankScanQueued then return end
	bankScanQueued = true
	C_Timer.After(BANK_SCAN_DELAY, function()
		bankScanQueued = false
		Inventory:ScanBank()
	end)
end

-- Lookup --------------------------------------------------------------------

-- Owned count of an item across the account, warband bank included. For lists
-- and goals, which ask about many items and need nothing else.
function Inventory:GetTotal(itemID)
	local bank = ns.db.account.bank
	local total = bank and bank[itemID] or 0
	for _, char in pairs(ns.db.chars) do
		total = total + (char.bags and char.bags[itemID] or 0) + (char.bank and char.bank[itemID] or 0)
	end
	return total
end

-- Owned counts of an item across the account, with who holds them. Returns:
--   total     number including the warband bank
--   holders   array of { key, bags, bank, total, isMe }, current character
--             first, then by total descending
--   warband   count in the account-wide warband bank
function Inventory:GetCounts(itemID)
	local me = ns:GetCharKey()
	local holders, total = {}, 0
	for key, char in pairs(ns.db.chars) do
		local bags = char.bags and char.bags[itemID] or 0
		local bank = char.bank and char.bank[itemID] or 0
		if bags + bank > 0 then
			holders[#holders + 1] = { key = key, bags = bags, bank = bank, total = bags + bank, isMe = key == me }
			total = total + bags + bank
		end
	end
	table.sort(holders, function(a, b)
		if a.isMe ~= b.isMe then return a.isMe end
		if a.total ~= b.total then return a.total > b.total end
		return a.key < b.key
	end)
	local warband = ns.db.account.bank and ns.db.account.bank[itemID] or 0
	return total + warband, holders, warband
end

-- Lifecycle -----------------------------------------------------------------

function Inventory:OnLogin()
	self:ScanBags()
	ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
		Inventory:ScanBags()
		QueueBankScan() -- bank tabs are containers too and fire the same event
	end)
	ns:RegisterEvent("BANKFRAME_OPENED", function()
		bankOpen = true
		QueueBankScan()
	end)
	ns:RegisterEvent("BANKFRAME_CLOSED", function()
		bankOpen = false
	end)
	ns:RegisterEvent("PLAYERBANKSLOTS_CHANGED", QueueBankScan)
	ns:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", QueueBankScan)
end
