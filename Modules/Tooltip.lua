local addonName, ns = ...

local Tooltip = ns:RegisterModule("Tooltip", {})

local MAX_COLLAPSED_PROFS = 2   -- professions named on the "Used in" line
local MAX_EXPANDED_RECIPES = 30 -- recipe lines in the Shift view before "and N more"

local COLOR_TEXT = "ffe8e2d0"
local COLOR_HINT = "ff9d9d9d"
local COLOR_HEADER = "ffffd100"
local COLOR_UNKNOWN = "ff9d9d9d"

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

-- Rendering -----------------------------------------------------------------

local function AddTierLine(tooltip, info)
	tooltip:AddLine(ns.Valuation:ColorTier(info.tier, "Reagent Atlas: " .. ns.Valuation:GetTierName(info.tier)))
end

local function AddSpellLine(tooltip, info)
	if not info.spellClasses then return end
	local names = {}
	for i, token in ipairs(info.spellClasses) do
		names[i] = ClassName(token)
	end
	tooltip:AddLine(Color("Spell reagent: " .. table.concat(names, ", "), COLOR_TEXT))
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
	end
	AddSpellLine(tooltip, info)
	if info.recipeCount > 0 then
		tooltip:AddLine(Color("Hold Shift for all recipes", COLOR_HINT))
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
			local text = ("· %s (%d)"):format(Tooltip:GetRecipeName(recipeID), ns.Recipes[recipeID].skill)
			tooltip:AddLine(Color(text, COLOR_UNKNOWN))
			shown = shown + 1
		end
	end
	if info.recipeCount > shown then
		tooltip:AddLine(Color(("...and %d more"):format(info.recipeCount - shown), COLOR_HINT))
	end

	AddSpellLine(tooltip, info)
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
