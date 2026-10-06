local Modules = script:FindFirstAncestor("Modules")
local Assets = Modules.Parent

local WeaponContext = require(Modules.Weapons.Core.WeaponContext)
local vars = require(Modules.Weapons.Core.WeaponState).get()
local config = require(Assets.GameConfig)
local Attachments = require(Modules.Weapons.Attachments.SPHAttachments)
local aimVignette = require(Modules.Weapons.Aiming.AimVignetteMod)
local weaponPushback = require(Modules.Weapons.Fire.WeaponPushbackMod)
local armPositionMod = require(Modules.Weapons.Aiming.ArmPositionMod)
local bulletHandler = require(Modules.Weapons.Fire.BulletHandler)
local headPoseReplicationMod = require(Modules.Weapons.Aiming.HeadPoseReplicationMod)
local laserSightMod = require(Modules.Weapons.Attachments.LaserSightMod)
local ubglSystem = require(Modules.Weapons.Attachments.UBGLHandlerMod)
local reticleMotionBlurMod = require(Modules.Weapons.Aiming.ReticleMotionBlurMod)
local SPH_Events = require(Modules.Core.Networking.SPH_Events)
local glareMod = require(Modules.Weapons.Attachments.GlareMod)
local camera = workspace.CurrentCamera
local userInputService = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")
local starterGui = game:GetService("StarterGui")
local replicatedStorage = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer

local WeaponLifecycle = {}

local ChangeDoF, CleanupVMAccessories, ClearThirdPersonGunCache, GetThirdPersonGunModel, FindProjectilePart
local PlayAnimation, StopAnimation, ToggleAiming, UnbindGunInputs
local aimDoF, animBase, character, defaultFOV
local depthOfField, equipConnections, gunRecoilSpring, gunRotSpring
local humanoid, inspectDoF, lpvoArmThrottle, lpvoThrottle
local moveSpring, overheatThrottle, playerToggleAttachment, recoilSpring
local storageCFrame, swaySpring, switchWeapon, vmAnimator

local Unequip, onCharacterAdded

Unequip = function(tool, skipAnimation, skipBackpackEnable)
	local unequippedProjectileName = vars.wepStats and vars.wepStats.projectile
	equipConnections:DisconnectAll()
	overheatThrottle:Reset()
	lpvoThrottle:Reset()
	lpvoArmThrottle:Reset()
	character:SetAttribute("BackpackDisabled", true)
	vars.holdingM1 = false
	vars.canFire = false
	vars.bulletsCurrentlyFired = 0
	if vars.preFireTrack then
		vars.preFireTrack:Stop(0)
		vars.preFireTrack = nil
	end
	vars.preFirePlaying = false
	vars.preFireReady = false
	if vars.unequipping then
		return
	end
	vars.unequipping = true
	if character:GetAttribute("IsSwimming") then
		skipAnimation = true
	end
	character:SetAttribute("HidingArmAccessories", true)
	CleanupVMAccessories()
	userInputService.MouseIconEnabled = true
	if vars.aiming then ToggleAiming(false) end

	ClearThirdPersonGunCache()

	local sphUI = player.PlayerGui:FindFirstChild("SPH_UI")
	if sphUI then
		local magCheckFrame = sphUI:FindFirstChild("MagCheck")
		if magCheckFrame then
			magCheckFrame.Visible = false
		end
		local magUI = sphUI:FindFirstChild("MagUI")
		if magUI then
			magUI.Visible = false
		end
	end


	vars.magCheckHeld = false
	vars.magCheckDebounce = false
	vars.magCheckAutoTriggered = false

	if vars.magCheckFadeOutTask then
		task.cancel(vars.magCheckFadeOutTask)
		vars.magCheckFadeOutTask = nil
	end


	vars.fireModeCheckHeld = false
	vars.fireModeCheckDebounce = false
	vars.fireModeCheckAutoTriggered = false

	gunRotSpring.Position = Vector3.zero
	gunRotSpring.Velocity = Vector3.zero

	if vars.fireModeCheckFadeOutTask then
		task.cancel(vars.fireModeCheckFadeOutTask)
		vars.fireModeCheckFadeOutTask = nil
	end


	if vars.wepStats then
		if vars.wepStats.magCheck and vars.loadedAnims[vars.wepStats.magCheck] then
			vars.loadedAnims[vars.wepStats.magCheck]:Stop(0)
			if vars.loadedAnims[vars.wepStats.magCheck .. "ThirdPerson"] then
				vars.loadedAnims[vars.wepStats.magCheck .. "ThirdPerson"]:Stop(0)
			end
		end

		local fireModeAnimName = vars.wepStats.firemodeCheck or vars.wepStats.switchAnim
		if fireModeAnimName and vars.loadedAnims[fireModeAnimName] then
			vars.loadedAnims[fireModeAnimName]:Stop(0)
			if vars.loadedAnims[fireModeAnimName .. "ThirdPerson"] then
				vars.loadedAnims[fireModeAnimName .. "ThirdPerson"]:Stop(0)
			end
		end
	end

	vars.isUnequippingForArmHiding = true
	character:SetAttribute("IsUnequippingForArmHiding", true)

	armPositionMod.Cleanup()

	if vars.inspecting then
		vars.inspecting = false
		if vars.wepStats then
			local inspectAnimToUse = vars.wepStats.InspectAnim or vars.wepStats.emptyInspect
			if inspectAnimToUse then
				StopAnimation(inspectAnimToUse, 0.05)
			end
		end
	end

	vars.preFirePlaying = false
	vars.preFireReady = false
	vars.preFireLocked = false
	if vars.preFireTrack then
		vars.preFireTrack:Stop(0)
		vars.preFireTrack = nil
	end  

	if vars.gunModel then
		bulletHandler.StopAutoSound(player, vars.gunModel)
	end

	vars.cancelReload = false
	vars.aimHeld = false
	vars.reloading = false
	vars.chambering = false
	vars.inspecting = false
	vars.switchingFireMode = false
	vars.togglingAttachment = false
	vars.magCheckHeld = false
	vars.magCheckDebounce = false
	vars.fireModeCheckHeld = false
	vars.fireModeCheckDebounce = false
	vars.emptyClickPlaying = false
	vars.emptyClickDebounce = false
	vars.cancelReload = true


	if aimDoF and vars.isAimDoFActive then
		vars.isAimDoFActive = false
		aimDoF.Enabled = false
		ChangeDoF(0, 0, 0, 0, true)
	end

	if vars.inspectDoFActive and inspectDoF then
		vars.inspectDoFActive = false
		inspectDoF.Enabled = false
	end

	for _, track in vmAnimator:GetPlayingAnimationTracks() do track:Stop(0) end
	for _, track in vars.characterAnimator:GetPlayingAnimationTracks() do track:Stop(0) end

	if vars.wepStats and (ubglSystem.IsActive() or ubglSystem.IsToggling()) then
		ubglSystem.ForceUnequip(skipAnimation)
	end

	local unequipAnim
	local _unequipToolName = tool and tool.Name
	local _unequipHasHolster = vars.wepStats and vars.wepStats.holster
	if not skipAnimation and vars.wepStats then
		if vars.wepStats.unequipAnim then
			unequipAnim = PlayAnimation(vars.wepStats.unequipAnim, {
				priority = Enum.AnimationPriority.Action2,
				looped = false,
				speed = vars.wepStats.unequipSpeedModifier or 1
			}, "Unequip")
		else
			local equipTrack = vars.loadedAnims[vars.wepStats.equipAnim]
			local equipTrackTP = vars.loadedAnims[vars.wepStats.equipAnim .. "ThirdPerson"]
			if equipTrack and equipTrackTP then
				if equipTrack.IsPlaying then equipTrack:Stop(0) end
				if equipTrackTP.IsPlaying then equipTrackTP:Stop(0) end
				equipTrack:Play(0)
				equipTrackTP:Play(0)
				equipTrack.TimePosition = equipTrack.Length
				equipTrackTP.TimePosition = equipTrackTP.Length
				equipTrack:AdjustSpeed(-1 * (vars.wepStats.equipSpeedModifier or 1))
				equipTrackTP:AdjustSpeed(-1 * (vars.wepStats.equipSpeedModifier or 1))
				unequipAnim = equipTrack
				if vars.firstPerson and vars.gunModel.Grip:FindFirstChild("Unequip") then
					vars.gunModel.Grip.Unequip:Play()
				end
			end
		end
		if unequipAnim then
			unequipAnim.Stopped:Wait()
		else
			task.wait(0.3)
		end
	end

	if _unequipHasHolster and _unequipToolName then
		local showHolsterRemote = SPH_Events.Find("GunEvents", "SPH_ShowHolster")
		if showHolsterRemote then
			showHolsterRemote:FireServer(_unequipToolName)
		end
	end
	character:SetAttribute("HidingArmAccessories", false)

	vars.currentHeat = 0; vars.isOverheated = false; vars.lastShotTime = 0; vars.cooldownStartTime = 0
	vars.slideReleaseHasPlayed = false
	vars.lastReloadCompletedTime = 0
	headPoseReplicationMod.ResetLocalThrottle()
	animBase.CFrame = storageCFrame
	vars.viewmodelVisible = false
	switchWeapon.send(nil)
	if tool == vars.equipped then
		vars.equipped = nil
		vars.wepStats = nil
	end
	userInputService.MouseIconEnabled = false
	ToggleAiming(false)
	aimVignette.Reset()
	weaponPushback.Reset()
	ubglSystem.Cleanup()
	for _, track in vmAnimator:GetPlayingAnimationTracks() do track:Stop(0.1) end
	for _, track in vars.characterAnimator:GetPlayingAnimationTracks() do track:Stop(0.1) end
	local saveName = tool and tool.Name
	if saveName and saveName ~= "" then
		for _, track in pairs(vars.loadedAnims) do
			if typeof(track) == "Instance" and track:IsA("AnimationTrack") and track.IsPlaying then
				pcall(function() track:Stop(0) end)
			end
		end
		vars.animCache[saveName] = vars.loadedAnims

		local cacheCount = 0
		for _ in pairs(vars.animCache) do cacheCount += 1 end
		if cacheCount > 3 then
			local oldest = next(vars.animCache)
			if oldest and oldest ~= saveName then
				for _, track in pairs(vars.animCache[oldest]) do
					pcall(function()
						if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
							track:Destroy()
						end
					end)
				end
				vars.animCache[oldest] = nil
			end
		end
	end	
	vars.loadedAnims = {}
	if config.lockFirstPerson then player.CameraMode = Enum.CameraMode.Classic end
	vars.sights = {}
	vars.fpSights = {}
	vars.tpSights = {}
	vars.attachmentFpSights = {}
	for sightUIKey, handle in pairs(vars.reticleBlurHandles) do
		reticleMotionBlurMod.Destroy(handle)
		vars.reticleBlurHandles[sightUIKey] = nil
	end
	vars.freeLook = false
	vars.freeLookOffset = vars.freeLookRotation:ToObjectSpace(camera.CFrame)
	vars.freeLookOffset -= vars.freeLookOffset.Position
	humanoid.AutoRotate = true
	if depthOfField then ChangeDoF(0,0,0,0) end
	vars.holdStance = 0; vars.holdAnim = nil
	if vars.laserEnabled then
		playerToggleAttachment.send({ AttachmentType = 1, Enabled = false })
	end
	if vars.flashlightEnabled then
		playerToggleAttachment.send({ AttachmentType = 0, Enabled = false })
		local fpFlashlightPart = vars.gunModel and Attachments:GetFlashlightSource(vars.gunModel)
		if fpFlashlightPart then
			vars.flashFX.mod.SetEnabled(fpFlashlightPart, false)
			glareMod.SetFlashlightActive(fpFlashlightPart, false)
		end
		local tpModel = GetThirdPersonGunModel()
		if tpModel then
			local tpFlashlightPart = Attachments:GetFlashlightSource(tpModel)
			if tpFlashlightPart then
				vars.flashFX.mod.SetEnabled(tpFlashlightPart, false)
				glareMod.SetFlashlightActive(tpFlashlightPart, false)
			end
		end
	end
	vars.laserEnabled = false; vars.flashlightEnabled = false
	laserSightMod.Reset()
	vars.flashFX.beamFP.Enabled = false
	vars.flashFX.beamTP.Enabled = false
	vars.aimTransitionPlaying = false
	vars.lpvoRingCurrentRotation = 0; vars.lpvoOriginalCFrame = nil; vars.lastZoomDirection = 0
	vars.inspecting = false
	UnbindGunInputs()
	if animBase:FindFirstChild("AnimBase_Grip") then animBase.AnimBase_Grip:Destroy() end
	local weaponFolder = vars.rig and vars.rig:FindFirstChild("Weapon")
	local oldGun = weaponFolder and weaponFolder:FindFirstChildWhichIsA("Model")
	if oldGun then
		if not vars.queuedTool then
			Attachments:CleanupMuzzleState(oldGun)
		end

		local projectilePart = unequippedProjectileName
			and FindProjectilePart(oldGun, unequippedProjectileName)
		if projectilePart then
			projectilePart:SetAttribute("SPH_FPHidden", nil)
			projectilePart:SetAttribute("ForceHidden_Anim", nil)
			projectilePart.Transparency = 1
			for _, child in ipairs(projectilePart:GetDescendants()) do
				if child:IsA("BasePart") then
					child.Transparency = 1
				elseif child:IsA("Decal") or child:IsA("Texture") then
					child.Transparency = 1
				end
			end
		end

		oldGun:Destroy()
	end
	recoilSpring.Position = Vector3.zero; recoilSpring.Velocity = Vector3.zero
	vars.prevCamRecoil = Vector3.zero
	gunRecoilSpring.Position = Vector3.zero; gunRecoilSpring.Velocity = Vector3.zero
	swaySpring.Position = Vector3.zero; swaySpring.Velocity = Vector3.zero
	moveSpring.Position = Vector3.zero; moveSpring.Velocity = Vector3.zero
	if vars.fireFovReturnTask then
		task.cancel(vars.fireFovReturnTask)
		vars.fireFovReturnTask = nil
	end
	vars.fireFovActive = false
	vars.storedAimFOV = nil
	camera.FieldOfView = defaultFOV

	local cleanupEvent = SPH_Events.Find("GunEvents", "CleanupCustomizeGUI")
	if cleanupEvent and cleanupEvent:IsA("BindableEvent") then
		cleanupEvent:Fire()
	end

	if not character:FindFirstChildWhichIsA("Tool") and not vars.switchingWeapons then
		task.delay(0.1, function()
			if not vars.queuedTool and not character:FindFirstChildWhichIsA("Tool") and not vars.equipping then
				vars.isUnequippingForArmHiding = false
				character:SetAttribute("IsUnequippingForArmHiding", false)
			end
		end)
	end

	local wasDropping = vars.dropping
	vars.dropping = false
	vars.unequipping = false
	if not vars.switchingWeapons and not vars.throwingGrenade and not character:GetAttribute("IsSwimming") then
		character:SetAttribute("BackpackDisabled", false)
	end

	if character:GetAttribute("IsSwimming") then
		character:SetAttribute("BackpackDisabled", true)
		pcall(function()
			starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
	end

	if wasDropping then
		if not skipBackpackEnable and not character:GetAttribute("IsSwimming") then
			pcall(function() starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true) end)
		end
		task.delay(0.05, function()
			if not vars.equipping and not vars.queuedTool then
				vars.isUnequippingForArmHiding = false
				character:SetAttribute("IsUnequippingForArmHiding", false)
			end
		end)
	end

	if vars.queuedTool then
		local nextTool = vars.queuedTool
		vars.queuedTool = nil
		local backpack = player:FindFirstChildOfClass("Backpack")
		local nextParent = nextTool.Parent
		if nextTool:IsA("Tool") and (nextParent == character or (backpack and nextParent == backpack)) then
			humanoid:EquipTool(nextTool)
		else
			vars.switchingWeapons = false
			character:SetAttribute("SwitchingWeapons", false)
			vars.isUnequippingForArmHiding = false
			character:SetAttribute("IsUnequippingForArmHiding", false)
			if not character:GetAttribute("IsSwimming") then
				character:SetAttribute("BackpackDisabled", false)
			end
		end
	end
end

onCharacterAdded = function(character)
	character:SetAttribute("BackpackDisabled", false)

	pcall(function()
		starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)
end

function WeaponLifecycle.init()
	local ctx = WeaponContext.get()
	ChangeDoF = ctx.ChangeDoF
	CleanupVMAccessories = ctx.CleanupVMAccessories
	ClearThirdPersonGunCache = ctx.ClearThirdPersonGunCache
	GetThirdPersonGunModel = ctx.GetThirdPersonGunModel
	FindProjectilePart = ctx.FindProjectilePart
	PlayAnimation = ctx.PlayAnimation
	StopAnimation = ctx.StopAnimation
	ToggleAiming = ctx.ToggleAiming
	UnbindGunInputs = ctx.UnbindGunInputs
	aimDoF = ctx.aimDoF
	animBase = ctx.animBase
	character = ctx.character
	defaultFOV = ctx.defaultFOV
	depthOfField = ctx.depthOfField
	equipConnections = ctx.equipConnections
	gunRecoilSpring = ctx.gunRecoilSpring
	gunRotSpring = ctx.gunRotSpring
	humanoid = ctx.humanoid
	inspectDoF = ctx.inspectDoF
	lpvoArmThrottle = ctx.lpvoArmThrottle
	lpvoThrottle = ctx.lpvoThrottle
	moveSpring = ctx.moveSpring
	overheatThrottle = ctx.overheatThrottle
	playerToggleAttachment = ctx.playerToggleAttachment
	recoilSpring = ctx.recoilSpring
	storageCFrame = ctx.storageCFrame
	swaySpring = ctx.swaySpring
	switchWeapon = ctx.switchWeapon
	vmAnimator = ctx.vmAnimator
end

WeaponLifecycle.Unequip = Unequip
WeaponLifecycle.onCharacterAdded = onCharacterAdded

return WeaponLifecycle