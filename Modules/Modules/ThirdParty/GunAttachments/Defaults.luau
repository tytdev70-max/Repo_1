--!nonstrict
-- GunAttachments/Defaults
-- Default options. These reproduce the conventions of the original SPH attachment
-- manager exactly, so a system created with no overrides behaves like the old one.

local Defaults = {}

Defaults.slots = {
	{ name = "Optics", mountPart = "OpticPart", order = 1, role = "optic" },
	{ name = "Underbarrel", mountPart = "GripPart", order = 2, role = "grip" },
	{ name = "Muzzle", mountPart = "MuzzlePart", order = 3, role = "muzzle", overridesMuzzle = true },
	{ name = "Stock", mountPart = "StockPart", order = 4 },
}

Defaults.options = {
	configModuleName = "Customization",
	allowUnknownSlots = false,
	modelRootNames = { "Grip", "Base" },
	nodeSuffix = "_Equipped",
	loadout = {
		folderName = "SavedAttachments",
		jsonAttribute = "SavedAttachmentsJSON",
		maxNameLength = 64,
	},
	stats = {
		writeSnapshots = true,
		originalAttribute = "OriginalStats",
		modifiedAttribute = "ModifiedStats",
	},
}

-- Instance / attribute names used by the muzzle-override protocol. Kept as constants
-- because other scripts (and existing content) observe them.
Defaults.attributes = {
	activeCustomMuzzle = "ActiveCustomMuzzle",
	originalTransparency = "OriginalTransparency_Muzzle",
	originalEnabled = "OriginalEnabled_Muzzle",
	preHidden = "MuzzlePreHidden",
	overridden = "OverriddenByAttachment",
	hiddenPartTransparency = "GunAttachments_OriginalTransparency",
}

-- Grip defaults (R6 arm name kept for compatibility).
Defaults.grip = {
	handToPosition = "Left Arm",
	transitionSpeed = 15,
}

Defaults.adsTweenDivisor = 20
Defaults.adsTweenFallback = 0.2

-- Recursively fills `target` with values from `source` where target has nil.
local function fill(target: { [any]: any }, source: { [any]: any })
	for key, value in pairs(source) do
		if target[key] == nil then
			if type(value) == "table" then
				local copy = {}
				fill(copy, value)
				target[key] = copy
			else
				target[key] = value
			end
		elseif type(target[key]) == "table" and type(value) == "table" and not (value :: any)[1] then
			fill(target[key], value)
		end
	end
end

-- Returns a new options table: user options layered over defaults. User tables are
-- shallow-copied so later mutation by the caller cannot affect a running system.
function Defaults.merge(user: { [string]: any }?): { [string]: any }
	local result: { [string]: any } = {}
	if user then
		for key, value in pairs(user) do
			if type(value) == "table" and key ~= "contentRoot" then
				result[key] = table.clone(value)
			else
				result[key] = value
			end
		end
	end
	fill(result, Defaults.options)
	if result.slots == nil then
		result.slots = {}
		for index, slot in ipairs(Defaults.slots) do
			result.slots[index] = table.clone(slot)
		end
	end
	result.hooks = result.hooks or {}
	result.services = result.services or {}
	return result
end

return Defaults
