---@diagnostic disable: undefined-global
-- Phase 5: browser model and window, bag markers, settings panel.
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

local NAMES = {
	[2589] = "Linen Cloth", [17056] = "Light Feather", [12360] = "Arcanite Bar",
	[12359] = "Thorium Bar", [17020] = "Arcane Powder", [20725] = "Nexus Crystal", [2604] = "Red Dye",
}

-- Brewdin knows a Tailoring recipe using Light Feather and carries 20;
-- Frostia has 5 in the bank.
local function altData()
	return {
		version = 1,
		chars = {
			["Brewdin-StubRealm"] = {
				class = "PRIEST",
				profs = { [197] = { rank = 225, known = { [990004] = true } } },
				bags = { [17056] = 20 }, bank = {},
			},
			["Frostia-OtherRealm"] = {
				class = "MAGE", profs = {}, bags = {}, bank = { [17056] = 5 },
			},
		},
	}
end

local function boot(savedVars)
	for id, name in pairs(NAMES) do stubs.itemNames[id] = name end
	return T.boot(savedVars or altData(), T.useFixture)
end

local function filters(over)
	local f = { search = "", prof = 0, minTier = 1, owned = false, craftable = false }
	for k, v in pairs(over or {}) do f[k] = v end
	return f
end

local function ids(rows)
	local out = {}
	for i, row in ipairs(rows) do out[i] = row.itemID end
	return table.concat(out, ",")
end

local function has(rows, itemID)
	for _, row in ipairs(rows) do
		if row.itemID == itemID then return true end
	end
	return false
end

-- Browser model -------------------------------------------------------------

test("BuildRows: all reagents, best tier first, then by score", function()
	local ns = boot()
	local rows = ns.Browser:BuildRows(filters())
	eq(#rows, 7, "every fixture reagent")
	for i = 2, #rows do
		local a, b = rows[i - 1], rows[i]
		assert(a.tier > b.tier or (a.tier == b.tier and a.score >= b.score),
			("order at %d: %s/%d before %s/%d"):format(i, a.name, a.tier, b.name, b.tier))
	end
end)

test("BuildRows: each filter narrows, and filters combine", function()
	local ns = boot()
	local B = ns.Browser
	eq(ids(B:BuildRows(filters({ prof = 197 }))), "17056,2589", "Tailoring")
	eq(ids(B:BuildRows(filters({ owned = true }))), "17056", "owned")
	eq(ids(B:BuildRows(filters({ craftable = true }))), "17056", "craftable")
	eq(ids(B:BuildRows(filters({ search = "FEATH" }))), "17056", "search, case-insensitive")
	eq(#B:BuildRows(filters({ prof = 164, owned = true })), 0, "Blacksmithing AND owned")
	eq(ids(B:BuildRows(filters({ prof = 197, craftable = true, owned = true }))), "17056", "three filters")
	for _, row in ipairs(B:BuildRows(filters({ minTier = 3 }))) do
		assert(row.tier >= 3, "min tier")
	end
	local all = #B:BuildRows(filters())
	local valuable = #B:BuildRows(filters({ minTier = 3 }))
	assert(valuable < all, "min tier hides lower tiers")
end)

test("BuildRows: uncached names keep their place, skip searches and are requested once", function()
	local ns = boot()
	local function order()
		local ids = {}
		for i, row in ipairs(ns.Browser:BuildRows(filters())) do ids[i] = row.itemID end
		return table.concat(ids, ",")
	end
	local before = order()
	stubs.itemNames[2604] = nil
	eq(order(), before, "rows don't move while a name loads")
	eq(has(ns.Browser:BuildRows(filters({ search = "dye" })), 2604), false, "not matched by search")
	ns.Browser:BuildRows(filters())
	local requests = 0
	for _, id in ipairs(stubs.itemLoads) do if id == 2604 then requests = requests + 1 end end
	eq(requests, 1, "load requested once")
end)

test("BuildRows uses the price-adjusted tier", function()
	_G.Auctionator = { API = { v1 = {
		GetAuctionPriceByItemID = function(_, id) if id == 12359 then return 500000 end end,
	} } }
	local ns = boot()
	local row
	for _, r in ipairs(ns.Browser:BuildRows(filters())) do
		if r.itemID == 12359 then row = r end
	end
	eq(row.tier, math.min(ns.Valuation:GetInfo(12359).tier + 1, 4), "raised by price")
end)

test("BuildRows handles 1,500 reagents quickly", function()
	local ns = boot()
	for i = 1, 1500 do
		local recipeID, itemID = 700000 + i, 600000 + i
		ns.Recipes[recipeID] = { prof = 165, skill = i % 300, out = 1, outQ = 1, reagents = { [itemID] = 1 } }
		ns.Reagents[itemID] = { r = { recipeID }, q = 1 + i % 3, sell = i }
		stubs.itemNames[itemID] = ("Reagent %04d"):format(i)
	end
	local start = os.clock()
	local rows = ns.Browser:BuildRows(filters())
	local elapsed = os.clock() - start
	eq(#rows, 1507, "rows")
	assert(elapsed < 0.5, ("BuildRows took %.3fs"):format(elapsed))
end)

test("GetDetail: recipes marked by who knows them, where the items are", function()
	local ns = boot()
	local d = ns.Browser:GetDetail(17056)
	eq(d.name, "Light Feather", "name")
	eq(d.owned, 25, "owned")
	eq(d.recipeCount, 7, "recipes")
	eq(d.craftable, 1, "craftable")
	eq(table.concat(d.where, "; "), "Bags 20 (Brewdin); Bank 5 (Frostia-OtherRealm)", "where")
	local known = {}
	for _, r in ipairs(d.recipes) do known[r.recipeID] = r.known .. ":" .. r.who end
	eq(known[990004], "alt:Brewdin", "alt recipe")
	eq(known[990001], "none:", "unknown recipe")
	eq(ns.Browser:GetDetail(424242), nil, "not a reagent")
end)

test("profession choices: All first, then by name", function()
	local ns = boot()
	local labels = {}
	for i, c in ipairs(ns.Browser:GetProfessionChoices()) do labels[i] = c.label end
	eq(table.concat(labels, ","), "All,Blacksmithing,Engineering,First Aid,Leatherworking,Tailoring", "choices")
end)

-- Browser window ------------------------------------------------------------

local function open(ns)
	stubs.slash("/ratlas", "")
	return ns.Browser
end

local function findWidget(pred)
	-- Walk every widget created so far (stubs keep them for event dispatch).
	for _, w in ipairs(stubs.allWidgets()) do
		if pred(w) then return w end
	end
end

test("/ratlas toggles the browser and fills the list", function()
	local ns = boot()
	eq(ns.Browser:IsShown(), false, "closed before")
	open(ns)
	eq(ns.Browser:IsShown(), true, "open")
	local list = findWidget(function(w) return w.template == "WowScrollBoxList" and w.provider and #w.provider.list > 0 end)
	assert(list, "list has rows")
	eq(#list.provider.list, 6, "default min tier Useful hides the Vendor-tier rows")
	local first = list.rows[1]
	contains(first.Name.text, list.provider.list[1].name, "row shows the name")
	stubs.slash("/ratlas", "")
	eq(ns.Browser:IsShown(), false, "closed again")
	eq(#stubs.errors, 0, "no errors")
end)

test("clicking a row fills the detail pane", function()
	local ns = boot()
	open(ns)
	local list = findWidget(function(w) return w.template == "WowScrollBoxList" and w.provider and #w.provider.list > 0 end)
	local row
	for _, r in ipairs(list.rows) do
		if r.itemID == 17056 then row = r end
	end
	row.scripts.OnClick(row)
	eq(row.Selected.shown, true, "row highlighted")
	local name = findWidget(function(w) return w.kind == "FontString" and type(w.text) == "string" and w.text:find("Light Feather", 1, true) and w.parent.kind == "Frame" end)
	assert(name, "detail name")
	local where = findWidget(function(w) return w.kind == "FontString" and type(w.text) == "string" and w.text:find("Where it is", 1, true) end)
	contains(where.text, "Bags 20 (Brewdin)", "where line")
end)

local function itemRow(id)
	local list = findWidget(function(w) return w.template == "WowScrollBoxList" and w.rows and w.rows[1] and w.rows[1].Owned end)
	for _, r in ipairs(list.rows) do
		if r.itemID == id then return r end
	end
end

test("modified click on a reagent links it instead of selecting", function()
	local ns = boot()
	open(ns)
	local row = itemRow(17056)
	stubs.modifier = "CHATLINK"
	row.scripts.OnClick(row)
	eq(table.concat(stubs.linked, ","), "item:17056", "linked")
	eq(row.Selected.shown, false, "not selected")
	stubs.modifier = nil
	row.scripts.OnClick(row)
	eq(#stubs.linked, 1, "plain click links nothing")
	eq(row.Selected.shown, true, "plain click selects")
end)

test("modified click on an uncached reagent falls back to selecting", function()
	local ns = boot()
	open(ns)
	local row = itemRow(17056)
	stubs.uncachedItems[17056] = true
	stubs.modifier = "CHATLINK"
	row.scripts.OnClick(row)
	eq(#stubs.linked, 0, "no link yet")
	eq(row.Selected.shown, true, "selected")
end)

test("recipe rows link the crafted item, or the spell for enchants", function()
	local ns = boot()
	ns.Recipes[990050] = { prof = 333, skill = 300, reagents = { [17056] = 1 } }
	stubs.modifier = "CHATLINK"
	eq(ns.Browser:HandleCraftedClick(990001), true, "crafted item")
	eq(ns.Browser:HandleCraftedClick(990050), true, "enchant")
	eq(table.concat(stubs.linked, ","), "item:990101,spell:990050", "links")
	stubs.modifier = nil
	eq(ns.Browser:HandleCraftedClick(990001), false, "plain click")
	eq(ns.Browser:HandleCraftedClick(990050), false, "plain click on an enchant")
	eq(#stubs.linked, 2, "nothing more linked")
end)

test("recipe icons link the recipe item, or the spell for trainer recipes", function()
	local ns = boot()
	ns.RecipeSources = { [990001] = { i = 555 } }
	stubs.modifier = "CHATLINK"
	eq(ns.Browser:HandleRecipeClick(990001), true, "recipe item")
	eq(ns.Browser:HandleRecipeClick(990002), true, "trainer recipe")
	eq(table.concat(stubs.linked, ","), "item:555,spell:990002", "links")
end)

test("each recipe row has its own recipe icon, wired to that recipe", function()
	local ns = boot()
	ns.RecipeSources = { [990001] = { i = 555 } }
	open(ns)
	ns.Browser:Select(17056)
	local list = findWidget(function(w) return w.template == "WowScrollBoxList" and w.rows and w.rows[1] and w.rows[1].Recipe end)
	local byID = {}
	for _, r in ipairs(list.rows) do byID[r.recipeID] = r end
	eq(byID[990001].Recipe.Icon.texture, 100555, "recipe item's icon")
	contains(byID[990002].Recipe.Icon.texture, "INV_Misc_Book", "trainer book")

	local item
	rawset(GameTooltip, "SetItemByID", function(_, id) item = id end)
	local row = byID[990001]
	row.scripts.OnEnter(row)
	eq(item, 990101, "row hover: crafted item")
	row.Recipe.scripts.OnEnter(row.Recipe)
	eq(item, 555, "icon hover: recipe item")
	rawset(GameTooltip, "SetItemByID", nil)

	stubs.modifier = "CHATLINK"
	row.scripts.OnClick(row)
	row.Recipe.scripts.OnClick(row.Recipe)
	eq(table.concat(stubs.linked, ","), "item:990101,item:555", "row links the item, icon the recipe")
end)

test("selecting a reagent preloads crafted and recipe items for their tooltips", function()
	local ns = boot()
	ns.RecipeSources = { [990001] = { i = 555 } }
	ns.Browser:GetDetail(17056)
	local loads = {}
	for _, id in ipairs(stubs.itemLoads) do loads[id] = true end
	eq(loads[990101], true, "crafted item")
	eq(loads[555], true, "recipe item")
end)

test("hovering an enchant previews the spell", function()
	local ns = boot()
	ns.Recipes[990050] = { prof = 333, skill = 300, reagents = { [17056] = 1 } }
	local spell
	rawset(GameTooltip, "SetSpellByID", function(_, id) spell = id end)
	ns.Browser:ShowCrafted({}, 990050, "Enchant")
	rawset(GameTooltip, "SetSpellByID", nil)
	eq(spell, 990050, "spell")
end)

test("filter checkboxes are saved and narrow the list", function()
	local saved = altData()
	local ns = boot(saved)
	open(ns)
	local owned = findWidget(function(w) return w.template == "UICheckButtonTemplate" and w.Text.text == "Owned" end)
	owned:SetChecked(true)
	owned.scripts.OnClick(owned)
	eq(saved.ui.filters.owned, true, "saved")
	local list = findWidget(function(w) return w.template == "WowScrollBoxList" and w.provider and w.parent.kind == "Frame" and w.rows and w.rows[1] and w.rows[1].Owned end)
	eq(#list.provider.list, 1, "only owned")
end)

test("dropdowns set filters; a missing dropdown template falls back to a button", function()
	local ns = boot()
	open(ns)
	local dropdown = findWidget(function(w) return w.template == "WowStyle1DropdownTemplate" end)
	-- Build the menu and pick the second option of the first dropdown (profession).
	local radios = {}
	dropdown.menu(dropdown, { CreateRadio = function(_, label, isSelected, set, value)
		radios[#radios + 1] = { label = label, isSelected = isSelected, set = set, value = value }
	end })
	eq(radios[1].label, "All", "first option")
	eq(radios[1].isSelected(radios[1].value), true, "All selected by default")
	radios[2].set(radios[2].value)
	eq(ns.db.ui.filters.prof, radios[2].value, "profession saved")

	stubs.reset()
	stubs.noDropdown = true
	ns = boot()
	open(ns)
	local button = findWidget(function(w) return w.template == "UIPanelButtonTemplate" and w.text == "All" end)
	eq(button.text, "All", "fallback shows the current choice")
	button.scripts.OnClick(button)
	eq(ns.db.ui.filters.prof, 164, "cycles to the next profession")
	eq(#stubs.errors, 0, "no errors")
end)

test("window position is saved on drag and restored after reload", function()
	local saved = altData()
	local ns = boot(saved)
	open(ns)
	local window = findWidget(function(w) return w.template == "ButtonFrameTemplate" end)
	window:ClearAllPoints()
	window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -80)
	window.scripts.OnDragStop(window)
	eq(table.concat({ saved.ui.point[1], saved.ui.point[2], saved.ui.point[3], saved.ui.point[4] }, " "),
		"TOPLEFT TOPLEFT 120 -80", "saved")

	stubs.reset()
	ns = boot(saved)
	open(ns)
	window = findWidget(function(w) return w.template == "ButtonFrameTemplate" end)
	local point, _, relPoint, x, y = window:GetPoint(1)
	eq(table.concat({ point, relPoint, x, y }, " "), "TOPLEFT TOPLEFT 120 -80", "restored")
end)

test("character data changes refresh an open browser", function()
	local ns = boot()
	open(ns)
	local list = findWidget(function(w) return w.template == "WowScrollBoxList" and w.rows and w.rows[1] and w.rows[1].Owned end)
	local before = list.provider
	ns:Fire("CHAR_DATA_CHANGED")
	stubs.runTimers()
	assert(list.provider ~= before, "rebuilt")
end)

test("background refreshes keep the recipe list's scroll; a new item starts at the top", function()
	local ns = boot()
	open(ns)
	ns.Browser:Select(17056)
	local list = findWidget(function(w) return w.template == "WowScrollBoxList" and w.rows and w.rows[1] and w.rows[1].Recipe end)
	list.scroll = 120
	local before = list.provider
	ns:Fire("CHAR_DATA_CHANGED")
	stubs.runTimers()
	assert(list.provider ~= before, "rebuilt")
	eq(list.scroll, 120, "scroll kept")

	ns.Browser:Select(2589)
	eq(list.scroll, 0, "new item from the top")
end)

-- Bag markers ---------------------------------------------------------------

-- One bag holding Linen (low tier), Arcanite Bar (Valuable) and an empty slot.
local function bootWithBag(savedVars)
	local bag = stubs.newBagFrame(0, { true, true, true })
	_G.ContainerFrameContainer = { ContainerFrames = { bag } }
	stubs.containers[0] = { { 2589, 10 }, { 12360, 2 } }
	local ns = boot(savedVars)
	return ns, bag
end

local function pipShown(button)
	local pip = button.ReagentAtlasPip
	return pip ~= nil and pip.fill.shown
end

test("bag markers: pip at or above the minimum tier, tier-colored", function()
	local ns, bag = bootWithBag()
	bag:UpdateItems()
	local arcanite = ns.Valuation:GetTier(12360)
	assert(arcanite >= 3, "fixture: Arcanite Bar is at least Valuable")
	eq(pipShown(bag.buttons[2]), true, "Arcanite marked")
	local c = bag.buttons[2].ReagentAtlasPip.fill.color
	local hex = ns.Valuation.TIERS[arcanite].color
	eq(math.floor(c[1] * 255 + 0.5), tonumber(hex:sub(3, 4), 16), "red channel")
	assert(ns.Valuation:GetTier(2589) < 3, "fixture: Linen below Valuable")
	eq(pipShown(bag.buttons[1]), false, "Linen not marked")
	eq(pipShown(bag.buttons[3]), false, "empty slot not marked")
end)

test("bag markers follow settings changes on open bags", function()
	local ns, bag = bootWithBag()
	bag:UpdateItems()
	Settings.settings.markers:SetValue(false)
	eq(pipShown(bag.buttons[2]), false, "markers off hides pips")
	Settings.settings.markers:SetValue(true)
	Settings.settings.markerMinTier:SetValue(2)
	eq(pipShown(bag.buttons[2]), true, "back on")
	eq(ns.db.settings.markerMinTier, 2, "saved")
	bag:Hide()
	Settings.settings.markers:SetValue(false)
	eq(pipShown(bag.buttons[2]), true, "closed bags are left alone until their next update")
end)

test("bag markers: an item moving out of a slot clears its pip", function()
	local _, bag = bootWithBag()
	bag:UpdateItems()
	stubs.containers[0][2] = nil
	bag:UpdateItems()
	eq(pipShown(bag.buttons[2]), false, "cleared")
end)

-- ElvUI bags ----------------------------------------------------------------

-- ElvUI's shape: engine[1]:GetModule("Bags"), BagFrames, frame.Bags[bagID][slotID]
-- and the item in slot.itemID.
local function fakeElvUI(items)
	local frame = stubs.newWidget("Frame")
	local bag = {}
	for slotID, itemID in ipairs(items) do
		local slot = stubs.newWidget("ItemButton", frame)
		slot.itemID = itemID or nil
		bag[slotID] = slot
	end
	frame.Bags = { [0] = bag, name = "not a bag" }
	local bags = { BagFrames = { frame } }
	function bags:UpdateSlot() end
	_G.ElvUI = { { GetModule = function(_, name) return name == "Bags" and bags or nil end } }
	return bags, frame, bag
end

test("ElvUI bags: slots filled before login get pips, and updates follow", function()
	local bags, frame, bag = fakeElvUI({ 12360, 2589, false })
	boot()
	eq(pipShown(bag[1]), true, "already there at login")
	eq(pipShown(bag[2]), false, "low tier unmarked")
	eq(pipShown(bag[3]), false, "empty unmarked")

	bag[1].itemID = nil
	bag[3].itemID = 12360
	bags:UpdateSlot(frame, 0, 1)
	bags:UpdateSlot(frame, 0, 3)
	eq(pipShown(bag[1]), false, "moved out")
	eq(pipShown(bag[3]), true, "moved in")
	eq(#stubs.errors, 0, "no errors")
end)

test("ElvUI bags: settings redraw open windows, unknown slots are ignored", function()
	local bags, frame, bag = fakeElvUI({ 12360 })
	boot()
	bags:UpdateSlot(frame, 9, 1)
	bags:UpdateSlot(frame, 0, 7)
	Settings.settings.markers:SetValue(false)
	eq(pipShown(bag[1]), false, "markers off")
	frame:Hide()
	Settings.settings.markers:SetValue(true)
	eq(pipShown(bag[1]), false, "closed windows wait")
	eq(#stubs.errors, 0, "no errors")
end)

test("an ElvUI without its bags module changes nothing", function()
	_G.ElvUI = { { GetModule = function() error("no such module") end } }
	local _, bag = bootWithBag()
	bag:UpdateItems()
	eq(pipShown(bag.buttons[2]), true, "Blizzard bags still marked")
	eq(#stubs.errors, 0, "no errors")
end)

-- Settings panel ------------------------------------------------------------

test("settings panel registers toggles and the tier dropdown", function()
	local ns = boot()
	eq(Settings.registered.name, "Reagent Atlas", "category")
	local kinds = {}
	for i, control in ipairs(Settings.controls) do kinds[i] = control.kind .. ":" .. control.setting.key end
	eq(table.concat(kinds, ","), "checkbox:tooltip,checkbox:markers,checkbox:minimapIcon,checkbox:useAuctionator,checkbox:trackerSound,dropdown:markerMinTier", "controls")
	local options = Settings.controls[6].options()
	eq(#options, 3, "Useful, Valuable, Keep!")
	eq(options[1].value, ns.Valuation.TIER_USEFUL, "first option")
end)

test("toggling the tooltip setting takes effect immediately", function()
	local ns = boot()
	Settings.settings.tooltip:SetValue(false)
	eq(ns.db.settings.tooltip, false, "saved")
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	eq(#tt.lines, 0, "no lines")
end)

test("/ratlas config opens settings, but not in combat", function()
	boot()
	stubs.slash("/ratlas", "config")
	eq(Settings.opened, "cat:Reagent Atlas", "opened")
	Settings.opened = nil
	stubs.combat = true
	stubs.slash("/ratlas", "config")
	eq(Settings.opened, nil, "not in combat")
	contains(table.concat(stubs.printed, "\n"), "in combat", "message")
end)

test("missing Settings API: no errors, config explains", function()
	stubs.reset()
	_G.Settings = nil
	boot()
	stubs.slash("/ratlas", "config")
	contains(table.concat(stubs.printed, "\n"), "not available", "message")
	eq(#stubs.errors, 0, "no errors")
end)

-- Every command has a UI equivalent -------------------------------------------

local function minimapButton()
	return findWidget(function(w) return w.kind == "Button" and w.parent == Minimap end)
end

test("minimap icon: left opens the browser, right opens settings", function()
	local ns = boot()
	local button = minimapButton()
	assert(button, "icon created")
	button.scripts.OnClick(button, "LeftButton")
	eq(ns.Browser:IsShown(), true, "browser open")
	button.scripts.OnClick(button, "LeftButton")
	eq(ns.Browser:IsShown(), false, "browser closed")
	button.scripts.OnClick(button, "RightButton")
	eq(Settings.opened, "cat:Reagent Atlas", "settings open")
end)

test("minimap icon follows its setting, the AddOns list entry stays", function()
	boot()
	local button = minimapButton()
	eq(button.shown, true, "shown by default")
	Settings.settings.minimapIcon:SetValue(false)
	eq(button.shown, false, "hidden")
	eq(#stubs.compartment, 1, "compartment entry")
	Settings.settings.minimapIcon:SetValue(true)
	eq(button.shown, true, "shown again")
end)

test("minimap icon hidden at login when turned off", function()
	boot({ version = 1, settings = { minimapIcon = false } })
	eq(minimapButton().shown, false, "hidden")
end)

test("AddOns list entry: same clicks as the icon, no global needed", function()
	local ns = boot()
	local entry = stubs.compartment[1]
	eq(entry.text, "Reagent Atlas", "name")
	entry.func(entry, { buttonName = "LeftButton" })
	eq(ns.Browser:IsShown(), true, "browser")
	entry.func(entry, { buttonName = "RightButton" })
	eq(Settings.opened, "cat:Reagent Atlas", "settings")
end)

test("dragging the minimap icon saves its angle, restored after reload", function()
	local saved = altData()
	boot(saved)
	local button = minimapButton()
	button.scripts.OnDragStart(button)
	stubs.cursor = { 500, 500 } -- straight above the center
	button.scripts.OnUpdate(button)
	button.scripts.OnDragStop(button)
	eq(saved.ui.minimapAngle, 90, "angle")
	eq(button.scripts.OnUpdate, nil, "stops following")
	stubs.reset()
	boot(saved)
	local _, _, _, x, y = minimapButton():GetPoint(1)
	T.near(x, 0, "x")
	T.near(y, 75, "y: radius 70 + 5")
end)

test("the browser's gear opens settings and closes the browser", function()
	local ns = boot()
	open(ns)
	local gear = findWidget(function(w) return w.kind == "Button" and w.parent and w.parent.template == "ButtonFrameTemplate" end)
	stubs.combat = true
	gear.scripts.OnClick(gear)
	eq(ns.Browser:IsShown(), true, "stays open when settings can't open")
	stubs.combat = false
	gear.scripts.OnClick(gear)
	eq(Settings.opened, "cat:Reagent Atlas", "settings")
	eq(ns.Browser:IsShown(), false, "browser closed")
end)

test("settings has an Open browser button", function()
	local ns = boot()
	eq(Settings.initializers[1].buttonText, "Open", "button")
	Settings.initializers[1].click()
	eq(ns.Browser:IsShown(), true, "open")
	Settings.initializers[1].click()
	eq(ns.Browser:IsShown(), true, "stays open")
end)

local function showPanel()
	local panel = Settings.canvas.frame
	panel:Show()
	return panel
end

local function panelList(pick)
	return findWidget(function(w) return w.template == "WowScrollBoxList" and w.parent == Settings.canvas.frame and pick(w) end)
end

test("status panel shows what /ratlas version prints", function()
	local ns = boot()
	eq(Settings.canvas.name, "Status & characters", "panel name")
	local panel = showPanel()
	local text = findWidget(function(w) return w.parent == panel and type(w.text) == "string" and w.text:find("recipe data", 1, true) end)
	assert(text, "status text")
	contains(text.text, "prices: none", "price source")
	contains(text.text, "v" .. ns.version, "version")
end)

test("character list: you first, Forget asks first and removes the alt", function()
	local saved = altData()
	saved.chars["Brewdin-StubRealm"].lastSeen = 1800000000
	boot(saved)
	showPanel()
	local list = panelList(function(w) return w.provider and w.provider.list[1] and w.provider.list[1].key end)
	local rows = list.provider.list
	eq(rows[1].isMe, true, "current character first")
	eq(#rows, 3, "all characters")
	eq(list.rows[1].Forget.shown, false, "no Forget on yourself")
	eq(list.rows[2].Seen.text, "last seen 2027-01-15", "last seen")

	local forget = list.rows[2].Forget
	forget.scripts.OnClick(forget)
	eq(stubs.popup.text, "Brewdin-StubRealm", "popup names the character")
	assert(saved.chars["Brewdin-StubRealm"], "nothing removed before confirming")
	stubs.popup.dialog.OnAccept()
	eq(saved.chars["Brewdin-StubRealm"], nil, "removed")
	eq(#list.provider.list, 2, "list refreshed")
end)

test("character data changes keep the settings lists' scroll", function()
	local ns = boot(altData())
	showPanel()
	local chars = panelList(function(w) return w.provider and w.provider.list[1] and w.provider.list[1].key end)
	local missing = panelList(function(w) return w ~= chars end)
	chars.scroll, missing.scroll = 30, 40
	ns:Fire("CHAR_DATA_CHANGED")
	eq(chars.scroll, 30, "characters")
	eq(missing.scroll, 40, "missing recipes")
end)

test("recipe data check lists missing recipes; empty list hidden", function()
	local ns = boot()
	showPanel()
	local note = findWidget(function(w) return type(w.text) == "string" and w.text:find("missing from the data", 1, true) end)
	contains(note.text, "data: 0", "none yet")
	local empty = panelList(function(w) return w.provider and #w.provider.list == 0 end)
	eq(empty.shown, false, "empty list hidden")

	stubs.tradeSkill = { profID = 165, skillLevel = 290, recipes = { [555555] = true } }
	stubs.fire("TRADE_SKILL_SHOW")
	stubs.runTimers()
	ns.SettingsUI:RefreshPanel()
	contains(note.text, "data: 1", "one missing")
	eq(empty.shown, true, "list shown")
	eq(#empty.provider.list, 1, "row")
end)

test("no Minimap or compartment: login stays quiet", function()
	local realMinimap = _G.Minimap
	_G.Minimap = nil
	_G.AddonCompartmentFrame = nil
	local ok, err = pcall(boot)
	_G.Minimap = realMinimap
	assert(ok, err)
	eq(#stubs.errors, 0, "no errors")
end)

-- Safe to sell --------------------------------------------------------------

test("safe to sell: owned, nothing of yours uses it, Useful or below", function()
	local ns = boot({
		version = 1,
		chars = {
			["Brewdin-StubRealm"] = {
				class = "WARRIOR", profs = { [197] = { rank = 100, known = {} } },
				bags = { [2589] = 5, [12359] = 3, [2604] = 1, [12360] = 2 }, bank = {},
			},
		},
	})
	eq(ids(ns.Browser:BuildRows(filters({ sell = true }))), "2604,12359", "Linen is Tailoring, Arcanite too good, the rest unowned")

	ns.Tracker:Add("item", 12359)
	eq(ids(ns.Browser:BuildRows(filters({ sell = true }))), "2604", "a tracked item stays")
	ns.Tracker:Remove("item", 12359)
	ns.Tracker:Add("recipe", 880002)
	eq(ids(ns.Browser:BuildRows(filters({ sell = true }))), "", "so do the reagents of a tracked recipe")
end)

test("safe to sell: a spell reagent stays if one of your classes casts with it", function()
	local ns = boot({
		version = 1,
		chars = { ["Brewdin-StubRealm"] = { class = "WARRIOR", profs = {}, bags = { [17020] = 4 }, bank = {} } },
	})
	eq(ids(ns.Browser:BuildRows(filters({ sell = true }))), "17020", "nobody casts with it")
	ns.db.chars["Brewdin-StubRealm"].class = "MAGE"
	eq(ids(ns.Browser:BuildRows(filters({ sell = true }))), "", "a mage needs it")
end)

test("the Safe to sell box is saved and filters the list", function()
	local saved = altData()
	local ns = boot(saved)
	open(ns)
	local check = findWidget(function(w) return w.template == "UICheckButtonTemplate" and (w.text == "Safe to sell" or (w.Text and w.Text.text == "Safe to sell")) end)
	assert(check, "box exists")
	check:SetChecked(true)
	check.scripts.OnClick(check)
	eq(saved.ui.filters.sell, true, "saved")
	eq(#stubs.errors, 0, "no errors")
end)
