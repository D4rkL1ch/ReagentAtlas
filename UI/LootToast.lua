local addonName, ns = ...

-- On-screen loot alert: each item's icon and name, then who can craft what
-- with it, or who could learn it. Click-through, fades on its own.
local LootToast = ns:RegisterModule("LootToast", {})

local WIDTH = 400
local PAD = 10
local ICON = 32
local ICON_GAP = 8
local ROW_GAP = 8
local DURATION = 8 -- seconds shown, the fade included
local FADE = 1
local MAX_SHOWN = 3 -- items in one toast; chat has the rest

local TEXT_WIDTH = WIDTH - 2 * PAD - ICON - ICON_GAP

local frame
local rows = {}

local function CreateRow()
	local row = CreateFrame("Frame", nil, frame)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(ICON, ICON)
	row.Icon:SetPoint("TOPLEFT")
	row.Title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Title:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", ICON_GAP, 0)
	row.Title:SetWidth(TEXT_WIDTH)
	row.Title:SetJustifyH("LEFT")
	row.Body = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Body:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -3)
	row.Body:SetWidth(TEXT_WIDTH)
	row.Body:SetJustifyH("LEFT")
	return row
end

local function OnUpdate(self, elapsed)
	self.remaining = self.remaining - elapsed
	if self.remaining <= 0 then
		self:Hide()
	elseif self.remaining < FADE then
		self:SetAlpha(self.remaining / FADE)
	end
end

local function CreateToast()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetWidth(WIDTH)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -150)
	frame:EnableMouse(false)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.75)
	local accent = frame:CreateTexture(nil, "BORDER")
	accent:SetPoint("TOPLEFT")
	accent:SetPoint("TOPRIGHT")
	accent:SetHeight(2)
	accent:SetColorTexture(1, 0.82, 0, 0.9)
	frame.More = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.More:SetJustifyH("LEFT")
	frame:SetScript("OnUpdate", OnUpdate)
	frame:Hide()
	LootToast.frame = frame
end

-- alerts: array of { itemID, title, details = array of lines }. Replaces what
-- is showing and starts the clock again.
function LootToast:Show(alerts)
	if not frame then CreateToast() end
	local y = -PAD
	local shown = math.min(#alerts, MAX_SHOWN)
	for i = 1, shown do
		local alert = alerts[i]
		local row = rows[i] or CreateRow()
		rows[i] = row
		row.Icon:SetTexture(C_Item.GetItemIconByID(alert.itemID))
		row.Title:SetText(alert.title)
		row.Body:SetText(table.concat(alert.details, "\n"))
		local height = math.max(ICON, row.Title:GetStringHeight() + 3 + row.Body:GetStringHeight())
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD, y)
		row:SetSize(WIDTH - 2 * PAD, height)
		row:Show()
		y = y - height - ROW_GAP
	end
	for i = shown + 1, #rows do rows[i]:Hide() end
	if #alerts > shown then
		frame.More:SetText(("+%d more, see chat"):format(#alerts - shown))
		frame.More:ClearAllPoints()
		frame.More:SetPoint("TOPLEFT", PAD, y)
		frame.More:Show()
		y = y - frame.More:GetStringHeight() - ROW_GAP
	else
		frame.More:Hide()
	end
	frame:SetHeight(-y - ROW_GAP + PAD)
	frame.remaining = DURATION
	frame:SetAlpha(1)
	frame:Show()
end
