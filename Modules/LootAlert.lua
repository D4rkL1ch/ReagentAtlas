local addonName, ns = ...

local LootAlert = ns:RegisterModule("LootAlert", {})

local BATCH_DELAY = 0.3 -- seconds; one loot window sends a message per item
local COOLDOWN = 600    -- seconds before the same item alerts again (farming)
local MAX_RECIPES = 3   -- recipe names per character before "+N"
local MAX_CRAFTERS = 3  -- character lines before "and N more"

local FALLBACK_SOUND = 8959 -- raid warning, if the client lacks the constant

-- Loot messages -------------------------------------------------------------

-- "You receive loot: %sx%d." -> "^You receive loot: (.+)x(%d+)%.$". Positional
-- tokens ("%1$s") in some locales are reduced to plain ones.
local function ToPattern(fmt)
	fmt = fmt:gsub("%%%d%$", "%%")
	local pattern = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. pattern .. "$"
end

local patterns

-- Only your own loot. Pushed items (quest rewards, vendor purchases) and
-- crafted ones use other strings, so they're left out: you chose those.
local function BuildPatterns()
	patterns = {
		ToPattern(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d."), -- before the single one, which would match it too
		ToPattern(LOOT_ITEM_SELF or "You receive loot: %s."),
	}
end

-- itemID, link and count of an item you looted, or nil for any other message.
function LootAlert:ParseLoot(text)
	if not patterns then BuildPatterns() end
	for _, pattern in ipairs(patterns) do
		local link, count = text:match(pattern)
		local itemID = link and tonumber(link:match("item:(%d+)"))
		if itemID then
			return itemID, link, tonumber(count) or 1
		end
	end
	return nil
end

-- Describing ----------------------------------------------------------------

local function PriceText(itemID)
	local price = ns.Pricing:GetPrice(itemID)
	return price and (" · AH " .. ns.Pricing:FormatMoney(price)) or ""
end

-- Characters that know recipes using the item: array of { key, isMe, recipes },
-- you first, then whoever knows the most. Recipes keep the data order, highest
-- skill first.
function LootAlert:GetCrafters(itemID)
	local byKey, crafters = {}, {}
	local me = ns:GetCharKey()
	local function Add(key, recipeID)
		local crafter = byKey[key]
		if not crafter then
			crafter = { key = key, isMe = key == me, recipes = {} }
			byKey[key] = crafter
			crafters[#crafters + 1] = crafter
		end
		crafter.recipes[#crafter.recipes + 1] = recipeID
	end
	for _, recipeID in ipairs(ns.Reagents[itemID].r) do
		if ns.Recipes[recipeID] then
			local isMe, alts = ns.Professions:GetKnownBy(recipeID)
			if isMe then Add(me, recipeID) end
			for _, key in ipairs(alts) do Add(key, recipeID) end
		end
	end
	table.sort(crafters, function(a, b)
		if a.isMe ~= b.isMe then return a.isMe end
		if #a.recipes ~= #b.recipes then return #a.recipes > #b.recipes end
		return a.key < b.key
	end)
	return crafters
end

local COLOR_YOURS = "ff1eff00" -- as in the tooltip: green for you, blue for alts
local COLOR_ALT = "ff66b3ff"
local COLOR_NONE = "ff9d9d9d"

-- "Brewdin can craft Arcanite Reaper, Arcanite Rod +2"
local function CrafterLine(crafter)
	local names = {}
	for i = 1, math.min(#crafter.recipes, MAX_RECIPES) do
		names[i] = ns.Tooltip:GetRecipeName(crafter.recipes[i])
	end
	local text = table.concat(names, ", ")
	if #crafter.recipes > MAX_RECIPES then
		text = text .. (" +%d"):format(#crafter.recipes - MAX_RECIPES)
	end
	local who = crafter.isMe and "You" or ns:CharDisplayName(crafter.key)
	return WrapTextInColorCode(("%s can craft %s"):format(who, text), crafter.isMe and COLOR_YOURS or COLOR_ALT)
end

-- A recipe item is news when one of your characters could learn it.
local function DescribeRecipe(itemID, link)
	local _, taught = ns.Tooltip:GetRecipesFor(itemID)
	for _, recipeID in ipairs(taught) do
		local learners = ns.Professions:GetLearners(recipeID)
		if #learners > 0 then
			local text, mine = ns.Tooltip:FormatLearners(learners)
			local details = { WrapTextInColorCode(text, mine and COLOR_YOURS or COLOR_ALT) }
			local isMe, alts = ns.Professions:GetKnownBy(recipeID)
			if isMe or #alts > 0 then
				details[2] = WrapTextInColorCode("Known by " .. ns.Tooltip:FormatNames(isMe, alts), COLOR_NONE)
			end
			return { itemID = itemID, title = link .. PriceText(itemID), details = details }
		end
	end
	return nil
end

-- A reagent is news at or above the minimum tier, with who can craft what.
local function DescribeReagent(itemID, link, count)
	if not ns.Valuation:GetInfo(itemID) then return nil end
	local tier = ns.Valuation:GetTier(itemID)
	if tier < ns.db.settings.lootMinTier then return nil end
	local looted = count > 1 and ("%sx%d"):format(link, count) or link
	local title = ("%s: %s%s"):format(looted, ns.Valuation:ColorTier(tier), PriceText(itemID))
	local details = {}
	local crafters = LootAlert:GetCrafters(itemID)
	for i = 1, math.min(#crafters, MAX_CRAFTERS) do
		details[i] = CrafterLine(crafters[i])
	end
	if #crafters > MAX_CRAFTERS then
		details[#details + 1] = WrapTextInColorCode(("and %d more characters"):format(#crafters - MAX_CRAFTERS), COLOR_NONE)
	elseif #crafters == 0 then
		details[1] = WrapTextInColorCode("None of your characters knows a recipe using it", COLOR_NONE)
	end
	return { itemID = itemID, title = title, details = details }
end

-- The alert for a looted item, or nil if it isn't worth one:
-- { itemID, title = link with tier or price, details = lines below it }.
function LootAlert:Describe(itemID, link, count)
	return DescribeRecipe(itemID, link) or DescribeReagent(itemID, link, count or 1)
end

-- Alerting ------------------------------------------------------------------

local pending = {}
local lastAlert = {} -- itemID -> GetTime() of its last alert, session only

-- One notice and sound per loot window, listing each item; chat keeps them.
local function Flush()
	local alerts = pending
	pending = {}
	for _, alert in ipairs(alerts) do
		ns:Print("Looted " .. alert.title)
		for _, line in ipairs(alert.details) do print("  " .. line) end
	end
	ns.LootToast:Show(alerts)
	ns:PlayAlertSound(ns.db.settings.lootSound and (SOUNDKIT and SOUNDKIT.RAID_WARNING or FALLBACK_SOUND))
end


-- Queues an alert for a loot message. Returns what happened, for lootdebug.
local function HandleLoot(text)
	if not ns.db.settings.lootAlerts then return "loot alerts are off" end
	-- Chat text can be a secret value in restricted content; never read one.
	if issecretvalue and issecretvalue(text) then return "secret text, skipped" end
	if type(text) ~= "string" then return "not text: " .. type(text) end
	local itemID, link, count = LootAlert:ParseLoot(text)
	if not itemID then return "not your loot (no match)" end
	local now = GetTime()
	if lastAlert[itemID] and now - lastAlert[itemID] < COOLDOWN then
		return ("item %d: on cooldown"):format(itemID)
	end
	local alert = LootAlert:Describe(itemID, link, count)
	if not alert then
		local tier = ns.Valuation:GetTier(itemID)
		if tier then
			return ("item %d: %s, below the minimum %s"):format(itemID, ns.Valuation:GetTierName(tier),
				ns.Valuation:GetTierName(ns.db.settings.lootMinTier))
		end
		return ("item %d: not a reagent or learnable recipe"):format(itemID)
	end
	lastAlert[itemID] = now
	pending[#pending + 1] = alert
	if #pending == 1 then C_Timer.After(BATCH_DELAY, Flush) end
	return ("item %d: alert"):format(itemID)
end

local debugging = false -- session only, /ratlas lootdebug

local function OnLoot(_, text)
	local result = HandleLoot(text)
	if debugging then
		local raw = type(text) == "string" and not (issecretvalue and issecretvalue(text))
			and text:gsub("|", "||") or "?"
		ns:Print(("loot: %s -> %s"):format(raw, result))
	end
end

-- Lifecycle -----------------------------------------------------------------

function LootAlert:OnInit()
	ns:RegisterCommand("lootdebug", "lootdebug - print every loot message and why it did or didn't alert", function()
		debugging = not debugging
		ns:Print(debugging and "loot debug on: loot something." or "loot debug off.")
	end)
end

function LootAlert:OnLogin()
	ns:RegisterEvent("CHAT_MSG_LOOT", OnLoot)
end
