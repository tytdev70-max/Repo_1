local Modules = script:FindFirstAncestor("Modules")
local Assets = Modules.Parent

local WeaponContext = require(Modules.Weapons.Core.WeaponContext)
local vars = require(Modules.Weapons.Core.WeaponState).get()
local config = require(Assets.GameConfig)
local assets = Assets
local animations = Assets.Animations
local attachmentManager = require(Modules.Weapons.Attachments.AttachmentManager)
local grenadeClient = require(Modules.Misc.Grenades.GrenadeClient)
local armPositionMod = require(Modules.Weapons.Aiming.ArmPositionMod)
local ubglSystem = require(Modules.Weapons.Attachments.UBGLHandlerMod)

local WeaponAnimation = {}

local warnedMissingFolder = {}
local warnedMissingInFolder = {}

local function GetAnimationObject(animName: string)
	if not animName then return nil end

	local wepStats = vars.wepStats
	if wepStats and wepStats.animFolder then
		local folderName = wepStats.animFolder
		local folder = animations:FindFirstChild(folderName)

		if not folder then
			if not warnedMissingFolder[folderName] then
				warnedMissingFolder[folderName] = true
				warn(("[WeaponAnimation] wepStats.animFolder is set to '%s' but no such folder exists under ReplicatedStorage.SPH_Assets.Animations. Falling back to flat lookup.")
					:format(folderName))
			end
		else
			local obj = folder:FindFirstChild(animName)
			if obj then
				return obj
			end

			local warnKey = folderName .. "/" .. animName
			if not warnedMissingInFolder[warnKey] then
				warnedMissingInFolder[warnKey] = true
				warn(("[WeaponAnimation] Animation '%s' not found in Animations.%s - did you forget to move it into the folder? Falling back to Animations.%s directly.")
					:format(animName, folderName, animName))
			end
		end
	end

	local fallback = animations:FindFirstChild(animName)
	if not fallback and wepStats and wepStats.animFolder then
		local warnKey = "MISSING::" .. animName
		if not warnedMissingInFolder[warnKey] then
			warnedMissingInFolder[warnKey] = true
			warn(("[WeaponAnimation] Animation '%s' could not be found in Animations.%s or Animations directly.")
				:format(animName, wepStats.animFolder))
		end
	end

	return fallback
end

local vmAnimator, playSound, repBoltOpen
local repChamber, repMagEject, repReload, EjectShell
local FindProjectilePart, GetThirdPersonGunModel, MoveBolt, SyncThirdPersonProjectile
local UpdateAllBulletTransparency, UpdateBulletTransparency

local IsAnimationBusy, StopConflictingAnimations, PlayRepSound, StopAnimation, PlayAnimation

local function GetMagAmmo()
	return vars.gunAmmo and vars.gunAmmo:FindFirstChild("MagAmmo")
end

local function GetToolValue(valueName)
	local value = vars.equipped and vars.equipped:FindFirstChild(valueName)
	return value ~= nil and value.Value
end

IsAnimationBusy = function()
	local fireAnimPlaying = vars.wepStats and vars.wepStats.fireAnim
		and vars.loadedAnims[vars.wepStats.fireAnim]
		and vars.loadedAnims[vars.wepStats.fireAnim].IsPlaying

	return vars.reloading or vars.chambering or vars.inspecting 
		or vars.equipping or vars.unequipping 
		or vars.magCheckDebounce or vars.switchingFireMode
		or vars.fireModeCheckDebounce or vars.togglingAttachment
		or vars.preFirePlaying or vars.emptyClickPlaying
		or fireAnimPlaying
end

StopConflictingAnimations = function(priority, transTime, isLooped)
	if vars.reloading or vars.inspecting or vars.chambering or vars.equipping or vars.unequipping then return end
	transTime = transTime or 0.05
	for name, track in pairs(vars.loadedAnims) do
		if typeof(track) == "Instance" and track:IsA("AnimationTrack") and track.IsPlaying then
			if track.Priority == priority and not string.find(name, "ThirdPerson") then
				if not track.Looped or isLooped then
					track:Stop(transTime)
					local tpTrack = vars.loadedAnims[name .. "ThirdPerson"]
					if tpTrack and typeof(tpTrack) == "Instance" and tpTrack:IsA("AnimationTrack") and tpTrack.IsPlaying then
						tpTrack:Stop(transTime)
					end
				end
			end
		end
	end
end

PlayRepSound = function(soundName)
	if not vars.dead then
		local isSuppressed = false
		if vars.equipped then
			local savedAttachments = vars.equipped:FindFirstChild("SavedAttachments")
			if savedAttachments then
				local muzzleData = savedAttachments:FindFirstChild("Muzzle")
				if muzzleData and muzzleData:IsA("StringValue") then
					local attachmentName = muzzleData.Value
					local categoryFolder = assets.GunAttachments:FindFirstChild("Muzzle")
					if categoryFolder then
						local attachmentFolder = categoryFolder:FindFirstChild(attachmentName)
						if attachmentFolder then
							local customizationModule = attachmentFolder:FindFirstChild("Customization")
							if customizationModule then
								local config = require(customizationModule)
								if config.EnableSilencer then
									isSuppressed = true
								end
							end
						end
					end
				end
			end
		end

		if isSuppressed then
			if soundName == "Fire" or soundName == "AutoFire" then
				soundName = "SilencedFire"
			elseif soundName == "Echo" then
				soundName = "SilencedEcho"
			elseif soundName == "AutoTail" then  
				soundName = "SilencedAutoTail"
			end
		end

		playSound.send({
			SoundName = soundName,
			FirstPerson = vars.firstPerson,
			Suppressed = isSuppressed,
		})

		if isSuppressed and (soundName == "Fire" or soundName == "AutoFire" or soundName == "Echo") then
			return
		end
	end
end

StopAnimation = function(animName:string, transTime:number)
	if vars.loadedAnims[animName] then
		if transTime then
			vars.loadedAnims[animName]:Stop(transTime)
			vars.loadedAnims[animName.."ThirdPerson"]:Stop(transTime)
		else
			vars.loadedAnims[animName]:Stop()
			vars.loadedAnims[animName.."ThirdPerson"]:Stop()
		end
	end
end

PlayAnimation = function(animName:string, parameters:table, animType:string, preload)
	parameters = parameters or {}

	if animName and (ubglSystem.IsActive() or ubglSystem.IsToggling()) then
		local isUBGLAnim = vars.wepStats and (
			animName == vars.wepStats.UBGLIdle
				or animName == vars.wepStats.UBGLEquip
				or animName == vars.wepStats.UBGLUnequip
				or animName == vars.wepStats.UBGLFire
				or animName == vars.wepStats.UBGLReload
		)
		if not isUBGLAnim then
			return nil, nil
		end
	end

	local animObject = GetAnimationObject(animName)
	local animToPlay, tpAnim
	if vars.loadedAnims[animName] then
		animToPlay = vars.loadedAnims[animName]
		tpAnim = vars.loadedAnims[animName.."ThirdPerson"]
	elseif animName and animObject then
		local newAnim = vmAnimator:LoadAnimation(animObject)
		newAnim.Looped = parameters.looped or false
		newAnim.Priority = parameters.priority or Enum.AnimationPriority.Action
		vars.loadedAnims[animName] = newAnim

		local thirdPersonAnim:AnimationTrack = vars.characterAnimator:LoadAnimation(animObject)
		thirdPersonAnim.Looped = parameters.looped or false
		thirdPersonAnim.Priority = parameters.priority or Enum.AnimationPriority.Action
		vars.loadedAnims[animName.."ThirdPerson"] = thirdPersonAnim

		newAnim.KeyframeReached:Connect(function(keyframeName)
			if not vars.equipped or not vars.wepStats then return end
			local grip = vars.gunModel and vars.gunModel:FindFirstChild("Grip")

			if grip and grip:FindFirstChild(keyframeName) then
				PlayRepSound(keyframeName)
			end

			if keyframeName == "MagIn" then
				if vars.firstPerson and vars.gunModel then
					local mag = FindProjectilePart(vars.gunModel, vars.wepStats.projectile)
					if mag then
						mag.Transparency = 0
						for _, child in ipairs(mag:GetDescendants()) do
							if child:IsA("BasePart") then
								child.LocalTransparencyModifier = 0
							end
						end
					end
					local bulletHolderPart = vars.wepStats.bulletHolder and vars.gunModel:FindFirstChild(vars.wepStats.bulletHolder)
					if bulletHolderPart then
						UpdateAllBulletTransparency(bulletHolderPart, 0)
					end
				end
				local tpGunModel = GetThirdPersonGunModel()
				if tpGunModel then
					local tpMag = FindProjectilePart(tpGunModel, vars.wepStats.projectile)
					if tpMag and not tpMag:GetAttribute("ForceHidden_Anim") then   
						tpMag.Transparency = 0
						for _, child in ipairs(tpMag:GetDescendants()) do
							if child:IsA("BasePart") then child.Transparency = 0 end
							if child:IsA("Decal") or child:IsA("Texture") then child.Transparency = 0 end
						end
					end
					local tpBulletHolder = vars.wepStats.bulletHolder and tpGunModel:FindFirstChild(vars.wepStats.bulletHolder)
					if tpBulletHolder then UpdateAllBulletTransparency(tpBulletHolder, 0) end
				end
				task.delay(0.4, function()
					if not vars.equipped or not vars.wepStats then return end
					local tpRetry = GetThirdPersonGunModel()
					if tpRetry then
						local tpMagRetry = FindProjectilePart(tpRetry, vars.wepStats.projectile)
						if tpMagRetry then
							local stillLoaded = false
							local magAmmo = GetMagAmmo()
							if vars.wepStats.operationType == 4 then
								stillLoaded = true  
							elseif vars.wepStats.openBolt then
								stillLoaded = magAmmo ~= nil and magAmmo.Value > 0
							else
								stillLoaded = GetToolValue("Chambered") or (magAmmo ~= nil and magAmmo.Value > 0)
							end
							if stillLoaded then
								tpMagRetry.Transparency = 0
								for _, child in ipairs(tpMagRetry:GetDescendants()) do
									if child:IsA("BasePart") then child.Transparency = 0 end
									if child:IsA("Decal") or child:IsA("Texture") then child.Transparency = 0 end
								end
							end
						end
					end
				end)
				repReload.send(nil)
				if vars.wepStats.magType > 1 and vars.wepStats.magType ~= 4 then
					newAnim.DidLoop:Once(function() StopAnimation(animName) end)
				end
			elseif keyframeName == "MagOut" then
				if vars.dead or not vars.equipped or not vars.wepStats or not vars.gunModel then return end
				if not vars.reloading or vars.cancelReload or vars.magDroppedThisReload then return end
				vars.magDroppedThisReload = true
				task.wait(0.05)
				if not vars.equipped or not vars.reloading then return end

				if vars.wepStats.keepProjectileVisibleDuringReload then
					return
				end

				local ejectionCFrame
				local dropPartNames = {}

				if typeof(vars.wepStats.MagDropName) == "table" and #vars.wepStats.MagDropName > 0 then
					dropPartNames = vars.wepStats.MagDropName
				elseif typeof(vars.wepStats.MagDropName) == "string" then
					dropPartNames = {vars.wepStats.MagDropName}
				else
					dropPartNames = {""}
				end

				if vars.firstPerson and vars.gunModel then
					local ejectionPoint = vars.gunModel.Grip:FindFirstChild("Mag") 
						or vars.gunModel.Grip:FindFirstChild("Muzzle")

					for _, name in ipairs(dropPartNames) do
						local dropPart = vars.gunModel:FindFirstChild(name, true)
							or (vars.wepStats.projectile ~= "Bullet" and vars.wepStats.projectile ~= "Mag" and vars.gunModel:FindFirstChild(vars.wepStats.projectile))
							or vars.gunModel:FindFirstChild("")

						if dropPart then
							if not ejectionCFrame then
								ejectionCFrame = ejectionPoint and ejectionPoint.WorldCFrame or dropPart.WorldCFrame
							end

							dropPart.Transparency = 1
							for _, child in ipairs(dropPart:GetDescendants()) do
								if child:IsA("BasePart") then
									child.LocalTransparencyModifier = 1
									child.Transparency = 1
								elseif child:IsA("Decal") or child:IsA("Texture") then
									child.Transparency = 1
								end
							end
						end
					end

					local bulletHolder = vars.wepStats.bulletHolder and vars.gunModel:FindFirstChild(vars.wepStats.bulletHolder)
					if bulletHolder then 
						UpdateAllBulletTransparency(bulletHolder, 1) 
					end
				end

				local tpGunModel = GetThirdPersonGunModel()
				if tpGunModel then
					for _, name in ipairs(dropPartNames) do
						local tpMag = FindProjectilePart(tpGunModel, name) 
							or tpGunModel:FindFirstChild(name, true)
						if tpMag then
							tpMag.Transparency = 1
							for _, child in ipairs(tpMag:GetDescendants()) do
								if child:IsA("BasePart") then
									child.Transparency = 1
								elseif child:IsA("Decal") or child:IsA("Texture") then
									child.Transparency = 1
								end
							end
						end
					end

					local tpBulletHolder = vars.wepStats.bulletHolder and tpGunModel:FindFirstChild(vars.wepStats.bulletHolder)
					if tpBulletHolder then 
						UpdateAllBulletTransparency(tpBulletHolder, 1) 
					end
				end

				if not ejectionCFrame and tpGunModel then
					local point = tpGunModel.Grip:FindFirstChild("Mag") or tpGunModel.Grip:FindFirstChild("Muzzle")
					if point and (point:IsA("BasePart") or point:IsA("Attachment")) then
						ejectionCFrame = point.WorldCFrame
					end
				end

				if ejectionCFrame then
					repMagEject.send({
						GunName = vars.equipped.Name,
						EjectionCFrame = ejectionCFrame,
						DropPartNames = dropPartNames,
						MagDropFolderSounds = vars.wepStats.MagDropFolderSounds,
					})
				end
			elseif keyframeName == "ShellInsert" or keyframeName == "BulletInsert" then
				local magAmmo = GetMagAmmo()
				local arcadePool = vars.gunAmmo and vars.gunAmmo:FindFirstChild("ArcadeAmmoPool")
				if vars.cancelReload then 
					vars.cancelReload = false
					newAnim.Looped = false
					newAnim.Stopped:Once(function()
						if not vars.equipped or not vars.wepStats then return end
						StopAnimation(newAnim.Name)
						if not GetToolValue("BoltReady") or vars.wepStats.openBolt then
							PlayAnimation(vars.wepStats.boltClose,{priority = Enum.AnimationPriority.Action2})
						else
							vars.reloading = false
						end
					end)
				elseif magAmmo and arcadePool and (magAmmo.Value + 1 >= magAmmo.MaxValue or arcadePool.Value - 1 <= 0) then
					newAnim.DidLoop:Once(function()
						if not vars.equipped or not vars.wepStats then return end
						StopAnimation(newAnim.Name)
						if not GetToolValue("BoltReady") or vars.wepStats.operationType == 3 or vars.wepStats.openBolt then
							PlayAnimation(vars.wepStats.boltClose,{priority = Enum.AnimationPriority.Action2})
						else
							vars.reloading = false
						end
					end)
				end

				local bulletHolderPart = vars.wepStats.bulletHolder and vars.gunModel and vars.gunModel:FindFirstChild(vars.wepStats.bulletHolder)
				if bulletHolderPart and magAmmo then
					local bulletNumber = magAmmo.MaxValue - magAmmo.Value
					UpdateBulletTransparency(bulletHolderPart, bulletNumber, 0)
				end

				repReload.send(nil)
			elseif keyframeName == "ClipInsertEnd" then
				local magAmmo = GetMagAmmo()
				if not magAmmo then return end
				local ammoNeeded = magAmmo.MaxValue - magAmmo.Value
				local clipSize = vars.wepStats.clipSize or vars.wepStats.magazineCapacity

				if ammoNeeded > 0 then
					StopAnimation(newAnim.Name)
					if ammoNeeded >= clipSize then
						PlayAnimation(vars.wepStats.clipReloadAnim,{looped = true,speed = vars.wepStats.reloadSpeedModifier,priority = Enum.AnimationPriority.Action2,transSpeed = 0.17})
					else
						PlayAnimation(vars.wepStats.reloadAnim,{speed = vars.wepStats.reloadSpeedModifier,priority = Enum.AnimationPriority.Action2,transSpeed = 0.17},"Reload")
					end
				end




			elseif keyframeName == "ClipInsert" then
				repReload.send(nil)
			elseif keyframeName == "SlideRelease" or keyframeName == "BoltClose" then
				repChamber.send(nil)
				if not vars.chambering then
					vars.lastReloadCompletedTime = tick()
					vars.slideReleaseHasPlayed = true
					vars.reloading = false
				end
				MoveBolt(CFrame.new(), true)
			elseif keyframeName == "SlidePull" then
				if not vars.ejected then
					EjectShell()
				end
			elseif keyframeName == "MagGrab" then
				if vars.cancelReload or not vars.reloading then return end
				if vars.gunModel and vars.wepStats.projectile ~= "Bullet" and vars.gunModel:FindFirstChild(vars.wepStats.projectile) then
					local projectile = vars.gunModel:FindFirstChild(vars.wepStats.projectile)
					projectile.LocalTransparencyModifier = 0
					for _, child in ipairs(projectile:GetDescendants()) do
						if child:IsA("BasePart") then
							child.LocalTransparencyModifier = 0
						end
					end
				end

				local thirdPersonGunModel = GetThirdPersonGunModel()
				if thirdPersonGunModel then
					local tpProjectile = FindProjectilePart(thirdPersonGunModel, vars.wepStats.projectile)
					if tpProjectile then
						tpProjectile.Transparency = 0
						for _, child in ipairs(tpProjectile:GetDescendants()) do
							if child:IsA("BasePart") then
								child.Transparency = 0
							elseif child:IsA("Decal") or child:IsA("Texture") then
								child.Transparency = 0
							end
						end
					end
				end
			elseif keyframeName == "BoltOpen" then
				repBoltOpen.send(nil)
				if not vars.ejected then
					EjectShell()
				end
			elseif keyframeName == "MagPouch" then
				local bulletHolderPart = vars.wepStats.bulletHolder and vars.gunModel and vars.gunModel:FindFirstChild(vars.wepStats.bulletHolder)
				if bulletHolderPart then
					UpdateAllBulletTransparency(bulletHolderPart, 0)
				end
			elseif keyframeName == "UBGLShell" then
				ubglSystem.HandleReloadKeyframe()	
			elseif vars.wepStats.grenade then
				grenadeClient.HandleThrowKeyframe(animName, keyframeName)
			end
		end)

		newAnim.Stopped:Connect(function()
			if animType == "Reload" then
				local wasCancelled = vars.cancelReload == true
				vars.reloading = false
				if not wasCancelled then
					vars.lastReloadCompletedTime = tick()
				end

				if vars.wepStats and (vars.wepStats.operationType == 4 or vars.wepStats.magType == 4) and not wasCancelled then
					local chambered = vars.equipped and vars.equipped:FindFirstChild("Chambered")
					if chambered and not chambered.Value then
						repReload.send(nil)
					end
				end

				local shouldBeLoaded = false
				local stoppedMagAmmo = GetMagAmmo()
				if vars.wepStats then
					if vars.wepStats.openBolt then
						shouldBeLoaded = stoppedMagAmmo ~= nil and stoppedMagAmmo.Value > 0
					else
						shouldBeLoaded = GetToolValue("Chambered") or (stoppedMagAmmo ~= nil and stoppedMagAmmo.Value > 0)
					end
				end
				if wasCancelled then
					shouldBeLoaded = GetToolValue("Chambered") or (stoppedMagAmmo ~= nil and stoppedMagAmmo.Value > 0)
				end

				if vars.wepStats and vars.wepStats.projectile ~= "Bullet" then
					if vars.gunModel and vars.gunModel:FindFirstChild(vars.wepStats.projectile, true) then
						local projectile = vars.gunModel:FindFirstChild(vars.wepStats.projectile, true)
						local visMod = shouldBeLoaded and 0 or 1
						projectile.LocalTransparencyModifier = visMod
						for _, child in ipairs(projectile:GetDescendants()) do
							if child:IsA("BasePart") then
								child.LocalTransparencyModifier = visMod
							end
						end
					end

					local tpGunModel = GetThirdPersonGunModel()
					if tpGunModel then
						local tpProjectile = FindProjectilePart(tpGunModel, vars.wepStats.projectile)
						if tpProjectile then
							local vis = shouldBeLoaded and 0 or 1
							tpProjectile.Transparency = vis
							if not shouldBeLoaded then
								tpProjectile:SetAttribute("ForceHidden_Anim", nil)
							end
							for _, child in ipairs(tpProjectile:GetDescendants()) do
								if child:IsA("BasePart") then
									child.Transparency = vis
								elseif child:IsA("Decal") or child:IsA("Texture") then
									child.Transparency = vis
								end
							end
						end
					end

					task.delay(0.5, function()
						if not vars.equipped or not vars.wepStats then return end
						if vars.reloading then return end 
						local tpGunModel2 = GetThirdPersonGunModel()
						if not tpGunModel2 then return end
						local tpProjectile2 = FindProjectilePart(tpGunModel2, vars.wepStats.projectile)
						if not tpProjectile2 then return end

						local isNowLoaded = false
						local delayedMagAmmo = GetMagAmmo()
						if vars.wepStats.operationType == 4 then
							isNowLoaded = GetToolValue("Chambered") or shouldBeLoaded
						elseif vars.wepStats.openBolt then
							isNowLoaded = delayedMagAmmo ~= nil and delayedMagAmmo.Value > 0
						else
							isNowLoaded = GetToolValue("Chambered") or (delayedMagAmmo ~= nil and delayedMagAmmo.Value > 0)
						end

						if isNowLoaded then
							tpProjectile2.Transparency = 0
							for _, child in ipairs(tpProjectile2:GetDescendants()) do
								if child:IsA("BasePart") then child.Transparency = 0 end
								if child:IsA("Decal") or child:IsA("Texture") then child.Transparency = 0 end
							end
						end
					end)

					task.delay(2, function()
						if vars.equipped then
							SyncThirdPersonProjectile()
						end
					end)
				else
					if vars.wepStats and vars.gunModel and vars.gunModel:FindFirstChild(vars.wepStats.projectile, true) then
						local projectile = vars.gunModel:FindFirstChild(vars.wepStats.projectile, true)
						if shouldBeLoaded then
							projectile.LocalTransparencyModifier = 0
							for _, child in ipairs(projectile:GetDescendants()) do
								if child:IsA("BasePart") then
									child.LocalTransparencyModifier = 0
								end
							end
						end
					end

					local tpGunModel = GetThirdPersonGunModel()
					if tpGunModel and shouldBeLoaded then
						local tpProjectile = FindProjectilePart(tpGunModel, vars.wepStats.projectile)
						if tpProjectile then
							tpProjectile.Transparency = 0
							for _, child in ipairs(tpProjectile:GetDescendants()) do
								if child:IsA("BasePart") then
									child.Transparency = 0
								elseif child:IsA("Decal") or child:IsA("Texture") then
									child.Transparency = 0
								end
							end
						end
					end

					task.delay(0.3, function()
						if vars.equipped then
							SyncThirdPersonProjectile()
						end
					end)

					task.delay(0.6, function()
						if vars.equipped then
							SyncThirdPersonProjectile()
						end
					end)
				end
			end
		end)

		animToPlay = newAnim
		tpAnim = thirdPersonAnim
	end

	local playAnimFP = true
	if animType == "AimAnim" and not config.firstPersonAimAnim then
		playAnimFP = false
	end

	if animToPlay and not preload then
		local incomingPriority = parameters.priority or animToPlay.Priority or Enum.AnimationPriority.Action
		local incomingLooped = parameters.looped or animToPlay.Looped or false
		StopConflictingAnimations(incomingPriority, parameters.transSpeed or 0.05, incomingLooped)

		if playAnimFP then
			animToPlay:Play(parameters.transSpeed or 0)
			animToPlay:AdjustSpeed(parameters.speed or 1)
		end
		tpAnim:Play(parameters.transSpeed or 0)
		tpAnim:AdjustSpeed(parameters.speed or 1)

		armPositionMod.ResetLockedArmTransform()
	end

	return animToPlay, animObject
end

function WeaponAnimation.init()
	local ctx = WeaponContext.get()
	vmAnimator = ctx.vmAnimator
	playSound = ctx.playSound
	repBoltOpen = ctx.repBoltOpen
	repChamber = ctx.repChamber
	repMagEject = ctx.repMagEject
	repReload = ctx.repReload
	EjectShell = ctx.EjectShell
	FindProjectilePart = ctx.FindProjectilePart
	GetThirdPersonGunModel = ctx.GetThirdPersonGunModel
	MoveBolt = ctx.MoveBolt
	SyncThirdPersonProjectile = ctx.SyncThirdPersonProjectile
	UpdateAllBulletTransparency = ctx.UpdateAllBulletTransparency
	UpdateBulletTransparency = ctx.UpdateBulletTransparency
end

WeaponAnimation.IsAnimationBusy = IsAnimationBusy
WeaponAnimation.StopConflictingAnimations = StopConflictingAnimations
WeaponAnimation.PlayRepSound = PlayRepSound
WeaponAnimation.StopAnimation = StopAnimation
WeaponAnimation.PlayAnimation = PlayAnimation

return WeaponAnimation
