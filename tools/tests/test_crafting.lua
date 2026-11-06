---@diagnostic disable: undefined-global
-- The browser's Crafting tab: the recipe and crafted item list, and the jumps
-- between it and the Reagents tab.
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

local NAMES = {
	[2589] = "Linen Cloth", [17056] = "Light Feather", [12360] = "Arcanite Bar",
	[20725] = "Nexus Crystal", [2604] = "Red Dye", [2996] = "Bolt of Linen Cloth",
	[1251] = "Linen Bandage", [990104] = "Feathered Sash", [880101] = "Arcanite Reaper",
}

-- The player knows the Feathered Sash recipe, Frostia an Arcanite one, and
-- Brewdin holds 20 Light Feathers.
local function saved()
	return {
		version = 1,
		chars = {
			["Tester-StubRealm"] = {
				class = "PRIEST",
				profs = { [197] = { rank = 225, known = { [990004] = true } } },
				bags = {}, bank = {},
			},
			["Brewdin-StubRealm"] = {
				class = "PRIEST", profs = {}, bags = { [17056] = 20 }, bank = {},
			},
			["Frostia-StubRealm"] = {
				class = "MAGE",
				profs = { [164] = { rank = 300, known = { [880001] = true } } },
				bags = {}, bank = {},
			},
		},
	}
end

local function boot(savedVars)
	for id, name in pairs(NAMES) do stubs.itemNames[id] = name end
	return T.boot(savedVars or saved(), T.useFixture)
end

local function filters(over)
	local f = { search = "", prof = 0, known = false, ready = false }
	for k, v in pairs(over or {}) do f[k] = v end
	return f
end

local function ids(rows)
	local out = {}
	for i, row in ipairs(rows) do out[i] = row.recipeID end
	return table.concat(out, ",")
end

local function findWidget(pred)
	for _, w in ipairs(stubs.allWidgets()) do
		if pred(w) then return w end
	end
end

local function button(label)
	return findWidget(function(w) return w.kind == "Button" and w.text == label end)
end

local function click(w) w.scripts.OnClick(w) end

local function openTab(ns)
	stubs.slash("/ratlas", "")
	click(button("Crafting"))
	return ns
end

local function recipeList()
	return findWidget(function(w) return w.template == "WowScrollBoxList" and w.rows and w.rows[1] and w.rows[1].Info end)
end

local function recipeRow(recipeID)
	for _, r in ipairs(recipeList().rows) do
		if r.recipeID == recipeID then return r end
	end
end

local function detailList()
	return findWidget(function(w)
		return w.template == "WowScrollBoxList" and w.provider and w.provider.list[1]
			and w.provider.list[1].type == "head"
	end)
end

-- Model ---------------------------------------------------------------------

test("lists every recipe, highest skill first", function()
	local ns = boot()
	local rows = ns.CraftingUI:BuildRows(filters())
	eq(#rows, 11, "all recipes")
	eq(rows[1].recipeID, 880001, "skill 300 first")
	eq(rows[#rows].skill, 1, "skill 1 last")
end)

test("search finds the crafted item and the recipe, whichever differs", function()
	local ns = boot()
	-- A smelting-style recipe: its spell is not named after its item.
	ns.Recipes[770001] = { prof = 186, skill = 1, out = 2589, outQ = 1, reagents = {} }
	stubs.spellNames[770001] = "Weave Something"
	eq(ids(ns.CraftingUI:BuildRows(filters({ search = "weave" }))), "770001", "by recipe")
	eq(ns.CraftingUI:BuildRows(filters({ search = "weave" }))[1].name, "Linen Cloth", "row shows the item")
	eq(ids(ns.CraftingUI:BuildRows(filters({ search = "linen cloth" }))), "2963,770001", "by item")
	stubs.spellNames[770001] = nil
end)

test("a recipe with no crafted item is listed by its recipe name", function()
	local ns = boot()
	ns.Recipes[770002] = { prof = 333, skill = 100, reagents = { [2589] = 1 } }
	stubs.spellNames[770002] = "Enchant Boots"
	local rows = ns.CraftingUI:BuildRows(filters({ search = "enchant boots" }))
	eq(rows[1].name, "Enchant Boots", "name")
	eq(rows[1].itemID, nil, "no item")
	local detail = ns.CraftingUI:GetDetail(770002)
	eq(detail.recipeName, nil, "the name is not repeated")
	eq(detail.isReagent, false, "not a reagent")
	stubs.spellNames[770002] = nil
end)

test("filters: profession, known by anyone, reagents in hand", function()
	local ns = boot()
	eq(ids(ns.CraftingUI:BuildRows(filters({ prof = 164 }))), "880001,880002", "profession")
	local known = ns.CraftingUI:BuildRows(filters({ known = true }))
	eq(ids(known), "880001,990004", "known by me or an alt")
	eq(known[1].known, "alt", "alt")
	eq(known[2].known, "me", "me")
	-- 20 feathers cover every feather recipe; nothing else is owned.
	local ready = ns.CraftingUI:BuildRows(filters({ ready = true }))
	eq(#ready, 7, "reagents in hand")
	for _, row in ipairs(ready) do
		assert(ns.Recipes[row.recipeID].reagents[17056], "uses feathers")
	end
end)

test("detail shows the reagents with have / need, then who knows it", function()
	local ns = boot()
	local detail = ns.CraftingUI:GetDetail(990004)
	eq(detail.name, "Feathered Sash", "crafted item")
	local rows = detail.rows
	eq(rows[1].text, "Reagents", "heading")
	eq(rows[2].itemID, 17056, "reagent")
	eq(rows[2].have, 20, "have")
	eq(rows[2].need, 3, "need")
	eq(rows[3].text, "Recipe", "heading")
	contains(rows[4].text, "Known by", "who")
end)

-- Window --------------------------------------------------------------------

test("the Crafting tab swaps panes and is remembered", function()
	local db = saved()
	local ns = boot(db)
	stubs.slash("/ratlas", "")
	local reagentPane = button("Tracking list").parent
	eq(button("Reagents").enabled, false, "starts on Reagents")
	click(button("Crafting"))
	eq(reagentPane.shown, false, "reagents hidden")
	eq(button("Crafting").enabled, false, "tab marked")
	eq(#recipeList().provider.list, 11, "recipes listed")
	assert(findWidget(function(w) return w.kind == "FontString" and type(w.text) == "string" and w.text:find("11 of 11 recipes", 1, true) end), "subtitle")
	eq(db.ui.browserTab, "crafting", "saved")
	click(button("Reagents"))
	eq(reagentPane.shown, true, "reagents back")
	eq(#stubs.errors, 0, "no errors")
	eq(ns.Browser:IsShown(), true, "still open")
end)

test("clicking a recipe shows what it takes; a reagent jumps to its tab", function()
	local ns = openTab(boot())
	local row = recipeRow(990004)
	click(row)
	eq(row.Selected.shown, true, "row highlighted")
	local title = findWidget(function(w) return type(w.text) == "string" and w.text:find("Feathered Sash", 1, true) and w.parent.kind == "Frame" end)
	assert(title, "detail title")
	local reagentRow
	for _, r in ipairs(detailList().rows) do
		if r.data.type == "reagent" then reagentRow = r end
	end
	contains(reagentRow.Count.text, "20 / 3", "have / need")
	click(reagentRow)
	eq(ns.db.ui.browserTab, "reagents", "switched")
	local where = findWidget(function(w) return w.kind == "FontString" and type(w.text) == "string" and w.text:find("Where it is", 1, true) end)
	contains(where.text, "Bags 20", "reagent detail")
end)

test("a recipe row on the Reagents tab opens that recipe", function()
	local ns = boot()
	stubs.slash("/ratlas", "")
	ns.Browser:Select(17056)
	local list = findWidget(function(w) return w.template == "WowScrollBoxList" and w.rows and w.rows[1] and w.rows[1].Recipe end)
	local row
	for _, r in ipairs(list.rows) do
		if r.recipeID == 990004 then row = r end
	end
	click(row)
	eq(ns.db.ui.browserTab, "crafting", "switched")
	eq(detailList().provider.list[2].itemID, 17056, "that recipe")
end)

test("a crafted item that is also a reagent links to it", function()
	local ns = boot()
	ns.Recipes[770003] = { prof = 164, skill = 200, out = 12360, outQ = 2, reagents = {} }
	openTab(ns)
	local go = button("Used as reagent")
	ns.CraftingUI:Select(990004)
	eq(go.shown, false, "hidden when not a reagent")
	ns.CraftingUI:Select(770003)
	eq(go.shown, true, "shown")
	click(go)
	eq(ns.db.ui.browserTab, "reagents", "switched")
end)

test("data arriving keeps the scroll; new filters and recipes start at the top", function()
	local ns = openTab(boot())
	local list = recipeList()
	ns.CraftingUI:Select(990004)
	local detail = detailList()
	list.scroll, detail.scroll = 300, 20
	local before = list.provider
	ns:Fire("CHAR_DATA_CHANGED")
	stubs.runTimers()
	assert(list.provider ~= before, "rebuilt")
	eq(list.scroll, 300, "list kept")
	eq(detail.scroll, 20, "detail kept")

	ns.CraftingUI:Select(990001)
	eq(detail.scroll, 0, "new recipe from the top")

	local known = findWidget(function(w) return w.template == "UICheckButtonTemplate" and w.parent == list.parent end)
	known:SetChecked(true)
	click(known)
	eq(list.scroll, 0, "new filter from the top")
end)

test("Track toggles the recipe and follows the tracking list", function()
	local ns = openTab(boot())
	ns.CraftingUI:Select(990004)
	local track = findWidget(function(w) return w.text == "Track" and w.parent.parent == recipeList().parent.parent end)
	click(track)
	assert(ns.Tracker:Find("recipe", 990004), "tracked")
	eq(track.text, "Untrack", "label")
	ns.Tracker:Remove("recipe", 990004)
	eq(track.text, "Track", "follows removal")
end)

test("every recipe in the generated data lists and opens", function()
	local ns = T.boot(nil)
	stubs.slash("/ratlas", "")
	click(button("Crafting"))
	local rows = ns.CraftingUI:BuildRows(filters())
	local total = 0
	for _ in pairs(ns.Recipes) do total = total + 1 end
	eq(#rows, total, "all listed")
	for _, row in ipairs(rows) do
		ns.CraftingUI:Select(row.recipeID)
	end
	eq(#stubs.errors, 0, "no errors")
end)

-- Value ---------------------------------------------------------------------

local function fakePrices(prices)
	_G.Auctionator = { API = { v1 = {
		GetAuctionPriceByItemID = function(_, itemID) return prices[itemID] end,
		GetAuctionAgeByItemID = function() return 0 end,
	} } }
end

test("a craft value adds reagents, takes the AH cut and counts every item made", function()
	local ns = boot()
	ns.Recipes[770004] = { prof = 164, skill = 100, out = 770104, outQ = 1, n = 5, reagents = { [12360] = 2, [2604] = 3 } }
	ns.Reagents[2604].buy = 10
	fakePrices({ [12360] = 1000, [770104] = 1000 })
	local value = ns.Pricing:GetCraftValue(770004)
	eq(value.cost, 2030, "2 bars at 10s, 3 dye at the vendor")
	eq(value.sale, 5000, "5 items")
	eq(value.profit, 2720, "95% of the sale less cost")
end)

test("a vendor reagent uses the AH price when that is lower", function()
	local ns = boot()
	ns.Recipes[770005] = { prof = 164, skill = 100, out = 770105, outQ = 1, reagents = { [2604] = 1 } }
	ns.Reagents[2604].buy = 10
	fakePrices({ [2604] = 4 })
	eq(ns.Pricing:GetCraftValue(770005).cost, 4, "cheaper on the AH")
end)

test("a reagent with no price leaves cost and profit unknown", function()
	local ns = boot()
	fakePrices({ [880101] = 90000, [12360] = 1000 })
	local value = ns.Pricing:GetCraftValue(880001)
	eq(value.cost, nil, "no cost")
	eq(value.unpriced, 2, "nexus and dye")
	eq(value.sale, 90000, "sale still known")
	eq(value.profit, nil, "no profit")
end)

test("the profit sort puts the best first and unknowns after, by skill", function()
	local ns = boot()
	fakePrices({ [2589] = 10, [2996] = 100, [1251] = 15 })
	local rows = ns.CraftingUI:BuildRows(filters({ sort = "profit" }))
	eq(rows[1].recipeID, 2963, "bolt: 95 less 20")
	eq(rows[1].profit, 75, "profit")
	eq(rows[2].recipeID, 3275, "bandage: 14 less 10")
	eq(rows[3].profit, nil, "no profit after that")
	eq(rows[3].recipeID, 880001, "then by skill")
end)

test("no lookups for the skill sort, and no prices means no value rows", function()
	local ns = boot()
	local asked = 0
	_G.Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() asked = asked + 1 end } } }
	ns.CraftingUI:BuildRows(filters())
	eq(asked, 0, "no lookups")
	_G.Auctionator = nil
	for _, row in ipairs(ns.CraftingUI:GetDetail(990004).rows) do
		assert(row.type ~= "value", "no value rows without Auctionator")
	end
	eq(#ns.CraftingUI:BuildRows(filters({ sort = "profit" })), 11, "profit sort still lists all")
end)

test("the detail pane shows the value and the list shows the profit", function()
	local ns = boot()
	fakePrices({ [2589] = 10, [2996] = 100 })
	stubs.slash("/ratlas", "")
	click(button("Crafting"))
	ns.CraftingUI:GetFilters().sort = "profit"
	ns.CraftingUI:Refresh()
	contains(recipeList().rows[1].Info.text, "+", "signed profit")
	ns.CraftingUI:Select(2963)
	local labels = {}
	for _, row in ipairs(detailList().provider.list) do
		if row.type == "value" then labels[#labels + 1] = row.text end
	end
	eq(table.concat(labels, ","), "Cost per craft,Sells for,Profit after AH cut", "rows")
	eq(#stubs.errors, 0, "no errors")
end)

test("every real recipe values without errors, with prices on everything", function()
	local ns = T.boot(nil)
	_G.Auctionator = { API = { v1 = {
		GetAuctionPriceByItemID = function(_, itemID) return itemID % 977 + 1 end,
		GetAuctionAgeByItemID = function() return 0 end,
	} } }
	local rows = ns.CraftingUI:BuildRows(filters({ sort = "profit" }))
	assert(rows[1].profit ~= nil, "profits")
	for i = 2, #rows do
		if rows[i - 1].profit and rows[i].profit then
			assert(rows[i - 1].profit >= rows[i].profit, "sorted")
		end
	end
	eq(#stubs.errors, 0, "no errors")
end)

-- Can learn -----------------------------------------------------------------

test("can learn needs the profession, the skill and not knowing it", function()
	local ns = boot()
	ns.RecipeSources = { [990004] = { i = 9004, req = 200 }, [990005] = { i = 9005, req = 226 } }
	-- The player has Tailoring 225 and knows 990004 (saved above); Frostia has
	-- Blacksmithing 300 and knows 880001.
	local rows = ns.CraftingUI:BuildRows(filters({ learnable = true }))
	local got = {}
	for _, row in ipairs(rows) do got[row.recipeID] = true end
	eq(got[990004], nil, "already known")
	eq(got[990005], nil, "needs 226, has 225")
	eq(got[880001], nil, "known by Frostia")
	eq(got[880002], true, "Frostia has the skill")
	eq(got[990001], nil, "nobody has Leatherworking")
end)

test("a trainer recipe has no recipe item, so its yellow skill stands in", function()
	local ns = boot()
	ns.RecipeSources = {}
	local learners = ns.Professions:GetLearners(990005)
	eq(learners[1].need, 180, "yellow skill")
	eq(learners[1].ready, true, "225 is enough")
end)

test("the detail pane says who could learn it", function()
	local ns = boot()
	ns.RecipeSources = { [880002] = { i = 9002, req = 310 } }
	local rows = ns.CraftingUI:GetDetail(880002).rows
	contains(rows[#rows].text, "Could learn: Frostia (300/310)", "rank and requirement")
end)
