-- Bootstrap/PreloadSetup
-- Asset preloading tasks (animations, projectiles).
-- All side-effects only; returns nothing useful.

local AssetRefs       = require(script.Parent.AssetRefs)
local StateInit       = require(script.Parent.StateInit)
local ServiceRefs     = require(script.Parent.ServiceRefs)
local ContentProvider = ServiceRefs.ContentProvider

local modules         = AssetRefs.modules
local animations      = AssetRefs.animations
local assets          = AssetRefs.assets
local warnPrefix      = StateInit.warnPrefix

local assetPreloader    = require(modules.Systems.AssetPreloader)
local gunModelPreloader = require(modules.Weapons.Equip.GunModelPreloader)
local weldMod           = require(modules.Weapons.Core.WeldMod)

local storageCFrame = StateInit.storageCFrame
local camera        = require(script.Parent.CameraSetup).camera

-- Preload animations synchronously-ish
assetPreloader.PreloadAllAnimations(animations)

-- Preload projectile assets
task.spawn(function()
	local projectilesFolder = assets:FindFirstChild("Projectiles")
	if projectilesFolder and projectilesFolder:IsA("Folder") then
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(projectilesFolder:GetDescendants())
		end)
		if not ok then
			warn(warnPrefix .. "Failed to preload grenade/projectile assets: " .. tostring(err))
		end
	end
end)

-- Preload gun models
gunModelPreloader.PreloadAllGunModels(assets, camera, storageCFrame, weldMod)

local PreloadSetup = {}
PreloadSetup.assetPreloader = assetPreloader
return PreloadSetup