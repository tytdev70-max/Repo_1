local Modules = script:FindFirstAncestor("Modules")
local Assets  = Modules.Parent

local WeaponContext     = require(Modules.Weapons.Core.WeaponContext)
local vars              = require(Modules.Weapons.Core.WeaponState).get()
local config            = require(Assets.GameConfig)
local attachmentSystem = require(Modules.ThirdParty.AttachmentSystem)
local weaponPushback    = require(Modules.Weapons.Fire.WeaponPushbackMod)
local ModelQueryCache   = require(Modules.Weapons.Core.ModelQueryCache)
local camera            = workspace.CurrentCamera
local userInputService  = game:GetService("UserInputService")

-- ─── Constants ────────────────────────────────────────────────────────────────

local FREELOOK_RECOVERY = 0.2
local PIVOT_OFFSET      = CFrame.new(0, 0.25, 0.35)
local PIVOT_OFFSET_INV  = PIVOT_OFFSET:Inverse()
local PUSHBACK_ALPHA    = 0.2 * 60  -- used with ExpAlpha

-- ─── Upvalues (set by init) ───────────────────────────────────────────────────

local ChangeHoldStance, ExpAlpha, GetThirdPersonGunModel, LerpNumber
local PlayAnimation, StopAnimation, ToggleAiming, ToggleSprint
local animBase, character, defaultFOV, gunRecoilSpring
local gunRotSpring, humanoid, humanoidRootPart, jumpSpring
local rayParams, recoilSpring, storageCFrame, swaySpring
local swaySpringRot   -- Spring (Vector3) for rotational sway
local swaySpringPos   -- Spring (Vector3) for positional offset sway
local Spring          -- the Spring module itself

local WeaponFrame = {}

-- ─── Shared helpers ───────────────────────────────────────────────────────────

-- Shared animBase origin setup (freeLook, offset, freelook recovery)
local function applyBasePosition()
	animBase.CFrame = CFrame.new((camera.CFrame * vars.offset).Position)

	if not vars.freeLook then
		animBase.CFrame *= camera.CFrame - camera.CFrame.Position
	else
		animBase.CFrame *= vars.freeLookRotation
	end

	vars.freeLookOffset = vars.freeLookOffset:Lerp(CFrame.new(), FREELOOK_RECOVERY * 60 * (1/60))
	animBase.CFrame     *= vars.freeLookOffset:Inverse()
end

-- dt is needed for freeLook lerp — patch applyBasePosition to accept dt
local function applyBasePositionDt(dt: number)
	animBase.CFrame = CFrame.new((camera.CFrame * vars.offset).Position)

	if not vars.freeLook then
		animBase.CFrame *= camera.CFrame - camera.CFrame.Position
	else
		animBase.CFrame *= vars.freeLookRotation
	end

	vars.freeLookOffset = vars.freeLookOffset:Lerp(CFrame.new(), FREELOOK_RECOVERY * dt * 60)
	animBase.CFrame     *= vars.freeLookOffset:Inverse()
end

-- Wall pushback + raise-gun logic. Returns nothing; mutates vars and animBase.
local function applyPushback(dt: number, originCFrame: CFrame, isGrenade: boolean)
	local rayDistance = vars.wepStats.gunLength
	local newRay      = workspace:Raycast(originCFrame.Position, originCFrame.LookVector * rayDistance, rayParams)

	-- Flat-direction secondary ray (non-grenade only)
	if not isGrenade then
		local flatRay = workspace:Raycast(
			originCFrame.Position,
			humanoidRootPart.CFrame.LookVector * rayDistance,
			rayParams
		)
		if flatRay and flatRay.Instance and not flatRay.Instance:HasTag("SPH_NoCollide") then
			if not newRay or
				(flatRay.Position - originCFrame.Position).Magnitude
				< (newRay.Position  - originCFrame.Position).Magnitude
			then
				newRay = flatRay
			end
		end
	end

	local lerpAlpha = ExpAlpha(PUSHBACK_ALPHA, dt)

	if newRay and newRay.Instance and not newRay.Instance:HasTag("SPH_NoCollide") then
		local distance = rayDistance - (originCFrame.Position - newRay.Position).Magnitude

		if config.pushBackViewmodel and distance > 0 then
			local tempDist = vars.blocked and distance / 2 or distance
			vars.pushbackOffset = LerpNumber(vars.pushbackOffset, tempDist, lerpAlpha)
		else
			vars.pushbackOffset = LerpNumber(vars.pushbackOffset, 0, lerpAlpha)
		end

		if config.raiseGunAtWall then
			local blockThreshold   = vars.wepStats.maxPushback
			local unblockThreshold = blockThreshold * 0.5

			if distance >= blockThreshold then
				if not vars.blocked then
					ChangeHoldStance(0)
					PlayAnimation(vars.wepStats.holdUpAnim, {
						looped    = true,
						priority  = Enum.AnimationPriority.Action,
						transSpeed = 0.3,
					})
					vars.blocked          = true
					vars.wallBlockCooldown = tick() + 0.3
					if vars.aiming and not isGrenade then ToggleAiming(false) end
				end
			elseif vars.blocked and distance < unblockThreshold then
				StopAnimation(vars.wepStats.holdUpAnim, 0.3)
				vars.blocked = false
				if not isGrenade then
					local canReAim = vars.aimHeld and not vars.aiming
						and vars.firstPerson and not vars.sprinting
						and tick() > (vars.wallBlockCooldown or 0)
					if canReAim then
						ToggleAiming(true)
					elseif vars.sprinting then
						ToggleSprint(true)
					end
				end
			end
		end
	else
		if vars.blocked then
			StopAnimation(vars.wepStats.holdUpAnim, 0.3)
			vars.blocked = false
			if not isGrenade then
				local canReAim = vars.aimHeld and not vars.aiming
					and vars.firstPerson and not vars.sprinting
					and tick() > (vars.wallBlockCooldown or 0)
				if canReAim then
					ToggleAiming(true)
				elseif vars.sprinting then
					ToggleSprint(true)
				end
			end
		end
		vars.pushbackOffset = LerpNumber(vars.pushbackOffset, 0, lerpAlpha)
	end

	animBase.CFrame *= CFrame.new(0, 0, vars.pushbackOffset)
end

-- Resolves how far (in degrees) the equipped weapon rolls left/right while strafing.
-- Each gun defines its own value via `maxStrafeRoll` in its WeaponStats.
-- Weapons that don't define it fall back to the legacy global
-- `config.maxStrafeRoll` (if still present), otherwise to 0 (no roll).
local function getMaxStrafeRoll(): number
	local wepStats = vars.wepStats
	local value = wepStats and tonumber(wepStats.maxStrafeRoll)
	if value == nil then
		value = tonumber(config.maxStrafeRoll) or 0
	end
	-- math.clamp requires min <= max, so always use a non-negative limit
	return math.abs(value)
end

-- Shared sway, lean, breathing (aiming-aware)
local function applySwayAndLean(dt: number, aiming: boolean)
	-- Jump sway
	local jumpSway = jumpSpring:update(dt)
	animBase.CFrame *= CFrame.new(0, jumpSway.X * 0.4, 0)
	animBase.CFrame *= CFrame.Angles(math.rad(jumpSway.X * 6), 0, math.rad(jumpSway.Y * 3))

	-- Strafe roll
	local relVel       = humanoidRootPart.CFrame:VectorToObjectSpace(humanoidRootPart.Velocity)
	local maxRoll      = getMaxStrafeRoll()
	local rollTarget   = aiming and 0 or math.clamp(-relVel.X, -maxRoll, maxRoll)
	if config.cameraTilting then rollTarget /= 2 end
	vars.rollAngle     = LerpNumber(vars.rollAngle, rollTarget, ExpAlpha(0.07 * 60, dt))
	animBase.CFrame   *= CFrame.Angles(0, 0, math.rad(vars.rollAngle))

	local strafeX         = relVel.X
	local strafeIntensity = math.clamp(math.abs(strafeX) / 16, 0, 1)
	local strafeSign      = strafeX >= 0 and 1 or -1

	local leanXTarget, leanYTarget, leanYawTarget, leanRollTarget = 0, 0, 0, 0
	if not aiming then
		leanXTarget    =  strafeSign * 0.3  * strafeIntensity  -- was 0.6, reduced
		leanYTarget    = -0.06              * strafeIntensity  -- was -0.12, reduced
		leanYawTarget  =  strafeSign * 4    * strafeIntensity  -- was 10, greatly reduced
		leanRollTarget = -strafeSign * 6    * strafeIntensity  -- was 15, greatly reduced
	end

	local leanAlpha      = ExpAlpha(0.08 * 60, dt)  -- was 0.15, slower = smoother
	vars.strafeLeanRoll  = LerpNumber(vars.strafeLeanRoll, leanRollTarget, leanAlpha)
	vars.strafeLeanX     = LerpNumber(vars.strafeLeanX,    leanXTarget,    leanAlpha)
	vars.strafeLeanY     = LerpNumber(vars.strafeLeanY,    leanYTarget,    leanAlpha)
	vars.strafeLeanYaw   = LerpNumber(vars.strafeLeanYaw,  leanYawTarget,  leanAlpha)

	animBase.CFrame *= CFrame.new(vars.strafeLeanX, vars.strafeLeanY, 0)
		* PIVOT_OFFSET
		* CFrame.Angles(0, math.rad(vars.strafeLeanYaw), math.rad(vars.strafeLeanRoll))
		* PIVOT_OFFSET_INV

	-- Move lean (forward/back) — unchanged
	local moveZ             = relVel.Z
	local moveLeanIntensity = math.clamp(math.abs(moveZ) / 16, 0, 1)
	local moveSign          = moveZ >= 0 and 1 or -1
	local leanPitchTarget, leanZTarget = 0, 0
	if not aiming then
		leanPitchTarget = -moveSign * 3    * moveLeanIntensity
		leanZTarget     = -moveSign * 0.25 * moveLeanIntensity
	end

	local moveLeanAlpha = ExpAlpha(0.05 * 60, dt)
	vars.moveLeanPitch  = LerpNumber(vars.moveLeanPitch, leanPitchTarget, moveLeanAlpha)
	vars.moveLeanZ      = LerpNumber(vars.moveLeanZ,     leanZTarget,     moveLeanAlpha)
	animBase.CFrame    *= CFrame.new(0, 0, vars.moveLeanZ)
	animBase.CFrame    *= CFrame.Angles(math.rad(vars.moveLeanPitch), 0, 0)

	-- Mouse sway — FIXED: smoother delta smoothing + softer spring shove
	local rawMouse = userInputService:GetMouseDelta()

	-- Slower lerp factor = smoother, less snappy response
	vars.smoothedMouseDelta = vars.smoothedMouseDelta:Lerp(
		rawMouse,
		math.min(1, 0.08 * dt * 60)  -- was 0.25, much smoother now
	)
	local mouseDelta = vars.smoothedMouseDelta

	local swayDiv   = aiming and 850 or 480   -- was 360, larger = less sway per pixel
	local vertDiv   = aiming and 340 or 220   -- was 150, larger = less vertical sway
	local rollInt   = aiming and 1.2 or 2.4

	-- Reduced shove magnitudes so the spring isn't hit as hard each frame
	swaySpring:shove(Vector3.new(
		-mouseDelta.X / swayDiv,
		mouseDelta.Y / vertDiv,
		-mouseDelta.X / (swayDiv * 8) * rollInt
		))

	local s      = swaySpring:update(dt)
	local sv     = swaySpring.InterpolatedVelocity
	local rotInt = aiming and 0.55 or 1.25

	-- Slightly reduced positional multipliers for smoother feel
	animBase.CFrame *= CFrame.new(s.X * 1.1, s.Y * 1.0, s.Z * 0.3)
	animBase.CFrame *= CFrame.Angles(
		math.rad(s.Y * 7.0  * rotInt),  -- was 8.8
		math.rad(s.X * 9.0  * rotInt),  -- was 11.2
		math.rad(s.Z * 32)
	) * CFrame.Angles(0, 0, math.rad(sv.X * (aiming and 15 or 25)))

	-- Breathing — unchanged
	local breathTarget   = aiming and config.breathingADSIntensity or 1
	vars.breathingBlend  = LerpNumber(vars.breathingBlend, breathTarget, ExpAlpha(config.breathingTransitionSpeed * 60, dt))

	local bTime   = tick() * config.breathingSpeed
	local bScale  = config.breathingIntensity * vars.breathingBlend

	animBase.CFrame *= CFrame.new(
		math.sin(bTime * 0.5) * config.breathingPosAmplitude.X * bScale,
		math.sin(bTime)       * config.breathingPosAmplitude.Y * bScale,
		0
	)
	animBase.CFrame *= CFrame.Angles(
		math.rad(math.sin(bTime * 0.5 + 1.05) * config.breathingRotAmplitude.X * bScale),
		0,
		math.rad(math.sin(bTime * 0.33)        * config.breathingRotAmplitude.Y * bScale)
	)
end

-- ─── Sight reticle update ─────────────────────────────────────────────────────

-- These lookups run every frame in first person; results are cached per instance
-- by ModelQueryCache and invalidated automatically when the hierarchy changes.

local function findAnySurfaceGui(sight: Instance): SurfaceGui?
	return sight:FindFirstChildWhichIsA("SurfaceGui")
end

-- SurfaceGui > Frame > (Reticle | Holo)   (same resolution order as before)
local function findSightUI(sight: Instance): GuiObject?
	local surfaceGui = sight:FindFirstChild("SurfaceGui")
	if not surfaceGui then return nil end
	local frame = surfaceGui:FindFirstChild("Frame")
	if not frame then return nil end
	return (frame:FindFirstChild("Reticle") or frame:FindFirstChild("Holo")) :: GuiObject?
end

-- Every SurfaceGui that belongs to a "SightReticle" part in the model
local function collectSightReticleGuis(model: Instance): { SurfaceGui }
	local guis = {}
	for _, part in model:GetDescendants() do
		if part.Name == "SightReticle" then
			local sg = part:FindFirstChildWhichIsA("SurfaceGui")
			if sg then table.insert(guis, sg) end
		end
	end
	return guis
end

local function updateSightReticles(dt: number)
	local aiming = vars.aiming

	-- Enable/disable SurfaceGuis on fpSights
	for _, sight in vars.fpSights do
		local sg = sight and sight.Parent and ModelQueryCache.get(sight, "anySurfaceGui", findAnySurfaceGui, nil)
		if sg then sg.Enabled = aiming end
	end

	-- Hide SightReticle SurfaceGuis on TP model
	local tpModel = GetThirdPersonGunModel()
	if tpModel and tpModel ~= vars.gunModel then
		for _, sg in ModelQueryCache.get(tpModel, "sightReticleGuis", collectSightReticleGuis, nil) do
			sg.Enabled = false
		end
	end

	if not aiming then return end

	local maxFOV = vars.wepStats.aimFovMax or defaultFOV
	local minFOV = vars.wepStats.aimFovMin or 30
	local fovDenom = maxFOV - minFOV
	local zoomRatio = fovDenom ~= 0
		and math.clamp((maxFOV - camera.FieldOfView) / fovDenom, 0, 1)
		or 0

	for _, sight in vars.fpSights do
		if not (sight and sight.Parent) then continue end
		local sightUI = ModelQueryCache.get(sight, "sightUI", findSightUI, nil) :: any
		if not sightUI or not table.find(vars.attachmentFpSights, sight) then continue end

		-- Parallax position (same formula regardless of ParallaxEffect flag)
		local rawSize  = sight.Size
		local safeSize = Vector3.new(
			math.max(math.abs(rawSize.X), 0.001),
			math.max(math.abs(rawSize.Y), 0.001),
			math.max(math.abs(rawSize.Z), 0.001)
		)
		local dist = sight.CFrame:PointToObjectSpace(camera.CFrame.Position) / safeSize
		sightUI.Position = UDim2.fromScale(0.5 + dist.X, 0.5 - dist.Y)

		if sightUI.Name == "Holo" then
			local s = camera.FieldOfView / 100
			sightUI.Size = UDim2.fromScale(s, s)
		elseif sightUI.Name == "Reticle" then
			local reticleConfig = attachmentSystem.GetReticleConfig(vars.gunModel)

			-- Determine base scale
			local cachedScale = sightUI:GetAttribute("OriginalSize")
			if not cachedScale or cachedScale <= 0 then
				if reticleConfig and reticleConfig.DynamicScaling then
					cachedScale = reticleConfig.BaseScale or 0.3
				else
					local raw = sightUI.Size.X.Scale
					cachedScale = (raw and raw > 0) and raw or 0.3
				end
				sightUI:SetAttribute("OriginalSize", cachedScale)
			end

			local s = cachedScale * (1 + zoomRatio)
			sightUI.Size = UDim2.fromScale(s, s)
		end
	end
end

-- ─── UpdateViewmodelPosition ─────────────────────────────────────────────────

local function UpdateViewmodelPosition(dt: number)
	if vars.dead or not vars.equipped or not vars.gunModel then return end

	applyBasePositionDt(dt)

	-- Aim offset
	local aimPart = attachmentSystem.GetAimPart(vars.gunModel, vars.sightIndex)
		or vars.gunModel:FindFirstChild("AimPart" .. vars.sightIndex)
		or vars.gunModel.AimPart

	local gripCF             = vars.gunModel.Grip.CFrame
	local aimPartLocalOffset = gripCF:ToObjectSpace(aimPart.CFrame)
	vars.aimTarget           = aimPartLocalOffset:ToObjectSpace(gripCF:ToObjectSpace(camera.CFrame))

	if not vars.aimTransitionPlaying then
		local aimSpeedMult = vars.wepStats.aimSpeed or 1
		local aimAlpha     = math.min(1, (0.7 / vars.wepStats.aimTime) * (vars.aiming and 0.3 or 0.2) * dt * 60 * aimSpeedMult)
		local aimTarget    = vars.aiming and vars.aimTarget or CFrame.new()
		vars.aimingOffset  = vars.aimingOffset:Lerp(aimTarget, aimAlpha)
	end

	if not vars.freeLook then
		animBase.CFrame *= vars.aimingOffset
	end

	-- Sight GUI visibility + reticle positioning
	if vars.firstPerson then
		updateSightReticles(dt)
	end

	-- Pushback
	local tpAnimBase   = vars.weaponRig:FindFirstChild("AnimBase")
	local originCFrame = vars.firstPerson and animBase.CFrame or (tpAnimBase and tpAnimBase.CFrame or animBase.CFrame)
	applyPushback(dt, originCFrame, false)
	weaponPushback.Report(vars.pushbackOffset)

	-- Sway, lean, breathing
	applySwayAndLean(dt, vars.aiming)

	-- Extra camera roll
	vars.extraCamRoll  = LerpNumber(vars.extraCamRoll, vars.tempCameraRoll, ExpAlpha(0.1 * 60, dt))
	animBase.CFrame   *= CFrame.Angles(0, 0, math.rad(vars.extraCamRoll))

	-- Hip fire movement
	if config.hipfireMove and (not vars.aiming or config.offCenterAiming) then
		local maxX       = config.hipfireMoveX / (vars.aiming and 4 or 1)
		local maxY       = config.hipfireMoveY / (vars.aiming and 4 or 1)
		local mouseDelta = vars.smoothedMouseDelta
		local speed      = config.hipfireMoveSpeed * dt * 60

		-- Raw unclamped accumulation
		local rawX = vars.hipRotation.X - mouseDelta.X * speed
		local rawY = vars.hipRotation.Y - mouseDelta.Y * speed

		-- Soft limit: past the boundary the value gets compressed
		-- instead of hard-stopped, so there's no snap at the edge
		local function softLimit(value: number, limit: number): number
			local sign = value >= 0 and 1 or -1
			local abs  = math.abs(value)
			if abs <= limit then
				return value
			end
			-- Exponential compression past the limit
			local over = abs - limit
			local compressed = limit + (1 - math.exp(-over * 0.10)) * (limit * 0.25)
			return sign * compressed
		end

		vars.hipRotation = Vector2.new(
			softLimit(rawX, maxX),
			softLimit(rawY, maxY)
		)
	else
		-- Smooth return to zero
		vars.hipRotation = vars.hipRotation:Lerp(Vector2.zero, 1 - 0.7 ^ (dt * 60))
	end
	animBase.CFrame *= CFrame.Angles(math.rad(vars.hipRotation.Y), math.rad(vars.hipRotation.X), 0)

	-- Gun recoil spring
	local gr = gunRecoilSpring:update(dt)
	animBase.CFrame *= CFrame.new(gr.Y, -gr.X, -gr.Z)
	animBase.CFrame *= CFrame.Angles(math.rad(gr.X * 3), math.rad(gr.Y * 2), 0)

	-- Camera recoil
	local newRecoil   = recoilSpring:update(dt)
	local recoilDelta = newRecoil - vars.prevCamRecoil
	if recoilDelta.Magnitude > 0.00001 then
		camera.CFrame = camera.CFrame * CFrame.Angles(
			math.rad(recoilDelta.X),
			math.rad(recoilDelta.Y),
			math.rad(recoilDelta.Z)
		)
	end
	vars.prevCamRecoil = newRecoil

	-- Gun rotation spring
	local grot = gunRotSpring:update(dt)
	animBase.CFrame *= CFrame.Angles(math.rad(grot.X), math.rad(grot.Y), math.rad(grot.Z))

	-- Crouch tilt
	local stance = character:GetAttribute("Stance")
	local crouchRollTarget  = (stance == "Crouched" and not vars.aiming) and 10 or 0
	local crouchPitchTarget = (stance == "Crouched" and not vars.aiming) and -5 or 0
	local crouchAlpha       = ExpAlpha(0.2 * 60, dt)
	vars.crouchRoll   = LerpNumber(vars.crouchRoll,  crouchRollTarget,  crouchAlpha)
	vars.crouchPitch  = LerpNumber(vars.crouchPitch, crouchPitchTarget, crouchAlpha)
	animBase.CFrame  *= CFrame.Angles(math.rad(vars.crouchPitch), 0, math.rad(vars.crouchRoll))

	-- Low health shake
	if config.lowHealthEffects then
		if humanoid.Health < 35 then
			local t = os.clock() * 5
			local d = 50
			vars.shakeCFrame = CFrame.new(
				math.noise(t, 0, 0) / d,
				math.noise(0, t, 0) / d,
				math.noise(0, 0, t) / d
			)
		else
			vars.shakeCFrame = vars.shakeCFrame:Lerp(CFrame.new(), ExpAlpha(0.1 * 60, dt))
		end
		animBase.CFrame *= vars.shakeCFrame
	end

	if not vars.viewmodelVisible then
		animBase.CFrame *= storageCFrame
	end
end

-- ─── UpdateGrenadeViewmodelPosition ──────────────────────────────────────────

local function UpdateGrenadeViewmodelPosition(dt: number)
	if vars.dead or not vars.equipped or not vars.gunModel then return end

	applyBasePositionDt(dt)

	if vars.wepStats.gunLength then
		local tpAnimBase   = vars.weaponRig:FindFirstChild("AnimBase")
		local originCFrame = vars.firstPerson and animBase.CFrame or (tpAnimBase and tpAnimBase.CFrame or animBase.CFrame)
		applyPushback(dt, originCFrame, true)
	end

	weaponPushback.Report(vars.pushbackOffset)

	-- Grenades never aim, pass false
	applySwayAndLean(dt, false)

	if not vars.viewmodelVisible then
		animBase.CFrame *= storageCFrame
	end
end

-- ─── Init ─────────────────────────────────────────────────────────────────────

function WeaponFrame.init()
	local ctx = WeaponContext.get()
	ChangeHoldStance    = ctx.ChangeHoldStance
	ExpAlpha            = ctx.ExpAlpha
	GetThirdPersonGunModel = ctx.GetThirdPersonGunModel
	LerpNumber          = ctx.LerpNumber
	PlayAnimation       = ctx.PlayAnimation
	StopAnimation       = ctx.StopAnimation
	ToggleAiming        = ctx.ToggleAiming
	ToggleSprint        = ctx.ToggleSprint
	animBase            = ctx.animBase
	character           = ctx.character
	defaultFOV          = ctx.defaultFOV
	gunRecoilSpring     = ctx.gunRecoilSpring
	gunRotSpring        = ctx.gunRotSpring
	humanoid            = ctx.humanoid
	humanoidRootPart    = ctx.humanoidRootPart
	jumpSpring          = ctx.jumpSpring
	rayParams           = ctx.rayParams
	recoilSpring        = ctx.recoilSpring
	storageCFrame       = ctx.storageCFrame
	swaySpring          = ctx.swaySpring
end

WeaponFrame.UpdateViewmodelPosition        = UpdateViewmodelPosition
WeaponFrame.UpdateGrenadeViewmodelPosition = UpdateGrenadeViewmodelPosition

return WeaponFrame