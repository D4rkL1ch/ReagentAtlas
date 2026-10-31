-- Recipe data for tests, in the same shape as Data/*.lua.
-- Light Feather (17056) mirrors the tooltip mockup: 7 recipes in 3 professions.
local R = {
	[2963] = { prof = 197, skill = 1, out = 2996, outQ = 1, reagents = { [2589] = 2 } },
	[3275] = { prof = 129, skill = 1, out = 1251, outQ = 1, reagents = { [2589] = 1 } },
	[990001] = { prof = 165, skill = 285, out = 990101, outQ = 2, reagents = { [17056] = 4 } },
	[990002] = { prof = 165, skill = 250, out = 990102, outQ = 2, reagents = { [17056] = 2 } },
	[990003] = { prof = 165, skill = 210, out = 990103, outQ = 2, reagents = { [17056] = 2 } },
	[990004] = { prof = 197, skill = 225, out = 990104, outQ = 2, reagents = { [17056] = 3 } },
	[990005] = { prof = 197, skill = 180, out = 990105, outQ = 1, reagents = { [17056] = 1 } },
	[990006] = { prof = 202, skill = 200, out = 990106, outQ = 2, reagents = { [17056] = 2 } },
	[990007] = { prof = 202, skill = 150, out = 990107, outQ = 1, reagents = { [17056] = 1 } },
	[880001] = { prof = 164, skill = 300, out = 880101, outQ = 4, reagents = { [12360] = 10 } },
	[880002] = { prof = 164, skill = 260, out = 880102, outQ = 3, reagents = { [12359] = 4 } },
}

local G = {
	[2589] = { r = { 2963, 3275 } },
	[17056] = { r = { 990001, 990002, 990004, 990003, 990006, 990005, 990007 }, spell = { "MAGE", "PRIEST" } },
	[12360] = { r = { 880001 } },
	[12359] = { r = { 880002 } },
	[17020] = { r = {}, spell = { "MAGE" } },
}

return {
	Recipes = R,
	Reagents = G,
	ProfessionNames = {
		[129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking",
		[197] = "Tailoring", [202] = "Engineering",
	},
}
