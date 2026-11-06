local addonName, ns = ...

local BagMarkers = ns:RegisterModule("BagMarkers", {})

local PIP_SIZE = 9    -- fill, before the 45 degree rotation
local PIP_BORDER = 2  -- black edge around the fill
local PIP_INSET = 5   -- from the button's top-left corner

-- Hex "ffRRGGBB" to r, g, b in 0-1.
local function HexToRGB(hex)
	return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

-- A diamond in the top-left corner: a black square with a colored square on
-- top, both rotated. Textures only, so it is safe on bag buttons in combat.
local function GetPip(button)
	local pip = button.ReagentAtlasPip
	if pip then return pip end
	local border = button:CreateTexture(nil, "OVERLAY", nil, 6)
	border:SetSize(PIP_SIZE + PIP_BORDER, PIP_SIZE + PIP_BORDER)
	border:SetPoint("CENTER", button, "TOPLEFT", PIP_INSET + PIP_SIZE / 2, -(PIP_INSET + PIP_SIZE / 2))
	border:SetColorTexture(0, 0, 0, 1)
	border:SetRotation(math.rad(45))
	local fill = button:CreateTexture(nil, "OVERLAY", nil, 7)
	fill:SetSize(PIP_SIZE, PIP_SIZE)
	fill:SetPoint("CENTER", border, "CENTER")
	fill:SetRotation(math.rad(45))
	pip = { border = border, fill = fill }
	button.ReagentAtlasPip = pip
	return pip
end

local function SetPip(button, tier)
	if not tier then
		local pip = button.ReagentAtlasPip
		if pip then
			pip.border:Hide()
			pip.fill:Hide()
		end
		return
	end
	local pip = GetPip(button)
	pip.fill:SetColorTexture(HexToRGB(ns.Valuation.TIERS[tier].color))
	pip.border:Show()
	pip.fill:Show()
end

-- Tier to mark an item with, or nil.
function BagMarkers:TierFor(itemID)
	local settings = ns.db.settings
	if not settings.markers or not itemID then return nil end
	local tier = ns.Valuation:GetTier(itemID)
	if tier and tier >= settings.markerMinTier then
		return tier
	end
	return nil
end

function BagMarkers:UpdateFrame(frame)
	if not frame.EnumerateValidItems then return end
	for _, button in frame:EnumerateValidItems() do
		local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
		SetPip(button, self:TierFor(info and info.itemID))
	end
end

-- Bag windows: the combined bag plus one frame per bag. Forever uses the
-- retail container frames (Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua).
local function EachContainerFrame(fn)
	if ContainerFrameCombinedBags then fn(ContainerFrameCombinedBags) end
	local holder = ContainerFrameContainer --[[@as table?]]
	local container = holder and holder.ContainerFrames
	if container then
		for _, frame in ipairs(container) do fn(frame) end
	end
end

-- ElvUI replaces the bag windows with its own buttons, which keep their item
-- in slot.itemID. It covers its bank windows too.
local elvBags -- ElvUI's Bags module, once hooked

local function FindElvUIBags()
	local engine = ElvUI
	local elv = type(engine) == "table" and engine[1]
	if not (elv and elv.GetModule) then return nil end
	local ok, bags = pcall(elv.GetModule, elv, "Bags", true)
	if ok and type(bags) == "table" and type(bags.UpdateSlot) == "function" and bags.BagFrames then
		return bags
	end
	return nil
end

local function UpdateElvUISlot(slot)
	SetPip(slot, BagMarkers:TierFor(slot.itemID))
end

-- includeClosed covers slots filled before the hook went in.
local function UpdateElvUI(includeClosed)
	for _, frame in pairs(elvBags.BagFrames) do
		if frame.Bags and (includeClosed or frame:IsShown()) then
			for _, bag in pairs(frame.Bags) do
				if type(bag) == "table" then
					for _, slot in ipairs(bag) do UpdateElvUISlot(slot) end
				end
			end
		end
	end
end

local function HookElvUI()
	elvBags = FindElvUIBags()
	if not elvBags then return false end
	hooksecurefunc(elvBags, "UpdateSlot", function(_, frame, bagID, slotID)
		local bag = frame and frame.Bags and frame.Bags[bagID]
		local slot = bag and bag[slotID]
		if slot then UpdateElvUISlot(slot) end
	end)
	UpdateElvUI(true)
	return true
end

-- Redraw pips on open bag windows only; our own refresh never calls Blizzard
-- or ElvUI update code (that would spread taint into the bag buttons).
function BagMarkers:Refresh()
	EachContainerFrame(function(frame)
		if frame:IsShown() then self:UpdateFrame(frame) end
	end)
	if elvBags then UpdateElvUI(false) end
end

local hooked = setmetatable({}, { __mode = "k" })

function BagMarkers:OnLogin()
	local count = 0
	EachContainerFrame(function(frame)
		if not hooked[frame] and frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", function(f) BagMarkers:UpdateFrame(f) end)
			hooked[frame] = true
			count = count + 1
		end
	end)
	local usingElvUI = HookElvUI()
	if count == 0 and not usingElvUI then
		ns:Print("bag markers unavailable: no bag frames found in this client.")
		return
	end
	local function Refresh() self:Refresh() end
	ns:RegisterMessage("SETTINGS_CHANGED", Refresh)
	ns:RegisterMessage("PRICES_CHANGED", Refresh)
end
