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
