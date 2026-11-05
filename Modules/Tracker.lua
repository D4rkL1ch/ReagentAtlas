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

-- Counts for an entry:
--   item    { have, need (nil = no goal), met }
--   recipe  { reagents = array of { itemID, have, need }, met }; need is
--           multiplied by the entry's number of crafts
function Tracker:GetStatus(entry)
	if entry.kind == "item" then
		local have = ns.Inventory:GetCounts(entry.id)
		return { have = have, need = entry.need, met = entry.need ~= nil and have >= entry.need }
	end
	local recipe = ns.Recipes[entry.id]
	local reagents, met = {}, recipe ~= nil
	for itemID, count in pairs(recipe and recipe.reagents or {}) do
		local need = count * entry.need
		local have = ns.Inventory:GetCounts(itemID)
		reagents[#reagents + 1] = { itemID = itemID, have = have, need = need }
		met = met and have >= need
	end
	table.sort(reagents, function(a, b) return a.itemID < b.itemID end)
	return { reagents = reagents, met = met }
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

-- Who knows the recipe, or else where to get it.
local function AddRecipeInfo(rows, recipeID)
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
					unconfirmed = AddRecipeInfo(rows, entry.id) or unconfirmed
				end
			end
		end
	end
	if unconfirmed then
		rows[#rows + 1] = { type = "note", text = ns.Sources.UNCONFIRMED_NOTE }
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
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, ALERT_COLOR)
	elseif UIErrorsFrame then
		UIErrorsFrame:AddMessage(text, ALERT_COLOR.r, ALERT_COLOR.g, ALERT_COLOR.b)
	end
	if ns.db.settings.trackerSound and PlaySound then
		-- The Master channel still plays with sound effects turned off.
		pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE or FALLBACK_SOUND, "Master")
	end
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

-- Runs once, SETTLE_DELAY after the last change.
local function QueueUpdate()
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
