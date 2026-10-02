-- MovementLean
-- BuildLeanRefs, ApplyMovementLean, lean ref tables for local and other players.
-- Also wires foot IK precondition signals (Running, Stance, Sprinting).

local Constants   = require(script.Parent.Constants)
local SharedState = require(script.Parent.SharedState)

type LeanRefs = Constants.LeanRefs

local config          = SharedState.config
local playerCharacter = SharedState.playerCharacter
local rootPart        = SharedState.rootPart
local humanoid        = SharedState.humanoid
local players         = game:GetService("Players")
local localPlayer     = SharedState.localPlayer

local Stance     = Constants.Stance
local StanceName = Constants.StanceName

-- ── Movement Lean Constants ───────────────────────────────────────────────

local RangeOfMotion         = math.abs(math.rad(config.movementLeanRangeOfMotionDeg))
local RangeOfMotionTorso    = math.rad(90 - config.movementLeanRangeOfMotionDeg)
local RangeOfMotionTorsoClamp = math.abs(RangeOfMotionTorso)
local LEAN_XZ_DIVISOR       = Constants.LEAN_XZ_DIVISOR
local RangeOfMotionXZ       = config.movementLeanRangeOfMotionDeg / LEAN_XZ_DIVISOR
local MaxPitchRadians        = math.abs(math.rad(config.movementLeanPitchMaxDeg))
local MaxHipTranslate        = math.abs(config.movementLeanMaxHipTranslate)
local VelocityClamp          = math.abs(config.movementLeanVelocityClamp)

-- ── BuildLeanRefs ─────────────────────────────────────────────────────────

local function BuildLeanRefs(character: Model, hrp: BasePart, hum: Humanoid): LeanRefs?
	local torso = character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return nil
	end

	local rj        = hrp:FindFirstChild("RootJoint")
	local neckJoint = torso:FindFirstChild("Neck")
	local rHip      = torso:FindFirstChild("Right Hip")
	local lHip      = torso:FindFirstChild("Left Hip")

	if not (rj and rj:IsA("Motor6D")
		and neckJoint and neckJoint:IsA("Motor6D")
		and rHip and rHip:IsA("Motor6D")
		and lHip and lHip:IsA("Motor6D")) then
		return nil
	end

	return {
		character = character,
		hrp       = hrp,
		humanoid  = hum,
		torso     = torso,
		rootJoint = rj,
		neck      = neckJoint,
		rightHip  = rHip,
		leftHip   = lHip,
		rootJointOriginalC0 = rj.C0,
		neckOriginalC0      = neckJoint.C0,
		rightHipOriginalC0  = rHip.C0,
		leftHipOriginalC0   = lHip.C0,
		smoothedDir         = Vector3.zero,

		leanRightHipC0 = rHip.C0,
		leanLeftHipC0  = lHip.C0,

		footIKActive              = false,
		footIKRightOffset         = 0,
		footIKLeftOffset          = 0,
		footIKTargetRightOffset   = 0,
		footIKTargetLeftOffset    = 0,
		footIKTargetRightNormal   = Vector3.new(0, 1, 0),
		footIKTargetLeftNormal    = Vector3.new(0, 1, 0),
		footIKRayParams           = nil,
	}
end

-- ── ApplyMovementLean ─────────────────────────────────────────────────────

local function ApplyMovementLean(dt: number, refs: LeanRefs): ()
	if not refs.rightHip.Parent or not refs.leftHip.Parent
		or not refs.rootJoint.Parent or not refs.neck.Parent then
		return
	end

	local disabled = refs.humanoid.Sit
		or refs.humanoid.Health <= 0
		or refs.character:GetAttribute("Stance") == StanceName[Stance.Prone]
		or refs.character:GetAttribute("SeatAnim") == true

	local targetDir = Vector3.zero
	if not disabled then
		local walkSpeed = math.max(refs.humanoid.WalkSpeed or 16, 1)
		local velLocal = refs.hrp.CFrame:VectorToObjectSpace(refs.hrp.AssemblyLinearVelocity)
		targetDir = Vector3.new(
			math.clamp(velLocal.X / walkSpeed, -VelocityClamp, VelocityClamp),
			0,
			math.clamp(velLocal.Z / walkSpeed, -VelocityClamp, VelocityClamp)
		)
	end

	local smoothingAlpha = math.clamp(dt * config.movementLeanSmoothingSpeed, 0, 1)
	refs.smoothedDir = refs.smoothedDir:Lerp(targetDir, smoothingAlpha)
	local dir = refs.smoothedDir

	local xResult = math.clamp(
		dir.X * (RangeOfMotion - (math.abs(dir.Z) * (RangeOfMotion / 2))),
		-RangeOfMotion, RangeOfMotion)
	local xResultTorso = math.clamp(
		dir.X * (RangeOfMotionTorso - (math.abs(dir.Z) * (RangeOfMotionTorso / 2))),
		-RangeOfMotionTorsoClamp, RangeOfMotionTorsoClamp)
	local xResultXZ = math.clamp(
		dir.X * (RangeOfMotionXZ - (math.abs(dir.Z) * (RangeOfMotionXZ / 2))),
		-MaxHipTranslate, MaxHipTranslate)

	if config.movementLeanInvertRollWhenMovingForward and dir.Z > 0.1 then
		xResult, xResultTorso, xResultXZ = -xResult, -xResultTorso, -xResultXZ
	end

	local pitchAmount, pitchTranslate = 0, 0
	if config.movementLeanPitchEnabled then
		pitchAmount = math.clamp(
			config.movementLeanPitchDirection * dir.Z * MaxPitchRadians,
			-MaxPitchRadians, MaxPitchRadians)
		pitchTranslate = math.clamp(
			-dir.Z * config.movementLeanPitchTranslateOffset,
			-MaxHipTranslate, MaxHipTranslate)
	end

	local rightHipResult = refs.rightHipOriginalC0
		* CFrame.new(-xResultXZ, 0, 0)
		* CFrame.Angles(0, -xResult, 0)
	local leftHipResult = refs.leftHipOriginalC0
		* CFrame.new(-xResultXZ, 0, 0)
		* CFrame.Angles(0, -xResult, 0)
	local rootJointResult = refs.rootJointOriginalC0
		* CFrame.new(0, 0, pitchTranslate)
		* CFrame.Angles(pitchAmount * config.movementLeanPitchWeightRoot, 0, -xResultTorso)
	local neckResult = refs.neckOriginalC0
		* CFrame.Angles(-pitchAmount * config.movementLeanPitchWeightNeck, 0, xResultTorso)

	local lerpTime = math.clamp(1 - config.movementLeanSpeed ^ dt, 0, 1)

	pcall(function()
		refs.leanRightHipC0 = refs.leanRightHipC0:Lerp(rightHipResult, lerpTime)
		refs.leanLeftHipC0  = refs.leanLeftHipC0:Lerp(leftHipResult,  lerpTime)
		refs.rootJoint.C0   = refs.rootJoint.C0:Lerp(rootJointResult, lerpTime)
		refs.neck.C0        = refs.neck.C0:Lerp(neckResult, lerpTime)

		if not refs.footIKActive then
			refs.rightHip.C0 = refs.leanRightHipC0
			refs.leftHip.C0  = refs.leanLeftHipC0
		end
	end)
end

-- ── Other Player Lean Setup ───────────────────────────────────────────────

local OTHER_CHARACTER_LOAD_TIMEOUT = Constants.OTHER_CHARACTER_LOAD_TIMEOUT
local otherLeanRefs            = SharedState.otherLeanRefs
local otherLeanRefsByCharacter = SharedState.otherLeanRefsByCharacter

local function SetupOtherLean(otherPlayer: Player, character: Model): ()
	local hrp = character:WaitForChild("HumanoidRootPart", OTHER_CHARACTER_LOAD_TIMEOUT)
	local hum = character:WaitForChild("Humanoid", OTHER_CHARACTER_LOAD_TIMEOUT)
	if not hrp or not hrp:IsA("BasePart") or not hum or not hum:IsA("Humanoid") then
		return
	end

	local refs = BuildLeanRefs(character, hrp, hum)
	otherLeanRefs[otherPlayer] = refs
	if refs then
		otherLeanRefsByCharacter[character] = refs
	end

	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			otherLeanRefs[otherPlayer] = nil
			otherLeanRefsByCharacter[character] = nil
		end
	end)
end

local function OnOtherPlayerAdded(otherPlayer: Player): ()
	if otherPlayer == localPlayer then return end
	otherPlayer.CharacterAdded:Connect(function(character: Model)
		SetupOtherLean(otherPlayer, character)
	end)
	if otherPlayer.Character then
		SetupOtherLean(otherPlayer, otherPlayer.Character)
	end
end

for _, otherPlayer in ipairs(players:GetPlayers()) do
	OnOtherPlayerAdded(otherPlayer)
end

players.PlayerAdded:Connect(OnOtherPlayerAdded)
players.PlayerRemoving:Connect(function(otherPlayer: Player): ()
	local refs = otherLeanRefs[otherPlayer]
	if refs then
		otherLeanRefsByCharacter[refs.character] = nil
	end
	otherLeanRefs[otherPlayer] = nil
end)

-- ── Build Local Lean Refs ─────────────────────────────────────────────────

SharedState.localLeanRefs = BuildLeanRefs(playerCharacter, rootPart, humanoid)

-- ── Public API ────────────────────────────────────────────────────────────

local MovementLean = {}
MovementLean.BuildLeanRefs     = BuildLeanRefs
MovementLean.ApplyMovementLean = ApplyMovementLean
MovementLean.SetupOtherLean    = SetupOtherLean

return MovementLean