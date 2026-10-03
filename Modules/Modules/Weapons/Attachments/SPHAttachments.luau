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

local Attachments = GunAttachments.new({
	contentRoot = getContentRoot,
	-- Default slots = Optics/Underbarrel/Muzzle/Stock, identical to the server whitelist
	-- (Constants.ATTACHMENT_CATEGORIES). Other categories were never persisted by the
	-- server before, so unknown slots stay disabled.
	allowUnknownSlots = false,
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
