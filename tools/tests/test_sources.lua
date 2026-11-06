---@diagnostic disable: undefined-global
local T = ...
local test, eq, contains, stubs = T.test, T.eq, T.contains, T.stubs

local NPCS = {
	[1] = { "Horde Vendor", "Orgrimmar", "H" },
	[2] = { "Alliance Vendor", "Stormwind City", "A" },
	[3] = { "Neutral Vendor", "Tanaris", "AH" },
	[4] = { "Unrestricted Vendor", "Winterspring", "" },
	[5] = { "Zoneless Dropper", "", "" },
	[6] = { "Ogre", "Dire Maul", "" },
}

local function boot(sources)
	return T.boot(nil, function(ns)
		T.useFixture(ns)
		ns.RecipeSources, ns.SourceNPCs = sources, NPCS
	end)
end

-- stubs: the player is Horde.
test("tags: vendors on the player's side, with extra zones counted", function()
	local ns = boot({
		[10] = { i = 100, v = { 1 } },
		[11] = { i = 100, v = { 2, 1, 3, 4 } },
		[12] = { i = 100, v = { 2 } },
	})
	eq(ns.Sources:GetTag(10), "Vendor · Orgrimmar", "reachable vendor")
	eq(ns.Sources:GetTag(11), "Vendor · Orgrimmar +2", "other faction not counted")
	eq(ns.Sources:GetTag(12), "Vendor · other faction", "only the other faction sells it")
	eq(select(2, ns.Sources:GetTag(10)), true, "vendor data is unconfirmed")
end)

test("tags: drops, quests, containers and hints", function()
	local ns = boot({
		[20] = { i = 1, d = { 6 } },
		[21] = { i = 1, d = { 5 } },
		[22] = { i = 1, dn = 9, dz = { "Molten Core" }, dzn = 2 },
		[23] = { i = 1, dn = 500, dz = { "Tanaris" }, dzn = 29 },
		[24] = { i = 1, dn = 7, dz = {}, dzn = 0 },
		[25] = { i = 1, q = { "A Quest" } },
		[26] = { i = 1, o = true },
		[27] = { i = 1, fac = "Cenarion Circle", rep = "Friendly" },
		[28] = { i = 1 },
	})
	local S = ns.Sources
	eq(S:GetTag(20), "Drop · Dire Maul", "named dropper")
	eq(S:GetTag(21), "Drop", "dropper with no zone")
	eq(S:GetTag(22), "Drop · Molten Core", "summarized drop")
	eq(S:GetTag(23), "World drop", "many zones")
	eq(S:GetTag(24), "Drop", "summary with no zone")
	eq(S:GetTag(25), "Quest", "quest")
	eq(S:GetTag(26), "Chest or container", "container")
	eq(S:GetTag(27), "Needs Cenarion Circle", "reputation hint")
	eq(select(2, S:GetTag(27)), false, "client data is not flagged unconfirmed")
	eq(S:GetTag(28), "Source unknown", "new recipe item")
	eq(S:GetTag(99), "Trainer (likely)", "no recipe item")
	eq(select(2, S:GetTag(99)), false, "the trainer guess says so itself")
end)

test("a vendor outranks every other source in the tag", function()
	local ns = boot({ [30] = { i = 1, v = { 1 }, q = { "Q" }, dn = 9, dz = { "Z" }, dzn = 1, o = true } })
	eq(ns.Sources:GetTag(30), "Vendor · Orgrimmar", "vendor first")
end)

test("detail lines list everything, capped, with the other faction summarized", function()
	local ns = boot({
		[40] = { i = 2589, v = { 1, 2, 3 }, q = { "Q1" }, d = { 6 }, o = true, fac = "Argent Dawn", rep = "Honored" },
		[41] = { i = 1, v = { 1, 1, 1, 1, 1, 1, 1 } },
		[42] = { i = 1, dn = 500, dz = { "Tanaris" }, dzn = 29 },
		[43] = { i = 1, dn = 9, dz = { "Molten Core", "Dire Maul" }, dzn = 2 },
		[44] = { i = 1, dn = 7, dz = {}, dzn = 0 },
		[45] = { i = 1 },
	})
	local S = ns.Sources
	local lines, unconfirmed = S:GetDetailLines(40)
	local text = table.concat(lines, "\n")
	eq(unconfirmed, true, "unconfirmed")
	contains(text, "Vendor: Horde Vendor (Orgrimmar)")
	contains(text, "Vendor: Neutral Vendor (Tanaris)")
	contains(text, "Also sold by 1 vendor of the other faction")
	contains(text, "Quest: Q1")
	contains(text, "Drop: Ogre (Dire Maul)")
	contains(text, "Found in chests or containers")
	contains(text, "Requires Argent Dawn: Honored")
	contains(table.concat((S:GetDetailLines(41)), "\n"), "...and 2 more")
	eq((S:GetDetailLines(42))[1], "World drop: 500 creatures in 29 zones", "world drop")
	eq((S:GetDetailLines(43))[1], "Drop: 9 creatures in Molten Core, Dire Maul", "zones")
	eq((S:GetDetailLines(44))[1], "Drop: 7 creatures", "no zones")
	local unknown, flagged = S:GetDetailLines(45)
	eq(unknown[#unknown], "Source not mapped for Forever yet", "unknown")
	eq(flagged, false, "unknown is not unconfirmed data")
	contains((S:GetDetailLines(99))[1], "trainer", "no recipe item")
end)

test("no source data (sample build): nothing shown", function()
	local ns = boot(nil)
	eq(ns.Sources:GetTag(10), nil, "no tag")
	eq(#ns.Sources:GetDetailLines(10), 0, "no lines")
end)

test("Shift tooltip: tag on unknown recipes only, one unconfirmed note", function()
	local ns = boot({
		[990001] = { i = 1, v = { 1 } },
		[990002] = { i = 1, v = { 1 } },
	})
	ns.db.chars["Tester-StubRealm"].profs = { [165] = { rank = 300, known = { [990002] = true } } }
	stubs.shift = true
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	local text = tt:Text()
	contains(text, "Feathered Jerkin (285) | Vendor · Orgrimmar")
	contains(text, "· Recipe #990003 (210) | Trainer (likely)")
	eq(select(2, text:gsub("unconfirmed in Forever", "")), 1, "note shown once")
	eq(text:find("Feathered Boots (250) | Vendor", 1, true), nil, "known recipe keeps its names")
end)

test("Shift tooltip: no note when nothing shown is unconfirmed", function()
	local ns = boot({})
	stubs.shift = true
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	eq(tt:Text():find(ns.Sources.UNCONFIRMED_NOTE, 1, true), nil, "no note")
end)

test("collapsed tooltip stays free of sources", function()
	boot({ [990001] = { i = 1, v = { 1 } } })
	local tt = stubs.newTooltip()
	tt:SetItem(17056)
	eq(tt:Text():find("Vendor ·", 1, true), nil, "no tag collapsed")
end)

test("browser detail: source for unknown recipes, names for known", function()
	local ns = boot({ [990001] = { i = 1, v = { 1 } }, [990002] = { i = 1, v = { 1 } } })
	ns.db.chars["Tester-StubRealm"].profs = { [165] = { rank = 300, known = { [990002] = true } } }
	local byID = {}
	for _, recipe in ipairs(ns.Browser:GetDetail(17056).recipes) do byID[recipe.recipeID] = recipe end
	eq(byID[990001].who, "Vendor · Orgrimmar", "unknown recipe shows its source")
	eq(byID[990002].who, "you", "known recipe shows who")
end)

test("hovering a recipe icon shows the recipe item and lists its source", function()
	local ns = boot({ [990001] = { i = 1, v = { 1 } } })
	local lines, item = {}, nil
	rawset(GameTooltip, "AddLine", function(_, text) lines[#lines + 1] = text end)
	rawset(GameTooltip, "SetItemByID", function(_, id) item = id end)
	ns.Browser:ShowRecipe({}, 990001, "Feathered Jerkin")
	rawset(GameTooltip, "AddLine", nil)
	rawset(GameTooltip, "SetItemByID", nil)
	eq(item, 1, "the item that teaches the recipe")
	local text = table.concat(lines, "\n")
	contains(text, "Vendor: Horde Vendor (Orgrimmar)")
	contains(text, ns.Sources.UNCONFIRMED_NOTE)
end)

-- Vendors seen in merchant windows ------------------------------------------

local function openMerchant(guid, name, items)
	_G.UnitGUID = function() return guid end
	local realUnitName = _G.UnitName
	_G.UnitName = function(unit) return unit == "npc" and name or realUnitName(unit) end
	_G.GetRealZoneText = function() return "Orgrimmar" end
	_G.GetMerchantNumItems = function() return #items end
	_G.GetMerchantItemID = function(i) return items[i] end
	stubs.fire("MERCHANT_SHOW")
	_G.UnitName = realUnitName
end

test("a recipe item in a merchant window is remembered and beats the data", function()
	local ns = boot({ [990001] = { i = 100, v = { 2 } }, [990002] = { i = 101 } })
	eq(select(2, ns.Sources:GetTag(990001)), true, "unconfirmed before")
	openMerchant("Creature-0-1-2-3-4242-0000", "Kirin Tor Vendor", { 100, 999, 101 })
	local tag, unconfirmed = ns.Sources:GetTag(990001)
	eq(tag, "Vendor · Orgrimmar", "seen vendor first")
	eq(unconfirmed, false, "confirmed")
	eq(ns.Sources:GetTag(990002), "Vendor · Orgrimmar", "fills a recipe with no source")
	eq(ns.db.seenVendors[999], nil, "other goods are not saved")
	eq(ns.db.seenVendors[100][4242][1], "Kirin Tor Vendor", "npc")
end)

test("detail lines lead with who was seen selling it", function()
	local ns = boot({ [990002] = { i = 101 } })
	stubs.itemNames[101] = "Pattern: Thing"
	openMerchant("Creature-0-1-2-3-4242-0000", "Some Vendor", { 101 })
	local lines, unconfirmed = ns.Sources:GetDetailLines(990002)
	eq(table.concat(lines, "|"), "Learned from Pattern: Thing|Seen at Some Vendor (Orgrimmar)", "lines")
	eq(unconfirmed, false, "confirmed")
end)

test("a merchant that is not a creature is ignored, and sightings survive a reload", function()
	local ns = boot({ [990002] = { i = 101 } })
	openMerchant("Player-1-00000001", "Someone", { 101 })
	eq(ns.db.seenVendors[101], nil, "not a vendor NPC")
	openMerchant("Creature-0-1-2-3-4242-0000", "Some Vendor", { 101 })
	local saved = ns.db
	local after = T.boot(saved, function(n)
		T.useFixture(n)
		n.RecipeSources, n.SourceNPCs = { [990002] = { i = 101 } }, NPCS
	end)
	eq(after.Sources:GetTag(990002), "Vendor · Orgrimmar", "kept")
end)

test("no merchant API means no scan and no error", function()
	local ns = boot({ [990002] = { i = 101 } })
	_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.UnitGUID = nil, nil, nil
	ns.Sources:ScanMerchant()
	eq(next(ns.db.seenVendors), nil, "nothing saved")
end)
