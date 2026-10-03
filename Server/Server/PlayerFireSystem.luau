-- PlayerFireSystem
-- PlayerFire: server-side fire validation, ammo deduction, projectile visibility,
-- and replication to nearby players.

local AssetRefs      = require(script.Parent.AssetRefs)
local GunSetupSystem = require(script.Parent.GunSetupSystem)

local assets           = AssetRefs.assets
local Attachments      = AssetRefs.Attachments
local Network          = AssetRefs.Network
local NetworkRangeUtil = AssetRefs.NetworkRangeUtil
local config           = AssetRefs.config
local warnPrefix       = AssetRefs.warnPrefix

local PlayerFireSystem = {}

function PlayerFireSystem.PlayerFire(player: Player, firePoint: CFrame, pelletDirections)
	local tool = player.Character:FindFirstChildWhichIsA("Tool")
	if not tool or not tool:IsA("Tool") then
		warn(warnPrefix .. "PlayerFire Canceled: No tool was found. Player: " .. player.Name)
		return
	end
	if not tool:FindFirstChild("SPH_Weapon") or not tool:FindFirstChild("Ammo") then return end

	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	local gunAmmo  = tool.Ammo
	local magAmmo  = gunAmmo.MagAmmo

	-- Suppressor detection
	local isSuppressed = Attachments:LoadoutHasFlag(tool, "EnableSilencer", "Muzzle")

	-- Ammo / bolt state
	if wepStats.fireMode == 4 then
		if not wepStats.openBolt then tool.Chambered.Value = false end
		tool.BoltReady.Value = false
	elseif not GunSetupSystem.IsGunLoaded(tool) then
		if tool.BoltReady.Value then return end
		if wepStats.emptyCloseBolt then
			tool.BoltReady.Value = true
			return
		end
	else
		if not wepStats.openBolt and not wepStats.shotgun then
			tool.Chambered.Value = false
		end
		if wepStats.shotgun then
			tool.Chambered.Value = false
			tool.BoltReady.Value = false
		else
			tool.BoltReady.Value = not wepStats.emptyLockBolt
			if magAmmo.Value > 0 then
				magAmmo.Value -= 1
				if not wepStats.openBolt then tool.Chambered.Value = true end
				tool.BoltReady.Value = true
			end
		end
	end

	-- Projectile visibility
	local point       = player.Character.HumanoidRootPart.Position
	local dist        = config.fireEffectDistance
	local gunModel
	local fireRig     = player.Character:FindFirstChild("WeaponRig")
	if fireRig then
		local fireWeaponFolder = fireRig:FindFirstChild("Weapon")
		if fireWeaponFolder then
			gunModel = fireWeaponFolder:FindFirstChildWhichIsA("Model")
		end
	end

	if wepStats.projectile and wepStats.projectile ~= "Mag"
		and gunModel and gunModel:FindFirstChild(wepStats.projectile, true) then
		local projectile = gunModel:FindFirstChild(wepStats.projectile, true)
		if projectile and projectile:IsA("BasePart") then
			if not projectile:GetAttribute("OriginalTransparency") then
				projectile:SetAttribute("OriginalTransparency", projectile.Transparency)
			end
			projectile.Transparency = 1
		end
		for _, child in ipairs(projectile:GetDescendants()) do
			if child:IsA("BasePart") then
				if not child:GetAttribute("OriginalTransparency") then
					child:SetAttribute("OriginalTransparency", child.Transparency)
				end
				child.Transparency = 1
			end
		end
	end

	local targets = NetworkRangeUtil.GetPlayersInRange(point, dist, player)
	Network.packets.ReplicateFire.sendToList({
		Shooter      = player,
		MuzzleCFrame = firePoint,
		Suppressed   = isSuppressed,
		Directions   = pelletDirections,
	}, targets)
end

return PlayerFireSystem