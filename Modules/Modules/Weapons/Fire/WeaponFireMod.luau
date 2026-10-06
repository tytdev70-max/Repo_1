local WeaponFireMod = {}

local Modules = script:FindFirstAncestor("Modules")
local vars = require(Modules.Weapons.Core.WeaponState).get()
local character
local camera
local defaultFOV
local rayParams
local config
local tweenService
local shootBlur
local Attachments = require(Modules.Weapons.Attachments.SPHAttachments)
local bulletHandler
local player
local playerGui
local ubglSystem
local fireModes
local playerFire
local repChamber
local repChamberSmoke
local repOverheat
local overheatThrottle
local recoilSpring
local gunRecoilSpring
local gunRotSpring

local ejectShell
local moveBoltAction
local chamberAnim
local isLoaded
local playAnimation
local playRepSound
local aimToFOV
local updateBulletTransparency
local findProjectilePart

local getThirdPersonGunModel

local cachedCustomizeGUI: Instance? = nil

local lastOverheatVisualModel: Instance? = nil
local lastOverheatVisualTPModel: Instance? = nil
local lastOverheatVisualEnabled: boolean? = nil
local lastOverheatVisualFirstPerson: boolean? = nil

function WeaponFireMod.Init(deps)
	getThirdPersonGunModel = deps.getThirdPersonGunModel
	character = deps.character
	camera = deps.camera
	defaultFOV = deps.defaultFOV
	rayParams = deps.rayParams
	config = deps.config
	tweenService = deps.tweenService
	shootBlur = deps.shootBlur
	bulletHandler = deps.bulletHandler
	player = deps.player
	playerGui = deps.playerGui
	ubglSystem = deps.ubglSystem
	fireModes = deps.fireModes
	playerFire = deps.playerFire
	repChamber = deps.repChamber
	repChamberSmoke = deps.repChamberSmoke
	repOverheat = deps.repOverheat
	overheatThrottle = deps.overheatThrottle
	recoilSpring = deps.recoilSpring
	gunRecoilSpring = deps.gunRecoilSpring
	gunRotSpring = deps.gunRotSpring

	ejectShell = deps.ejectShell
	moveBoltAction = deps.moveBoltAction
	chamberAnim = deps.chamberAnim
	isLoaded = deps.isLoaded
	playAnimation = deps.playAnimation
	playRepSound = deps.playRepSound
	aimToFOV = deps.aimToFOV
	updateBulletTransparency = deps.updateBulletTransparency
	findProjectilePart = deps.findProjectilePart

	cachedCustomizeGUI = nil
	lastOverheatVisualModel = nil
	lastOverheatVisualTPModel = nil
	lastOverheatVisualEnabled = nil
	lastOverheatVisualFirstPerson = nil
end

local function GetCustomizeGUI(): Instance?
	if cachedCustomizeGUI and cachedCustomizeGUI.Parent then
		return cachedCustomizeGUI
	end
	-- the customize menu: Gunsmith or CustomizeGunGUI (GameConfig.customizeMenu)
	cachedCustomizeGUI = playerGui:FindFirstChild("Gunsmith") or playerGui:FindFirstChild("CustomizeGunGUI")
	return cachedCustomizeGUI
end

local function UpdateOverheat(dt: number)
	local equipped = vars.equipped
	local wepStats = vars.wepStats
	local gunModel = vars.gunModel

	if equipped and wepStats and gunModel then
		local attachmentHeatConfig = Attachments:GetConfigField(gunModel, "Muzzle", "overHeating")
		local heatConfig = attachmentHeatConfig or wepStats.overHeating

		if heatConfig and heatConfig.Enabled then
			local currentTime = tick()

			if vars.isOverheated then
				if currentTime - vars.cooldownStartTime >= heatConfig.OverheatCooldown then
					vars.currentHeat = math.max(0, vars.currentHeat - (heatConfig.CoolRate * dt))
					if vars.currentHeat <= 0 then
						vars.isOverheated = false
						vars.currentHeat = 0
					end
				end
			elseif currentTime - vars.lastShotTime >= heatConfig.HeatDissipationDelay then
				vars.currentHeat = math.max(0, vars.currentHeat - (heatConfig.CoolRate * dt))
			end

			local shouldEnable = (vars.currentHeat / heatConfig.MaxHeat) > 0.5
			local tpGunModel = getThirdPersonGunModel()

			local visualStateChanged = (gunModel ~= lastOverheatVisualModel)
				or (tpGunModel ~= lastOverheatVisualTPModel)
				or (shouldEnable ~= lastOverheatVisualEnabled)
				or (vars.firstPerson ~= lastOverheatVisualFirstPerson)

			if visualStateChanged then
				lastOverheatVisualModel = gunModel
				lastOverheatVisualTPModel = tpGunModel
				lastOverheatVisualEnabled = shouldEnable
				lastOverheatVisualFirstPerson = vars.firstPerson

				local function SetExclusiveOverheat(model, enable)
					if not model then return end

					local grip = model:FindFirstChild("Grip")
					local activeMuzzle = Attachments:GetActiveMuzzle(model)
						or (grip and (grip:FindFirstChild("Muzzle") or grip))

					for _, emitter in ipairs(model:GetDescendants()) do
						if emitter:IsA("ParticleEmitter") and emitter.Name == heatConfig.heatEffectName then
							emitter.Enabled = false
						end
					end

					if not activeMuzzle then
						return
					end

					local heatEffect = activeMuzzle:FindFirstChild(heatConfig.heatEffectName)
					if heatEffect and heatEffect:IsA("ParticleEmitter") then
						heatEffect.Enabled = enable
					end
				end

				SetExclusiveOverheat(gunModel, shouldEnable)

				if tpGunModel then
					SetExclusiveOverheat(tpGunModel, not vars.firstPerson and shouldEnable)
				end
			end

			if overheatThrottle:ShouldSend(shouldEnable) then
				repOverheat.send(shouldEnable)
			end
		else
			vars.currentHeat = 0
			vars.isOverheated = false
			vars.lastShotTime = 0
			vars.cooldownStartTime = 0
		end
	else
		vars.currentHeat = 0
		vars.isOverheated = false
		vars.lastShotTime = 0
		vars.cooldownStartTime = 0
	end
end

local function UpdateFireLoop(dt: number)
	local equipped = vars.equipped
	local wepStats = vars.wepStats
	local gunModel = vars.gunModel
	local gunAmmo = vars.gunAmmo
	local sprinting = vars.sprinting
	local reloading = vars.reloading
	local aiming = vars.aiming
	local freeLook = vars.freeLook
	local curFireMode = vars.curFireMode
	local weaponRig = vars.weaponRig
	local proneMoveAnim = vars.proneMoveAnim

	local customizeGUI = GetCustomizeGUI()
	local menuOpen = customizeGUI and customizeGUI.Enabled

	if equipped and not vars.dead and vars.holdingM1 and vars.cycled and not sprinting and not reloading and not vars.chambering and not vars.inspecting
		and camera.CameraType == Enum.CameraType.Custom
		and not vars.magCheckHeld and not vars.magCheckDebounce
		and not vars.fireModeCheckHeld and not vars.fireModeCheckDebounce
		and not menuOpen and camera.CameraType == Enum.CameraType.Custom
		and not vars.unequipping and not vars.dropping
		and not ubglSystem.IsActive() and not ubglSystem.IsToggling() then

		if not gunAmmo or not gunAmmo.Parent or not gunAmmo:FindFirstChild("MagAmmo") then
			vars.cycled = true
			return
		end

		if vars.canFire
			and not vars.blocked
			and vars.holdStance == 0
			and isLoaded()
			and curFireMode > 0
			and (config.fireWithFreelook or (not config.fireWithFreelook and not freeLook))
			and not vars.equipping
			and not vars.inspecting
			and (not wepStats.preFire or vars.preFireReady) then

			if proneMoveAnim and proneMoveAnim.IsPlaying then return end
			if not vars.firstPerson and not config.thirdPersonFiring then return end

			if wepStats.fireAnim then
				local fireTrack = playAnimation(wepStats.fireAnim, {priority = Enum.AnimationPriority.Action2, looped = false})
				if fireTrack and wepStats.preFire then
					vars.preFireLocked = true
					fireTrack.Stopped:Once(function()
						vars.preFireLocked = false
					end)
				end
			end

			vars.bulletsCurrentlyFired += 1
			vars.ejected = false
			vars.lastReloadCompletedTime = 0

			local heatConfig = Attachments:GetConfigField(gunModel, "Muzzle", "overHeating") or wepStats.overHeating
			if heatConfig and heatConfig.Enabled then
				vars.currentHeat = vars.currentHeat + heatConfig.HeatPerShot
				vars.lastShotTime = tick()

				if vars.currentHeat >= heatConfig.MaxHeat then
					vars.currentHeat = heatConfig.MaxHeat
					vars.isOverheated = true
					vars.cooldownStartTime = tick()
				end
			end

			if curFireMode == fireModes.Semi or curFireMode == fireModes.Manual or (curFireMode == fireModes.Burst and vars.bulletsCurrentlyFired >= wepStats.burstNumber) then
				vars.canFire = false
				vars.holdingM1 = false
			end
			vars.cycled = false
			local capturedFireGeneration = vars.equipGeneration
			local curModel = gunModel

			local fpModel = gunModel
			local tpModel = getThirdPersonGunModel()

			if wepStats.chamberEffectEnabled == true then
				local fpChamberAttachment = fpModel.Grip:FindFirstChild("Chamber")
				if fpChamberAttachment then
					for _, effect in ipairs(fpChamberAttachment:GetChildren()) do
						if effect:IsA("ParticleEmitter") then
							effect.Enabled = true
							local emitCount = effect:GetAttribute("EmitCount")
							if emitCount then
								effect:Emit(emitCount)
							end
						end
					end
					local duration = wepStats.chamberEffectDuration or 0.1
					task.delay(duration, function()
						if fpChamberAttachment then
							for _, effect in ipairs(fpChamberAttachment:GetChildren()) do
								if effect:IsA("ParticleEmitter") then
									effect.Enabled = false
								end
							end
						end
					end)

					repChamberSmoke.send(duration)
				end

				if not vars.firstPerson and tpModel then
					local tpChamberAttachment = tpModel.Grip:FindFirstChild("Chamber")
					if tpChamberAttachment then
						for _, effect in ipairs(tpChamberAttachment:GetChildren()) do
							if effect:IsA("ParticleEmitter") then
								effect.Enabled = true
								local emitCount = effect:GetAttribute("EmitCount")
								if emitCount then
									effect:Emit(emitCount)
								end
							end
						end
						local duration = wepStats.chamberEffectDuration or 0.1
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
				end
			end

			local recoilStats = wepStats.recoil
			local vertRecoil = recoilStats.vertical
			local horzRecoil = recoilStats.horizontal
			horzRecoil *= 100
			local horzBound = math.floor(math.abs(horzRecoil))
			horzRecoil = math.random(-horzBound, horzBound)
			horzRecoil /= 100

			if aiming then
				vertRecoil /= (recoilStats.aimReduction or 1)
				horzRecoil /= (recoilStats.aimReduction or 1)
			end
			if character:GetAttribute("Stance") == "Prone" then
				vertRecoil /= 3
				horzRecoil /= 3
			end

			recoilSpring:shove(Vector3.new(vertRecoil, horzRecoil, recoilStats.camShake))

			recoilStats = wepStats.gunRecoil
			vertRecoil = recoilStats.vertical

			horzRecoil = recoilStats.horizontal
			horzRecoil *= 100
			local gunHorzBound = math.floor(math.abs(horzRecoil))
			horzRecoil = math.random(-gunHorzBound, gunHorzBound)

			if character:GetAttribute("Stance") == "Prone" then
				vertRecoil /= 1.5
				horzRecoil /= 1.5
			end

			horzRecoil /= 100

			gunRecoilSpring:shove(Vector3.new(vertRecoil, horzRecoil, recoilStats.punchMultiplier))

			local rotStats = wepStats.rotationalRecoil
			if rotStats then
				local pitch = rotStats.pitch or 0
				local yaw = rotStats.yaw or 0
				local roll = rotStats.roll or 0

				local yawBound = math.floor(math.abs(yaw))
				local rollBound = math.floor(math.abs(roll))
				yaw = math.random(-yawBound, yawBound)
				roll = math.random(-rollBound, rollBound)

				if aiming then
					local reduction = rotStats.aimReduction or 1
					pitch = pitch / reduction
					yaw = yaw / reduction
					roll = roll / reduction
				end

				gunRotSpring:shove(Vector3.new(pitch, yaw, roll))
			end

			if curFireMode ~= fireModes.Manual and not wepStats.shotgun then
				ejectShell()
			end

			local bulletHolderPart = wepStats.bulletHolder and gunModel:FindFirstChild(wepStats.bulletHolder)
			if bulletHolderPart then
				local bulletNumber = gunAmmo.MagAmmo.MaxValue - (gunAmmo.MagAmmo.Value - 1)
				updateBulletTransparency(bulletHolderPart, bulletNumber, 1)
			end

			local tempGunModel = gunModel
			if not vars.firstPerson then
				tempGunModel = getThirdPersonGunModel() or gunModel
			end
			local isAutoFire = (curFireMode == fireModes.Auto)

			-- Any mounted slot may suppress (Muzzle, Barrel, ...).
			local isSuppressed = Attachments:AnyActiveFlag(gunModel, "EnableSilencer")

			bulletHandler.FireFX(player, tempGunModel, "Muzzle", wepStats.muzzleChance, nil, isAutoFire, isSuppressed)

			moveBoltAction(wepStats.boltDist)

			local shotCount = (wepStats.shotgun and wepStats.shotgunPellets) or 1
			local pelletDirections = {}
			repeat
				shotCount -= 1
				local bulletOrigin, bulletDirection
				local tempSpread = wepStats.spread * 100
				local spreadCFrame = CFrame.Angles(math.rad(math.random(-tempSpread, tempSpread) / 100), math.rad(math.random(-tempSpread, tempSpread) / 100), 0)
				if vars.firstPerson then
					local muzzleCFrame = curModel.Grip.Muzzle.WorldCFrame
					local desiredMuzzlePos = muzzleCFrame.Position
					local safeOrigin = camera.CFrame.Position
					local toMuzzle = desiredMuzzlePos - safeOrigin

					if toMuzzle.Magnitude > 0.01 then
						local wallCheck = workspace:Raycast(safeOrigin, toMuzzle, rayParams)
						if wallCheck and wallCheck.Instance and not wallCheck.Instance:HasTag("SPH_NoCollide") then
							bulletOrigin = wallCheck.Position - (toMuzzle.Unit * 0.1)
						else
							bulletOrigin = desiredMuzzlePos
						end
					else
						bulletOrigin = desiredMuzzlePos
					end

					bulletDirection = (muzzleCFrame * spreadCFrame).LookVector
				else
					local tpFireModel = getThirdPersonGunModel()
					local muzzle = tpFireModel and tpFireModel:FindFirstChild("Grip") and tpFireModel.Grip:FindFirstChild("Muzzle")
					if not muzzle then
						vars.cycled = true
						return
					end
					local muzzlePosition = muzzle.WorldCFrame.Position
					local muzzleDirection = muzzle.WorldCFrame.LookVector

					local rayOrigin = muzzlePosition + (muzzleDirection * -3)
					local rayResult = workspace:Raycast(rayOrigin, muzzleDirection * 3, rayParams)
					if rayResult then
						bulletOrigin = rayResult.Position + muzzleDirection * -0.1
					else
						bulletOrigin = muzzle.WorldCFrame.Position
					end

					bulletDirection = (muzzle.WorldCFrame * spreadCFrame).LookVector
				end

				local bulletVelocity = (bulletDirection * wepStats.muzzleVelocity * config.meterMultiplier)

				local tracerColor = nil
				if wepStats.tracers and gunAmmo.MagAmmo.Value % wepStats.tracerTiming == 0 then
					tracerColor = wepStats.tracerColor
				end

				bulletHandler.FireBullet(weaponRig, bulletOrigin, bulletDirection, bulletVelocity, equipped, player, tracerColor)
				table.insert(pelletDirections, bulletDirection)
			until shotCount <= 0

			playerFire.send({
				MuzzleCFrame = curModel.Grip.Muzzle.WorldCFrame,
				Directions = pelletDirections,
			})

			local cycleTime = wepStats.fireRate
			if curFireMode == fireModes.Burst and wepStats.burstFireRate then
				cycleTime = wepStats.burstFireRate
			end

			if gunModel and wepStats.projectile ~= "Bullet" and gunModel:FindFirstChild(wepStats.projectile) then
				local projectile = gunModel:FindFirstChild(wepStats.projectile)
				projectile.LocalTransparencyModifier = 1
				for _, child in ipairs(projectile:GetDescendants()) do
					if child:IsA("BasePart") then
						child.LocalTransparencyModifier = 1
					end
				end
			end

			local tpGunModel = getThirdPersonGunModel()
			if tpGunModel then
				local tpProjectile = findProjectilePart(tpGunModel, wepStats.projectile)
				if tpProjectile then
					tpProjectile.Transparency = 1
					for _, child in ipairs(tpProjectile:GetDescendants()) do
						if child:IsA("BasePart") then
							child.Transparency = 1
						elseif child:IsA("Decal") or child:IsA("Texture") then
							child.Transparency = 1
						end
					end
				end
			end

			if wepStats.fireBlur and wepStats.fireBlur > 0 and shootBlur then
				if shootBlur:FindFirstChild("BlurTweenIn") then
					shootBlur.BlurTweenIn:Cancel()
				end
				if shootBlur:FindFirstChild("BlurTweenOut") then
					shootBlur.BlurTweenOut:Cancel()
				end

				local tweenIn = tweenService:Create(
					shootBlur,
					TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Size = wepStats.fireBlur}
				)
				tweenIn.Name = "BlurTweenIn"
				tweenIn:Play()

				task.delay(0.05, function()
					if not shootBlur or not shootBlur.Parent then return end
					local tweenOut = tweenService:Create(
						shootBlur,
						TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{Size = 0}
					)
					tweenOut.Name = "BlurTweenOut"
					tweenOut:Play()
					tweenOut:Play()
				end)
			end

			if wepStats.fireFov and wepStats.fireFov.fireFov then
				if vars.fireFovReturnTask then
					task.cancel(vars.fireFovReturnTask)
					vars.fireFovReturnTask = nil
				end

				local targetFireFOV = wepStats.fireFov.fireFov
				local normalFOV = wepStats.fireFov.normalFov or defaultFOV
				local tweenInTime = wepStats.fireFov.tweenInTime or 0.03
				local holdTime = wepStats.fireFov.holdTime or 0.08
				local tweenOutTime = wepStats.fireFov.tweenOutTime or 0.12

				if aiming then
					if not vars.fireFovActive then
						vars.storedAimFOV = vars.aimFOVTarget
						vars.aimFOVTarget = targetFireFOV
						aimToFOV(targetFireFOV)
					end
				else
					tweenService:Create(camera, TweenInfo.new(tweenInTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						FieldOfView = targetFireFOV
					}):Play()
				end

				vars.fireFovActive = true

				vars.fireFovReturnTask = task.delay(holdTime, function()
					vars.fireFovActive = false

					if not vars.equipped then return end

					if vars.aiming then
						if vars.storedAimFOV then
							vars.aimFOVTarget = vars.storedAimFOV
							vars.storedAimFOV = nil
							aimToFOV(vars.aimFOVTarget)
						else
							local liveWepStats = vars.wepStats
							vars.aimFOVTarget = (liveWepStats and (liveWepStats.aimFovDefault or liveWepStats.aimFov)) or defaultFOV
							aimToFOV(vars.aimFOVTarget)
						end
					else
						tweenService:Create(camera, TweenInfo.new(tweenOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							FieldOfView = normalFOV
						}):Play()
					end
				end)
			end

			local fireInterval = 60 / cycleTime
			local nowFireTime = os.clock()
			local scheduledBase = vars.nextScheduledFireTime
			if not scheduledBase or scheduledBase < nowFireTime then
				scheduledBase = nowFireTime
			end
			vars.nextScheduledFireTime = scheduledBase + fireInterval

			local waitDuration = vars.nextScheduledFireTime - os.clock()
			if waitDuration > 0 then
				task.wait(waitDuration)
			end

			local liveEquipped = vars.equipped
			if not liveEquipped or vars.unequipping or vars.dropping or vars.dead
				or vars.equipGeneration ~= capturedFireGeneration
				or ubglSystem.IsActive() or ubglSystem.IsToggling() then
				vars.cycled = true
				return
			end
			local liveGunAmmo = vars.gunAmmo
			if not liveGunAmmo or not liveGunAmmo:FindFirstChild("MagAmmo") then
				vars.cycled = true
				return
			end
			local liveWepStats = vars.wepStats
			local liveCurFireMode = vars.curFireMode
			local liveReloading = vars.reloading

			local liveChambered = liveEquipped:FindFirstChild("Chambered")
			if liveCurFireMode ~= fireModes.Manual then
				if liveWepStats.emptyLockBolt and liveGunAmmo.MagAmmo.Value <= 0 and not (liveChambered and liveChambered.Value) then
					moveBoltAction(liveWepStats.boltDist, true)
				else
					moveBoltAction(CFrame.new(), true)
				end
			end

			if liveWepStats.autoChamber and liveCurFireMode == fireModes.Manual and not liveReloading then
				chamberAnim()
			end

			vars.cycled = true
		elseif not isLoaded() then
			local magAmmo = gunAmmo:FindFirstChild("MagAmmo")
			local magValue = magAmmo and magAmmo.Value or 0
			local chamberedValue = equipped:FindFirstChild("Chambered")
			local boltReadyValue = equipped:FindFirstChild("BoltReady")
			if curFireMode == fireModes.Manual and magValue > 0 and not reloading and not vars.chambering then
				chamberAnim()
				vars.holdingM1 = false
			elseif wepStats.shotgun and magValue > 0 and not reloading and not vars.chambering then
				chamberAnim()
			elseif wepStats.emptyCloseBolt and not (chamberedValue and chamberedValue.Value) and not (boltReadyValue and boltReadyValue.Value) and vars.bulletsCurrentlyFired == 0 and not vars.emptyClickDebounce then
				vars.holdingM1 = false
				repChamber.send(nil)
				playRepSound("SlideRelease")
				moveBoltAction(CFrame.new())
			end
		end
	end
end

function WeaponFireMod.Update(dt: number)
	if not vars.equipped then
		return
	end

	UpdateOverheat(dt)
	UpdateFireLoop(dt)
end

return WeaponFireMod