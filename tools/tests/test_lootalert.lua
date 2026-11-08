---@diagnostic disable: undefined-global
-- Loot alerts: looted recipes your characters could learn, valuable reagents.
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

local FEATHER, ARCANITE, LINEN_CLOTH = 17056, 12360, 2589
local POWDER = 17020 -- a spell reagent no recipe uses
local PATTERN = 9001    -- teaches 990004 (Tailoring 225)
local BS_PATTERN = 9002 -- teaches 880002 (Blacksmithing)

local function link(itemID, name)
	return ("|cff1eff00|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(itemID, name)
end

local toasts

local function loot(itemID, name, count)
	local text = count and ("You receive loot: %sx%d."):format(link(itemID, name), count)
		or ("You receive loot: %s."):format(link(itemID, name))
	stubs.fire("CHAT_MSG_LOOT", text, "Tester")
end

local function chars()
	return {
		version = 2,
		chars = {
			["Tester-StubRealm"] = { class = "MAGE", profs = { [197] = { rank = 200, known = { [990005] = true } } }, bags = {}, bank = {} },
			["Brewdin-StubRealm"] = { class = "PRIEST", profs = {
				[197] = { rank = 225, known = { [990004] = true } },
				[165] = { rank = 300, known = { [990001] = true, [990002] = true } },
			}, bags = {}, bank = {} },
			["Smithy-StubRealm"] = { class = "WARRIOR", profs = { [164] = { rank = 300, known = { [880001] = true } } }, bags = {}, bank = {} },
		},
	}
end

local function boot(savedVars)
	stubs.spellNames[990001] = "Feathered Jerkin"
	stubs.spellNames[990002] = "Feathered Boots"
	stubs.spellNames[990004] = "Feathered Cloak"
	stubs.spellNames[990005] = "Feather Charm"
	stubs.spellNames[880001] = "Arcanite Reaper"
	local ns = T.boot(savedVars or chars(), T.useFixture)
	ns.RecipeSources = { [990004] = { i = PATTERN }, [880002] = { i = BS_PATTERN, req = 260 } }
	stubs.printed, stubs.notices, stubs.sounds = {}, {}, {}
	toasts = {}
	local show = ns.LootToast.Show
	ns.LootToast.Show = function(self, alerts)
		toasts[#toasts + 1] = alerts
		return show(self, alerts)
	end
	return ns
end

local function strip(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"))
end

-- Toast i as text: each item's title, then its details.
local function toast(i)
	local out = {}
	for _, alert in ipairs(toasts[i]) do
		out[#out + 1] = alert.title
		for _, line in ipairs(alert.details) do out[#out + 1] = line end
	end
	return strip(table.concat(out, "\n"))
end

local function chat()
	return (table.concat(stubs.printed, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"))
end

-- Parsing -------------------------------------------------------------------

test("loot messages: single, stacked, and everything else", function()
	local ns = boot()
	local L = ns.LootAlert
	local id, l, count = L:ParseLoot("You receive loot: " .. link(FEATHER, "Light Feather") .. ".")
	eq(id, FEATHER, "single id")
	eq(count, 1, "single count")
	eq(l, link(FEATHER, "Light Feather"), "link")
	id, _, count = L:ParseLoot("You receive loot: " .. link(FEATHER, "Light Feather") .. "x12.")
	eq(id, FEATHER, "stack id")
	eq(count, 12, "stack count")
	eq(L:ParseLoot("Brewdin receives loot: " .. link(FEATHER, "Light Feather") .. "."), nil, "someone else's")
	eq(L:ParseLoot("You receive item: " .. link(FEATHER, "Light Feather") .. "."), nil, "pushed item")
	eq(L:ParseLoot("You create: " .. link(FEATHER, "Light Feather") .. "."), nil, "crafted")
end)

test("the client's localized loot strings are used, positional tokens too", function()
	_G.LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
	_G.LOOT_ITEM_SELF_MULTIPLE = "Ihr erhaltet Beute: %1$sx%2$d."
	local ns = boot()
	local id, _, count = ns.LootAlert:ParseLoot("Ihr erhaltet Beute: " .. link(FEATHER, "Leichte Feder") .. "x3.")
	_G.LOOT_ITEM_SELF, _G.LOOT_ITEM_SELF_MULTIPLE = nil, nil
	eq(id, FEATHER, "id")
	eq(count, 3, "count")
end)

-- Recipes -------------------------------------------------------------------

test("a looted recipe says who could learn it and who knows it", function()
	boot()
	loot(PATTERN, "Pattern: Feathered Cloak")
	eq(#toasts, 0, "batched")
	stubs.runTimers()
	eq(#toasts, 1, "one notice")
	contains(toast(1), "Could learn: you (200/225)", "on screen")
	eq(#stubs.notices, 0, "no raid warning")
	local text = chat()
	contains(text, "Looted [Pattern: Feathered Cloak]", "header")
	contains(text, "Could learn: you (200/225)", "learners with rank")
	contains(text, "Known by Brewdin", "known")
	eq(#stubs.sounds, 1, "sound")
end)

test("a recipe for an alt names the alt", function()
	boot()
	loot(BS_PATTERN, "Plans: Something")
	stubs.runTimers()
	contains(toast(1), "Could learn: Smithy (300)", "on screen")
	contains(chat(), "Could learn: Smithy (300)", "rank")
end)

test("a recipe nobody can learn stays quiet", function()
	local saved = chars()
	saved.chars["Smithy-StubRealm"] = nil
	boot(saved)
	loot(BS_PATTERN, "Plans: Something")
	stubs.runTimers()
	eq(#toasts, 0, "no notice")
	eq(#stubs.printed, 0, "no chat")
end)

-- Reagents ------------------------------------------------------------------

test("a reagent below the minimum tier stays quiet", function()
	local ns = boot()
	assert(ns.Valuation:GetTier(LINEN_CLOTH) < ns.db.settings.lootMinTier, "fixture: linen is low")
	loot(LINEN_CLOTH, "Linen Cloth", 5)
	stubs.runTimers()
	eq(#toasts, 0, "no notice")
end)

test("a valuable reagent lists what each character can craft with it", function()
	local ns = boot()
	ns.db.settings.lootMinTier = ns.Valuation:GetTier(FEATHER)
	loot(FEATHER, "Light Feather", 4)
	stubs.runTimers()
	local text = chat()
	contains(text, "Looted [Light Feather]x4: " .. ns.Valuation:GetTierName(ns.Valuation:GetTier(FEATHER)), "header")
	contains(text, "You can craft Feather Charm", "yours")
	contains(text, "Brewdin can craft Feathered Jerkin, Feathered Boots, Feathered Cloak", "alt, highest skill first")
	contains(toast(1), "Brewdin can craft Feathered Jerkin, Feathered Boots, Feathered Cloak", "on screen")
	assert(text:find("You can craft") < text:find("Brewdin can craft"), "you first")
end)

test("a valuable reagent nobody uses says so", function()
	local ns = boot()
	ns.db.settings.lootMinTier = 1
	loot(POWDER, "Arcane Powder")
	stubs.runTimers()
	contains(chat(), "None of your characters knows a recipe using it", "nobody")
end)

test("the AH price is shown when Auctionator has one", function()
	local ns = boot()
	ns.db.settings.lootMinTier = 1
	_G.Auctionator = { API = { v1 = {
		GetAuctionPriceByItemID = function(_, id) if id == ARCANITE then return 123456 end end,
		GetAuctionAgeByItemID = function() return 0 end,
	} } }
	loot(ARCANITE, "Arcanite Bar")
	stubs.runTimers()
	contains(chat(), "AH", "price")
	contains(chat(), "Smithy can craft Arcanite Reaper", "crafter")
end)

-- Batching, cooldown, settings ----------------------------------------------

test("one loot window gives one notice and one sound, chat lists each", function()
	local ns = boot()
	ns.db.settings.lootMinTier = 1
	loot(FEATHER, "Light Feather")
	loot(ARCANITE, "Arcanite Bar")
	stubs.runTimers()
	eq(#toasts, 1, "one notice")
	eq(#toasts[1], 2, "both in it")
	contains(toast(1), "Light Feather", "first")
	contains(toast(1), "Arcanite Bar", "second")
	eq(#stubs.sounds, 1, "one sound")
	contains(chat(), "Light Feather", "each in chat")
	contains(chat(), "Arcanite Bar", "each in chat")
end)

test("the same item doesn't alert again while farming", function()
	local ns = boot()
	ns.db.settings.lootMinTier = 1
	loot(FEATHER, "Light Feather")
	stubs.runTimers()
	stubs.runTimers(60)
	loot(FEATHER, "Light Feather")
	stubs.runTimers()
	eq(#toasts, 1, "cooldown")
	stubs.runTimers(600)
	loot(FEATHER, "Light Feather")
	stubs.runTimers()
	eq(#toasts, 2, "alerts again later")
end)

test("settings: alerts off, sound off", function()
	local ns = boot()
	ns.db.settings.lootMinTier = 1
	Settings.settings.lootSound:SetValue(false)
	loot(FEATHER, "Light Feather")
	stubs.runTimers()
	eq(#toasts, 1, "shown")
	eq(#stubs.sounds, 0, "silent")
	Settings.settings.lootAlerts:SetValue(false)
	loot(ARCANITE, "Arcanite Bar")
	stubs.runTimers()
	eq(#toasts, 1, "off")
end)

test("secret chat text is never read", function()
	local ns = boot()
	ns.db.settings.lootMinTier = 1
	_G.issecretvalue = function() return true end
	loot(FEATHER, "Light Feather")
	_G.issecretvalue = nil
	stubs.runTimers()
	eq(#toasts, 0, "skipped")
	eq(#stubs.errors, 0, "no errors")
end)

test("lootdebug prints each loot message and why it did or didn't alert", function()
	local ns = boot()
	stubs.slash("/ratlas", "lootdebug")
	loot(LINEN_CLOTH, "Linen Cloth")
	stubs.fire("CHAT_MSG_LOOT", "Brewdin receives loot: " .. link(FEATHER, "Light Feather") .. ".", "Brewdin")
	local text = table.concat(stubs.printed, "\n")
	contains(text, "below the minimum " .. ns.Valuation:GetTierName(ns.db.settings.lootMinTier), "tier reason")
	contains(text, "||Hitem:2589", "raw link shown")
	contains(text, "not your loot", "no match")
	stubs.slash("/ratlas", "lootdebug")
	stubs.printed = {}
	loot(LINEN_CLOTH, "Linen Cloth")
	eq(#stubs.printed, 0, "off again")
end)

-- On-screen toast -------------------------------------------------------------

test("the toast shows each item's icon, title and what to craft, then fades", function()
	local ns = boot()
	ns.db.settings.lootMinTier = 1
	loot(FEATHER, "Light Feather")
	stubs.runTimers()
	local frame = ns.LootToast.frame
	eq(frame:IsShown(), true, "shown")
	local rows = {}
	for _, w in ipairs(stubs.allWidgets()) do
		if w.parent == frame and w.Icon then rows[#rows + 1] = w end
	end
	eq(#rows, 1, "one row")
	eq(rows[1].Icon.texture, 100000 + FEATHER, "icon")
	contains(strip(rows[1].Title.text), "Light Feather", "title")
	contains(strip(rows[1].Body.text), "You can craft Feather Charm\nBrewdin can craft", "details, one per line")
	eq(frame.More:IsShown(), false, "nothing more")
	frame.scripts.OnUpdate(frame, 7.5)
	eq(frame:IsShown(), true, "still up")
	assert(frame:GetAlpha() < 1, "fading")
	frame.scripts.OnUpdate(frame, 1)
	eq(frame:IsShown(), false, "gone")
end)

test("a big loot window shows three items and points to chat for the rest", function()
	local ns = boot()
	ns.db.settings.lootMinTier = 1
	loot(FEATHER, "Light Feather")
	loot(ARCANITE, "Arcanite Bar")
	loot(POWDER, "Arcane Powder")
	loot(12359, "Thorium Bar")
	stubs.runTimers()
	local frame = ns.LootToast.frame
	eq(frame.More:IsShown(), true, "more line")
	eq(frame.More.text, "+1 more, see chat", "count")
	contains(chat(), "Thorium Bar", "all in chat")
	-- A smaller window afterwards hides the extra rows and the more line.
	ns.LootToast:Show({ toasts[1][1] })
	eq(frame.More:IsShown(), false, "more hidden")
	local visible = 0
	for _, w in ipairs(stubs.allWidgets()) do
		if w.parent == frame and w.Icon and w:IsShown() then visible = visible + 1 end
	end
	eq(visible, 1, "one row left")
end)
