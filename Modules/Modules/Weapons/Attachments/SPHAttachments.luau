--!nonstrict
-- SPHAttachments
-- SPH's integration point for the standalone GunAttachments package.
--
-- This is the ONLY module that knows about both SPH and GunAttachments. It creates
-- one attachment system per Lua VM (module cache = singleton) configured with SPH's
-- content folder and SPH-specific hooks, and returns it.
--
--     local Attachments = require(Modules.Weapons.Attachments.SPHAttachments)
--     Attachments:ApplyLoadout(gunModel, tool, player)
--
-- See Modules/ThirdParty/GunAttachments/README.md for the API.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script:FindFirstAncestor("Modules")
local GunAttachments = require(Modules.ThirdParty.GunAttachments)
local WeaponLighting = require(script.Parent.WeaponLighting)

-- Content folder: ReplicatedStorage.SPH_Assets.GunAttachments.
-- Resolved lazily so requiring this module never yields (the old manager used
-- WaitForChild at require time). A background wait keeps the old guarantee that the
-- folder is picked up as soon as it replicates.
local contentRoot: Instance? = nil
local function getContentRoot(): Instance?
	if contentRoot and contentRoot.Parent then
		return contentRoot
	end
	local assets = ReplicatedStorage:FindFirstChild("SPH_Assets")
	contentRoot = assets and assets:FindFirstChild("GunAttachments") or nil
	return contentRoot
end
task.spawn(function()
	local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
	contentRoot = assets:WaitForChild("GunAttachments")
end)

-- Old behaviour of ApplyAttachmentStats(tool, nil): use the first-person viewmodel's
-- gun (workspace.CurrentCamera/<ViewRig>/Weapon/<GunModel>).
local function resolveViewmodelGun(_tool: Instance): Instance?
	local camera = workspace.CurrentCamera
	local viewRig = camera and camera:FindFirstChildWhichIsA("Model")
	local weaponFolder = viewRig and viewRig:FindFirstChild("Weapon")
	return weaponFolder and weaponFolder:FindFirstChildWhichIsA("Model") or nil
end

-- Flashlight/Laser stat blocks contain Color3 values that do not survive the JSON
-- snapshot; re-inject the authored values (same as the old manager).
local function reinjectLighting(tool: Instance, stats: any)
	local authored = WeaponLighting.GetStatsForSource(tool)
	if authored then
		stats.Flashlight = authored.Flashlight
		stats.Laser = authored.Laser
	end
end

-- SPH slot list — the SINGLE source of truth for attachment capacity. It is the server
-- whitelist (SanitizeLoadout), the mount-part map, the stats order, and the list of
-- slots the Customize UI can show. To add an attachment type: add a row here, put
-- content in SPH_Assets/GunAttachments/<Slot>/<Name>, and add a <mountPart> with an
-- Attachment named <Name> to every gun that should accept it. No UI code is needed.
--
-- The first four rows are the original slots, unchanged (names, mount parts, order,
-- roles), so existing loadouts, content and stats behave exactly as before. A slot
-- only appears in the UI for guns that have its mount part and fitting content.
local SLOTS = {
	{ name = "Optics", mountPart = "OpticPart", order = 1, role = "optic" },
	{ name = "Underbarrel", mountPart = "GripPart", order = 2, role = "grip" },
	{ name = "Muzzle", mountPart = "MuzzlePart", order = 3, role = "muzzle", overridesMuzzle = true },
	{ name = "Stock", mountPart = "StockPart", order = 4 },
	-- Extended muzzle category (barrel extensions, compensators). Mounted before the
	-- muzzle device; the muzzle point comes from the highest-order muzzle slot.
	{ name = "Barrel", mountPart = "BarrelPart", order = 2.5, role = "muzzle", overridesMuzzle = true },
	-- Magazines (capacity etc. via ApplyStats).
	{ name = "Magazine", mountPart = "MagazinePart", order = 5 },
	-- Dual sights: a second optic (canted / piggyback). Its AimParts follow the
	-- primary optic's in the sight-switch cycle.
	{ name = "SecondaryOptic", mountPart = "SecondaryOpticPart", order = 6, role = "optic" },
}

local Attachments = GunAttachments.new({
	contentRoot = getContentRoot,
	slots = SLOTS,
	-- Categories outside SLOTS are rejected (matches the original server whitelist).
	allowUnknownSlots = false,
	-- Capacity / conflict rules (enforced server-side by SanitizeLoadout). Off by
	-- default; set a number here for a global cap, or a "MaxAttachments" number
	-- attribute on a Tool for a per-weapon cap. Conflicts come from attachment configs
	-- (ConflictsWith = { "Slot" | "Slot/Name" }).
	rules = {
		maxAttachments = nil,
		capacityAttribute = "MaxAttachments",
	},
	hooks = {
		resolveModel = resolveViewmodelGun,
		onSnapshotRestored = reinjectLighting,
	},
	log = {
		warn = function(prefix, ...)
			warn(prefix, ...)
		end,
	},
})

return Attachments
