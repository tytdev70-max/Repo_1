--!strict
-- Constants
-- All frozen enumerations, stance definitions, numeric constants, and the LeanRefs type.
-- No dependencies. Pure data.

local Constants = {}

-- Stance enum
Constants.Stance = table.freeze({
	Standing = 0,
	Crouched = 1,
	Prone    = 2,
})

-- Stance name map
Constants.StanceName = table.freeze({
	[0] = "Standing",
	[1] = "Crouched",
	[2] = "Prone",
})

-- Sprint animation constants
Constants.SPRINT_FADE_IN        = 0.2
Constants.SPRINT_FADE_OUT       = 0.25
Constants.SPRINT_STANCE_FADE_OUT= 0.2

-- Stamina constants
Constants.DEFAULT_MAX_STAMINA          = 100
Constants.DEFAULT_STAMINA_DRAIN_RATE   = 15   -- Stamina points drained per second while sprinting
Constants.DEFAULT_STAMINA_REGEN_RATE   = 15   -- Stamina points regenerated per second while not sprinting
Constants.DEFAULT_STAMINA_REGEN_DELAY  = 0.5  -- Delay in seconds before regeneration starts after sprinting
Constants.STAMINA_SLOWDOWN_THRESHOLD   = 30   -- Stamina level below which sprinting speed slows down to walk speed
Constants.STAMINA_RECOVERY_THRESHOLD   = 30   -- Stamina level required to sprint again after exhaustion (0 stamina)

-- Prone constants
Constants.PRONE_HIP_HEIGHT       = -1.8
Constants.PRONE_TWEEN_MULTIPLIER = 1.5

-- Walk speed lerp
Constants.WALK_SPEED_LERP_SPEED  = 12

-- Strafe dot threshold
Constants.STRAFE_DOT_THRESHOLD   = 0.7

-- Lean XZ divisor
Constants.LEAN_XZ_DIVISOR        = 140

-- Other character load timeout
Constants.OTHER_CHARACTER_LOAD_TIMEOUT = 5

-- Character load timeout
Constants.CHARACTER_LOAD_TIMEOUT = 20

-- Foot IK settle epsilon
Constants.FOOT_IK_SETTLE_EPSILON = 0.001

-- Default sprint animation
Constants.DEFAULT_SPRINT_ANIMATION_ID = "rbxassetid://129508796824948"

-- LeanRefs type (exported for use in typed modules)
export type LeanRefs = {
	character: Model,
	hrp: BasePart,
	humanoid: Humanoid,
	torso: BasePart,
	rootJoint: Motor6D,
	neck: Motor6D,
	rightHip: Motor6D,
	leftHip: Motor6D,
	rootJointOriginalC0: CFrame,
	neckOriginalC0: CFrame,
	rightHipOriginalC0: CFrame,
	leftHipOriginalC0: CFrame,
	smoothedDir: Vector3,

	leanRightHipC0: CFrame,
	leanLeftHipC0: CFrame,

	footIKActive: boolean,
	footIKRightOffset: number,
	footIKLeftOffset: number,
	footIKTargetRightOffset: number,
	footIKTargetLeftOffset: number,
	footIKTargetRightNormal: Vector3,
	footIKTargetLeftNormal: Vector3,
	footIKRayParams: RaycastParams?,
}

return Constants