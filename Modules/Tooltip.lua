local addonName, ns = ...

local Tooltip = ns:RegisterModule("Tooltip", {})

local MAX_COLLAPSED_PROFS = 2   -- professions named on the "Used in" line
local MAX_EXPANDED_RECIPES = 30 -- recipe lines in the Shift view before "and N more"
local MAX_NAMES = 3             -- character names listed before "+N"
local POISONS = 40              -- a class skill: rogues have it without a profession entry

-- The default font has no check mark glyph; use the ready-check texture.
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "

local COLOR_TEXT = "ffe8e2d0"
local COLOR_HINT = "ff9d9d9d"
local COLOR_HEADER = "ffffd100"
local COLOR_UNKNOWN = "ff9d9d9d"
local COLOR_YOURS = "ff1eff00"
local COLOR_ALT = "ff66b3ff"

local function Color(text, color)
	return WrapTextInColorCode(text, color)
end

-- Names ---------------------------------------------------------------------

local profNames = {}

-- Localized profession name from the client, falling back to the generated
-- English name.
function Tooltip:GetProfessionName(skillLineID)
	local name = profNames[skillLineID]
	if name then return name end
	if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
		local ok, result = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, skillLineID)
		if ok and type(result) == "string" and result ~= "" then
			name = result
		end
	end
	name = name or (ns.ProfessionNames and ns.ProfessionNames[skillLineID]) or ("Profession " .. skillLineID)
	profNames[skillLineID] = name
	return name
end

function Tooltip:GetRecipeName(recipeID)
	---@type string?
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID)
	if not name then
		local recipe = ns.Recipes[recipeID]
		if recipe and recipe.out and C_Item and C_Item.GetItemNameByID then
			name = C_Item.GetItemNameByID(recipe.out)
		end
	end
	return name or ("Recipe #" .. recipeID)
end

local function ClassName(token)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
end

-- Localized class name in its class color.
local function ColoredClassName(token)
	local name = ClassName(token)
	local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(token)
	return color and color:WrapTextInColorCode(name) or Color(name, COLOR_TEXT)
end

-- Rendering -----------------------------------------------------------------

-- "Reagent Atlas: Valuable · AH 1s 20c (3 days old)"; the tier includes the
-- auction price adjustment when Auctionator has a fresh price.
local function AddTierLine(tooltip, info)
	local tier, price, age = ns.Valuation:GetTier(info.itemID)
	local text = ns.Valuation:ColorTier(tier, "Reagent Atlas: " .. ns.Valuation:GetTierName(tier))
	if price then
		local priceText = "· AH " .. ns.Pricing:FormatMoney(price)
		if age and age >= 1 then
			priceText = priceText .. (age == 1 and " (1 day old)" or (" (%d days old)"):format(age))
		end
		text = text .. " " .. Color(priceText, COLOR_TEXT)
	end
	tooltip:AddLine(text)
end

-- Your own class gets a short green note; otherwise name the classes.
local function AddSpellLine(tooltip, info)
	local classes = info.spellClasses
	if not classes then return end
	local _, playerClass = UnitClass("player")
	local names = {}
	for i, token in ipairs(classes) do
		if token == playerClass then
			tooltip:AddLine(Color("Spell reagent for your class", COLOR_YOURS))
			return
		end
		names[i] = ColoredClassName(token)
	end
	tooltip:AddLine(Color("Spell reagent for ", COLOR_TEXT) .. table.concat(names, Color(", ", COLOR_TEXT)))
end

-- Explains why a vendor-sold reagent never rates above Useful.
local function AddVendorLine(tooltip, info)
	if info.vendor then
		tooltip:AddLine(Color("Sold by vendors", COLOR_HINT))
	end
end

-- "you, Brewdin, Frostia +2": the current character first, at most
-- MAX_NAMES names.
local function NameList(isMe, keys)
	local names = {}
	if isMe then names[1] = "you" end
	for _, key in ipairs(keys) do
		if #names >= MAX_NAMES then
			return table.concat(names, ", ") .. (" +%d"):format(#keys + (isMe and 1 or 0) - MAX_NAMES)
		end
		names[#names + 1] = ns:CharDisplayName(key)
	end
	return table.concat(names, ", ")
end

-- Shared with the browser's recipe list.
function Tooltip:FormatNames(isMe, keys)
	return NameList(isMe, keys)
end

-- Recipes using the item that any of your characters can craft.
local function AddCraftLine(tooltip, info)
	local count, isMe, altSet = 0, false, {}
	for _, recipeID in ipairs(ns.Reagents[info.itemID].r) do
		local mine, alts = ns.Professions:GetKnownBy(recipeID)
		if mine or #alts > 0 then
			count = count + 1
			isMe = isMe or mine
			for _, key in ipairs(alts) do altSet[key] = true end
		end
	end
	if count == 0 then return end
	local alts = {}
	for key in pairs(altSet) do alts[#alts + 1] = key end
	table.sort(alts)
	local who = NameList(isMe, alts)
	if isMe then
		tooltip:AddLine(Color(("You can craft %d (%s)"):format(count, who), COLOR_YOURS))
	else
		tooltip:AddLine(Color(("Your alts can craft %d (%s)"):format(count, who), COLOR_ALT))
	end
end

local function AddOwnedLine(tooltip, info)
	local total, holders, warband = ns.Inventory:GetCounts(info.itemID)
	if total == 0 then return end
	local text = ("Owned: %d"):format(total)
	if #holders > 1 then
		text = text .. (" across %d characters"):format(#holders)
	end
	if warband > 0 then
		text = text .. (#holders > 0 and " + warband bank" or " (warband bank)")
	end
	tooltip:AddLine(Color(text, COLOR_TEXT))
end

local function AddCollapsed(tooltip, info)
	AddTierLine(tooltip, info)
	if info.recipeCount > 0 then
		local profs = {}
		for i = 1, math.min(#info.professions, MAX_COLLAPSED_PROFS) do
			profs[i] = Tooltip:GetProfessionName(info.professions[i])
		end
		local profText = table.concat(profs, ", ")
		if #info.professions > MAX_COLLAPSED_PROFS then
			profText = profText .. "..."
		end
		local noun = info.recipeCount == 1 and "recipe" or "recipes"
		tooltip:AddLine(Color(("Used in %d %s · %s"):format(info.recipeCount, noun, profText), COLOR_TEXT))
		tooltip:AddLine(Color(("Highest: %s %d"):format(Tooltip:GetProfessionName(info.topProf), info.topSkill), COLOR_TEXT))
		AddCraftLine(tooltip, info)
	end
	AddSpellLine(tooltip, info)
	AddVendorLine(tooltip, info)
	AddOwnedLine(tooltip, info)
	if info.recipeCount > 0 then
		tooltip:AddLine(Color("Hold Shift for all recipes", COLOR_HINT))
	end
end

-- Green with a check if you know the recipe, blue with the alt's name if an
-- alt does, grey with where to get it otherwise. Returns true if that source
-- is unconfirmed.
local function AddRecipeLine(tooltip, recipeID)
	local label = ("%s (%d)"):format(Tooltip:GetRecipeName(recipeID), ns.Recipes[recipeID].skill)
	local isMe, alts = ns.Professions:GetKnownBy(recipeID)
	if isMe then
		tooltip:AddDoubleLine(Color(CHECK .. label, COLOR_YOURS), Color(NameList(true, alts), COLOR_YOURS))
	elseif #alts > 0 then
		tooltip:AddDoubleLine(Color(CHECK .. label, COLOR_ALT), Color(NameList(false, alts), COLOR_ALT))
	else
		local tag, unconfirmed = ns.Sources:GetTag(recipeID)
		if tag then
			tooltip:AddDoubleLine(Color("· " .. label, COLOR_UNKNOWN), Color(tag, COLOR_HINT))
			return unconfirmed
		end
		tooltip:AddLine(Color("· " .. label, COLOR_UNKNOWN))
	end
	return false
end

-- Per-character owned counts, as in the mockup: "Brewdin    Bags 27 · Bank 20".
local function AddOwnedBreakdown(tooltip, info)
	local total, holders, warband = ns.Inventory:GetCounts(info.itemID)
	if total == 0 then return end
	tooltip:AddLine(" ")
	for _, h in ipairs(holders) do
		local where = {}
		if h.bags > 0 then where[#where + 1] = "Bags " .. h.bags end
		if h.bank > 0 then where[#where + 1] = "Bank " .. h.bank end
		local name = h.isMe and "You" or ns:CharDisplayName(h.key)
		tooltip:AddDoubleLine(Color(name, COLOR_TEXT), Color(table.concat(where, " · "), COLOR_TEXT))
	end
	if warband > 0 then
		tooltip:AddDoubleLine(Color("Warband bank", COLOR_TEXT), Color(tostring(warband), COLOR_TEXT))
	end
end

local function AddExpanded(tooltip, info)
	AddTierLine(tooltip, info)

	-- Group the item's recipes (already sorted by skill desc) by profession.
	local byProf = {}
	for _, recipeID in ipairs(ns.Reagents[info.itemID].r) do
		local recipe = ns.Recipes[recipeID]
		if recipe then
			local list = byProf[recipe.prof]
			if not list then
				list = {}
				byProf[recipe.prof] = list
			end
			list[#list + 1] = recipeID
		end
	end

	local shown, anyUnconfirmed = 0, false
	for _, prof in ipairs(info.professions) do
		if shown >= MAX_EXPANDED_RECIPES then break end
		tooltip:AddLine(Color(Tooltip:GetProfessionName(prof), COLOR_HEADER))
		for _, recipeID in ipairs(byProf[prof]) do
			if shown >= MAX_EXPANDED_RECIPES then break end
			anyUnconfirmed = AddRecipeLine(tooltip, recipeID) or anyUnconfirmed
			shown = shown + 1
		end
	end
	if info.recipeCount > shown then
		tooltip:AddLine(Color(("...and %d more"):format(info.recipeCount - shown), COLOR_HINT))
	end
	if anyUnconfirmed then
		tooltip:AddLine(Color(ns.Sources.UNCONFIRMED_NOTE, COLOR_HINT))
	end

	AddSpellLine(tooltip, info)
	AddVendorLine(tooltip, info)
	AddOwnedBreakdown(tooltip, info)
end

-- Crafted items and recipe items ---------------------------------------------

local NO_RECIPES = {}
local craftedBy, taughtBy -- itemID -> recipeIDs, built on first use

local function Append(index, itemID, recipeID)
	local list = index[itemID]
	if not list then
		list = {}
		index[itemID] = list
	end
	list[#list + 1] = recipeID
end

local function BySkill(a, b)
	local skillA, skillB = ns.Recipes[a].skill, ns.Recipes[b].skill
	if skillA ~= skillB then return skillA > skillB end
	return a < b
end

local function BuildRecipeIndex()
	craftedBy, taughtBy = {}, {}
	for recipeID, recipe in pairs(ns.Recipes) do
		if recipe.out then Append(craftedBy, recipe.out, recipeID) end
		local source = ns.RecipeSources and ns.RecipeSources[recipeID]
		if source and source.i then Append(taughtBy, source.i, recipeID) end
	end
	for _, index in ipairs({ craftedBy, taughtBy }) do
		for _, list in pairs(index) do table.sort(list, BySkill) end
	end
end

-- Recipes that make the item, and recipes the item teaches.
function Tooltip:GetRecipesFor(itemID)
	if not craftedBy then BuildRecipeIndex() end
	return craftedBy[itemID] or NO_RECIPES, taughtBy[itemID] or NO_RECIPES
end

local function AddKnownLine(tooltip, recipeID)
	local isMe, alts = ns.Professions:GetKnownBy(recipeID)
	if not isMe and #alts == 0 then return false end
	tooltip:AddLine(Color("Known by " .. NameList(isMe, alts), isMe and COLOR_YOURS or COLOR_ALT))
	return true
end

-- "Could learn: you (290), Brewdin (250/300) +1": rank alone when it's enough,
-- rank/needed when it isn't yet. Returns the text and whether you can.
function Tooltip:FormatLearners(learners)
	local names = {}
	for i = 1, math.min(#learners, MAX_NAMES) do
		local learner = learners[i]
		local name = learner.isMe and "you" or ns:CharDisplayName(learner.key)
		local rank = learner.ready and tostring(learner.rank) or ("%d/%d"):format(learner.rank, learner.need)
		names[i] = ("%s (%s)"):format(name, rank)
	end
	local text = "Could learn: " .. table.concat(names, ", ")
	if #learners > MAX_NAMES then text = text .. (" +%d"):format(#learners - MAX_NAMES) end
	return text, learners[1].isMe and learners[1].ready
end

local function AddLearnersLine(tooltip, learners)
	local text, mine = Tooltip:FormatLearners(learners)
	tooltip:AddLine(Color(text, mine and COLOR_YOURS or COLOR_ALT))
end

-- One craft's reagents against what you own, for the Shift view.
local function AddReagentLines(tooltip, recipeID)
	local status = ns.Tracker:GetStatus({ kind = "recipe", id = recipeID, need = 1 })
	for _, reagent in ipairs(status.reagents) do
		local name = ns.Browser:GetItemName(reagent.itemID) or ("Item #" .. reagent.itemID)
		tooltip:AddDoubleLine(Color(name, COLOR_TEXT), Color(("%d / %d"):format(reagent.have, reagent.need),
			reagent.have >= reagent.need and COLOR_YOURS or COLOR_TEXT))
	end
end

-- A recipe item answers "is this any use to me?": who knows it already, who
-- has the profession to learn it, or that nobody does.
local function AddTaughtRecipe(tooltip, recipeID, expanded)
	local name = Tooltip:GetRecipeName(recipeID)
	tooltip:AddLine(Color("Reagent Atlas: Teaches " .. name, COLOR_HEADER))
	local known = AddKnownLine(tooltip, recipeID)
	local learners = ns.Professions:GetLearners(recipeID)
	if #learners > 0 then
		AddLearnersLine(tooltip, learners)
	elseif not known and ns.Recipes[recipeID].prof ~= POISONS then
		local prof = Tooltip:GetProfessionName(ns.Recipes[recipeID].prof)
		tooltip:AddLine(Color(("None of your characters has %s"):format(prof), COLOR_UNKNOWN))
	end
	if expanded then AddReagentLines(tooltip, recipeID) end
end

-- A crafted item: which profession makes it and who can. Returns true if a
-- source shown is unconfirmed.
local function AddCraftedRecipe(tooltip, recipeID, expanded)
	local recipe = ns.Recipes[recipeID]
	local prof = Tooltip:GetProfessionName(recipe.prof)
	tooltip:AddLine(Color(("Reagent Atlas: Crafted with %s %d"):format(prof, recipe.skill), COLOR_HEADER))
	local unconfirmed = false
	if not AddKnownLine(tooltip, recipeID) then
		if expanded then
			local lines
			lines, unconfirmed = ns.Sources:GetDetailLines(recipeID)
			tooltip:AddLine(Color("None of your characters knows this", COLOR_UNKNOWN))
			for _, line in ipairs(lines) do tooltip:AddLine(Color(line, COLOR_HINT)) end
		else
			local tag
			tag, unconfirmed = ns.Sources:GetTag(recipeID)
			tooltip:AddDoubleLine(Color("None of your characters knows this", COLOR_UNKNOWN), Color(tag or "", COLOR_HINT))
		end
	end
	if expanded then AddReagentLines(tooltip, recipeID) end
	return unconfirmed
end

-- Everything the item teaches or is crafted by, then one note on unconfirmed sources.
local function AddRecipeSections(tooltip, crafted, taught, expanded)
	local unconfirmed = false
	for _, recipeID in ipairs(taught) do
		AddTaughtRecipe(tooltip, recipeID, expanded)
	end
	for _, recipeID in ipairs(crafted) do
		unconfirmed = AddCraftedRecipe(tooltip, recipeID, expanded) or unconfirmed
	end
	if unconfirmed then
		tooltip:AddLine(Color(ns.Sources.UNCONFIRMED_NOTE, COLOR_HINT))
	end
end

-- Builds the Reagent Atlas section for an item. Separate from the hook so it
-- can be tested and reused (e.g. by the browser detail pane). An item can be
-- both crafted and a reagent, so the sections stack.
function Tooltip:AddItemLines(tooltip, itemID, expanded)
	local info = ns.Valuation:GetInfo(itemID)
	local crafted, taught = self:GetRecipesFor(itemID)
	local hasRecipes = #crafted > 0 or #taught > 0
	if not info and not hasRecipes then return false end
	tooltip:AddLine(" ")
	AddRecipeSections(tooltip, crafted, taught, expanded)
	if info and expanded then
		AddExpanded(tooltip, info)
	elseif info then
		AddCollapsed(tooltip, info)
	end
	-- A reagent with recipes already has its own hint, and Shift shows both.
	if hasRecipes and not expanded and not (info and info.recipeCount > 0) then
		tooltip:AddLine(Color("Hold Shift for reagents", COLOR_HINT))
	end
	return true
end

-- Hooks ---------------------------------------------------------------------

-- Tooltips we added lines to, so Shift can refresh them. Weak keys: never
-- keep a tooltip alive.
local annotated = setmetatable({}, { __mode = "k" })

local function OnItemTooltip(tooltip, data)
	if not ns.db.settings.tooltip then return end
	if tooltip.IsForbidden and tooltip:IsForbidden() then return end
	local itemID = data and data.id
	if Tooltip:AddItemLines(tooltip, itemID, IsShiftKeyDown()) then
		annotated[tooltip] = true
	end
end

local function OnModifierChanged(_, key)
	if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
	for tooltip in pairs(annotated) do
		if tooltip:IsShown() and tooltip.RefreshData then
			tooltip:RefreshData()
		else
			annotated[tooltip] = nil
		end
	end
end

function Tooltip:OnInit()
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then
		ns:Print("item tooltips unavailable: TooltipDataProcessor not found in this client.")
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	ns:RegisterEvent("MODIFIER_STATE_CHANGED", OnModifierChanged)
end
