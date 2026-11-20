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
local RETRY_DELAY = 5  -- seconds between retries while a reminder is owed but blocked
local MIN_GAP = 60     -- seconds between two reminders
local LOAD_GRACE = 60  -- seconds after login an empty tracking list may still be loading
local FALLBACK_SOUND = 8959 -- raid warning, if the client lacks the constant

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
-- A trigger (login, death, resurrect, instance change, tracking switched off)
-- marks a reminder as owed. The check shows it once nothing blocks it; while
-- something does (combat, dead, flying, the one-minute gap) it retries on a
-- timer instead of dropping it, so no order of events can lose it.

local lastReminder      -- GetTime() of the last reminder, session only
local loginTime = 0
local owed = false
local checkQueued = false
local wasInInstance = false

local QueueCheck

-- Battlegrounds and arenas have nothing to gather; dungeons and raids do.
local function InPvPInstance()
	local _, instanceType = IsInInstance()
	return instanceType == "pvp" or instanceType == "arena"
end

local function Check()
	if not owed then return end
	if not ns.db.settings.gatherReminder or InPvPInstance() then
		owed = false -- leaving the battleground asks again
		return
	end
	if InCombatLockdown() or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then
		QueueCheck(RETRY_DELAY)
		return
	end
	local now = GetTime()
	if lastReminder and now - lastReminder < MIN_GAP then
		QueueCheck(MIN_GAP - (now - lastReminder))
		return
	end
	local names, anyActive = GatherReminder:GetState()
	if #names == 0 and now - loginTime < LOAD_GRACE then
		QueueCheck(RETRY_DELAY) -- the tracking list may not be loaded yet
		return
	end
	owed = false
	if #names == 0 or anyActive then return end
	local text = GatherReminder:GetReminder()
	lastReminder = now
	ns:Print(text .. ". Turn it on from the tracking menu on the minimap.")
	ns:ShowAlert(text, COLOR, ns.db.settings.gatherSound and (SOUNDKIT and SOUNDKIT.RAID_WARNING or FALLBACK_SOUND))
end

function QueueCheck(delay)
	if checkQueued then return end
	checkQueued = true
	C_Timer.After(delay or CHECK_DELAY, function()
		checkQueued = false
		Check()
	end)
end

local function Request(delay)
	owed = true
	QueueCheck(delay)
end

-- Login, /reload, and entering or leaving an instance; not every loading screen.
local function OnEnteringWorld(_, isInitialLogin, isReloadingUi)
	local inInstance = IsInInstance() and true or false
	if isInitialLogin or isReloadingUi then
		loginTime = GetTime()
		Request(LOGIN_DELAY)
	elseif inInstance ~= wasInInstance then
		Request()
	end
	wasInInstance = inInstance
end

-- Gathering tracking switched off (on purpose, by accident or by dying).
-- Switching from herbs to minerals may pass through "off"; the delayed check
-- reads the state again, so only a tracking that stays off reminds.
local wasActive = false

local function OnTrackingChanged()
	local _, anyActive = GatherReminder:GetState()
	if wasActive and not anyActive then
		Request()
	elseif owed then
		QueueCheck() -- the list may have just loaded after login
	end
	wasActive = anyActive
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
	wasInInstance = IsInInstance() and true or false
	wasActive = select(2, self:GetState())
	ns:RegisterEvent("MINIMAP_UPDATE_TRACKING", OnTrackingChanged)
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", OnEnteringWorld)
	-- Death may clear tracking. Owed from the moment of death, the reminder
	-- comes once alive and out of combat, however the resurrect happened.
	ns:RegisterEvent("PLAYER_DEAD", function() Request() end)
	ns:RegisterEvent("PLAYER_ALIVE", function() Request() end)   -- resurrected at the body, or released
	ns:RegisterEvent("PLAYER_UNGHOST", function() Request() end) -- resurrected from ghost form
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if owed then QueueCheck() end
	end)
end
