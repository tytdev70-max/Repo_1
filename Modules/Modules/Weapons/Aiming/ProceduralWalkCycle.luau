local ProceduralWalkCycle = {}
local Modules = script:FindFirstAncestor("Modules")
local vars = require(Modules.Weapons.Core.WeaponState).get()

local WALK_CYCLE_CONFIG = {
	horizontalAmplitude = 0.15,
	verticalAmplitude = 0.10,
	frequencyRatio = 2,

	stepImpactDepth = 0.12,
	stepImpactDuration = 0.15,
	stepFrequency = 1.8,

	rollMultiplier = 3.8,
	pitchMultiplier = 1.8,
	yawMultiplier = 1,

	positionLagSpeed = 8,
	rotationLagSpeed = 6,
	velocityInfluence = 0.3,

	minSpeed = 2,
	maxSpeed = 16,
	aimDampening = 0.35,
}

ProceduralWalkCycle.Config = WALK_CYCLE_CONFIG

local deps

function ProceduralWalkCycle.Init(dependencies)
	deps = dependencies
end

local function CalculateStepImpact(dt)
	local humanoidRootPart = deps.humanoidRootPart
	local currentTime = tick()

	local movementSpeed = humanoidRootPart.Velocity.Magnitude
	if movementSpeed < WALK_CYCLE_CONFIG.minSpeed then
		vars.stepPhase = 0
		return 0
	end

	local speedRatio = math.clamp((movementSpeed - WALK_CYCLE_CONFIG.minSpeed) / (WALK_CYCLE_CONFIG.maxSpeed - WALK_CYCLE_CONFIG.minSpeed), 0, 1)
	local adjustedFrequency = WALK_CYCLE_CONFIG.stepFrequency * (0.6 + speedRatio * 0.4)

	vars.stepPhase = vars.stepPhase + dt * adjustedFrequency

	local currentStepCount = math.floor(vars.stepPhase * 2)
	if currentStepCount > vars.currentStep then
		vars.currentStep = currentStepCount
		vars.lastStepTime = currentTime
	end

	local timeSinceStep = currentTime - vars.lastStepTime
	if timeSinceStep < WALK_CYCLE_CONFIG.stepImpactDuration then
		local impactProgress = timeSinceStep / WALK_CYCLE_CONFIG.stepImpactDuration
		local impactCurve = math.exp(-impactProgress * 8) * (1 - impactProgress ^ 2)
		return -WALK_CYCLE_CONFIG.stepImpactDepth * impactCurve * (0.7 + speedRatio * 0.3)
	end

	return 0
end

local function CalculateLissajousPattern(time, speedRatio)
	local a = 1
	local b = WALK_CYCLE_CONFIG.frequencyRatio

	local x = WALK_CYCLE_CONFIG.horizontalAmplitude * math.sin(a * time * math.pi * 2)
	local y = WALK_CYCLE_CONFIG.verticalAmplitude * math.sin(b * time * math.pi * 2)

	return Vector2.new(x * speedRatio, y * speedRatio)
end

function ProceduralWalkCycle.Update(dt)
	local humanoid = deps.humanoid
	local humanoidRootPart = deps.humanoidRootPart
	local animBase = deps.animBase
	local equipped = vars.equipped
	local aiming = vars.aiming
	local sprinting = vars.sprinting

	local movementSpeed = humanoidRootPart.Velocity.Magnitude
	local movementVelocity = humanoidRootPart.Velocity

	local isGrounded = humanoid.FloorMaterial ~= Enum.Material.Air

	local speedRatio = math.clamp((movementSpeed - WALK_CYCLE_CONFIG.minSpeed) / (WALK_CYCLE_CONFIG.maxSpeed - WALK_CYCLE_CONFIG.minSpeed), 0, 1)

	if aiming then
		speedRatio = speedRatio * WALK_CYCLE_CONFIG.aimDampening
	end

	local sprintMultiplier = (sprinting and not aiming) and 1.4 or 1.0

	if movementSpeed > WALK_CYCLE_CONFIG.minSpeed and not humanoid.Sit and isGrounded then
		local stepImpact = CalculateStepImpact(dt)
		local pattern = CalculateLissajousPattern(vars.stepPhase, speedRatio * sprintMultiplier)

		if equipped then
			local velocityDelta = (movementVelocity - vars.lastMovementVelocity) * WALK_CYCLE_CONFIG.velocityInfluence
			local localVelocityDelta = humanoidRootPart.CFrame:VectorToObjectSpace(velocityDelta)

			local targetX = pattern.x + localVelocityDelta.X * 0.015
			local targetY = pattern.y + stepImpact + math.abs(localVelocityDelta.Z) * 0.008
			local targetZ = 0

			local targetRoll = -pattern.x * WALK_CYCLE_CONFIG.rollMultiplier * sprintMultiplier
			local targetPitch = pattern.y * WALK_CYCLE_CONFIG.pitchMultiplier * sprintMultiplier
			local targetYaw = pattern.x * WALK_CYCLE_CONFIG.yawMultiplier

			targetRoll = targetRoll + localVelocityDelta.X * 2
			targetPitch = targetPitch - localVelocityDelta.Z * 0.8

			local targetPos = Vector3.new(targetX, targetY, targetZ)
			local targetRot = Vector3.new(targetPitch, targetYaw, targetRoll)

			vars.walkInertiaPos = vars.walkInertiaPos + (targetPos - vars.walkInertiaPos) * WALK_CYCLE_CONFIG.positionLagSpeed * dt
			vars.walkInertiaRot = vars.walkInertiaRot + (targetRot - vars.walkInertiaRot) * WALK_CYCLE_CONFIG.rotationLagSpeed * dt
			vars.lastMovementVelocity = movementVelocity

			animBase.CFrame = animBase.CFrame * CFrame.new(vars.walkInertiaPos)
			animBase.CFrame = animBase.CFrame * CFrame.Angles(
				math.rad(vars.walkInertiaRot.X),
				math.rad(vars.walkInertiaRot.Y),
				math.rad(vars.walkInertiaRot.Z)
			)
		end

		local camX = pattern.x * 0.6 * sprintMultiplier
		local camY = pattern.y * 0.3 * sprintMultiplier + stepImpact * 1.0 * sprintMultiplier
		local camRoll = -pattern.x * 20 * sprintMultiplier
		local camPitch = pattern.y * 10 * sprintMultiplier + stepImpact * 24 * sprintMultiplier

		local camTargetPos = Vector3.new(camX, camY, 0)
		local camTargetRot = Vector3.new(camPitch, 0, camRoll)

		vars.cameraWalkPos = vars.cameraWalkPos + (camTargetPos - vars.cameraWalkPos) * WALK_CYCLE_CONFIG.positionLagSpeed * dt
		vars.cameraWalkRot = vars.cameraWalkRot + (camTargetRot - vars.cameraWalkRot) * WALK_CYCLE_CONFIG.rotationLagSpeed * dt
	else
		local decaySpeed = not isGrounded and 14 or 8
		local rotDecaySpeed = not isGrounded and 10 or 5

		vars.cameraWalkPos = vars.cameraWalkPos:Lerp(Vector3.zero, decaySpeed * dt)
		vars.cameraWalkRot = vars.cameraWalkRot:Lerp(Vector3.zero, rotDecaySpeed * dt)

		if equipped then
			vars.walkInertiaPos = vars.walkInertiaPos:Lerp(Vector3.zero, decaySpeed * dt)
			vars.walkInertiaRot = vars.walkInertiaRot:Lerp(Vector3.zero, rotDecaySpeed * dt)

			if vars.walkInertiaPos.Magnitude > 0.001 then
				animBase.CFrame = animBase.CFrame * CFrame.new(vars.walkInertiaPos)
				animBase.CFrame = animBase.CFrame * CFrame.Angles(
					math.rad(vars.walkInertiaRot.X),
					math.rad(vars.walkInertiaRot.Y),
					math.rad(vars.walkInertiaRot.Z)
				)
			else
				vars.walkInertiaPos = Vector3.zero
				vars.walkInertiaRot = Vector3.zero
				if isGrounded then
					vars.stepPhase = 0
					vars.currentStep = 0
				end
			end

			vars.lastMovementVelocity = Vector3.zero
		end
	end
end

return ProceduralWalkCycle