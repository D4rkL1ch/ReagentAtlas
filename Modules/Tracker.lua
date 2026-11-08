local addonName, ns = ...

local Tracker = ns:RegisterModule("Tracker", {})

-- Items moved between bags and bank are counted twice or not at all until the
-- bank scan catches up (Inventory.BANK_SCAN_DELAY, 0.2s), so goals are checked
-- only once the counts have been quiet for this long.
local SETTLE_DELAY = 0.5
-- Bags can read as partly empty right after login. Checking then would re-arm
-- a met goal and alert again on every login.
local LOGIN_DELAY = 5

local FALLBACK_SOUND = 888 -- level-up fanfare, if the client lacks the constant
local ALERT_COLOR = { r = 0.12, g = 1, b = 0 }

-- Goal ----------------------------------------------------------------------

local function ItemName(itemID)
	return ns.Browser:GetItemName(itemID) or ("Item #" .. itemID)
end

local function ByItemID(a, b)
	return a.itemID < b.itemID
end

-- Counts for an entry:
--   item    { have, need (nil = no goal), met }
--   recipe  { reagents = array of { itemID, have, need }, met }; need is
--           multiplied by the entry's number of crafts
function Tracker:GetStatus(entry)
	if entry.kind == "item" then
		local have = ns.Inventory:GetTotal(entry.id)
		return { have = have, need = entry.need, met = entry.need ~= nil and have >= entry.need }
	end
	local recipe = ns.Recipes[entry.id]
	local reagents, met = {}, recipe ~= nil
	for itemID, count in pairs(recipe and recipe.reagents or {}) do
		local need = count * entry.need
		local have = ns.Inventory:GetTotal(itemID)
		reagents[#reagents + 1] = { itemID = itemID, have = have, need = need }
		met = met and have >= need
	end
	table.sort(reagents, ByItemID)
	return { reagents = reagents, met = met }
end

-- Whether you own enough for one craft: GetStatus().met without building its
-- rows, for filtering whole lists.
function Tracker:HasReagents(recipeID)
	local recipe = ns.Recipes[recipeID]
	if not recipe then return false end
	for itemID, count in pairs(recipe.reagents) do
		if ns.Inventory:GetTotal(itemID) < count then return false end
	end
	return true
end

-- Marks an entry met or not without alerting: changing the list yourself is
-- not news, and only a later gain should make a sound.
local function Sync(entry)
	entry.done = entry.need ~= nil and Tracker:GetStatus(entry).met or nil
end

-- List ----------------------------------------------------------------------

function Tracker:GetEntries()
	return ns.db.tracked
end

function Tracker:Find(kind, id)
	for _, entry in ipairs(ns.db.tracked) do
		if entry.kind == kind and entry.id == id then return entry end
	end
	return nil
end

-- Set of items the list is after: tracked reagents and what tracked recipes use.
function Tracker:GetNeededItems()
	local needed = {}
	for _, entry in ipairs(ns.db.tracked) do
		if entry.kind == "item" then
			needed[entry.id] = true
		else
			local recipe = ns.Recipes[entry.id]
			for itemID in pairs(recipe and recipe.reagents or {}) do needed[itemID] = true end
		end
	end
	return needed
end

-- kind is "item" (a reagent) or "recipe". Reagents start without a goal,
-- recipes with one craft. Returns the entry, or nil for unknown IDs.
function Tracker:Add(kind, id)
	local entry = self:Find(kind, id)
	if entry then return entry end
	if not ((kind == "item" and ns.Reagents[id]) or (kind == "recipe" and ns.Recipes[id])) then
		return nil
	end
	entry = { kind = kind, id = id, need = kind == "recipe" and 1 or nil }
	Sync(entry)
	table.insert(ns.db.tracked, entry)
	ns:Fire("TRACKER_CHANGED")
	return entry
end

function Tracker:Remove(kind, id)
	for i, entry in ipairs(ns.db.tracked) do
		if entry.kind == kind and entry.id == id then
			table.remove(ns.db.tracked, i)
			ns:Fire("TRACKER_CHANGED")
			return
		end
	end
end

-- Returns true if the entry is tracked after the call.
function Tracker:Toggle(kind, id)
	if self:Find(kind, id) then
		self:Remove(kind, id)
		return false
	end
	return self:Add(kind, id) ~= nil
end

-- Sets how many of a reagent you need, or how many crafts of a recipe. Empty
-- or zero clears a reagent's goal and puts a recipe back to one craft.
function Tracker:SetNeed(entry, count)
	count = count and math.floor(count) or 0
	if count > 0 then
		entry.need = count
	else
		entry.need = entry.kind == "recipe" and 1 or nil
	end
	Sync(entry)
	ns:Fire("TRACKER_CHANGED")
end

function Tracker:SetCollapsed(entry, collapsed)
	entry.collapsed = collapsed or nil
	ns:Fire("TRACKER_CHANGED")
end

-- Rows ----------------------------------------------------------------------

-- Appends who knows the recipe, or else where to get it. Returns true if any
-- of that is unconfirmed source data.
function Tracker:AddRecipeInfo(rows, recipeID)
	local isMe, alts = ns.Professions:GetKnownBy(recipeID)
	if isMe or #alts > 0 then
		rows[#rows + 1] = {
			type = "info", recipeID = recipeID, known = isMe and "me" or "alt",
			text = "Known by " .. ns.Tooltip:FormatNames(isMe, alts),
		}
		return false
	end
	local lines, unconfirmed = ns.Sources:GetDetailLines(recipeID)
	for _, line in ipairs(lines) do
		rows[#rows + 1] = { type = "info", recipeID = recipeID, text = line }
	end
	return unconfirmed
end

-- The window's list, flattened: an entry row per entry, then for recipes one
-- row per reagent and per source line unless collapsed.
function Tracker:GetRows()
	local rows, unconfirmed = {}, false
	for _, entry in ipairs(ns.db.tracked) do
		local status = self:GetStatus(entry)
		if entry.kind == "item" then
			rows[#rows + 1] = {
				type = "entry", entry = entry, status = status, name = ItemName(entry.id), itemID = entry.id,
			}
		else
			local recipe = ns.Recipes[entry.id]
			if recipe and recipe.out then ns.Browser:GetItemName(recipe.out) end -- cached for links
			rows[#rows + 1] = {
				type = "entry", entry = entry, status = status, name = ns.Tooltip:GetRecipeName(entry.id),
			}
			if not entry.collapsed then
				for _, reagent in ipairs(status.reagents) do
					rows[#rows + 1] = {
						type = "reagent", itemID = reagent.itemID, name = ItemName(reagent.itemID),
						have = reagent.have, need = reagent.need,
					}
				end
				if recipe then
					unconfirmed = self:AddRecipeInfo(rows, entry.id) or unconfirmed
				end
			end
		end
	end
	if unconfirmed then
		rows[#rows + 1] = { type = "note", text = ns.Sources.UNCONFIRMED_NOTE }
	end
	return rows
end

-- Shopping list -------------------------------------------------------------

local function SortedKeys(map)
	local keys = {}
	for key in pairs(map) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

-- The recipe to make an item you're short of: one of yours if you have it,
-- else an alt's. Nil means it has to be bought, farmed or looted: nobody knows
-- a recipe, it's sold by vendors, or the recipe only converts another material.
local function CraftRoute(itemID)
	local reagent = ns.Reagents[itemID]
	if reagent and reagent.vendor then return nil end
	local route
	for _, recipeID in ipairs((ns.Tooltip:GetRecipesFor(itemID))) do
		if not ns.Recipes[recipeID].conv then
			local isMe, alts = ns.Professions:GetKnownBy(recipeID)
			if isMe then return recipeID end
			if #alts > 0 then route = route or recipeID end
		end
	end
	return route
end

-- Fills a demand from stock, then by crafting, then as missing. Stock is
-- spent as it goes, so an item is never counted for two demands, and what a
-- batch makes beyond the demand serves the next one. path guards against
-- recipe loops.
local function Allocate(plan, itemID, count, path)
	local stock = plan.stock[itemID]
	if not stock then
		stock = ns.Inventory:GetTotal(itemID)
	end
	local used = math.min(stock, count)
	plan.stock[itemID] = stock - used
	local short = count - used
	if short == 0 then return end

	local recipeID = CraftRoute(itemID)
	if not recipeID or path[recipeID] then
		plan.missing[itemID] = (plan.missing[itemID] or 0) + short
		return
	end
	local recipe = ns.Recipes[recipeID]
	local made = recipe.n or 1
	local crafts = math.ceil(short / made)
	plan.crafts[recipeID] = (plan.crafts[recipeID] or 0) + crafts
	plan.stock[itemID] = plan.stock[itemID] + crafts * made - short
	path[recipeID] = true
	for _, reagentID in ipairs(SortedKeys(recipe.reagents)) do
		Allocate(plan, reagentID, recipe.reagents[reagentID] * crafts, path)
	end
	path[recipeID] = nil
end

-- What all tracked recipes need together. Unlike the list itself, where each
-- entry counts on its own, reagents are shared out here. Reagent goals aren't
-- included: they may be for the same recipes, and adding them would double up.
--   totals   itemID -> reagents needed by tracked recipes
--   missing  itemID -> count to buy, farm or loot
--   crafts   recipeID -> crafts needed to make reagents you're short of
function Tracker:GetShoppingPlan()
	local plan = { totals = {}, missing = {}, crafts = {}, stock = {} }
	for _, entry in ipairs(ns.db.tracked) do
		local recipe = entry.kind == "recipe" and ns.Recipes[entry.id]
		if recipe then
			for itemID, count in pairs(recipe.reagents) do
				plan.totals[itemID] = (plan.totals[itemID] or 0) + count * entry.need
			end
		end
	end
	for _, itemID in ipairs(SortedKeys(plan.totals)) do
		Allocate(plan, itemID, plan.totals[itemID], {})
	end
	return plan
end

-- The shopping view's rows, what to do first: get, craft, then the totals.
function Tracker:GetShoppingRows()
	local plan = self:GetShoppingPlan()
	local rows = {}
	local missing = SortedKeys(plan.missing)
	table.sort(missing, function(a, b)
		local nameA, nameB = ItemName(a), ItemName(b)
		if nameA ~= nameB then return nameA < nameB end
		return a < b
	end)
	if #missing > 0 then
		rows[#rows + 1] = { type = "head", text = "Still to get" }
	end
	for _, itemID in ipairs(missing) do
		local reagent = ns.Reagents[itemID]
		rows[#rows + 1] = {
			type = "shop", itemID = itemID, name = ItemName(itemID), count = plan.missing[itemID],
			vendor = reagent ~= nil and reagent.vendor == true,
		}
	end

	local crafts = SortedKeys(plan.crafts)
	table.sort(crafts, function(a, b)
		local skillA, skillB = ns.Recipes[a].skill, ns.Recipes[b].skill
		if skillA ~= skillB then return skillA < skillB end
		return a < b
	end)
	if #crafts > 0 then
		rows[#rows + 1] = { type = "head", text = "Craft first" }
	end
	for _, recipeID in ipairs(crafts) do
		local isMe, alts = ns.Professions:GetKnownBy(recipeID)
		rows[#rows + 1] = {
			type = "craft", recipeID = recipeID, name = ns.Tooltip:GetRecipeName(recipeID),
			count = plan.crafts[recipeID], who = ns.Tooltip:FormatNames(isMe, alts), mine = isMe,
		}
	end

	local totals = SortedKeys(plan.totals)
	if #totals > 0 then
		if #missing == 0 and #crafts == 0 then
			rows[#rows + 1] = { type = "note", text = "You have everything for your tracked recipes." }
		end
		rows[#rows + 1] = { type = "head", text = "All reagents" }
	end
	for _, itemID in ipairs(totals) do
		rows[#rows + 1] = {
			type = "reagent", itemID = itemID, name = ItemName(itemID),
			have = ns.Inventory:GetTotal(itemID), need = plan.totals[itemID],
		}
	end
	return rows
end

-- Alerts --------------------------------------------------------------------

local function AlertText(entry)
	if entry.kind == "item" then
		return ("You have enough %s (%d)"):format(ItemName(entry.id), entry.need)
	end
	local name = ns.Tooltip:GetRecipeName(entry.id)
	if entry.need > 1 then
		return ("You have the reagents for %s x%d"):format(name, entry.need)
	end
	return ("You have the reagents for %s"):format(name)
end

local function Notify(completed)
	for _, entry in ipairs(completed) do
		ns:Print(AlertText(entry))
	end
	local text = #completed == 1 and AlertText(completed[1]) or ("%d tracked goals met"):format(#completed)
	local sound = ns.db.settings.trackerSound and (SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE or FALLBACK_SOUND)
	ns:ShowAlert(text, ALERT_COLOR, sound)
end

-- Alerts on goals that became met; goals that fell short again re-arm. done is
-- saved, so a goal met once doesn't alert again on the next login.
function Tracker:Check()
	local completed = {}
	for _, entry in ipairs(ns.db.tracked) do
		if entry.need then
			local met = self:GetStatus(entry).met
			if met and not entry.done then
				completed[#completed + 1] = entry
			end
			entry.done = met or nil
		end
	end
	if #completed > 0 then Notify(completed) end
end

-- Lifecycle -----------------------------------------------------------------

local settled = false -- false until LOGIN_DELAY has passed
local generation = 0

-- Runs once, SETTLE_DELAY after the last change. With nothing tracked there is
-- nothing to check or redraw.
local function QueueUpdate()
	if #ns.db.tracked == 0 then return end
	generation = generation + 1
	local mine = generation
	C_Timer.After(SETTLE_DELAY, function()
		if mine ~= generation then return end
		if settled then Tracker:Check() end
		ns:Fire("TRACKER_CHANGED")
	end)
end

function Tracker:OnInit()
	ns:RegisterMessage("CHAR_DATA_CHANGED", QueueUpdate)
end

function Tracker:OnLogin()
	C_Timer.After(LOGIN_DELAY, function()
		settled = true
		QueueUpdate()
	end)
end
