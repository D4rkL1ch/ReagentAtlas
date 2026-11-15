local addonName, ns = ...

local GatherReminder = ns:RegisterModule("GatherReminder", {})

-- Gathering tracking spells. A character only has one in the minimap
-- tracking list once it knows the spell, so non-gatherers never see a reminder.
local TRACKING_SPELLS = {
	[2383] = true, -- Find Herbs (Herbalism)
	[2580] = true, -- Find Minerals (Mining)
	[8387] = true, -- Find Herbs and Find Minerals under other IDs in the DB2;
	[8388] = true, -- harmless if Forever's tracking list never uses them
}

local LOGIN_DELAY = 5  -- seconds; tracking state loads a moment after login
local CHECK_DELAY = 3  -- seconds; resurrect and loading-screen events come in bursts
local MIN_GAP = 60     -- seconds between two reminders

local COLOR = { r = 1, g = 0.82, b = 0 }

-- Tracking state ------------------------------------------------------------

-- Names of the gathering trackings this character has, and whether any of
-- them is on. Classic-style clients allow one tracking at a time, so one
-- active gathering tracking counts as fine.
function GatherReminder:GetState()
	local M = C_Minimap
	if not (M and M.GetNumTrackingTypes and M.GetTrackingInfo) then return {}, false end
	local names, anyActive = {}, false
	for index = 1, M.GetNumTrackingTypes() do
		local info = M.GetTrackingInfo(index)
		if info and info.spellID and TRACKING_SPELLS[info.spellID] then
			names[#names + 1] = info.name
			anyActive = anyActive or info.active
		end
	end
	table.sort(names)
	return names, anyActive
end

-- Reminder text, or nil if there is nothing to remind about.
function GatherReminder:GetReminder()
	local names, anyActive = self:GetState()
	if #names == 0 or anyActive then return nil end
	return ("%s %s off"):format(table.concat(names, " / "), #names > 1 and "are" or "is")
end

-- Checking ------------------------------------------------------------------

local lastReminder      -- GetTime() of the last reminder, session only
local afterCombat = false
local checkQueued = false
local wasInInstance = false

local function Check()
	if not ns.db.settings.gatherReminder then return end
	if InCombatLockdown() then
		afterCombat = true
		return
	end
	if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
	if IsInInstance() then return end
	if lastReminder and GetTime() - lastReminder < MIN_GAP then return end
	local text = GatherReminder:GetReminder()
	if not text then return end
	lastReminder = GetTime()
	ns:Print(text .. ". Turn it on from the tracking menu on the minimap.")
	ns:ShowAlert(text, COLOR)
end

local function QueueCheck(delay)
	if checkQueued then return end
	checkQueued = true
	C_Timer.After(delay or CHECK_DELAY, function()
		checkQueued = false
		Check()
	end)
end

-- Login, /reload and leaving an instance; not every loading screen.
local function OnEnteringWorld(_, isInitialLogin, isReloadingUi)
	local inInstance = IsInInstance()
	if isInitialLogin or isReloadingUi then
		QueueCheck(LOGIN_DELAY)
	elseif wasInInstance and not inInstance then
		QueueCheck()
	end
	wasInInstance = inInstance
end

-- Gathering tracking switched off (on purpose or by accident). Switching
-- from herbs to minerals may pass through "off"; the delayed check reads the
-- state again, so only a tracking that stays off reminds.
local wasActive = false

local function OnTrackingChanged()
	local _, anyActive = GatherReminder:GetState()
	if wasActive and not anyActive then
		QueueCheck()
	end
	wasActive = anyActive
end

local function OnRegenEnabled()
	if afterCombat then
		afterCombat = false
		QueueCheck()
	end
end

-- Prints the minimap tracking list, to confirm spell IDs in-game.
local function PrintTracking()
	local M = C_Minimap
	if not (M and M.GetNumTrackingTypes and M.GetTrackingInfo) then
		ns:Print("the minimap tracking API is not available.")
		return
	end
	ns:Print("minimap tracking:")
	for index = 1, M.GetNumTrackingTypes() do
		local info = M.GetTrackingInfo(index)
		if info then
			print(("  %s (spell %s)%s%s"):format(tostring(info.name), tostring(info.spellID),
				info.active and " - on" or "", TRACKING_SPELLS[info.spellID] and " - gathering" or ""))
		end
	end
	ns:Print(GatherReminder:GetReminder() or "no reminder needed.")
end

-- Lifecycle -----------------------------------------------------------------

function GatherReminder:OnInit()
	ns:RegisterCommand("tracking", "tracking - list minimap tracking and whether Find Herbs / Find Minerals is on", PrintTracking)
end

function GatherReminder:OnLogin()
	wasInInstance = IsInInstance()
	wasActive = select(2, self:GetState())
	ns:RegisterEvent("MINIMAP_UPDATE_TRACKING", OnTrackingChanged)
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", OnEnteringWorld)
	ns:RegisterEvent("PLAYER_ALIVE", function() QueueCheck() end)   -- resurrected at the body or by a spell
	ns:RegisterEvent("PLAYER_UNGHOST", function() QueueCheck() end) -- resurrected from ghost form
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", OnRegenEnabled)
end
