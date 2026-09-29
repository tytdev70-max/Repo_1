--!strict

local Modules = script:FindFirstAncestor("Modules")
local Assets = Modules.Parent

local WeaponContext = require(Modules.Weapons.Core.WeaponContext)
local vars = require(Modules.Weapons.Core.WeaponState).get()
local config = require(Assets.GameConfig)
local ubglSystem = require(Modules.Weapons.Attachments.UBGLHandlerMod)
local userInputService = game:GetService("UserInputService")

local WeaponSequences = {}

local ChangeHoldStance, CollectAndManageSights, GetThirdPersonGunModel, PlayAnimation
local StopAnimation, ToggleAiming, ToggleSprint, animBase
local character, fireModes, gunRecoilSpring, gunRotSpring
local vmAnimator, warnPrefix

local PlayEmptyClickAnimation, ChamberAnim, IdleAnim, EquipAnim, ReloadAnim

local function GetToolValue(tool, valueName)
	local value = tool and tool:FindFirstChild(valueName)
	return value ~= nil and value.Value
end

local function GetMagAmmo()
	return vars.gunAmmo and vars.gunAmmo:FindFirstChild("MagAmmo")
end

PlayEmptyClickAnimation = function()
	if not vars.wepStats.emptyClick or vars.emptyClickPlaying or vars.emptyClickDebounce then return end

	vars.emptyClickPlaying = true
	vars.emptyClickDebounce = true

	local originalDamping = gunRecoilSpring.Damping
	local originalSpeed   = gunRecoilSpring.Speed

	gunRecoilSpring.Damping = 8
	gunRecoilSpring.Speed   = 14

	local pushZ = -0.08

	gunRecoilSpring:shove(Vector3.new(0, 0, pushZ))

	task.wait(0.45)

	gunRecoilSpring.Damping = originalDamping
	gunRecoilSpring.Speed   = originalSpeed

	vars.emptyClickPlaying = false
	vars.emptyClickDebounce = false
end

ChamberAnim = function()
	if vars.inspecting or vars.chambering then return end  
	if not vars.equipped or not vars.wepStats then return end
	local animNameToPlay
	if vars.wepStats.shotgun or GetToolValue(vars.equipped, "BoltReady") or vars.curFireMode == fireModes.Manual then
		animNameToPlay = vars.wepStats.boltChamber
	else
		animNameToPlay = vars.wepStats.boltClose
	end

	if animNameToPlay then
		vars.reloading = true
		vars.chambering = true
		local chamberMagAmmo = GetMagAmmo()
		local hasAnythingToEject = (not vars.ejected)
			or GetToolValue(vars.equipped, "Chambered")
			or (vars.wepStats.openBolt and chamberMagAmmo ~= nil and chamberMagAmmo.Value > 0)
		if hasAnythingToEject then
			vars.ejected = false
		end
		ChangeHoldStance(0)

		if vars.wepStats.fireAnim then
			StopAnimation(vars.wepStats.fireAnim, 0.05)
		end

		local playingAnim:AnimationTrack = PlayAnimation(animNameToPlay,{priority = Enum.AnimationPriority.Action2,transSpeed = 0.05})
		if playingAnim then
			playingAnim.Stopped:Once(function()
				vars.chambering = false
				vars.reloading = false
				vars.canFire = true
			end)
		else
			vars.reloading = false
			vars.chambering = false
			vars.canFire = true
		end
	end
end

IdleAnim = function()
	if not vars.equipped or not vars.wepStats then return end
	if ubglSystem.IsActive() or ubglSystem.IsToggling() then return end

	if vars.wepStats.fireAnim then
		StopAnimation(vars.wepStats.fireAnim, 0.05)
	end
	if vars.wepStats.sprintAnim then
		StopAnimation(vars.wepStats.sprintAnim, 0.05)
	end
	if vars.wepStats.UBGLIdle then
		StopAnimation(vars.wepStats.UBGLIdle, 0.05)
	end

	local success = pcall(function()
		PlayAnimation(vars.wepStats.idleAnim, {looped = true, priority = Enum.AnimationPriority.Idle})
	end)

	if not success then
		warn("[CharacterClient] Failed to play idle animation:", vars.wepStats.idleAnim)
	end
end

EquipAnim = function()
	local capturedGeneration = vars.equipGeneration  
	character:SetAttribute("BackpackDisabled", true)
	vars.equipping = true
	userInputService.MouseIconEnabled = false

	gunRotSpring.Damping = vars.wepStats.rotationalRecoil.damping or 4
	gunRotSpring.Speed = vars.wepStats.rotationalRecoil.speed or 6

	vars.viewmodelVisible = false
	if vars.aiming then ToggleAiming(false) end
	local hasBeenEquipped = vars.equipped:GetAttribute("HasBeenEquipped")
	local useFirstAnim = not hasBeenEquipped and vars.wepStats.equipFirst ~= nil
	local animToPlay = useFirstAnim and vars.wepStats.equipFirst or vars.wepStats.equipAnim
	local speedMultiplier = useFirstAnim and (vars.wepStats.equipFirstSpeedModifier or 1) or (vars.wepStats.equipSpeedModifier or 1)
	if not hasBeenEquipped then
		vars.equipped:SetAttribute("HasBeenEquipped", true)
	end


	CollectAndManageSights(vars.gunModel)


	local startTime = tick()
	repeat
		task.wait()
	until tick() - startTime > 0.5
		or (vars.gunModel and vars.gunModel.Parent and vars.gunModel:FindFirstChild("Grip")
			and animBase:FindFirstChild("AnimBase_Grip")
			and animBase.AnimBase_Grip.Part0 and animBase.AnimBase_Grip.Part1
			and vmAnimator)


	local animTrack = PlayAnimation(animToPlay, {
		priority = Enum.AnimationPriority.Action2,
		looped = false,
		speed = speedMultiplier
	}, "Equip")

	if vars.firstPerson then
		task.spawn(function()
			task.wait()
			vars.viewmodelVisible = true
		end)
	end

	if animTrack then
		animTrack.Stopped:Once(function()
			if vars.equipGeneration ~= capturedGeneration then return end 
			vars.equipping = false
			vars.sprinting = character:GetAttribute("Sprinting")
			ToggleSprint(vars.sprinting)
			userInputService.MouseIconEnabled = false
			if vars.switchingWeapons then
				character:SetAttribute("BackpackDisabled", true)
			elseif not character:GetAttribute("IsSwimming") then
				character:SetAttribute("BackpackDisabled", false)
			end
		end)
	else

		if vars.firstPerson then
			vars.viewmodelVisible = true
		end
		vars.equipping = false
		vars.sprinting = character:GetAttribute("Sprinting")
		ToggleSprint(vars.sprinting)
		userInputService.MouseIconEnabled = false
		if vars.switchingWeapons then
			character:SetAttribute("BackpackDisabled", true)
		elseif not character:GetAttribute("IsSwimming") then
			character:SetAttribute("BackpackDisabled", false)
		end
	end
end

ReloadAnim = function()
	if not vars.equipped or not vars.wepStats then return end
	if vars.inspecting or vars.reloading then return end
	local capturedTool = vars.equipped
	if not config.canReloadWhileAiming and vars.aiming then
		ToggleAiming(false)
	end
	vars.cancelReload = false
	vars.magDroppedThisReload = false
	vars.slideReleaseHasPlayed = false     
	local capturedGeneration = vars.equipGeneration 
	ChangeHoldStance(0)
	if vars.wepStats.fireAnim then
		StopAnimation(vars.wepStats.fireAnim, 0.1)
	end
	vars.reloading = true
	
	if vars.wepStats.keepProjectileVisibleDuringReload
		and vars.wepStats.projectile and vars.wepStats.projectile ~= "Bullet" and vars.gunModel then

		local function show(part)
			if not part then return end
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 0
				part.Transparency = 0
			end
			for _, c in ipairs(part:GetDescendants()) do
				if c:IsA("BasePart") then
					c.LocalTransparencyModifier = 0
					c.Transparency = 0
				elseif c:IsA("Decal") or c:IsA("Texture") then
					c.Transparency = 0
				end
			end
		end

		show(vars.gunModel:FindFirstChild(vars.wepStats.projectile, true))

		local tpGun = GetThirdPersonGunModel()
		if tpGun then
			show(tpGun:FindFirstChild(vars.wepStats.projectile, true))
		end
	end

	local magAmmo = GetMagAmmo()
	local magEmpty = (magAmmo == nil) or magAmmo.Value <= 0
	local isEmpty = (magEmpty and not GetToolValue(capturedTool, "Chambered"))
	local useEmptyReloadAnim = isEmpty and vars.wepStats.emptyReloadAnim

	if vars.wepStats.magType ~= 4 and (vars.wepStats.operationType == 3 or (vars.wepStats.operationType == 2 and magEmpty and not GetToolValue(capturedTool, "Chambered"))) then
		if vars.wepStats.operationType == 3 then
			vars.ejected = false
		end
		local boltOpenTrack = PlayAnimation(vars.wepStats.boltOpen, {speed = vars.wepStats.reloadSpeedModifier, priority = Enum.AnimationPriority.Action2, transSpeed = 0.17})
		if not boltOpenTrack then
			warn(warnPrefix .. "To use operation type " .. vars.wepStats.operationType .. ", a 'boltOpen' animation is required.")
			vars.reloading = false
			return
		end
		boltOpenTrack.Stopped:Once(function()
			if not vars.reloading or vars.equipped ~= capturedTool or vars.equipGeneration ~= capturedGeneration then return end

			local liveMagAmmo = GetMagAmmo()
			local arcadePool = vars.gunAmmo and vars.gunAmmo:FindFirstChild("ArcadeAmmoPool")
			local clipSize = vars.wepStats.clipSize or vars.wepStats.magazineCapacity

			if vars.wepStats.magType == 3
				and liveMagAmmo and arcadePool
				and (liveMagAmmo.MaxValue - liveMagAmmo.Value) >= clipSize
				and arcadePool.Value >= clipSize then
				PlayAnimation(vars.wepStats.clipReloadAnim, {looped = true, speed = vars.wepStats.reloadSpeedModifier, priority = Enum.AnimationPriority.Action2, transSpeed = 0.17})
			else
				local reloadAnimName = useEmptyReloadAnim and vars.wepStats.emptyReloadAnim or vars.wepStats.reloadAnim
				local bulletInsert = PlayAnimation(reloadAnimName, {speed = vars.wepStats.reloadSpeedModifier, priority = Enum.AnimationPriority.Action2, transSpeed = 0.17, looped = true}, "Reload")
				if bulletInsert and vars.wepStats.magType > 1 then bulletInsert.Looped = true end
			end
		end)
	else
		local reloadAnimName = useEmptyReloadAnim and vars.wepStats.emptyReloadAnim or vars.wepStats.reloadAnim
		local reloadAnim = PlayAnimation(reloadAnimName, {speed = vars.wepStats.reloadSpeedModifier, priority = Enum.AnimationPriority.Action2, transSpeed = 0.17}, "Reload")
		if not reloadAnim then
			vars.reloading = false
			return
		end
		if vars.wepStats.autoChamber and vars.wepStats.magType ~= 4 then
			reloadAnim.Stopped:Once(function()
				if not vars.reloading or vars.equipped ~= capturedTool or vars.equipGeneration ~= capturedGeneration then return end

				if not GetToolValue(capturedTool, "Chambered") or vars.wepStats.openBolt then
					vars.reloading = true
					local animNameToPlay
					if GetToolValue(capturedTool, "BoltReady") then
						animNameToPlay = vars.wepStats.boltChamber
					else
						animNameToPlay = vars.wepStats.boltClose
					end
					PlayAnimation(animNameToPlay, {priority = Enum.AnimationPriority.Action2, transSpeed = 0.05})
				end
			end)
		end
	end
end

function WeaponSequences.init()
	local ctx = WeaponContext.get()
	ChangeHoldStance = ctx.ChangeHoldStance
	CollectAndManageSights = ctx.CollectAndManageSights
	GetThirdPersonGunModel = ctx.GetThirdPersonGunModel
	PlayAnimation = ctx.PlayAnimation
	StopAnimation = ctx.StopAnimation
	ToggleAiming = ctx.ToggleAiming
	ToggleSprint = ctx.ToggleSprint
	animBase = ctx.animBase
	character = ctx.character
	fireModes = ctx.fireModes
	gunRecoilSpring = ctx.gunRecoilSpring
	gunRotSpring = ctx.gunRotSpring
	vmAnimator = ctx.vmAnimator
	warnPrefix = ctx.warnPrefix
end

WeaponSequences.PlayEmptyClickAnimation = PlayEmptyClickAnimation
WeaponSequences.ChamberAnim = ChamberAnim
WeaponSequences.IdleAnim = IdleAnim
WeaponSequences.EquipAnim = EquipAnim
WeaponSequences.ReloadAnim = ReloadAnim

return WeaponSequences
