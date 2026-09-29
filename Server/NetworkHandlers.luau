-- NetworkHandlers
-- All Network.packets.X.listen(...) bindings and related remote event connections.

local ServiceRefs        = require(script.Parent.ServiceRefs)
local AssetRefs          = require(script.Parent.AssetRefs)
local Constants          = require(script.Parent.Constants)
local ServerState        = require(script.Parent.ServerState)
local ServerHelpers      = require(script.Parent.ServerHelpers)
local ArmLerpSystem      = require(script.Parent.ArmLerpSystem)
local GunSetupSystem     = require(script.Parent.GunSetupSystem)
local GunDropSystem      = require(script.Parent.GunDropSystem)
local PlayerFireSystem   = require(script.Parent.PlayerFireSystem)
local EventRefs          = require(script.Parent.EventRefs)

local ServiceRefs_debris = ServiceRefs.debris
local HttpService        = ServiceRefs.HttpService
local assets             = AssetRefs.assets
local modules            = AssetRefs.modules
local config             = AssetRefs.config
local Network            = AssetRefs.Network
local NetworkRangeUtil   = AssetRefs.NetworkRangeUtil
local MaterialCodec      = AssetRefs.MaterialCodec
local attachmentSystem  = AssetRefs.attachmentSystem
local grenadeHandler     = AssetRefs.grenadeHandler
local glassShatterMod    = AssetRefs.glassShatterMod
local HitResolutionMod   = AssetRefs.HitResolutionMod
local ubglHandler        = AssetRefs.ubglHandler
local magEjection        = AssetRefs.magEjection

local MAX_WEAPON_PUSHBACK        = Constants.MAX_WEAPON_PUSHBACK
local MAX_ARM_C0_DISTANCE        = Constants.MAX_ARM_C0_DISTANCE
local MAX_FIRE_MODE              = Constants.MAX_FIRE_MODE
local FOOTSTEP_REPLICATION_RANGE = Constants.FOOTSTEP_REPLICATION_RANGE
local FALL_SOUND_PITCH_VARIANCE  = Constants.FALL_SOUND_PITCH_VARIANCE
local ARM_PACKET_IGNORE_DURATION = Constants.ARM_PACKET_IGNORE_DURATION
local LPVO_STATES                = Constants.LPVO_STATES
-- NOTE: attachment categories are owned by ThirdParty.AttachmentSystem now;
-- the server validates requests through its public API instead of keeping a
-- second copy of the category set here.
local SERVER_SKIPPED_SOUND_NAMES = Constants.SERVER_SKIPPED_SOUND_NAMES
local GRIP_TARGET_EPSILON        = Constants.GRIP_TARGET_EPSILON

local serverGripTargets      = ServerState.serverGripTargets
local lpvoLockedArms         = ServerState.lpvoLockedArms
local lpvoArmTargets         = ServerState.lpvoArmTargets
local lpvoPreGripTarget      = ServerState.lpvoPreGripTarget
local playerLPVOArmMotor     = ServerState.playerLPVOArmMotor
local playerArmIgnoreUntil   = ServerState.playerArmIgnoreUntil
local playerADSVisualStates  = ServerState.playerADSVisualStates
local pendingGrenadeThrows   = ServerState.pendingGrenadeThrows
local playerLeanStates       = ServerState.playerLeanStates
local shellEjectCooldowns    = ServerState.shellEjectCooldowns

local IsValidCFrame            = ServerHelpers.IsValidCFrame
local FindAnimArmMotor         = ServerHelpers.FindAnimArmMotor
local FindServerLeverRingPart  = ServerHelpers.FindServerLeverRingPart
local FindServerLeverRingMotor = ServerHelpers.FindServerLeverRingMotor
local ResolveLPVOZoomConfig    = ServerHelpers.ResolveLPVOZoomConfig
local GetEquippedWeaponTool    = ServerHelpers.GetEquippedWeaponTool
local RememberArmRestC0        = ServerHelpers.RememberArmRestC0
local GetArmRestC0             = ServerHelpers.GetArmRestC0
local GetServerWeaponModel     = ServerHelpers.GetServerWeaponModel
local ResolveServerGripC0      = ServerHelpers.ResolveServerGripC0
local BroadcastGripHand        = ServerHelpers.BroadcastGripHand
local ResetPlayerGunReplicationState = ServerHelpers.ResetPlayerGunReplicationState
local RefreshPlayerArmReplication    = ServerHelpers.RefreshPlayerArmReplication

local EnsureArmLerpHeartbeat = ArmLerpSystem.EnsureArmLerpHeartbeat

local function SetOverheatEffectActive(model: Model, enable: boolean, heatEffectName: string)
	if not model then return end
	local activeMuzzle = attachmentSystem.GetMuzzle(model)
		or model.Grip:FindFirstChild("Muzzle")
		or model.Grip
	for _, emitter in ipairs(model:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") and emitter.Name == heatEffectName then
			emitter.Enabled = false
		end
	end
	local heatEffect = activeMuzzle:FindFirstChild(heatEffectName)
	if heatEffect and heatEffect:IsA("ParticleEmitter") then
		heatEffect.Enabled = enable
	end
end

local NetworkHandlers = {}

function NetworkHandlers.init()
	-- Body Anim
	Network.packets.BodyAnimRequest.listen(function(angle, player: Player)
		if player.Character
			and (player.Character:FindFirstChild("Torso") or player.Character:FindFirstChild("UpperTorso"))
			and player.Character.Humanoid.Health > 0 then
			local targets = NetworkRangeUtil.GetPlayersInRange(
				player.Character.HumanoidRootPart.Position, config.animDistance, player)
			Network.packets.BodyAnimCommand.sendToList({ Character = player.Character, Angle = angle }, targets)
		end
	end)

	-- Switch Weapon
	Network.packets.SwitchWeaponRequest.listen(function(tool: Tool?, player: Player)
		ResetPlayerGunReplicationState(player)
		if not player.Character or player.Character:FindFirstChild("Humanoid").Health <= 0 then return end
		pendingGrenadeThrows[player] = nil
		local rig = player.Character:FindFirstChild("WeaponRig")
		if not rig then return end
		local curWeapon = rig.Weapon:FindFirstChildWhichIsA("Model")
		local torso     = player.Character:FindFirstChild("UpperTorso") or player.Character:FindFirstChild("Torso")
		if not torso then return end

		if curWeapon then curWeapon:Destroy() end

		if tool and tool:IsA("Tool") then
			if tool:FindFirstChild("Ammo") then
				tool:SetAttribute("HasBeenEquipped", true)
			end
			if torso:FindFirstChild("Left Shoulder")  then torso["Left Shoulder"].Enabled  = false end
			if torso:FindFirstChild("Right Shoulder") then torso["Right Shoulder"].Enabled = false end
			GunSetupSystem.EquipGun(rig, tool, player)
		else
			if torso:FindFirstChild("Left Shoulder")  then torso["Left Shoulder"].Enabled  = true end
			if torso:FindFirstChild("Right Shoulder") then torso["Right Shoulder"].Enabled = true end
			if rig:FindFirstChild("law") then rig.law.Enabled = false end
			if rig:FindFirstChild("raw") then rig.raw.Enabled = false end
		end
	end)

	-- Reload
	Network.packets.ReloadRequest.listen(function(_, player: Player)
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		if not tool then return end
		if not tool:FindFirstChild("SPH_Weapon") or not tool:FindFirstChild("Ammo") then return end
		local wepStats       = require(tool.SPH_Weapon.WeaponStats)
		local magAmmo        = tool.Ammo.MagAmmo
		local arcadeAmmoPool = tool.Ammo.ArcadeAmmoPool
		if not wepStats.operationType or type(wepStats.operationType) == "string" then
			wepStats.operationType = 1
		end
		if not wepStats.magType or type(wepStats.magType) == "string" then
			wepStats.magType = 1
		end
		if wepStats.infiniteAmmo then
			if wepStats.magType == 2 then
				magAmmo.Value += 1
			elseif wepStats.magType == 3 then
				local ammoNeeded = magAmmo.MaxValue - magAmmo.Value
				local clipSize   = (wepStats.clipSize or wepStats.magazineCapacity)
				if ammoNeeded >= clipSize then
					magAmmo.Value += clipSize
				else
					magAmmo.Value += 1
				end
			else
				magAmmo.Value = magAmmo.MaxValue
			end
		elseif arcadeAmmoPool.Value > 0 then
			if wepStats.magType == 1 or wepStats.magType == 4 then
				local ammoNeeded = magAmmo.MaxValue - magAmmo.Value
				if arcadeAmmoPool.Value > ammoNeeded then
					magAmmo.Value        = magAmmo.MaxValue
					arcadeAmmoPool.Value -= ammoNeeded
				else
					magAmmo.Value        += arcadeAmmoPool.Value
					arcadeAmmoPool.Value  = 0
				end
			elseif wepStats.magType == 2 then
				if arcadeAmmoPool.Value > 0 then
					magAmmo.Value        += 1
					arcadeAmmoPool.Value -= 1
				end
			elseif wepStats.magType == 3 then
				local ammoNeeded = magAmmo.MaxValue - magAmmo.Value
				local clipSize   = (wepStats.clipSize or wepStats.magazineCapacity)
				if ammoNeeded >= clipSize and arcadeAmmoPool.Value >= ammoNeeded then
					magAmmo.Value        += clipSize
					arcadeAmmoPool.Value -= clipSize
				else
					magAmmo.Value        += 1
					arcadeAmmoPool.Value -= 1
				end
			end
		end
		if (wepStats.operationType == 4 or wepStats.magType == 4) and not tool.Chambered.Value then
			tool.Chambered.Value  = true
			magAmmo.Value        -= 1
		end

		local gunModel = player.Character.WeaponRig.Weapon:FindFirstChildWhichIsA("Model")
		if wepStats.projectile and wepStats.projectile ~= "Mag"
			and gunModel and gunModel:FindFirstChild(wepStats.projectile, true) then
			local projectile = gunModel:FindFirstChild(wepStats.projectile, true)
			local isLoaded   = false
			if wepStats.openBolt then
				isLoaded = magAmmo.Value > 0
			else
				isLoaded = tool:FindFirstChild("Chambered") and tool.Chambered.Value
			end
			if isLoaded then
				projectile.Transparency = projectile:GetAttribute("OriginalTransparency") or 0
				for _, child in ipairs(projectile:GetDescendants()) do
					if child:IsA("BasePart") or child:IsA("MeshPart") then
						child.Transparency = 0
					end
				end
			else
				if not projectile:GetAttribute("OriginalTransparency") then
					projectile:SetAttribute("OriginalTransparency", projectile.Transparency)
				end
				projectile.Transparency = 1
				for _, child in ipairs(projectile:GetDescendants()) do
					if child:IsA("BasePart") then child.Transparency = 1 end
				end
			end
		end
	end)

	-- Play Sound
	Network.packets.PlaySoundRequest.listen(function(Data, player: Player)
		local soundName = Data.SoundName
		if SERVER_SKIPPED_SOUND_NAMES[soundName] then return end
		local character = player.Character
		if not character then return end
		local rig = character:FindFirstChild("WeaponRig")
		if not rig then return end
		local weaponModel = rig.Weapon:FindFirstChildWhichIsA("Model")
		if not weaponModel then return end
		local grip = weaponModel:FindFirstChild("Grip")
		if not grip then return end
		local soundToPlay = grip:FindFirstChild(soundName)
		if not soundToPlay or not soundToPlay:IsA("Sound") then
			warn(AssetRefs.warnPrefix .. "Sound '" .. soundName .. "' not found for replication on player " .. player.Name)
			return
		end
		soundToPlay.TimePosition = 0
		soundToPlay:Play()
	end)

	-- Bullet Hit
	Network.packets.BulletHit.listen(HitResolutionMod.HandleBulletHit)

	-- Chamber
	Network.packets.PlayerChamberRequest.listen(function(_, player: Player)
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		if tool and tool.Parent == player.Character then
			tool.BoltReady.Value = true
			if tool:FindFirstChild("Chambered") then tool.Chambered.Value = false end
			if tool.Ammo.MagAmmo.Value > 0 and tool:FindFirstChild("Chambered") then
				tool.Ammo.MagAmmo.Value -= 1
				tool.Chambered.Value     = true
			end
		end
	end)

	-- Bolt Open
	Network.packets.RepBoltOpenRequest.listen(function(_, player: Player)
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		if tool and tool.Parent == player.Character then
			tool.BoltReady.Value = false
			if tool:FindFirstChild("Chambered") then tool.Chambered.Value = false end
		end
	end)

	-- Fall Damage
	Network.packets.FallDamageRequest.listen(function(damage, player)
		damage = math.abs(damage)
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if not humanoid then return end
		if humanoid.Health <= damage then
			local killer = Instance.new("StringValue", player.Character)
			killer.Name  = "Killer"
			killer.Value = "Falling"
		end
		humanoid:TakeDamage(damage)

		local fallSounds = assets.Sounds.FallDamage
		local newSound   = fallSounds[Constants.GetFallDamageSoundName(damage)]:Clone()
		newSound.PlaybackSpeed += math.random(-FALL_SOUND_PITCH_VARIANCE, FALL_SOUND_PITCH_VARIANCE) / 100
		newSound.Parent = player.Character.PrimaryPart
		newSound:Play()
		ServiceRefs_debris:AddItem(newSound, newSound.TimeLength)
	end)

	-- Move Bolt
	Network.packets.MoveBoltRequest.listen(function(Data, player)
		local direction, magAmmo = Data.Direction, Data.MagAmmo
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local targets = NetworkRangeUtil.GetPlayersInRange(
				player.Character.HumanoidRootPart.Position, config.fireEffectDistance, player)
			Network.packets.ReplicateBolt.sendToList({
				Player    = player,
				Direction = direction,
				MagAmmo   = magAmmo,
				Instant   = false,
			}, targets)
		end
	end)

	-- Switch Fire Mode
	Network.packets.SwitchFireModeRequest.listen(function(newFireMode, player)
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		if not tool or not tool:FindFirstChild("SPH_Weapon") then return end
		if type(newFireMode) ~= "number" or newFireMode < 0 or newFireMode > MAX_FIRE_MODE then return end
		local ok, wepStats = pcall(require, tool.SPH_Weapon.WeaponStats)
		if not ok then return end
		if newFireMode ~= 0 and not (wepStats.fireSwitch and wepStats.fireSwitch[newFireMode]) then return end
		tool.FireMode.Value = newFireMode
	end)

	-- Chamber Smoke
	Network.packets.ReplicateChamberSmokeRequest.listen(function(duration, player)
		if not player.Character then return end
		local rig = player.Character:FindFirstChild("WeaponRig")
		if not rig then return end
		local weaponFolder = rig:FindFirstChild("Weapon")
		if not weaponFolder then return end
		local weapon = weaponFolder:FindFirstChildWhichIsA("Model")
		if not weapon then return end
		local grip = weapon:FindFirstChild("Grip")
		if not grip then return end
		local tpChamberAttachment = grip:FindFirstChild("Chamber")
		if tpChamberAttachment then
			for _, effect in ipairs(tpChamberAttachment:GetChildren()) do
				if effect:IsA("ParticleEmitter") then
					effect.Enabled = true
					local emitCount = effect:GetAttribute("EmitCount")
					if emitCount then effect:Emit(emitCount) end
				end
			end
			task.delay(duration, function()
				if tpChamberAttachment then
					for _, effect in ipairs(tpChamberAttachment:GetChildren()) do
						if effect:IsA("ParticleEmitter") then
							effect.Enabled = false
						end
					end
				end
			end)
		end
	end)

	-- Overheat
	Network.packets.ReplicateOverheatRequest.listen(function(shouldEnable, player)
		if not player.Character then return end
		local rig = player.Character:FindFirstChild("WeaponRig")
		if not rig then return end
		local weapon = rig.Weapon:FindFirstChildWhichIsA("Model")
		if not weapon then return end
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		if not tool or not tool:FindFirstChild("SPH_Weapon") then return end
		local wepStats = require(tool.SPH_Weapon.WeaponStats)
		local attachmentHeatConfig = attachmentSystem.GetOverheatConfig(weapon)
		local heatConfig = attachmentHeatConfig or wepStats.overHeating
		if not heatConfig or not heatConfig.Enabled then return end
		SetOverheatEffectActive(weapon, shouldEnable, heatConfig.heatEffectName)
	end)

	-- LPVO Ring
	Network.packets.ReplicateLPVORingRequest.listen(function(Data, player)
		local leverC0, armC0, interactionState = Data.LeverC0, Data.ArmC0, Data.State
		if not IsValidCFrame(leverC0, MAX_ARM_C0_DISTANCE) then return end
		if armC0 ~= nil and not IsValidCFrame(armC0, MAX_ARM_C0_DISTANCE) then armC0 = nil end
		if type(interactionState) ~= "string" or not LPVO_STATES[interactionState] then return end

		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		local rig = character:FindFirstChild("WeaponRig")
		if not rig then return end
		local animBase = rig:FindFirstChild("AnimBase")
		if not animBase then return end

		if interactionState == "Exit" then
			local armMotor = playerLPVOArmMotor[player]
			playerLPVOArmMotor[player] = nil

			if armMotor and armMotor.Parent and lpvoLockedArms[armMotor] then
				lpvoLockedArms[armMotor] = nil
				lpvoArmTargets[armMotor] = nil

				local gripRestoreTarget = nil
				local freshGrip = ResolveServerGripC0(player)
				if freshGrip then
					local freshMotor = FindAnimArmMotor(freshGrip.animBase, freshGrip.armName)
					if freshMotor == armMotor then gripRestoreTarget = freshGrip.targetC0 end
				end
				if not gripRestoreTarget then gripRestoreTarget = lpvoPreGripTarget[armMotor] end
				lpvoPreGripTarget[armMotor] = nil

				if gripRestoreTarget then
					serverGripTargets[armMotor] = { target = gripRestoreTarget, active = true }
					EnsureArmLerpHeartbeat()
				else
					local restTarget = GetArmRestC0(armMotor) or armMotor:GetAttribute("OriginalC0")
					if restTarget then armMotor.C0 = restTarget end
				end
				armMotor:SetAttribute("OriginalC0", nil)
			end
			return
		end

		local ignoreUntil = playerArmIgnoreUntil[player]
		if ignoreUntil and os.clock() < ignoreUntil then return end

		local tool = GetEquippedWeaponTool(player)
		if not tool then return end

		local weapon = rig.Weapon:FindFirstChildWhichIsA("Model")
		if not weapon then return end

		local lpvoZoom = ResolveLPVOZoomConfig(tool, weapon)
		if not lpvoZoom or not lpvoZoom.Enabled then return end

		local leverRing = FindServerLeverRingPart(weapon, lpvoZoom.leverRingName)
		if leverRing then
			local leverMotor = FindServerLeverRingMotor(weapon, leverRing, lpvoZoom.leverRingName)
			if leverMotor and leverMotor:IsA("Motor6D") then
				leverMotor.C0 = leverC0
			end
		end

		local adsState = playerADSVisualStates[player]
		if not (adsState and adsState.Aiming) then return end
		if not lpvoZoom.moveArm then return end

		local armName  = lpvoZoom.armToMove or "Right Arm"
		local armMotor = FindAnimArmMotor(animBase, armName)
		if not armMotor then return end

		playerLPVOArmMotor[player] = armMotor

		if interactionState == "Enter" then
			lpvoLockedArms[armMotor] = true
			RememberArmRestC0(armMotor)
			if not armMotor:GetAttribute("OriginalC0") then
				armMotor:SetAttribute("OriginalC0", GetArmRestC0(armMotor) or armMotor.C0)
			end
			local activeGrip = serverGripTargets[armMotor]
			local freshGrip  = ResolveServerGripC0(player)
			if freshGrip and freshGrip.armName == armName then
				lpvoPreGripTarget[armMotor] = freshGrip.targetC0
			elseif activeGrip and activeGrip.active then
				lpvoPreGripTarget[armMotor] = activeGrip.target
			else
				lpvoPreGripTarget[armMotor] = nil
			end
			serverGripTargets[armMotor] = nil
			if armC0 then
				lpvoArmTargets[armMotor] = { target = armC0, active = true }
				EnsureArmLerpHeartbeat()
			end

		elseif interactionState == "Update" then
			if not lpvoLockedArms[armMotor] then
				lpvoLockedArms[armMotor] = true
				RememberArmRestC0(armMotor)
				if not armMotor:GetAttribute("OriginalC0") then
					armMotor:SetAttribute("OriginalC0", GetArmRestC0(armMotor) or armMotor.C0)
				end
				serverGripTargets[armMotor] = nil
			end
			if armC0 then
				lpvoArmTargets[armMotor] = { target = armC0, active = true }
				EnsureArmLerpHeartbeat()
			end
		end
	end)

	-- Player Fire
	Network.packets.PlayerFire.listen(function(Data, player)
		PlayerFireSystem.PlayerFire(player, Data.MuzzleCFrame, Data.Directions)
	end)

	-- UBGL
	Network.packets.PlayerFireUBGL.listen(function(Data, player: Player)
		ubglHandler.Fire(player, Data.FirePointCFrame, Data.Direction)
	end)
	Network.packets.UBGLReload.listen(function(_, player: Player)
		ubglHandler.Reload(player)
	end)

	-- Begin Grenade Throw
	Network.packets.PlayerBeginGrenadeThrow.listen(function(_, player)
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		local tool = character:FindFirstChildWhichIsA("Tool")
		if not tool or not tool:FindFirstChild("SPH_Weapon") then return end
		local wepStats = require(tool.SPH_Weapon.WeaponStats)
		if wepStats.weaponType ~= "Grenade" then return end
		pendingGrenadeThrows[player] = { wepStats = wepStats, tool = tool }
	end)

	-- Throw Grenade
	Network.packets.PlayerThrowGrenade.listen(function(Data, player)
		local direction, clientOrigin, isLowThrow = Data.Direction, Data.ClientOrigin, Data.IsLowThrow
		local character = player.Character
		if not character then return end
		local pending = pendingGrenadeThrows[player]
		if not pending then return end
		local tool = character:FindFirstChildWhichIsA("Tool")
		if pending.tool and tool ~= pending.tool then return end
		local wepStats = pending.wepStats
		if tool and tool:FindFirstChild("SPH_Weapon") then
			wepStats = require(tool.SPH_Weapon.WeaponStats)
		end
		if not wepStats or wepStats.weaponType ~= "Grenade" then return end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		if typeof(direction) ~= "Vector3" or direction.Magnitude == 0 then
			direction = hrp.CFrame.LookVector
		end
		direction = direction.Unit
		local origin = hrp.Position + Vector3.new(0, 1.5, 0) + direction * 2
		if typeof(clientOrigin) == "Vector3" then
			local maxDistanceFromRoot = 6
			if (clientOrigin - hrp.Position).Magnitude <= maxDistanceFromRoot then
				origin = clientOrigin
			end
		end
		grenadeHandler.Throw(player, wepStats, origin, direction, false, isLowThrow == true)
		if tool and wepStats.grenade and wepStats.grenade.consumeOnThrow then
			tool:Destroy()
		end
		pendingGrenadeThrows[player] = nil
	end)

	-- Grenade Cosmetic Detach
	Network.packets.RequestGrenadeCosmeticDetach.listen(function(Data, player)
		local toolName, groupId = Data.ToolName, Data.GroupId
		if not player.Character then return end
		local wepStats
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		if tool and tool.Name == toolName and tool:FindFirstChild("SPH_Weapon") then
			wepStats = require(tool.SPH_Weapon.WeaponStats)
		else
			local pending = pendingGrenadeThrows[player]
			if pending and pending.wepStats then wepStats = pending.wepStats end
		end
		if not wepStats or wepStats.weaponType ~= "Grenade" or not wepStats.grenade then return end
		local detachConfig
		if wepStats.grenade.detachables then
			for _, candidate in ipairs(wepStats.grenade.detachables) do
				if candidate.id == groupId then detachConfig = candidate break end
			end
		end
		if not detachConfig and wepStats.grenade.lowThrow and wepStats.grenade.lowThrow.detachables then
			for _, candidate in ipairs(wepStats.grenade.lowThrow.detachables) do
				if candidate.id == groupId then detachConfig = candidate break end
			end
		end
		if not detachConfig then return end
		local rig = player.Character:FindFirstChild("WeaponRig")
		if not rig then return end
		local weaponModel = rig.Weapon:FindFirstChildWhichIsA("Model")
		if not weaponModel then return end
		grenadeHandler.DetachGrenadeCosmeticGroup(weaponModel, detachConfig, ServerState.shells)
	end)

	-- Character Sound
	EventRefs.playCharacterSoundEvent.OnServerEvent:Connect(function(player, soundType)
		local lastCharacterSound = player:GetAttribute("LastCharacterSound") or 0
		local timeSinceLastSound = os.clock() - lastCharacterSound
		local humanoidRootPart   = player.Character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart and timeSinceLastSound > 0.05 then
			local soundList = assets.Sounds[soundType]:GetChildren()
			local newSound  = soundList[math.random(#soundList)]:Clone()
			newSound.Parent = humanoidRootPart
			newSound:Play()
			ServiceRefs_debris:AddItem(newSound, newSound.TimeLength)
		end
		player:SetAttribute("LastCharacterSound", os.clock())
	end)

	-- Footstep
	Network.packets.FootstepRequest.listen(function(Data, player)
		local foot, volume = Data.Foot, Data.Volume
		local material = MaterialCodec.Decode(Data.MaterialCode)
		if foot and foot:IsDescendantOf(player.Character) and player.Character then
			local targets = NetworkRangeUtil.GetPlayersInRange(
				player.Character.HumanoidRootPart.Position, Constants.FOOTSTEP_REPLICATION_RANGE, player)
			Network.packets.FootstepReplicate.sendToList({
				Player       = player,
				MaterialCode = Data.MaterialCode,
				Foot         = foot,
				Volume       = volume,
			}, targets)
		end
	end)

	-- Drop Gun
	Network.packets.PlayerDropGunRequest.listen(function(_, player)
		GunDropSystem.DropGun(player, nil)
	end)
	EventRefs.dropGunEvent.Event:Connect(GunDropSystem.DropGun)

	-- Toggle Attachment
	Network.packets.PlayerToggleAttachmentRequest.listen(function(Data, player)
		local attachmentType, toggle = Data.AttachmentType, Data.Enabled
		if not player.Character then return end
		local rig = player.Character:FindFirstChild("WeaponRig")
		if not rig then return end
		local weaponFolder = rig:FindFirstChild("Weapon")
		if not weaponFolder then return end
		local weapon = weaponFolder:FindFirstChildWhichIsA("Model")
		if not weapon then return end
		if attachmentType == 0 then
			local flashlightPart = attachmentSystem.GetFlashlightSource(weapon)
			if flashlightPart then
				Network.packets.ToggleAttachmentReplicate.sendToAllExcept({
					LaserPart      = flashlightPart,
					Toggle         = toggle,
					OtherCharacter = nil,
				}, player)
			end
		elseif attachmentType == 1 then
			local laserPart = attachmentSystem.GetLaserSource(weapon)
			if laserPart then
				Network.packets.ToggleAttachmentReplicate.sendToAllExcept({
					LaserPart      = laserPart,
					Toggle         = toggle,
					OtherCharacter = player.Character,
				}, player)
			end
		end
	end)

	-- Grip Hand
	Network.packets.ReplicateGripHandRequest.listen(function(Data, player)
		local targetC0, armName = Data.ArmC0, Data.ArmName
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		local ignoreUntil = playerArmIgnoreUntil[player]
		if ignoreUntil and os.clock() < ignoreUntil and targetC0 ~= nil then return end

		if targetC0 ~= nil then
			if not GetEquippedWeaponTool(player) then return end
			if not IsValidCFrame(targetC0, MAX_ARM_C0_DISTANCE) then return end
			local resolved = ResolveServerGripC0(player)
			if not resolved then
				targetC0 = nil
			else
				targetC0 = resolved.targetC0
				armName  = resolved.armName
			end
		end

		local rig = character:FindFirstChild("WeaponRig")
		if not rig then return end
		local animBase = rig:FindFirstChild("AnimBase")
		if not animBase then return end

		local armMotor = FindAnimArmMotor(animBase, armName)
		if not armMotor then return end

		if lpvoLockedArms[armMotor] then
			if targetC0 then lpvoPreGripTarget[armMotor] = targetC0 end
			return
		end

		if targetC0 then
			RememberArmRestC0(armMotor)
			if not armMotor:GetAttribute("OriginalC0_Grip") then
				armMotor:SetAttribute("OriginalC0_Grip", GetArmRestC0(armMotor) or armMotor.C0)
			end
			local current = serverGripTargets[armMotor]
			if current and current.active
				and (current.target.Position - targetC0.Position).Magnitude < GRIP_TARGET_EPSILON then
				return
			end
			serverGripTargets[armMotor] = { target = targetC0, active = true }
			EnsureArmLerpHeartbeat()
		else
			local rest = GetArmRestC0(armMotor) or armMotor:GetAttribute("OriginalC0_Grip")
			if rest then
				serverGripTargets[armMotor] = { target = rest, active = false }
				EnsureArmLerpHeartbeat()
				armMotor:SetAttribute("OriginalC0_Grip", nil)
			else
				serverGripTargets[armMotor] = nil
			end
		end

		BroadcastGripHand(player, targetC0, armName)
	end)

	-- Mag Grab
	Network.packets.MagGrabRequest.listen(function(_, player)
		if not player or not player.Character then return end
		local tool     = player.Character:FindFirstChildWhichIsA("Tool")
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if not tool or not humanoid or humanoid.Health <= 0 then return end
		if not tool:FindFirstChild("SPH_Weapon") then return end
		local wepStats = require(tool.SPH_Weapon.WeaponStats)
		local rig = player.Character:FindFirstChild("WeaponRig")
		if not rig then return end
		local weaponModel = rig.Weapon:FindFirstChildWhichIsA("Model")
		if not weaponModel then return end
		local magPart = weaponModel:FindFirstChild("Mag")
		if not magPart and wepStats.projectile ~= "Bullet" then
			magPart = weaponModel:FindFirstChild(wepStats.projectile)
		end
		if magPart then
			Network.packets.ReplicateMagGrab.sendToAllExcept({
				TargetPlayer = player,
				MagPart      = magPart,
			}, player)
		end
	end)

	-- Mag Eject
	Network.packets.ReplicateMagEjectRequest.listen(function(Data, player)
		if not player or not player.Character then return end
		local lastEject = player:GetAttribute("SPH_LastMagEject") or 0
		if tick() - lastEject < 0.4 then return end
		player:SetAttribute("SPH_LastMagEject", tick())
		magEjection.ejectMagServer(player, Data.GunName, Data.EjectionCFrame, Data.DropPartNames, ServerState.shells, Data.MagDropFolderSounds)
	end)

	-- Lean
	Network.packets.PlayerLeanRequest.listen(function(leanDirection, player)
		if not player or not player.Character then return end
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		ServerState.playerLeanStates[player] = leanDirection
		Network.packets.ReplicateLean.sendToAllExcept({
			Character     = player.Character,
			LeanDirection = leanDirection,
		}, player)
	end)

	-- Foot IK
	Network.packets.PlayerFootIKRequest.listen(function(Data, player)
		if not player or not player.Character then return end
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end
		local targets = NetworkRangeUtil.GetPlayersInRange(rootPart.Position, config.animDistance, player)
		Network.packets.ReplicateFootIK.sendToList({
			Character   = player.Character,
			Active      = Data.Active,
			RightOffset = Data.RightOffset,
			LeftOffset  = Data.LeftOffset,
			RightNormal = Data.RightNormal,
			LeftNormal  = Data.LeftNormal,
		}, targets)
	end)

	-- Aim
	Network.packets.PlayerAimRequest.listen(function(state, player)
		if not player or not player.Character then return end
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		ServerState.playerAimStates[player] = state
	end)

	-- Weapon Pushback
	Network.packets.WeaponPushbackRequest.listen(function(amount, player)
		if not player or not player.Character then return end
		local character = player.Character
		local humanoid  = character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		local rig = character:FindFirstChild("WeaponRig")
		if not rig then return end
		local tool = character:FindFirstChildWhichIsA("Tool")
		if not tool or not tool:FindFirstChild("SPH_Weapon") then return end
		if tool.Parent ~= character then return end
		local ok, wepStats = pcall(require, tool.SPH_Weapon.WeaponStats)
		if not ok or type(wepStats) ~= "table" then return end
		if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return end
		local configuredMax = tonumber(wepStats.gunLength) or 0
		local maxPushback   = math.clamp(configuredMax, 0, MAX_WEAPON_PUSHBACK)
		local clamped       = math.clamp(amount, 0, maxPushback)
		if rig:GetAttribute("WeaponPushback") == clamped then return end
		rig:SetAttribute("WeaponPushback", clamped)
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end
		local targets = NetworkRangeUtil.GetPlayersInRange(rootPart.Position, config.animDistance, player)
		Network.packets.WeaponPushbackReplicate.sendToList({
			Character = character,
			Pushback  = clamped,
		}, targets)
	end)

	-- Aim State
	Network.packets.PlayerAimStateRequest.listen(function(Data, player)
		if not player or not player.Character then return end
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		local isAiming   = Data.Aiming == true
		local sightIndex = Data.SightIndex or 1
		playerADSVisualStates[player] = { Aiming = isAiming, SightIndex = sightIndex }

		if not isAiming then
			playerLPVOArmMotor[player] = nil
			local rig      = player.Character:FindFirstChild("WeaponRig")
			local animBase = rig and rig:FindFirstChild("AnimBase")
			local freshGrip = ResolveServerGripC0(player)
			local freshMotor = freshGrip and FindAnimArmMotor(freshGrip.animBase, freshGrip.armName)
			if animBase then
				for _, motor in ipairs(animBase:GetChildren()) do
					if motor:IsA("Motor6D") then
						lpvoLockedArms[motor] = nil
						lpvoArmTargets[motor] = nil
						local gripRestore = (freshMotor == motor and freshGrip.targetC0)
							or lpvoPreGripTarget[motor]
						lpvoPreGripTarget[motor] = nil
						if gripRestore then
							serverGripTargets[motor] = { target = gripRestore, active = true }
						else
							local rest = GetArmRestC0(motor) or motor:GetAttribute("OriginalC0")
							if rest then motor.C0 = rest end
							serverGripTargets[motor] = nil
						end
						motor:SetAttribute("OriginalC0", nil)
					end
				end
			end
		end

		local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end
		local targets = NetworkRangeUtil.GetPlayersInRange(rootPart.Position, config.fireEffectDistance, player)
		Network.packets.AimStateReplicate.sendToList({
			Character  = player.Character,
			Aiming     = isAiming,
			SightIndex = sightIndex,
		}, targets)
	end)

	-- Shell Eject
	Network.packets.ShellEjectRequest.listen(function(_, player)
		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
		local now = tick()
		if shellEjectCooldowns[player] and (now - shellEjectCooldowns[player]) < 0.05 then return end
		shellEjectCooldowns[player] = now
		local rootPos = player.Character.HumanoidRootPart.Position
		local targets = NetworkRangeUtil.GetPlayersInRange(rootPos, config.fireEffectDistance, player)
		Network.packets.ShellEjectReplicate.sendToList(player, targets)
	end)

	-- Apply Attachments
	EventRefs.applyAttachmentsEvent.OnServerEvent:Connect(function(player, selectedAttachments)
		if typeof(selectedAttachments) ~= "table" then return end
		if not player.Character then return end
		local tool = GetEquippedWeaponTool(player)
		if not tool then return end
		local rig = player.Character:FindFirstChild("WeaponRig")
		if not rig then return end
		local weaponModel = rig.Weapon:FindFirstChildWhichIsA("Model")
		if not weaponModel then return end

		print("[Server] Received attachment request from:", player.Name)
		local encodedOk, encodedAttachments = pcall(HttpService.JSONEncode, HttpService, selectedAttachments)
		if encodedOk then print("[Server] Attachments:", encodedAttachments) end

		-- Reject what the attachment system would reject, and let it own the
		-- definition of a well-formed request (category set, name length).
		local accepted = {}
		for category, attachmentName in pairs(selectedAttachments) do
			if attachmentSystem.IsValidRequest(attachmentName, category)
				and attachmentSystem.IsCompatible(attachmentName, category, tool.Name) then
				accepted[category] = attachmentName
			end
		end

		local fitted, failed = attachmentSystem.ApplyLoadout(player, tool, weaponModel, accepted)
		if failed and failed > 0 then
			warn(string.format("[Server] %d attachment(s) failed to apply for %s",
				failed, player.Name))
		end

		-- Only persist what actually fitted, so the saved loadout can never
		-- describe attachments the weapon is not wearing.
		local persisted = {}
		for category in pairs(accepted) do
			if attachmentSystem.Has(weaponModel, category) then
				persisted[category] = accepted[category]
			end
		end
		attachmentSystem.SetSaved(tool, persisted)

		print(string.format("[Server]   Applied %d attachment(s) for %s",
			fitted or 0, player.Name))
		RefreshPlayerArmReplication(player)
	end)

	-- Glass Pierce
	Network.packets.PierceGlassRequest.listen(function(Data, player)
		local glassPart, hitPosition = Data.GlassPart, Data.HitPosition
		if not glassShatterMod.IsGlass(glassPart) then return end
		if not config.glassShatter then return end
		if glassPart:GetAttribute("Shattered") then return end
		local character = player.Character
		if not character or not character:FindFirstChild("Humanoid") then return end
		if character.Humanoid.Health <= 0 then return end
		local safeHitPosition = hitPosition or glassPart.Position
		glassShatterMod.Shatter(glassPart, safeHitPosition, Vector3.new(0, 0, -10))
	end)

	-- Part Visibility
	Network.packets.PartVisibilityRequest.listen(function(Data, player)
		local partName, visible = Data.PartName, Data.Visible
		if not player or not player.Character then return end
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		local rig = player.Character:FindFirstChild("WeaponRig")
		if not rig then return end
		local weaponModel = rig.Weapon:FindFirstChildWhichIsA("Model")
		if not weaponModel then return end
		local part = weaponModel:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Transparency = visible and 0 or 1
			for _, child in ipairs(part:GetDescendants()) do
				if child:IsA("BasePart") then
					child.Transparency = visible and 0 or 1
				end
			end
		end
		local rootPos = player.Character.HumanoidRootPart.Position
		local targets = NetworkRangeUtil.GetPlayersInRange(rootPos, config.fireEffectDistance, player)
		Network.packets.PartVisibilityReplicate.sendToList({
			TargetCharacter = player.Character,
			PartName        = partName,
			Visible         = visible,
		}, targets)
	end)

	-- Glass Restored
	EventRefs.glassRestoredEvent.OnServerEvent:Connect(function(player, glassPart, origTransparency)
		-- Handled by client; server just replicates
	end)
end

return NetworkHandlers