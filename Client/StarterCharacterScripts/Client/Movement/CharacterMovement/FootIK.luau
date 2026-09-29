-- FootIK
-- All R6 Foot IK (foot planting) logic:
-- ray casting, computing foot C0, smoothing, replication, disable logic.

local Constants   = require(script.Parent.Constants)
local SharedState = require(script.Parent.SharedState)

type LeanRefs = Constants.LeanRefs

local config      = SharedState.config
local Stance      = Constants.Stance
local StanceName  = Constants.StanceName

-- Network (loaded lazily to avoid circular dependency ordering issues)
local networkingModules = SharedState.networkingModules
local Network = require(networkingModules:WaitForChild("SPH_Network") :: ModuleScript) :: any
local ClientBridge = require(networkingModules:WaitForChild("ClientBridge") :: ModuleScript) :: any
local ReplicationThrottle = require(networkingModules:WaitForChild("ReplicationThrottle") :: ModuleScript) :: any

local playerCharacter  = SharedState.playerCharacter
local otherLeanRefsByCharacter = SharedState.otherLeanRefsByCharacter
local humanoid         = SharedState.humanoid

-- ── Helper ────────────────────────────────────────────────────────────────

local function LerpNumber(number: number, target: number, speed: number): number
	return number + (target - number) * speed
end

-- ── Throttle ──────────────────────────────────────────────────────────────

local footIKThrottle = ReplicationThrottle.new(config.footIKReplicationRate)

-- ── Leg Adjustment Compute ────────────────────────────────────────────────

local function ComputeLegAdjustment(offset: number, side: number): (number, number)
	if offset > 0 then
		return offset * config.footIKLegForwardMultiplier * side, offset * config.footIKLegPitchMultiplier
	end
	return 0, 0
end

local function ComputeFootC0(
	origC0: CFrame,
	offset: number,
	worldNormal: Vector3,
	torsoCF: CFrame,
	rootCF: CFrame,
	side: number
): CFrame
	local localNormal    = torsoCF:VectorToObjectSpace(worldNormal)
	local surfacePitch   = math.atan2(-localNormal.Z, localNormal.Y)
	local surfaceRoll    = math.atan2(localNormal.X, localNormal.Y)
	local rootYaw        = math.atan2(rootCF.LookVector.X, rootCF.LookVector.Z)
	local torsoYaw       = math.atan2(torsoCF.LookVector.X, torsoCF.LookVector.Z)
	local relativeYaw    = rootYaw - torsoYaw
	local forwardShift, liftPitch = ComputeLegAdjustment(offset, side)

	return origC0
		* CFrame.new(forwardShift, offset, 0)
		* CFrame.Angles(surfacePitch, relativeYaw, surfaceRoll + liftPitch * side)
end

-- ── Foot Raycast ──────────────────────────────────────────────────────────

local function CastFoot(footWorldCFrame: CFrame, rayParams: RaycastParams): (number, Vector3)
	local origin    = footWorldCFrame.Position + Vector3.new(0, config.footIKOffsetY, 0)
	local direction = Vector3.new(0, -config.footIKRayLength, 0)
	local result    = workspace:Raycast(origin, direction, rayParams)

	if result then
		local dist   = (origin - result.Position).Magnitude
		local offset = math.clamp(
			config.footIKRayLength - dist - config.footIKBaseOffset,
			-config.footIKMaxDrop, config.footIKMaxHeight)
		return offset, result.Normal
	end

	return 0, Vector3.new(0, 1, 0)
end

-- ── Reset / Disable ───────────────────────────────────────────────────────

local function ResetFootIKJoints(refs: LeanRefs): ()
	if refs.rightHip.Parent then
		refs.rightHip.C0 = refs.leanRightHipC0
	end
	if refs.leftHip.Parent then
		refs.leftHip.C0 = refs.leanLeftHipC0
	end
end

local function DisableFootIK(refs: LeanRefs, replicateImmediately: boolean?): ()
	refs.footIKActive              = false
	refs.footIKTargetRightOffset   = 0
	refs.footIKTargetLeftOffset    = 0
	refs.footIKTargetRightNormal   = Vector3.new(0, 1, 0)
	refs.footIKTargetLeftNormal    = Vector3.new(0, 1, 0)
	refs.footIKRightOffset         = 0
	refs.footIKLeftOffset          = 0
	ResetFootIKJoints(refs)

	if replicateImmediately then
		local disabledSnapshot = {
			Active      = false,
			RightOffset = 0,
			LeftOffset  = 0,
			RightNormal = Vector3.new(0, 1, 0),
			LeftNormal  = Vector3.new(0, 1, 0),
		}
		Network.packets.PlayerFootIKRequest.send(disabledSnapshot)
		if footIKThrottle then
			footIKThrottle:ForceSend(disabledSnapshot)
		end
	end
end

-- ── Should Disable ────────────────────────────────────────────────────────

local function ShouldDisableFootIK(character: Model, hum: Humanoid): boolean
	local stanceAttr = character:GetAttribute("Stance")
	if stanceAttr == StanceName[Stance.Prone] or stanceAttr == StanceName[Stance.Crouched] then
		return true
	end

	local state = hum:GetState()
	if state == Enum.HumanoidStateType.Climbing
		or state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Freefall then
		return true
	end

	if hum.MoveDirection.Magnitude > 0 then return true end
	if hum.Sit          then return true end
	if hum.PlatformStand then return true end
	if not hum.AutoRotate then return true end
	if hum.SeatPart      then return true end

	return false
end

-- ── Ray Params Builder ────────────────────────────────────────────────────

local function BuildFootIKRayParams(character: Model): RaycastParams
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	return rayParams
end

-- ── Update Target ─────────────────────────────────────────────────────────

local function UpdateLocalFootIKTarget(refs: LeanRefs): ()
	if ShouldDisableFootIK(refs.character, refs.humanoid) then
		if refs.footIKActive then
			DisableFootIK(refs, true)
		end
		return
	end

	refs.footIKActive = true

	local torsoCF        = refs.torso.CFrame
	local rightFootWorld = torsoCF * config.footIKRightFootLocalCFrame
	local leftFootWorld  = torsoCF * config.footIKLeftFootLocalCFrame

	local rightOffset, rightNormal = CastFoot(rightFootWorld, refs.footIKRayParams :: RaycastParams)
	local leftOffset, leftNormal   = CastFoot(leftFootWorld,  refs.footIKRayParams :: RaycastParams)

	refs.footIKTargetRightOffset = rightOffset
	refs.footIKTargetLeftOffset  = leftOffset
	refs.footIKTargetRightNormal = rightNormal
	refs.footIKTargetLeftNormal  = leftNormal
end

-- ── Step (per frame) ─────────────────────────────────────────────────────

local function StepFootIK(dt: number, refs: LeanRefs): ()
	if not refs.rightHip.Parent or not refs.leftHip.Parent then return end

	if not refs.footIKActive then
		if refs.footIKRightOffset ~= 0 or refs.footIKLeftOffset ~= 0 then
			refs.footIKRightOffset = 0
			refs.footIKLeftOffset  = 0
			ResetFootIKJoints(refs)
		end
		return
	end

	local alpha = 1 - math.exp(-config.footIKAdjustmentSpeed * dt)
	refs.footIKRightOffset = LerpNumber(refs.footIKRightOffset, refs.footIKTargetRightOffset, alpha)
	refs.footIKLeftOffset  = LerpNumber(refs.footIKLeftOffset,  refs.footIKTargetLeftOffset,  alpha)

	local torsoCF = refs.torso.CFrame
	local hrpCF   = refs.hrp.CFrame

	refs.rightHip.C0 = ComputeFootC0(
		refs.leanRightHipC0, refs.footIKRightOffset,
		refs.footIKTargetRightNormal, torsoCF, hrpCF, 1)
	refs.leftHip.C0  = ComputeFootC0(
		refs.leanLeftHipC0,  refs.footIKLeftOffset,
		refs.footIKTargetLeftNormal,  torsoCF, hrpCF, -1)
end

-- ── Replication ───────────────────────────────────────────────────────────

local function FootIKSnapshotDelta(a: any, b: any): number
	if a.Active ~= b.Active then return math.huge end
	local rightDelta = math.abs(a.RightOffset - b.RightOffset)
		+ (a.RightNormal - b.RightNormal).Magnitude
	local leftDelta  = math.abs(a.LeftOffset  - b.LeftOffset)
		+ (a.LeftNormal  - b.LeftNormal).Magnitude
	return rightDelta + leftDelta
end

local function ReplicateFootIKIfNeeded(refs: LeanRefs): ()
	local snapshot = {
		Active      = refs.footIKActive,
		RightOffset = refs.footIKTargetRightOffset,
		LeftOffset  = refs.footIKTargetLeftOffset,
		RightNormal = refs.footIKTargetRightNormal,
		LeftNormal  = refs.footIKTargetLeftNormal,
	}

	if footIKThrottle:ShouldSend(snapshot, config.footIKReplicationThreshold, FootIKSnapshotDelta) then
		Network.packets.PlayerFootIKRequest.send(snapshot)
	end
end

-- ── Init local refs and signals ───────────────────────────────────────────

local function InitLocalFootIK(): ()
	local localLeanRefs = SharedState.localLeanRefs
	if not localLeanRefs then return end

	localLeanRefs.footIKRayParams = BuildFootIKRayParams(playerCharacter)

	if config.footIKEnabled then
		humanoid.Running:Connect(function(speed: number): ()
			local refs = SharedState.localLeanRefs
			if speed > 0 and refs then
				DisableFootIK(refs, true)
			end
		end)

		playerCharacter:GetAttributeChangedSignal("Stance"):Connect(function(): ()
			local refs = SharedState.localLeanRefs
			if refs and playerCharacter:GetAttribute("Stance") ~= StanceName[Stance.Standing] then
				DisableFootIK(refs, true)
			end
		end)

		playerCharacter:GetAttributeChangedSignal("Sprinting"):Connect(function(): ()
			local refs = SharedState.localLeanRefs
			if refs and playerCharacter:GetAttribute("Sprinting") == true then
				DisableFootIK(refs, true)
			end
		end)
	end
end

InitLocalFootIK()

-- ── ClientBridge Binding ──────────────────────────────────────────────────

ClientBridge.bind("footIK", Network.packets.ReplicateFootIK, function(Data: any): ()
	local otherCharacter: Model? = Data.Character
	if not otherCharacter or otherCharacter == playerCharacter then return end

	local refs = otherLeanRefsByCharacter[otherCharacter]
	if not refs then return end

	refs.footIKActive              = Data.Active
	refs.footIKTargetRightOffset   = Data.RightOffset
	refs.footIKTargetLeftOffset    = Data.LeftOffset
	refs.footIKTargetRightNormal   = Data.RightNormal
	refs.footIKTargetLeftNormal    = Data.LeftNormal
end)

-- ── Public API ────────────────────────────────────────────────────────────

local FootIK = {}
FootIK.DisableFootIK            = DisableFootIK
FootIK.UpdateLocalFootIKTarget  = UpdateLocalFootIKTarget
FootIK.StepFootIK               = StepFootIK
FootIK.ReplicateFootIKIfNeeded  = ReplicateFootIKIfNeeded
FootIK.BuildFootIKRayParams     = BuildFootIKRayParams
FootIK.footIKThrottle           = footIKThrottle

return FootIK