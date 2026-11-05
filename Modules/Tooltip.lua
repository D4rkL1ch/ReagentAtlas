local addonName, ns = ...

local Tooltip = ns:RegisterModule("Tooltip", {})

local MAX_COLLAPSED_PROFS = 2   -- professions named on the "Used in" line
local MAX_EXPANDED_RECIPES = 30 -- recipe lines in the Shift view before "and N more"
local MAX_NAMES = 3             -- character names listed before "+N"

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
-- alt does, grey otherwise.
local function AddRecipeLine(tooltip, recipeID)
	local label = ("%s (%d)"):format(Tooltip:GetRecipeName(recipeID), ns.Recipes[recipeID].skill)
	local isMe, alts = ns.Professions:GetKnownBy(recipeID)
	if isMe then
		tooltip:AddDoubleLine(Color(CHECK .. label, COLOR_YOURS), Color(NameList(true, alts), COLOR_YOURS))
	elseif #alts > 0 then
		tooltip:AddDoubleLine(Color(CHECK .. label, COLOR_ALT), Color(NameList(false, alts), COLOR_ALT))
	else
		tooltip:AddLine(Color("· " .. label, COLOR_UNKNOWN))
	end
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

	local shown = 0
	for _, prof in ipairs(info.professions) do
		if shown >= MAX_EXPANDED_RECIPES then break end
		tooltip:AddLine(Color(Tooltip:GetProfessionName(prof), COLOR_HEADER))
		for _, recipeID in ipairs(byProf[prof]) do
			if shown >= MAX_EXPANDED_RECIPES then break end
			AddRecipeLine(tooltip, recipeID)
			shown = shown + 1
		end
	end
	if info.recipeCount > shown then
		tooltip:AddLine(Color(("...and %d more"):format(info.recipeCount - shown), COLOR_HINT))
	end

	AddSpellLine(tooltip, info)
	AddVendorLine(tooltip, info)
	AddOwnedBreakdown(tooltip, info)
end

-- Builds the Reagent Atlas section for an item. Separate from the hook so it
-- can be tested and reused (e.g. by the browser detail pane).
function Tooltip:AddItemLines(tooltip, itemID, expanded)
	local info = ns.Valuation:GetInfo(itemID)
	if not info then return false end
	tooltip:AddLine(" ")
	if expanded then
		AddExpanded(tooltip, info)
	else
		AddCollapsed(tooltip, info)
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
