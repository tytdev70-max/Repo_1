local Modules = script:FindFirstAncestor("Modules")
local Assets = Modules.Parent

local WeaponContext = require(Modules.Weapons.Core.WeaponContext)
local vars = require(Modules.Weapons.Core.WeaponState).get()
local config = require(Assets.GameConfig)
local Attachments = require(Modules.Weapons.Attachments.SPHAttachments)
local aimingSystemMod = require(Modules.Weapons.Aiming.AimingSystemMod)
local bulletHandler = require(Modules.Weapons.Fire.BulletHandler)
local grenadeClient = require(Modules.Misc.Grenades.GrenadeClient)
local laserSightMod = require(Modules.Weapons.Attachments.LaserSightMod)
local glareMod = require(Modules.Weapons.Attachments.GlareMod)
local magCheckDisplay = require(Modules.Weapons.UI.MagCheckDisplay)
local fireModeCheckDisplay = require(Modules.Weapons.UI.FireModeCheckDisplay)
local mobileSupport = require(Modules.Weapons.UI.MobileSupportMod)
local ubglSystem = require(Modules.Weapons.Attachments.UBGLHandlerMod)
local camera = workspace.CurrentCamera
local userInputService = game:GetService("UserInputService")
local contextActionService = game:GetService("ContextActionService")
local starterGui = game:GetService("StarterGui")
local player = game:GetService("Players").LocalPlayer
local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

local WeaponInput = {}

local BindAiming, ChamberAnim, ChangeHoldStance, GetThirdPersonGunModel
local IsAnimationBusy, IsLoaded, PlayAnimation, PlayEmptyClickAnimation
local PlayRepSound, ReloadAnim, StopAnimation, SwitchFireMode
local ToggleAiming, ToggleSprint, Unequip, aimFOVTargetRef
local fireModes, humanoid, inspectDoF, perGunSightIndex
local playerDropGun, playerToggleAttachment, switchFireMode

local HandleInput, BindGunInputs, UnbindGunInputs

local function GetMagAmmo()
	local gunAmmo = vars.gunAmmo
	if not gunAmmo or not gunAmmo.Parent then
		return nil
	end
	return gunAmmo:FindFirstChild("MagAmmo")
end

HandleInput = function(actionName, inputState, inputObject)
	local inputBegan = Enum.UserInputState.Begin
	local inputEnded = Enum.UserInputState.End

	if inputState ~= inputBegan and inputState ~= inputEnded then
		return
	end


	local customizeGUI = playerGui:FindFirstChild("CustomizeGunGUI")
	if customizeGUI and customizeGUI.Enabled then
		return
	end


	if vars.equipping or vars.unequipping or vars.dropping then
		return
	end

	if vars.equipped and vars.wepStats and vars.wepStats.weaponType == "Grenade" then
		grenadeClient.HandleGrenadeInput(actionName, inputState, inputObject)
		return
	end

	if actionName == "SPH_Trigger" and inputState == Enum.UserInputState.End then
		vars.holdingM1 = false
		if vars.curFireMode ~= fireModes.Manual then
			vars.canFire = true
		end
	end

	if vars.equipped and vars.wepStats and vars.wepStats.UBGL and vars.wepStats.UBGL.Enabled and (ubglSystem.IsActive() or ubglSystem.IsToggling()) then
		if ubglSystem.IsActive() and (actionName == "SPH_Trigger" or actionName == "SPH_Reload") then
			ubglSystem.HandleUBGLInput(actionName, inputState, inputObject)
			return
		elseif actionName ~= "SPH_ToggleUBGL" and actionName ~= "SPH_DropGun" then
			return
		end
	end

	if vars.inspecting then

		if actionName ~= "SPH_Inspect" then
			return
		end
	end

	if vars.equipped then 
		if actionName == "SPH_Trigger" then
			if inputState == inputBegan then 

				if vars.magCheckHeld or vars.magCheckDebounce or vars.fireModeCheckHeld or vars.fireModeCheckDebounce then
					return
				end

				vars.cancelReload = true
				if vars.reloading and vars.wepStats and vars.wepStats.projectile and vars.wepStats.projectile ~= "Bullet" and vars.gunModel then
					local magAmmo = GetMagAmmo()
					local chambered = vars.equipped and vars.equipped:FindFirstChild("Chambered")
					local stillLoaded = (chambered and chambered.Value) or (magAmmo and magAmmo.Value > 0)
					if not stillLoaded then
						local projectile = vars.gunModel:FindFirstChild(vars.wepStats.projectile, true)
						if projectile then
							projectile.LocalTransparencyModifier = 1
							for _, child in ipairs(projectile:GetDescendants()) do
								if child:IsA("BasePart") then
									child.LocalTransparencyModifier = 1
								end
							end
						end
					end
				end
				if not (vars.sprinting or vars.reloading) then 
					vars.holdingM1 = true
					local magAmmo = GetMagAmmo()
					if not IsLoaded() and not (vars.curFireMode == fireModes.Manual and magAmmo and magAmmo.Value > 0) then
						if vars.wepStats and vars.wepStats.preFire and not vars.preFirePlaying and not vars.preFireReady and not vars.preFireLocked and not vars.blocked and not vars.freeLook then
							vars.preFirePlaying = true
							vars.preFireReady = false
							local preFireTrack = PlayAnimation(vars.wepStats.preFire, {priority = Enum.AnimationPriority.Action2, looped = false})
							vars.preFireTrack = preFireTrack
							if preFireTrack then
								preFireTrack.Stopped:Once(function()
									if vars.holdingM1 then
										vars.preFireReady = true
									end
									vars.preFirePlaying = false
									vars.preFireTrack = nil
								end)
							else
								vars.preFirePlaying = false
								vars.preFireReady = true
							end
						elseif not vars.emptyClickPlaying and not vars.emptyClickDebounce then
							PlayRepSound("Click")
							PlayEmptyClickAnimation()
						end
					elseif vars.wepStats and vars.wepStats.preFire and not vars.preFirePlaying and not vars.preFireReady and not vars.preFireLocked and not vars.blocked and not vars.freeLook then
						vars.preFirePlaying = true
						vars.preFireReady = false
						local preFireTrack = PlayAnimation(vars.wepStats.preFire, {priority = Enum.AnimationPriority.Action2, looped = false})
						vars.preFireTrack = preFireTrack
						if preFireTrack then
							preFireTrack.Stopped:Once(function()
								if vars.holdingM1 then
									vars.preFireReady = true
								end
								vars.preFirePlaying = false
								vars.preFireTrack = nil
							end)
						else
							vars.preFirePlaying = false
							vars.preFireReady = true
						end
					end
				end
			else  
				vars.holdingM1 = false
				vars.nextScheduledFireTime = nil
				if vars.preFirePlaying then
					if vars.preFireTrack then
						vars.preFireTrack:Stop(0.15)
						vars.preFireTrack = nil
					end
					vars.preFirePlaying = false
				end
				vars.preFireReady = false
				if vars.curFireMode ~= fireModes.Manual then
					vars.canFire = true
				end
				vars.bulletsCurrentlyFired = 0
				if vars.curFireMode == fireModes.Auto and vars.gunModel then
					bulletHandler.StopAutoSound(player, vars.gunModel)
				end
			end
		elseif actionName == "SPH_DropGun" and inputState == inputBegan then
			if not config.gunDropping then return end
			if vars.equipping or vars.unequipping or vars.dropping then return end
			if not vars.equipped then return end
			vars.dropping = true
			pcall(function() starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)
			Unequip(vars.equipped, false, true)
			playerDropGun.send(nil)

			task.delay(0.2, function()
				if not vars.equipping and not vars.queuedTool then
					pcall(function() starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true) end)
				end
			end)
		elseif actionName == "SPH_Reload" then
			if inputState == inputBegan then

				if vars.fireModeCheckHeld or vars.fireModeCheckDebounce then
					return
				end

				vars.magCheckHeld = true
				vars.magCheckStartTime = tick()

				vars.magCheckAutoTriggered = false


				task.spawn(function()
					task.wait(vars.HOLD_THRESHOLD)

					if vars.magCheckHeld and not vars.magCheckDebounce then

						vars.magCheckAutoTriggered = true

						vars.magCheckHeld = false
						magCheckDisplay.DoMagCheck()
					end
				end)

			elseif inputState == inputEnded then
				local holdDuration = tick() - vars.magCheckStartTime
				local wasHeld = vars.magCheckHeld

				vars.magCheckHeld = false


				if vars.magCheckAutoTriggered then
					vars.magCheckAutoTriggered = false
					return
				end

				if wasHeld and holdDuration >= vars.HOLD_THRESHOLD then
					magCheckDisplay.DoMagCheck()
				else

					if not vars.magCheckDebounce and vars.equipped and vars.gunAmmo and not vars.reloading and vars.cycled then
						local magAmmo = GetMagAmmo()
						if not magAmmo then
							return
						end
						local arcadeAmmoPool = vars.gunAmmo:FindFirstChild("ArcadeAmmoPool")
						local chamberedVal = vars.equipped:FindFirstChild("Chambered")
						local isMagFull = magAmmo.Value >= magAmmo.MaxValue
						local hasChamberedRound = chamberedVal ~= nil and chamberedVal.Value

						if isMagFull and hasChamberedRound then
							return
						end

						if vars.wepStats.infiniteAmmo or (arcadeAmmoPool and arcadeAmmoPool.Value > 0) then
							if (vars.wepStats.openBolt and magAmmo.Value < magAmmo.MaxValue) then
								ReloadAnim()
							else
								if (vars.wepStats.operationType == 4 and vars.equipped.Chambered.Value)
									or (vars.wepStats.operationType == 3 and vars.wepStats.magType ~= 4 and magAmmo.MaxValue > 1 and magAmmo.Value + 1 >= magAmmo.MaxValue)
									or (vars.wepStats.operationType == 2 and magAmmo.Value >= magAmmo.MaxValue) then
									return
								end
								ReloadAnim()
							end
						end
					end
				end
			end
		elseif actionName == "SPH_HoldAim" then
			if vars.magCheckHeld or vars.magCheckDebounce or vars.fireModeCheckHeld or vars.fireModeCheckDebounce then
				return
			end
			if not userInputService.TouchEnabled and not config.toggleAiming then 
				if inputState == inputBegan and not vars.blocked and not vars.sprinting and not vars.freeLook then
					vars.aimHeld = true
					ToggleSprint(false)
					ToggleAiming(true)
				elseif vars.aiming then 
					vars.aimHeld = false
					ToggleAiming(false)
				end
			elseif inputState == inputBegan then 
				if not vars.blocked and not vars.aiming and not vars.sprinting and not vars.freeLook then 
					vars.aimHeld = true
					ToggleSprint(false)
					ToggleAiming(true)
				else
					vars.aimHeld = false
					ToggleAiming(false)
				end
			end
		elseif actionName == "SPH_Chamber" and inputState == inputBegan and not vars.reloading and vars.cycled then 

			if vars.magCheckHeld or vars.magCheckDebounce or vars.fireModeCheckHeld or vars.fireModeCheckDebounce then
				return
			end
			ChamberAnim()
		elseif actionName == "SPH_SwitchSights" and inputState == inputBegan and vars.aiming
			and (vars.gunModel:FindFirstChild("AimPart2") or Attachments:GetSightCount(vars.gunModel) > 1) then
			-- Sight count: mounted optics when they provide several sights (dual sights /
			-- multi-reticle optic), otherwise the gun's own AimPart, AimPart2, ...
			local attachmentSights = Attachments:GetSightCount(vars.gunModel)
			local tempIndex = vars.sightIndex
			tempIndex += 1
			local hasNext = if attachmentSights > 1
				then tempIndex <= attachmentSights
				else vars.gunModel:FindFirstChild("AimPart"..tempIndex) ~= nil
			if hasNext then
				vars.sightIndex = tempIndex
				PlayRepSound("AimUp")
			else
				vars.sightIndex = 1
				PlayRepSound("AimDown")
			end


			if vars.equipped then
				perGunSightIndex[vars.equipped.Name] = vars.sightIndex
			end
			
			aimingSystemMod.UpdateADSVisual(vars.gunModel, vars.wepStats, vars.sightIndex, vars.aiming)
			aimingSystemMod.ReplicateAimState(true)
		elseif actionName == "SPH_Freelook" then 
			if userInputService.TouchEnabled then
				if inputState == inputBegan then 
					if not vars.freeLook then
						vars.freeLook = true
						humanoid.AutoRotate = false
						vars.freeLookRotation = camera.CFrame - camera.CFrame.Position
						if vars.aiming then ToggleAiming(false) end
					else
						vars.freeLook = false
						vars.freeLookOffset = vars.freeLookRotation:ToObjectSpace(camera.CFrame)
						vars.freeLookOffset = vars.freeLookOffset - vars.freeLookOffset.Position
						humanoid.AutoRotate = true
					end
				end
			else
				if inputState == inputBegan then
					if not vars.firstPerson then return end 
					vars.freeLook = true
					humanoid.AutoRotate = false
					vars.freeLookRotation = camera.CFrame - camera.CFrame.Position
					if vars.aiming then ToggleAiming(false) end
				else 
					if vars.freeLook == true then
						vars.freeLook = false
						vars.freeLookOffset = vars.freeLookRotation:ToObjectSpace(camera.CFrame)
						vars.freeLookOffset = vars.freeLookOffset - vars.freeLookOffset.Position
						humanoid.AutoRotate = true
					end
				end
			end
		elseif actionName == "SPH_Inspect" and inputState == inputBegan then

			if vars.magCheckHeld or vars.magCheckDebounce or vars.fireModeCheckHeld or vars.fireModeCheckDebounce then
				return
			end

			if vars.inspecting or vars.reloading or vars.sprinting or vars.blocked or vars.equipping or vars.chambering or vars.aiming then
				if vars.aiming then ToggleAiming(false) end  
				return
			end


			local currentTime = tick()


			local inspectAnimToUse
			local chamberedVal = vars.equipped:FindFirstChild("Chambered")
			local magAmmo = GetMagAmmo()
			local isEmpty = (magAmmo ~= nil and magAmmo.Value <= 0 and not (chamberedVal and chamberedVal.Value))
			local boltReadyVal = vars.equipped:FindFirstChild("BoltReady")
			local boltLockedBack = not (boltReadyVal and boltReadyVal.Value) 


			if isEmpty and boltLockedBack and vars.wepStats.emptyInspect then

				inspectAnimToUse = vars.wepStats.emptyInspect
			elseif vars.wepStats.InspectAnim then

				inspectAnimToUse = vars.wepStats.InspectAnim
			else

				return
			end

			vars.inspecting = true
			vars.lastInspectTime = currentTime
			ChangeHoldStance(0)

			if vars.wepStats.fireAnim then
				StopAnimation(vars.wepStats.fireAnim, 0.05)
			end

			if inspectDoF and not vars.isAimDoFActive then
				vars.inspectDoFActive = true
				inspectDoF.Enabled = true
			end

			local inspectTrack = PlayAnimation(inspectAnimToUse, {
				priority = Enum.AnimationPriority.Action2,
				transSpeed = 0.2
			})

			local function StopInspectDoF()
				if not vars.inspectDoFActive then return end
				vars.inspectDoFActive = false
				if inspectDoF then
					inspectDoF.Enabled = false
				end
			end

			if inspectTrack then
				inspectTrack.Stopped:Once(function()
					vars.inspecting = false
					StopInspectDoF()
				end)
			else
				vars.inspecting = false
				StopInspectDoF()
			end
		elseif actionName == "SPH_HoldUp" and inputState == inputBegan and not vars.reloading then 
			ChangeHoldStance(1)
		elseif actionName == "SPH_HoldPatrol" and inputState == inputBegan and not vars.reloading then 
			ChangeHoldStance(2)
		elseif actionName == "SPH_HoldDown" and inputState == inputBegan and not vars.reloading then 
			ChangeHoldStance(3)
		elseif actionName == "SPH_SwitchFireMode" then
			if inputState == inputBegan then

				if vars.magCheckHeld or vars.magCheckDebounce or vars.reloading or vars.chambering then return end


				vars.fireModeCheckHeld = true
				vars.fireModeCheckStartTime = tick()
				vars.fireModeCheckAutoTriggered = false

				task.spawn(function()
					task.wait(vars.HOLD_THRESHOLD)
					if vars.fireModeCheckHeld and not vars.fireModeCheckDebounce then
						vars.fireModeCheckAutoTriggered = true
						vars.fireModeCheckHeld = false
						fireModeCheckDisplay.DoFireModeCheck()
					end
				end)

			elseif inputState == inputEnded then
				local holdDuration = tick() - vars.fireModeCheckStartTime
				local wasHeld = vars.fireModeCheckHeld
				vars.fireModeCheckHeld = false


				if vars.fireModeCheckAutoTriggered then
					vars.fireModeCheckAutoTriggered = false
					return
				end

				if wasHeld and holdDuration >= vars.HOLD_THRESHOLD then

					fireModeCheckDisplay.DoFireModeCheck()
				else

					if vars.fireModeCheckDebounce or not vars.equipped or vars.reloading or vars.chambering or vars.magCheckDebounce then return end


					if vars.wepStats.fireAnim then
						local fireFP = vars.loadedAnims[vars.wepStats.fireAnim]
						local fireTP = vars.loadedAnims[vars.wepStats.fireAnim .. "ThirdPerson"]
						if fireFP then fireFP:Stop() end
						if fireTP then fireTP:Stop() end
					end


					SwitchFireMode()
				end
			end
		elseif actionName == "SPH_ToggleLaser" and inputState == inputBegan 
			and (vars.gunModel.Grip:FindFirstChild("Laser") or Attachments:AnyActiveFlag(vars.gunModel, "EnableLaser")) then
			laserSightMod.ToggleLocalLaser()
		elseif actionName == "SPH_ToggleFlashlight" and inputState == inputBegan then
			local fireAnimPlaying = vars.wepStats and vars.wepStats.fireAnim
				and vars.loadedAnims[vars.wepStats.fireAnim]
				and vars.loadedAnims[vars.wepStats.fireAnim].IsPlaying

			if vars.togglingAttachment or IsAnimationBusy() or vars.sprinting
				or vars.holdStance ~= 0 or fireAnimPlaying then return end

			local flashlightPart = Attachments:GetFlashlightSource(vars.gunModel)
			if not flashlightPart then return end

			local function ApplyFlashlightState()
				vars.flashlightEnabled = not vars.flashlightEnabled
				vars.flashFX.mod.SetEnabled(flashlightPart, vars.flashlightEnabled, vars.wepStats)
				PlayRepSound("Button")
				playerToggleAttachment.send({ AttachmentType = 0, Enabled = vars.flashlightEnabled })

				vars.flashFX.beamFP.Enabled = vars.flashlightEnabled and vars.firstPerson
				vars.flashFX.beamTP.Enabled = vars.flashlightEnabled and not vars.firstPerson

				local flashColor = glareMod.ResolveFlashlightColor(flashlightPart, vars.wepStats)

				local tpGunModel = GetThirdPersonGunModel()
				local tpFlashlightPart = tpGunModel and Attachments:GetFlashlightSource(tpGunModel)
				if tpFlashlightPart then
					vars.flashFX.mod.SetEnabled(tpFlashlightPart, vars.flashlightEnabled and not vars.firstPerson, vars.wepStats)
				end

				glareMod.SetFlashlightModelActive(flashlightPart, tpFlashlightPart, vars.firstPerson, vars.flashlightEnabled, flashColor, vars.wepStats)
			end

			if vars.wepStats.activateFlashlightLaser and not IsAnimationBusy() then
				vars.togglingAttachment = true
				local animTrack = PlayAnimation(vars.wepStats.activateFlashlightLaser, {priority = Enum.AnimationPriority.Action2})

				if animTrack then
					local keyframeConnection
					keyframeConnection = animTrack.KeyframeReached:Connect(function(keyframeName)
						if keyframeName == "Button" then
							ApplyFlashlightState()
							if keyframeConnection then
								keyframeConnection:Disconnect()
								keyframeConnection = nil
							end
						end
					end)
					animTrack.Stopped:Once(function()
						vars.togglingAttachment = false
						if keyframeConnection then
							keyframeConnection:Disconnect()
							keyframeConnection = nil
						end
					end)
				else
					ApplyFlashlightState()
					vars.togglingAttachment = false
				end
			else
				ApplyFlashlightState()
			end
		elseif actionName == "SPH_ToggleUBGL" and inputState == inputBegan then
			ubglSystem.ToggleUBGL()	
		end
	end	
end

BindGunInputs = function()
	contextActionService:BindActionAtPriority("SPH_Trigger",          HandleInput, false, config.gunInputPriority, unpack(config.fireGun))
	contextActionService:BindActionAtPriority("SPH_DropGun",          HandleInput, false, config.gunInputPriority, unpack(config.dropKey))
	contextActionService:BindActionAtPriority("SPH_Reload",           HandleInput, false, config.gunInputPriority, unpack(config.keyReload))
	contextActionService:BindActionAtPriority("SPH_Chamber",          HandleInput, false, config.gunInputPriority, unpack(config.keyChamber))
	contextActionService:BindActionAtPriority("SPH_SwitchSights",     HandleInput, false, config.gunInputPriority, unpack(config.sightSwitch))
	contextActionService:BindActionAtPriority("SPH_Freelook",         HandleInput, false, config.gunInputPriority, unpack(config.freeLook))
	contextActionService:BindActionAtPriority("SPH_HoldUp",           HandleInput, false, config.gunInputPriority, unpack(config.holdUp))
	contextActionService:BindActionAtPriority("SPH_HoldPatrol",       HandleInput, false, config.gunInputPriority, unpack(config.holdPatrol))
	contextActionService:BindActionAtPriority("SPH_HoldDown",         HandleInput, false, config.gunInputPriority, unpack(config.holdDown))
	contextActionService:BindActionAtPriority("SPH_SwitchFireMode",   HandleInput, false, config.gunInputPriority, unpack(config.switchFireMode))
	contextActionService:BindActionAtPriority("SPH_ToggleLaser",      HandleInput, false, config.gunInputPriority, unpack(config.toggleLaser))
	contextActionService:BindActionAtPriority("SPH_ToggleFlashlight", HandleInput, false, config.gunInputPriority, unpack(config.toggleFlashlight))
	contextActionService:BindActionAtPriority("SPH_Inspect",          HandleInput, false, config.gunInputPriority, unpack(config.keyInspect))

	if vars.wepStats.UBGL and vars.wepStats.UBGL.Enabled then
		contextActionService:BindActionAtPriority("SPH_ToggleUBGL", HandleInput, false, config.gunInputPriority, unpack(config.toggleUBGL))
	end

	if vars.firstPerson then
		BindAiming()
	end

	mobileSupport.SetupMobileButtons(aimFOVTargetRef)
end

UnbindGunInputs = function()
	contextActionService:UnbindAction("SPH_Trigger")
	contextActionService:UnbindAction("SPH_DropGun")
	contextActionService:UnbindAction("SPH_Reload")
	contextActionService:UnbindAction("SPH_HoldAim")
	contextActionService:UnbindAction("SPH_Chamber")
	contextActionService:UnbindAction("SPH_SwitchSights")
	contextActionService:UnbindAction("SPH_Freelook")
	contextActionService:UnbindAction("SPH_HoldUp")
	contextActionService:UnbindAction("SPH_HoldPatrol")
	contextActionService:UnbindAction("SPH_HoldDown")
	contextActionService:UnbindAction("SPH_SwitchFireMode")
	contextActionService:UnbindAction("SPH_ToggleLaser")
	contextActionService:UnbindAction("SPH_ToggleFlashlight")
	contextActionService:UnbindAction("SPH_Inspect")
	contextActionService:UnbindAction("SPH_ToggleUBGL")
	mobileSupport.DestroyMobileButtons()
end

function WeaponInput.init()
	local ctx = WeaponContext.get()
	BindAiming = ctx.BindAiming
	ChamberAnim = ctx.ChamberAnim
	ChangeHoldStance = ctx.ChangeHoldStance
	GetThirdPersonGunModel = ctx.GetThirdPersonGunModel
	IsAnimationBusy = ctx.IsAnimationBusy
	IsLoaded = ctx.IsLoaded
	PlayAnimation = ctx.PlayAnimation
	PlayEmptyClickAnimation = ctx.PlayEmptyClickAnimation
	PlayRepSound = ctx.PlayRepSound
	ReloadAnim = ctx.ReloadAnim
	StopAnimation = ctx.StopAnimation
	SwitchFireMode = ctx.SwitchFireMode
	ToggleAiming = ctx.ToggleAiming
	ToggleSprint = ctx.ToggleSprint
	Unequip = ctx.Unequip
	aimFOVTargetRef = ctx.aimFOVTargetRef
	fireModes = ctx.fireModes
	humanoid = ctx.humanoid
	inspectDoF = ctx.inspectDoF
	perGunSightIndex = ctx.perGunSightIndex
	playerDropGun = ctx.playerDropGun
	playerToggleAttachment = ctx.playerToggleAttachment
	switchFireMode = ctx.switchFireMode
end

WeaponInput.HandleInput = HandleInput
WeaponInput.BindGunInputs = BindGunInputs
WeaponInput.UnbindGunInputs = UnbindGunInputs

return WeaponInput
