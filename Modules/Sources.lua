local addonName, ns = ...

local Sources = ns:RegisterModule("Sources", {})

local WORLD_DROP_ZONES = 8 -- drops spread over this many zones read as a world drop
local MAX_DETAIL_NPCS = 5  -- vendors and creatures listed before "and N more"

Sources.UNCONFIRMED_NOTE = "Sources are Classic-era data, unconfirmed in Forever"

-- NPCs of a list the player's faction can reach, then the others. An empty
-- sides value means no faction restriction is recorded.
local function SplitBySide(npcIDs)
	local side = (UnitFactionGroup("player") or ""):sub(1, 1)
	local reachable, other = {}, {}
	for _, npcID in ipairs(npcIDs) do
		local npc = ns.SourceNPCs[npcID]
		if npc then
			if npc[3] == "" or side == "" or npc[3]:find(side, 1, true) then
				reachable[#reachable + 1] = npc
			else
				other[#other + 1] = npc
			end
		end
	end
	return reachable, other
end

-- "Dustwallow Marsh" or "Dustwallow Marsh +2": the first zone and how many
-- other distinct zones follow.
local function ZoneSummary(npcs)
	local seen, zones = {}, {}
	for _, npc in ipairs(npcs) do
		if npc[2] ~= "" and not seen[npc[2]] then
			seen[npc[2]] = true
			zones[#zones + 1] = npc[2]
		end
	end
	if #zones == 0 then return nil end
	return #zones > 1 and ("%s +%d"):format(zones[1], #zones - 1) or zones[1]
end

local function VendorTag(src)
	local reachable = SplitBySide(src.v)
	if #reachable == 0 then return "Vendor · other faction" end
	local zone = ZoneSummary(reachable)
	return zone and ("Vendor · " .. zone) or "Vendor"
end

local function DropTag(src)
	if src.dn then
		if src.dzn >= WORLD_DROP_ZONES then return "World drop" end
		return src.dz[1] and ("Drop · " .. src.dz[1]) or "Drop"
	end
	local zone = ZoneSummary(Sources:GetNPCs(src.d))
	return zone and ("Drop · " .. zone) or "Drop"
end

-- Vendors you've seen selling recipe items ------------------------------------

-- Who sold a recipe's item in your merchant windows, as { name, zone } arrays
-- in a stable order. Unlike the generated sources, this is Forever itself.
local function SeenVendors(src)
	local list, seen = {}, ns.db.seenVendors[src.i]
	if not seen then return list end
	local ids = {}
	for npcID in pairs(seen) do ids[#ids + 1] = npcID end
	table.sort(ids)
	for i, npcID in ipairs(ids) do list[i] = seen[npcID] end
	return list
end

-- Notes any recipe items the open merchant sells. Only reads the window.
function Sources:ScanMerchant()
	if not (GetMerchantNumItems and GetMerchantItemID and UnitGUID) then return end
	local kind, _, _, _, _, id = strsplit("-", UnitGUID("npc") or "")
	local npcID = tonumber(id)
	if kind ~= "Creature" or not npcID then return end
	local name, zone = UnitName("npc"), GetRealZoneText and GetRealZoneText() or ""
	for i = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(i)
		if itemID and name then
			local _, taught = ns.Tooltip:GetRecipesFor(itemID)
			if #taught > 0 then
				local seen = ns.db.seenVendors[itemID] or {}
				seen[npcID] = { name, zone }
				ns.db.seenVendors[itemID] = seen
			end
		end
	end
end

function Sources:OnInit()
	local function Scan() self:ScanMerchant() end
	ns:RegisterEvent("MERCHANT_SHOW", Scan)
	ns:RegisterEvent("MERCHANT_UPDATE", Scan) -- items can arrive after the window opens
end

-- Short label for a recipe: tag, unconfirmed. Returns nil without source data
-- (a sample build). unconfirmed is true for anything from QuestieDB; the
-- faction requirement comes from the client and a missing recipe item is
-- spelled out as a guess.
function Sources:GetTag(recipeID)
	local all = ns.RecipeSources
	if not all then return nil end
	local src = all[recipeID]
	if not src then return "Trainer (likely)", false end
	local seen = SeenVendors(src)[1]
	if seen then return seen[2] ~= "" and ("Vendor · " .. seen[2]) or "Vendor", false end
	if src.v then return VendorTag(src), true end
	if src.q then return "Quest", true end
	if src.d or src.dn then return DropTag(src), true end
	if src.o then return "Chest or container", true end
	if src.fac then return "Needs " .. src.fac, false end
	return "Source unknown", false
end

function Sources:GetNPCs(npcIDs)
	local npcs = {}
	for _, npcID in ipairs(npcIDs or {}) do
		npcs[#npcs + 1] = ns.SourceNPCs[npcID]
	end
	return npcs
end

local function AddNPCLines(lines, label, npcs)
	for i, npc in ipairs(npcs) do
		if i > MAX_DETAIL_NPCS then
			lines[#lines + 1] = ("...and %d more"):format(#npcs - MAX_DETAIL_NPCS)
			return
		end
		local text = label .. ": " .. npc[1]
		lines[#lines + 1] = npc[2] ~= "" and ("%s (%s)"):format(text, npc[2]) or text
	end
end

-- Everything known about a recipe's source: lines of text, unconfirmed.
function Sources:GetDetailLines(recipeID)
	local all = ns.RecipeSources
	if not all then return {}, false end
	local src = all[recipeID]
	if not src then
		return { "No recipe item exists, so a trainer probably teaches this" }, false
	end

	local lines = {}
	local itemName = ns.Browser:GetItemName(src.i)
	if itemName then lines[1] = "Learned from " .. itemName end

	local seen = SeenVendors(src)
	for i = 1, math.min(#seen, MAX_DETAIL_NPCS) do
		local vendor = seen[i]
		lines[#lines + 1] = vendor[2] ~= "" and ("Seen at %s (%s)"):format(vendor[1], vendor[2]) or ("Seen at " .. vendor[1])
	end

	local unconfirmed = false
	if src.v then
		unconfirmed = true
		local reachable, other = SplitBySide(src.v)
		AddNPCLines(lines, "Vendor", reachable)
		if #other > 0 then
			lines[#lines + 1] = ("Also sold by %d vendor%s of the other faction"):format(#other, #other == 1 and "" or "s")
		end
	end
	for _, quest in ipairs(src.q or {}) do
		unconfirmed = true
		lines[#lines + 1] = "Quest: " .. quest
	end
	if src.d then
		unconfirmed = true
		AddNPCLines(lines, "Drop", self:GetNPCs(src.d))
	elseif src.dn then
		unconfirmed = true
		if src.dzn >= WORLD_DROP_ZONES then
			lines[#lines + 1] = ("World drop: %d creatures in %d zones"):format(src.dn, src.dzn)
		elseif #src.dz > 0 then
			lines[#lines + 1] = ("Drop: %d creatures in %s"):format(src.dn, table.concat(src.dz, ", "))
		else
			lines[#lines + 1] = ("Drop: %d creatures"):format(src.dn)
		end
	end
	if src.o then
		unconfirmed = true
		lines[#lines + 1] = "Found in chests or containers"
	end
	if src.fac then
		lines[#lines + 1] = src.rep and ("Requires %s: %s"):format(src.fac, src.rep) or ("Requires " .. src.fac)
	end
	if not unconfirmed and not src.fac and #seen == 0 then
		lines[#lines + 1] = "Source not mapped for Forever yet"
	end
	return lines, unconfirmed
end
