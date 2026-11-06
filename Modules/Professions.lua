local addonName, ns = ...

local Professions = ns:RegisterModule("Professions", {})

local SCAN_DELAY = 0.5 -- seconds; TRADE_SKILL_LIST_UPDATE fires in bursts

-- Map a skill line (possibly a child tier line) to the top-level profession
-- used in the generated data, or nil if it isn't one we track.
local function NormalizeProf(skillLineID)
	if not skillLineID then return nil end
	if ns.ProfessionNames[skillLineID] then return skillLineID end
	if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
		local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
		if ok and info and ns.ProfessionNames[info.parentProfessionID] then
			return info.parentProfessionID
		end
	end
	return nil
end

local function GetProf(char, profID)
	local prof = char.profs[profID]
	if not prof then
		prof = { known = {} }
		char.profs[profID] = prof
	end
	prof.known = prof.known or {}
	return prof
end

-- Skill ranks ---------------------------------------------------------------

-- Ranks come from the spellbook profession list, so they're current without
-- opening a profession window. Professions no longer listed are dropped,
-- together with their known recipes (unlearning loses them in-game too).
function Professions:ScanRanks()
	if not (GetProfessions and GetProfessionInfo) then return end
	local char = ns:GetCharData()
	if not char then return end

	-- prof1, prof2, first aid, fishing, cooking; unlearned slots are nil
	local indices = { n = 5, GetProfessions() }
	local seen, any = {}, false
	for i = 1, indices.n do
		local index = indices[i]
		if index then
			local _, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
			local profID = NormalizeProf(skillLine)
			if profID then
				local prof = GetProf(char, profID)
				prof.rank, prof.maxRank = rank, maxRank
				seen[profID] = true
				any = true
			end
		end
	end

	-- An empty list may just mean skill data isn't loaded yet; never prune on it.
	if any then
		for profID in pairs(char.profs) do
			if not seen[profID] then
				char.profs[profID] = nil
			end
		end
	end
	ns:Fire("CHAR_DATA_CHANGED")
end

-- Known recipes -------------------------------------------------------------

-- Recipes the open profession window reports as learned but that the
-- generated data lacks, for /ratlas diff. Session only.
local missingFromData = {}

-- Only record our own profession window, not a linked, guild or NPC one.
local function IsOwnTradeSkill()
	local T = C_TradeSkillUI
	if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return false end
	if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
	if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
	if T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember() then return false end
	if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
	return true
end

function Professions:ScanRecipes()
	local T = C_TradeSkillUI
	if not (T and T.GetBaseProfessionInfo and T.GetRecipeInfo) then return end
	if not IsOwnTradeSkill() then return end
	local base = T.GetBaseProfessionInfo()
	local profID = base and NormalizeProf(base.professionID)
	if not profID then return end
	local char = ns:GetCharData()
	if not char then return end

	-- GetAllRecipeIDs ignores the window's filters, so its result is complete
	-- and can replace what we had; the filtered list can only add.
	local complete = T.GetAllRecipeIDs ~= nil
	local ids = complete and T.GetAllRecipeIDs() or (T.GetFilteredRecipeIDs and T.GetFilteredRecipeIDs())
	if not ids or #ids == 0 then return end

	local prof = GetProf(char, profID)
	local known = complete and {} or prof.known
	for _, recipeID in ipairs(ids) do
		local info = T.GetRecipeInfo(recipeID)
		if info and info.learned then
			known[recipeID] = true
			if not ns.Recipes[recipeID] then
				missingFromData[recipeID] = info.name or true
			end
		end
	end
	prof.known = known
	if base.skillLevel and base.skillLevel > 0 then
		prof.rank, prof.maxRank = base.skillLevel, base.maxSkillLevel
	end
	ns:Fire("CHAR_DATA_CHANGED")
end

local scanQueued = false
local function QueueRecipeScan()
	if scanQueued then return end
	scanQueued = true
	C_Timer.After(SCAN_DELAY, function()
		scanQueued = false
		Professions:ScanRecipes()
	end)
end

-- Learning a recipe doesn't need the window: the data says which profession.
local function OnRecipeLearned(_, recipeID)
	local recipe = recipeID and ns.Recipes[recipeID]
	local char = ns:GetCharData()
	if not (recipe and char) then return end
	GetProf(char, recipe.prof).known[recipeID] = true
	ns:Fire("CHAR_DATA_CHANGED")
end

-- Lookup --------------------------------------------------------------------

-- recipeID -> array of character keys that know it; rebuilt lazily.
local knownIndex

local function BuildIndex()
	knownIndex = {}
	for key, char in pairs(ns.db.chars) do
		for _, prof in pairs(char.profs or {}) do
			for recipeID in pairs(prof.known or {}) do
				local list = knownIndex[recipeID]
				if not list then
					list = {}
					knownIndex[recipeID] = list
				end
				list[#list + 1] = key
			end
		end
	end
end

-- Who can craft a recipe: (true if the current character knows it, sorted
-- array of other character keys that know it).
function Professions:GetKnownBy(recipeID)
	if not knownIndex then BuildIndex() end
	local list = knownIndex[recipeID]
	local alts = {}
	if not list then return false, alts end
	local me = ns:GetCharKey()
	local isMe = false
	for _, key in ipairs(list) do
		if key == me then
			isMe = true
		else
			alts[#alts + 1] = key
		end
	end
	table.sort(alts)
	return isMe, alts
end

-- Characters with the recipe's profession who don't know it: array of
-- { key, isMe, rank, need, ready }, you first, then highest rank. ready means
-- the rank is enough. need is the recipe item's required skill; trainer recipes
-- have no such item, so theirs is where the recipe turns yellow, a little above
-- the real requirement. Known recipes are only recorded from an opened
-- profession window, so this can include someone who has it.
function Professions:GetLearners(recipeID)
	local recipe = ns.Recipes[recipeID]
	local learners = {}
	if not recipe then return learners end
	local source = ns.RecipeSources and ns.RecipeSources[recipeID]
	local need = source and source.req or recipe.skill
	local me = ns:GetCharKey()
	for key, char in pairs(ns.db.chars) do
		local prof = char.profs and char.profs[recipe.prof]
		if prof and not (prof.known and prof.known[recipeID]) then
			local rank = prof.rank or 0
			learners[#learners + 1] = { key = key, isMe = key == me, rank = rank, need = need, ready = rank >= need }
		end
	end
	table.sort(learners, function(a, b)
		if a.isMe ~= b.isMe then return a.isMe end
		if a.rank ~= b.rank then return a.rank > b.rank end
		return a.key < b.key
	end)
	return learners
end

-- Learned recipes missing from the data, as sorted "Name (id)" lines. Only
-- profession windows opened this session are checked.
function Professions:GetMissingRecipes()
	local names = {}
	for recipeID, name in pairs(missingFromData) do
		names[#names + 1] = ("%s (%d)"):format(type(name) == "string" and name or "?", recipeID)
	end
	table.sort(names)
	return names
end

-- Lifecycle -----------------------------------------------------------------

function Professions:OnInit()
	ns:RegisterMessage("CHAR_DATA_CHANGED", function() knownIndex = nil end)
	ns:RegisterCommand("diff", "diff - learned recipes missing from the recipe data", function()
		local names = Professions:GetMissingRecipes()
		if #names == 0 then
			ns:Print("no differences found. Open each profession window first; only what was opened this session is checked.")
		else
			ns:Print(("%d learned recipes are missing from the recipe data (build %s):"):format(#names, tostring(ns.DATA_BUILD)))
			for _, line in ipairs(names) do
				print("  " .. line)
			end
		end
	end)
end

function Professions:OnLogin()
	self:ScanRanks()
	ns:RegisterEvent("SKILL_LINES_CHANGED", function() Professions:ScanRanks() end)
	ns:RegisterEvent("TRADE_SKILL_SHOW", QueueRecipeScan)
	ns:RegisterEvent("TRADE_SKILL_LIST_UPDATE", QueueRecipeScan)
	ns:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", QueueRecipeScan)
	ns:RegisterEvent("NEW_RECIPE_LEARNED", OnRecipeLearned)
end
