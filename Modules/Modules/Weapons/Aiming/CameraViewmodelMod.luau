local CameraViewmodelMod = {}

local Modules        = script:FindFirstAncestor("Modules")
local weaponMath     = require(Modules.Weapons.Math.WeaponMath)
local expAlpha       = weaponMath.ExpAlpha
local lerpNumber     = weaponMath.LerpNumber
local getRotationBetween = weaponMath.GetRotationBetween

local vars           = require(Modules.Weapons.Core.WeaponState).get()
local reticleMotionBlurMod = require(script.Parent.ReticleMotionBlurMod)

-- // Module-level state (set by Init)

local character, humanoid, humanoidRootPart
local rootJoint, neckJoint, leftHipJoint, rightHipJoint
local defaultLeftHipC0, defaultRightHipC0
local camera, animBase, config, defaultFOV, storageCFrame
local headPoseReplicationMod, attachmentManager, grenadeClient
local laserSightMod, glareMod, aimingSystemMod, proceduralWalkCycle
local ubglSystem, userInputService, armPositionMod
local aimFOVTargetRef, ZOOM_SENSITIVITY_REDUCTION, moveSpring, player
local getThirdPersonGunModel

local bindAiming, unbindAiming, resetHead, refreshViewmodel
local updateViewmodelPosition, updateGrenadeViewmodelPosition
local toggleSprint, playAnimation, stopAnimation
local findProjectilePart, syncThirdPersonProjectile, aimToFOV

-- // Per-update state

local oldCamCF: CFrame?        = nil
local cachedHead: BasePart?    = nil
local cachedTPMagModel         = nil
local cachedTPMag              = nil

-- // Camera clip

local CAMERA_CLIP_MARGIN        = 0.35
local CAMERA_CLIP_TIGHTEN_RATE  = 30
local CAMERA_CLIP_RELEASE_RATE  = 7
local cameraClipLength: number? = nil
local cameraClipParams: RaycastParams? = nil

local function buildCameraClipParams()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.IgnoreWater = true
	p.RespectCanCollide = true

	local filter = { character, camera }
	local sphWorkspace = workspace:FindFirstChild("SPH_Workspace")
	if sphWorkspace then filter[#filter + 1] = sphWorkspace end
	p.FilterDescendantsInstances = filter

	return p
end

local function ClampCameraOffsetForWalls(offset: Vector3, dt: number): Vector3
	local lateral       = Vector3.new(offset.X, 0, offset.Z)
	local lateralLength = lateral.Magnitude

	if lateralLength < 0.05 then
		cameraClipLength = lateralLength
		return offset
	end

	local head      = cachedHead
	local eyeHeight = head and (head.Position.Y - humanoidRootPart.Position.Y + math.min(0, offset.Y)) or 0
	local rayOrigin = humanoidRootPart.Position + Vector3.new(0, eyeHeight, 0)
	local rayDir    = humanoidRootPart.CFrame:VectorToWorldSpace(lateral.Unit) * lateralLength

	local result = workspace:Raycast(rayOrigin, rayDir, cameraClipParams)
	local limit  = lateralLength
	if result then
		limit = math.max(0, (result.Position - rayOrigin).Magnitude - CAMERA_CLIP_MARGIN)
	end

	if not cameraClipLength then
		cameraClipLength = limit
	else
		local rate       = limit < cameraClipLength and CAMERA_CLIP_TIGHTEN_RATE or CAMERA_CLIP_RELEASE_RATE
		cameraClipLength = cameraClipLength + (limit - cameraClipLength) * expAlpha(rate, dt)
	end

	if cameraClipLength >= lateralLength then return offset end

	local scale = math.max(0, cameraClipLength) / lateralLength
	return Vector3.new(offset.X * scale, offset.Y, offset.Z * scale)
end

-- // Cached head lookup

local function GetCachedHead(): BasePart?
	if cachedHead and cachedHead.Parent == character then return cachedHead end
	cachedHead = character:FindFirstChild("Head") :: BasePart?
	return cachedHead
end

-- // Cached per-frame flashlight raycast params

local flashRayParams: RaycastParams? = nil

local function GetFlashRayParams(gunModel): RaycastParams
	if not flashRayParams then
		flashRayParams = RaycastParams.new()
		flashRayParams.FilterType = Enum.RaycastFilterType.Exclude
		flashRayParams.RespectCanCollide = true
	end
	flashRayParams.FilterDescendantsInstances = { gunModel, character }
	return flashRayParams
end

-- // Cached prone raycast params

local proneRayParams: RaycastParams? = nil

local function GetProneRayParams(): RaycastParams
	if not proneRayParams then
		proneRayParams = RaycastParams.new()
		proneRayParams.FilterType = Enum.RaycastFilterType.Exclude
		proneRayParams.IgnoreWater = true
		proneRayParams.RespectCanCollide = true
	end
	proneRayParams.FilterDescendantsInstances = { character }
	return proneRayParams
end

-- // Init

function CameraViewmodelMod.Init(deps)
	getThirdPersonGunModel   = deps.getThirdPersonGunModel
	character                = deps.character
	humanoid                 = deps.humanoid
	humanoidRootPart         = deps.humanoidRootPart
	rootJoint                = deps.rootJoint
	neckJoint                = deps.neckJoint
	leftHipJoint             = deps.leftHipJoint
	rightHipJoint            = deps.rightHipJoint
	defaultLeftHipC0         = deps.defaultLeftHipC0
	defaultRightHipC0        = deps.defaultRightHipC0
	camera                   = deps.camera
	animBase                 = deps.animBase
	config                   = deps.config
	defaultFOV               = deps.defaultFOV
	storageCFrame            = deps.storageCFrame
	headPoseReplicationMod   = deps.headPoseReplicationMod
	attachmentManager        = deps.attachmentManager
	grenadeClient            = deps.grenadeClient
	laserSightMod            = deps.laserSightMod
	glareMod                 = deps.glareMod
	aimingSystemMod          = deps.aimingSystemMod
	proceduralWalkCycle      = deps.proceduralWalkCycle
	ubglSystem               = deps.ubglSystem
	userInputService         = deps.userInputService
	armPositionMod           = deps.armPositionMod
	aimFOVTargetRef          = deps.aimFOVTargetRef
	ZOOM_SENSITIVITY_REDUCTION = deps.ZOOM_SENSITIVITY_REDUCTION
	moveSpring               = deps.moveSpring
	player                   = deps.player

	bindAiming               = deps.bindAiming
	unbindAiming             = deps.unbindAiming
	resetHead                = deps.resetHead
	refreshViewmodel         = deps.refreshViewmodel
	updateViewmodelPosition  = deps.updateViewmodelPosition
	updateGrenadeViewmodelPosition = deps.updateGrenadeViewmodelPosition
	toggleSprint             = deps.toggleSprint
	playAnimation            = deps.playAnimation
	stopAnimation            = deps.stopAnimation
	findProjectilePart       = deps.findProjectilePart
	syncThirdPersonProjectile = deps.syncThirdPersonProjectile
	aimToFOV                = deps.aimToFOV

	-- Reset per-session state
	oldCamCF         = nil
	cameraClipLength  = nil
	cachedHead        = nil
	cachedTPMagModel  = nil
	cachedTPMag       = nil
	flashRayParams    = nil
	proneRayParams    = nil

	-- Build clip params once per session (character/camera don't change mid-session)
	cameraClipParams = buildCameraClipParams()

	vars.lastHealth = humanoid.Health
end

-- ─── Update ───────────────────────────────────────────────────────────────────

function CameraViewmodelMod.Update(dt: number)
	if dt > 0.2 then return end  -- skip if < 5 FPS

	local moving     = humanoid.MoveDirection.Magnitude > 0
	local equipped   = vars.equipped
	local wepStats   = vars.wepStats
	local gunModel   = vars.gunModel
	local aiming     = vars.aiming
	local freeLook   = vars.freeLook
	local sprinting  = vars.sprinting

	-- ── Prone move animation ─────────────────────────────────────────────────
	local proneMoveAnim = vars.proneMoveAnim
	if config.proneEnabled and proneMoveAnim and character:GetAttribute("Stance") == "Prone"
		and equipped and humanoid.FloorMaterial ~= Enum.Material.Air
		and not ubglSystem.IsActive() and not ubglSystem.IsToggling() then

		if moving and not proneMoveAnim.IsPlaying then
			playAnimation(wepStats.proneMoveAnim, { transSpeed = 0.5 })
		elseif not moving and proneMoveAnim.IsPlaying then
			stopAnimation(wepStats.proneMoveAnim, 0.5)
		end
	elseif proneMoveAnim and proneMoveAnim.IsPlaying then
		stopAnimation(wepStats.proneMoveAnim, 0.5)
	end

	-- ── Camera base + seat clamping ──────────────────────────────────────────
	local baseCameraCF = camera.CFrame
	local cameraDelta  = CFrame.new()

	if (humanoid.Sit and not vars.vehicleSeated and vars.firstPerson or freeLook) and config.cameraLimitInSeats then
		local localCF  = humanoidRootPart.CFrame:ToObjectSpace(camera.CFrame)
		local x, y, z   = localCF:ToOrientation()
		local p          = camera.CFrame.Position
		local xlimit     = math.rad(math.clamp(math.deg(x), -60, 60))
		local ylimit     = math.rad(math.clamp(math.deg(y), -60, 60))
		local zlimit     = math.rad(math.clamp(math.deg(z), -60, 60))
		local limited    = humanoidRootPart.CFrame:ToWorldSpace(
			CFrame.new(p.X, p.Y, p.Z) * CFrame.fromOrientation(xlimit, ylimit, zlimit)
		)
		baseCameraCF = CFrame.new(camera.CFrame.Position) * (limited - limited.Position)
	end

	-- ── Camera animation (FakeCamera) ────────────────────────────────────────
	if config.cameraAnimation and equipped and vars.firstPerson then
		local fakeCamera = animBase:FindFirstChild("FakeCamera")
		if fakeCamera then
			local newCamCF = fakeCamera.Transform:Inverse()
			if oldCamCF then
				cameraDelta  = cameraDelta * oldCamCF:ToObjectSpace(newCamCF)
				animBase.CFrame = animBase.CFrame * fakeCamera.Transform:Inverse()
			end
			oldCamCF = newCamCF
		end
	end

	if not vars.dead then
		camera.CFrame = baseCameraCF * cameraDelta
	end

	local head = GetCachedHead()
	if vars.dead or not head then return end

	-- ── Neck / head rotation ─────────────────────────────────────────────────
	do
		local torsoDirection = (humanoid.RigType == Enum.HumanoidRigType.R6)
			and character.Torso.CFrame.LookVector
			or  character.UpperTorso.CFrame.LookVector

		local lookDirection = sprinting and humanoidRootPart.CFrame or camera.CFrame

		if config.cameraAnimation and equipped and not vars.firstPerson then
			local fakeCamera = animBase:FindFirstChild("FakeCamera")
			if fakeCamera then
				local fx, _, fz = fakeCamera.Transform:ToOrientation()
				lookDirection = lookDirection * CFrame.Angles(fx, 0, 0) * CFrame.Angles(0, 0, fz)
			end
		end

		local camDir      = humanoidRootPart.CFrame:ToObjectSpace(lookDirection).LookVector
		local rotCF       = CFrame.Angles(0, math.asin(camDir.X) / 1.15, 0)
			* CFrame.Angles(-math.asin(lookDirection.LookVector.Y) + math.asin(torsoDirection.Y), 0, 0)
		local neckCF      = CFrame.new(0, -0.5, 0) * rotCF * CFrame.Angles(-math.rad(90), 0, math.rad(180))
		neckJoint.C1      = neckJoint.C1:Lerp(neckCF, 1 - math.exp(-config.headRotationSpeed * dt))
		headPoseReplicationMod.SendLocalPose(neckJoint.C1)
	end

	local fpSights          = vars.fpSights
	local tpSights          = vars.tpSights
	local attachmentFpSights = vars.attachmentFpSights
	local cameraOffsetTarget = Vector3.zero

	-- ── First-person transition: TP → FP ────────────────────────────────────
	if not vars.firstPerson and head.LocalTransparencyModifier >= vars.fpThreshold then
		vars.firstPerson      = true
		vars.snapCameraOffset = true

		local function disableSightGuis(list)
			for _, sight in list do
				local sg = sight:FindFirstChild("SurfaceGui")
				if sg then sg.Enabled = false end
			end
		end
		disableSightGuis(tpSights)
		disableSightGuis(fpSights)

		if equipped then
			if not (wepStats and wepStats.weaponType == "Grenade") then bindAiming() end
			vars.viewmodelVisible = true

			if vars.flashlightEnabled then
				local fpPart = attachmentManager.GetFlashlightSource(gunModel)
				if fpPart then vars.flashFX.mod.SetEnabled(fpPart, true) end

				local tpModel = getThirdPersonGunModel()
				local tpPart  = tpModel and attachmentManager.GetFlashlightSource(tpModel)
				if tpPart then vars.flashFX.mod.SetEnabled(tpPart, false) end

				vars.flashFX.beamTP.Enabled = false
				vars.flashFX.beamFP.Enabled = true
			end
		end

		-- ── First-person transition: FP → TP ────────────────────────────────────
	elseif vars.firstPerson and head.LocalTransparencyModifier <= vars.fpThreshold then
		syncThirdPersonProjectile()

		if aiming then
			player.CameraMaxZoomDistance = 0.5
			player.CameraMinZoomDistance = 0.5
		else
			vars.firstPerson      = false
			vars.snapCameraOffset = true

			if vars.freeLook then
				vars.freeLook        = false
				vars.freeLookOffset  = vars.freeLookRotation:ToObjectSpace(camera.CFrame)
				vars.freeLookOffset -= vars.freeLookOffset.Position
				humanoid.AutoRotate  = true
			end

			grenadeClient.CleanupGrenadeCosmeticParts()
		end

		for _, sight in fpSights do
			local sg = sight:FindFirstChild("SurfaceGui")
			if sg then sg.Enabled = false end
		end

		unbindAiming()
		vars.viewmodelVisible = false
		animBase.CFrame       = storageCFrame

		if equipped then
			if vars.flashlightEnabled then
				vars.flashFX.beamFP.Enabled = false
				vars.flashFX.beamTP.Enabled = true
			end

			local fpPart = attachmentManager.GetFlashlightSource(gunModel)
			if fpPart then vars.flashFX.mod.SetEnabled(fpPart, false) end

			if vars.flashlightEnabled then
				local tpModel = getThirdPersonGunModel()
				local tpPart  = tpModel and attachmentManager.GetFlashlightSource(tpModel)
				if tpPart then vars.flashFX.mod.SetEnabled(tpPart, true) end
			end
		end

		resetHead()

		local tpGunModel = getThirdPersonGunModel()
		if tpGunModel then
			for _, part in tpGunModel:GetDescendants() do
				if part.Name == "SightReticle" then
					local sg = part:FindFirstChild("SurfaceGui")
					if sg then sg.Enabled = false end
				end
			end
		end
	end

	if vars.firstPerson and aiming and equipped then
		player.CameraMaxZoomDistance = 0.5
		player.CameraMinZoomDistance = 0.5
	end

	-- ── TP magazine hiding ────────────────────────────────────────────────────
	local tpGunModel = getThirdPersonGunModel()

	if vars.firstPerson and tpGunModel then
		local tpMag
		if cachedTPMagModel == tpGunModel and cachedTPMag and cachedTPMag.Parent then
			tpMag = cachedTPMag
		else
			tpMag            = findProjectilePart(tpGunModel, wepStats and wepStats.projectile)
			cachedTPMagModel = tpGunModel
			cachedTPMag      = tpMag
		end

		if tpMag and not tpMag:GetAttribute("SPH_FPHidden") then
			tpMag:SetAttribute("SPH_FPHidden", true)
			tpMag.Transparency = 1
			for _, child in tpMag:GetDescendants() do
				if child:IsA("BasePart") or child:IsA("Decal") or child:IsA("Texture") then
					child.Transparency = 1
				end
			end
		end
	elseif equipped and not vars.firstPerson then
		cachedTPMagModel = nil
		cachedTPMag      = nil
		syncThirdPersonProjectile()
	end

	-- ── Camera offset (body, stance, lean) ───────────────────────────────────
	if config.firstPersonBody and vars.firstPerson then
		local xHead         = humanoidRootPart.CFrame:ToObjectSpace(camera.CFrame):ToEulerAngles()
		local rotationOffset = -1.2 + (xHead + 1.4) / 2.8
		cameraOffsetTarget  = Vector3.new(0, 0, rotationOffset - 0.4)
	end

	local xOffset = 0
	local yOffset = 0
	local zOffset = cameraOffsetTarget.Z
	local stance  = character:GetAttribute("Stance")

	if stance == "Crouched" then
		yOffset = -1
		if vars.firstPerson then zOffset -= 0.3 end
	elseif config.proneEnabled and stance == "Prone" then
		yOffset = -1.25
		if vars.firstPerson then zOffset = -1.45 end
	end

	local lean = character:GetAttribute("LeanDirection") or 0
	if lean ~= 0 then
		xOffset  = lean > 0 and 1 or -1
		yOffset += -0.2
	end

	if not vars.dead and not vars.vehicleSeated
		and camera.CameraType == Enum.CameraType.Custom and humanoid.Health > 0 then

		local targetOffset = Vector3.new(xOffset, yOffset, zOffset)
		local currentHealth = humanoid.Health

		if currentHealth < vars.lastHealth then
			humanoid.CameraOffset = Vector3.zero
			vars.lastHealth       = currentHealth
			task.wait(0.1)
		else
			vars.lastHealth = currentHealth
		end

		local newOffset: Vector3
		if vars.snapCameraOffset then
			vars.snapCameraOffset = false
			cameraClipLength      = nil
			newOffset             = targetOffset
		else
			newOffset = humanoid.CameraOffset:Lerp(targetOffset, expAlpha(0.12 * 60, dt))
		end

		newOffset = ClampCameraOffsetForWalls(newOffset, dt)
		humanoid.CameraOffset = newOffset.Magnitude < 10 and newOffset or Vector3.zero

		local leanAlpha = expAlpha(0.1 * 60, dt)
		rootJoint.C1    = rootJoint.C1:Lerp(
			CFrame.new(-xOffset / 2, 0, 0) * CFrame.Angles(math.rad(90), math.rad(180) + math.rad(17 * lean), 0),
			leanAlpha
		)

		if leftHipJoint and rightHipJoint and defaultLeftHipC0 and defaultRightHipC0 then
			local counter = CFrame.Angles(0, 0, math.rad(17 * lean))
			leftHipJoint.C0  = leftHipJoint.C0:Lerp(counter * defaultLeftHipC0, leanAlpha)
			rightHipJoint.C0 = rightHipJoint.C0:Lerp(counter * defaultRightHipC0, leanAlpha)
		end

		local rollDelta = vars.cameraLeanRotation - vars.prevTotalCameraRoll
		if math.abs(rollDelta) > 0.0001 then
			camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, math.rad(rollDelta))
		end
		vars.prevTotalCameraRoll = vars.cameraLeanRotation
	else
		humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.zero, 0.2 * dt * 60)
	end

	-- ── Viewmodel update ─────────────────────────────────────────────────────
	if equipped and camera.CameraType == Enum.CameraType.Custom then
		if vars.firstPerson and not vars.viewmodelVisible then
			refreshViewmodel()
			toggleSprint(sprinting)
		end

		if wepStats and wepStats.weaponType == "Grenade" then
			updateGrenadeViewmodelPosition(dt)
		else
			updateViewmodelPosition(dt)

			if config.allowAimTilt and vars.firstPerson then
				local targetTilt = (aiming and equipped) and -4 or 0
				vars.aimTiltAngle = lerpNumber(vars.aimTiltAngle, targetTilt, expAlpha(0.09 * 60, dt))
				if math.abs(vars.aimTiltAngle) > 0.0001 then
					camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, math.rad(vars.aimTiltAngle))
				end
			end
		end
	else
		vars.viewmodelVisible = false
		animBase.CFrame       = storageCFrame
	end

	-- ── Walk cycle + move sway ────────────────────────────────────────────────
	if not humanoid.Sit then
		proceduralWalkCycle.Update(dt)
	end

	local updatedMoveSway = Vector3.zero
	if equipped then
		updatedMoveSway = moveSpring:update(dt)
		animBase.CFrame = animBase.CFrame:ToWorldSpace(
			CFrame.new(updatedMoveSway.Y, updatedMoveSway.X, 0)
				* CFrame.Angles(updatedMoveSway.Y * 0.3, 0, updatedMoveSway.Y * 0.8)
		)
	end

	laserSightMod.UpdateLocalLaser()
	glareMod.Update(dt)

	-- ── Flashlight ────────────────────────────────────────────────────────────
	if vars.flashlightEnabled and equipped then
		local flashlightPart = attachmentManager.GetFlashlightSource(gunModel)
		if not flashlightPart then
			vars.flashlightEnabled = false
		else
			local tpModel        = getThirdPersonGunModel()
			local tpFlashlightPart = tpModel and attachmentManager.GetFlashlightSource(tpModel)

			if flashlightPart or tpFlashlightPart then
				local flashColor = glareMod.ResolveFlashlightColor(flashlightPart or tpFlashlightPart)
				glareMod.SetFlashlightModelActive(flashlightPart, tpFlashlightPart, vars.firstPerson, true, flashColor)
			end

			local rayParams = GetFlashRayParams(gunModel)
			if vars.firstPerson then
				vars.flashFX.mod.UpdateBeam(vars.flashFX.beamFP, flashlightPart, vars.flashFX.endFP, rayParams)
			elseif tpFlashlightPart then
				vars.flashFX.mod.UpdateBeam(vars.flashFX.beamTP, tpFlashlightPart, vars.flashFX.endTP, rayParams)
			end
		end
	end

	-- ── Camera bob ────────────────────────────────────────────────────────────
	if config.cameraMovement and vars.firstPerson and not humanoid.Sit
		and not vars.vehicleSeated and camera.CameraType == Enum.CameraType.Custom then

		camera.CFrame = camera.CFrame * CFrame.Angles(
			math.rad(updatedMoveSway.X / config.cameraBobDampening),
			math.rad(updatedMoveSway.Y / config.cameraBobDampening),
			0
		)
	end

	-- ── Walk camera animation ─────────────────────────────────────────────────
	if config.walkCameraAnimation and vars.firstPerson and not humanoid.Sit
		and not vars.vehicleSeated and camera.CameraType == Enum.CameraType.Custom then

		local posDelta = vars.cameraWalkPos - vars.prevCameraWalkPos
		local rotDelta = vars.cameraWalkRot - vars.prevCameraWalkRot
		vars.prevCameraWalkPos = vars.cameraWalkPos
		vars.prevCameraWalkRot = vars.cameraWalkRot

		camera.CFrame = camera.CFrame
			* CFrame.new(posDelta.X, posDelta.Y, 0)
			* CFrame.Angles(math.rad(rotDelta.X), 0, math.rad(rotDelta.Z))
	end

	-- ── Sight reticle positioning & motion blur ───────────────────────────────
	for _, sight in fpSights do
		if not (sight and sight.Parent) then continue end
		local surfaceGui = sight:FindFirstChild("SurfaceGui")
		if not surfaceGui then continue end
		local frame = surfaceGui:FindFirstChild("Frame")
		if not frame then continue end

		local sightUI = frame:FindFirstChild("Reticle") or frame:FindFirstChild("Holo")
		if not sightUI then continue end

		if aiming and table.find(attachmentFpSights, sight) then
			local rawSize = sight.Size
			local safeSize = Vector3.new(
				math.max(math.abs(rawSize.X), 0.001),
				math.max(math.abs(rawSize.Y), 0.001),
				math.max(math.abs(rawSize.Z), 0.001)
			)
			local dist = sight.CFrame:PointToObjectSpace(camera.CFrame.Position) / safeSize
			local uiPos = UDim2.fromScale(0.5 + dist.X, 0.5 - dist.Y)
			sightUI.Position = uiPos

			-- Motion blur
			local blurCfg     = (wepStats and wepStats.reticleMotionBlur) or {}
			local blurEnabled = if blurCfg.Enabled ~= nil then blurCfg.Enabled else config.reticleMotionBlur ~= false
			if blurEnabled then
				local handle = vars.reticleBlurHandles[sightUI]
				if not handle then
					handle = reticleMotionBlurMod.Create(sightUI, blurCfg.TrailCount or config.reticleBlurTrailCount)
					vars.reticleBlurHandles[sightUI] = handle
				end
				reticleMotionBlurMod.Update(
					handle,
					Vector2.new(0.5 + dist.X, 0.5 - dist.Y),
					dt,
					blurCfg.Sensitivity or config.reticleBlurSensitivity,
					blurCfg.MaxOffset   or config.reticleBlurMaxOffset,
					blurCfg.MaxAlpha    or config.reticleBlurMaxAlpha
				)
			end

			if sightUI.Name == "Holo" then
				local s = camera.FieldOfView / 100
				sightUI.Size = UDim2.fromScale(s, s)
			elseif sightUI.Name == "Reticle" then
				local maxFOV   = wepStats.aimFovMax or defaultFOV
				local minFOV   = wepStats.aimFovMin or 30
				local denom    = maxFOV - minFOV
				local zoomRatio = denom ~= 0
					and math.clamp((maxFOV - camera.FieldOfView) / denom, 0, 1)
					or 0

				local cachedScale = sightUI:GetAttribute("OriginalSize")
				if not cachedScale or cachedScale <= 0 then
					local raw = sightUI.Size.X.Scale
					cachedScale = (raw and raw > 0) and raw or 0.3
					sightUI:SetAttribute("OriginalSize", cachedScale)
				end

				local s = cachedScale * (1 + zoomRatio)
				sightUI.Size = UDim2.fromScale(s, s)
			end
		else
			local handle = vars.reticleBlurHandles[sightUI]
			if handle then reticleMotionBlurMod.Reset(handle) end
		end
	end

	armPositionMod.Update(dt)

	-- ── Aiming FOV + sensitivity ──────────────────────────────────────────────
	if vars.aiming then
		local aimFOVTarget = aimFOVTargetRef.value
		vars.aimFOVTarget  = aimFOVTarget
		aimToFOV(aimFOVTarget)

		if wepStats and wepStats.aimFovMax and wepStats.aimFovMin
			and wepStats.aimFovMax > wepStats.aimFovMin then
			local zoomRatio = math.clamp(
				(wepStats.aimFovMax - camera.FieldOfView) / (wepStats.aimFovMax - wepStats.aimFovMin),
				0, 1
			)
			userInputService.MouseDeltaSensitivity = vars.aimSensitivity * (1 - zoomRatio * ZOOM_SENSITIVITY_REDUCTION)
		end
	end

	laserSightMod.UpdateOtherPlayerLasers()
	aimingSystemMod.UpdateRemoteAimVisuals(dt)

	-- ── Prone floor alignment ─────────────────────────────────────────────────
	if config.proneEnabled and stance == "Prone" and config.proneAngle then
		local rayResult = workspace:Raycast(
			humanoidRootPart.Position,
			Vector3.new(0, -2, 0),
			GetProneRayParams()
		)
		if rayResult then
			local rot = getRotationBetween(humanoidRootPart.CFrame.UpVector, rayResult.Normal, Vector3.new(1, 0, 0))
			rootJoint.C0 *= CFrame.Angles(rot.X, rot.Y, rot.Z)
		end
	end
end

return CameraViewmodelMod