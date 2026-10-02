-- GunSetupSystem
-- SetupGun, EquipGun, EquipGrenadeServerModel, IsGunLoaded.

local AssetRefs     = require(script.Parent.AssetRefs)
local Constants     = require(script.Parent.Constants)
local ServerState   = require(script.Parent.ServerState)
local ServerHelpers = require(script.Parent.ServerHelpers)

local assets            = AssetRefs.assets
local modules           = AssetRefs.modules
local weldMod           = AssetRefs.weldMod
local attachmentManager = AssetRefs.attachmentManager
local Network           = AssetRefs.Network
local NetworkRangeUtil  = AssetRefs.NetworkRangeUtil
local ubglHandler       = AssetRefs.ubglHandler
local config            = AssetRefs.config
local warnPrefix        = AssetRefs.warnPrefix
local players           = require(script.Parent.ServiceRefs).players

local GunSetupSystem = {}

function GunSetupSystem.SetupGun(tool: Tool, wepStats)
	tool.CanBeDropped = false
	if wepStats.weaponType == "Grenade" then return end

	local ammoFolder = tool:FindFirstChild("Ammo")
	if not ammoFolder then
		ammoFolder        = Instance.new("Folder")
		ammoFolder.Name   = "Ammo"
		ammoFolder.Parent = tool
	end

	local magAmmo = ammoFolder:FindFirstChild("MagAmmo")
	if not magAmmo then
		magAmmo          = Instance.new("DoubleConstrainedValue")
		magAmmo.Name     = "MagAmmo"
		magAmmo.MaxValue = wepStats.magazineCapacity
		magAmmo.Value    = wepStats.magazineAmmo or magAmmo.MaxValue
		magAmmo.Parent   = ammoFolder
	end

	if not ammoFolder:FindFirstChild("ArcadeAmmoPool") then
		local arcadeAmmoPool          = Instance.new("DoubleConstrainedValue")
		arcadeAmmoPool.Name           = "ArcadeAmmoPool"
		arcadeAmmoPool.MaxValue       = wepStats.maxAmmoPool
		arcadeAmmoPool.Value          = wepStats.startAmmoPool
		arcadeAmmoPool.Parent         = ammoFolder
	end

	if not wepStats.openBolt and not tool:FindFirstChild("Chambered") then
		local chambered       = Instance.new("BoolValue")
		chambered.Value       = wepStats.startChambered
		chambered.Name        = "Chambered"
		chambered.Parent      = tool
		if chambered.Value then
			if magAmmo.Value > 0 then
				magAmmo.Value -= 1
			else
				chambered.Value = false
			end
		end
	end

	if not tool:FindFirstChild("BoltReady") then
		local boltReady       = Instance.new("BoolValue")
		boltReady.Value       = true
		boltReady.Name        = "BoltReady"
		boltReady.Parent      = tool
	end

	if not tool:FindFirstChild("FireMode") then
		local fireMode        = Instance.new("IntValue")
		fireMode.Value        = wepStats.fireMode
		fireMode.Name         = "FireMode"
		fireMode.Parent       = tool
	end

	ubglHandler.SetupAmmo(tool, wepStats)
end

function GunSetupSystem.EquipGrenadeServerModel(rig, tool, wepStats)
	local gun = assets.WeaponModels[tool.Name]:Clone()

	if not wepStats.disableAutoRigging then
		weldMod.WeldModel(gun, gun.Grip, false)
		for _, partName in ipairs(wepStats.rigParts or {}) do
			if gun:FindFirstChild(partName) then
				local existingWeld = gun.Grip:FindFirstChild("Grip_" .. partName)
				if existingWeld then existingWeld:Destroy() end
				local newMotor = weldMod.M6D(gun.Grip, gun[partName])
				newMotor.Name   = partName
				newMotor.Parent = gun.Grip
			end
		end
		for _, desc in ipairs(gun:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
				desc.CastShadow = false
			end
		end
	end

	gun.Parent = rig.Weapon

	if rig.AnimBase:FindFirstChild("GunMotor") then
		rig.AnimBase.GunMotor:Destroy()
	end

	local gunMotor = weldMod.BlankM6D(rig.AnimBase, gun.Grip)
	gunMotor.Name  = "GunMotor"
	rig.law.Enabled = true
	rig.raw.Enabled = true
	local grenadeBaseWeld = rig:FindFirstChild("BaseWeld")
	if grenadeBaseWeld and grenadeBaseWeld:IsA("JointInstance") then
		grenadeBaseWeld.C0 = wepStats.serverOffset or CFrame.new()
	end

	GunSetupSystem.SetupGun(tool, wepStats)
	ubglHandler.SetupAmmo(tool, wepStats)

	return gun
end

function GunSetupSystem.EquipGun(rig: Model, tool: Tool, equipPlayer: Player)
	if tool.Parent == rig.Parent and assets.WeaponModels:FindFirstChild(tool.Name) then
		if not tool:FindFirstChild("SPH_Weapon") then
			warn(warnPrefix .. "EquipGun: '" .. tool.Name .. "' has no SPH_Weapon yet (not replicated). Skipping.")
			return
		end
		local wepStats = require(tool.SPH_Weapon.WeaponStats)

		if wepStats.weaponType == "Grenade" then
			return GunSetupSystem.EquipGrenadeServerModel(rig, tool, wepStats)
		end

		local gun = assets.WeaponModels[tool.Name]:Clone()

		if not wepStats.disableAutoRigging then
			weldMod.WeldModel(gun, gun.Grip, false)
			for _, partName in ipairs(wepStats.rigParts) do
				if gun:FindFirstChild(partName) then
					gun.Grip["Grip_" .. partName]:Destroy()
					local newMotor = weldMod.M6D(gun.Grip, gun[partName])
					newMotor.Name   = partName
					newMotor.Parent = gun.Grip
				end
			end
			for _, desc: BasePart in gun:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.CanCollide = false
					desc.CastShadow = false
				end
			end
		end

		local projectile = gun:FindFirstChild(wepStats.projectile, true)
		if (wepStats.openBolt or not tool.Chambered.Value)
			and projectile
			and wepStats.projectile ~= "Bullet"
			and projectile.Name ~= "Mag" then
			projectile:SetAttribute("OriginalTransparency", projectile.Transparency)
			projectile.Transparency = 1
			for _, child in ipairs(projectile:GetDescendants()) do
				if child:IsA("BasePart") then child.Transparency = 1 end
			end
		end

		for _, part in ipairs(gun:GetDescendants()) do
			if part.Name == "SightReticle" then
				local sg = part:FindFirstChildWhichIsA("SurfaceGui")
				if sg then sg.Enabled = false end
			end
		end

		gun.Parent = rig.Weapon

		for _, part in ipairs(gun:GetDescendants()) do
			if part:IsA("BasePart") and part.Name == "" then
				part.Transparency = 1
			end
		end

		attachmentManager.ClearAllAttachments(gun)
		attachmentManager.PrepareForEquip(gun)

		if tool:FindFirstChild("SavedAttachments") then
			for _, attachmentData in ipairs(tool.SavedAttachments:GetChildren()) do
				if attachmentData:IsA("StringValue") and attachmentData.Value ~= "" then
					local category       = attachmentData.Name
					local attachmentName = attachmentData.Value
					local success = attachmentManager.EquipAttachment(
						players:GetPlayerFromCharacter(rig.Parent),
						tool, gun, attachmentName, category)
					if success then
						print("[Server] Applied", attachmentName, "to TP model")
					else
						warn("[Server] Failed to apply", attachmentName, "to TP model")
					end
				end
			end
		end

		if rig.AnimBase:FindFirstChild("GunMotor") then
			rig.AnimBase:FindFirstChild("GunMotor"):Destroy()
		end

		local gunMotor = weldMod.BlankM6D(rig.AnimBase, gun.Grip)
		gunMotor.Name   = "GunMotor"
		rig.law.Enabled = true
		rig.raw.Enabled = true
		local baseWeld  = rig:FindFirstChild("BaseWeld")
		if baseWeld and baseWeld:IsA("JointInstance") then
			baseWeld.C0 = wepStats.serverOffset or CFrame.new()
		end

		GunSetupSystem.SetupGun(tool, wepStats)

		local boltReadyVal = tool:FindFirstChild("BoltReady")
		local ammoFolder   = tool:FindFirstChild("Ammo")
		local magAmmoVal   = ammoFolder and ammoFolder:FindFirstChild("MagAmmo")

		if boltReadyVal and not boltReadyVal.Value and wepStats.boltDist then
			if not magAmmoVal then
				warn(warnPrefix .. "EquipGun: '" .. tool.Name .. "' lost its Ammo folder mid-equip (likely destroyed by drop despawn/eviction). Skipping bolt sync.")
			else
				local bh       = require(modules.Weapons.Fire.BulletHandler)
				local magValue = magAmmoVal.Value
				pcall(bh.MoveBolt, gun, wepStats, wepStats.boltDist, magValue, true)
				if equipPlayer and equipPlayer.Character then
					local hrp = equipPlayer.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						local sendDirection = typeof(wepStats.boltDist) == "CFrame"
							and wepStats.boltDist
							or CFrame.new(0, 0, -wepStats.boltDist)
						local targets = NetworkRangeUtil.GetPlayersInRange(
							hrp.Position, config.fireEffectDistance, equipPlayer)
						Network.packets.ReplicateBolt.sendToList({
							Player    = equipPlayer,
							Direction = sendDirection,
							MagAmmo   = magValue,
							Instant   = true,
						}, targets)
					end
				end
			end
		end

		return gun
	end
end

function GunSetupSystem.IsGunLoaded(tool)
	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	local gunAmmo  = tool.Ammo
	return not wepStats.openBolt and tool.Chambered.Value
		or wepStats.openBolt and gunAmmo.MagAmmo.Value > 0
end

return GunSetupSystem