-- AnimationSetup
-- Loads all animation tracks used by CharacterMovement.
-- Sets initial looped/priority flags.
-- Exposes animation tracks for use by other modules.

local Constants    = require(script.Parent.Constants)
local SharedState  = require(script.Parent.SharedState)

local config   = SharedState.config
local humanoid = SharedState.humanoid
local assets   = SharedState.assets

-- ── Animation Folder Resolution ───────────────────────────────────────────

local animationsFolder = assets:WaitForChild("Animations")
local movementAnimationsFolder = animationsFolder:FindFirstChild("Movement")
if not movementAnimationsFolder then
	warn("[CharacterMovement] Animations.Movement folder not found - Crouch/Prone animations will fail to load. Did you forget to create ReplicatedStorage.SPH_Assets.Animations.Movement?")
end

local function GetMovementAnimation(animName: string): Animation
	local anim = movementAnimationsFolder and movementAnimationsFolder:FindFirstChild(animName)
	if not anim then
		anim = animationsFolder:FindFirstChild(animName)
		if anim then
			warn(("[CharacterMovement] '%s' found in Animations directly, not in Animations.Movement - did you forget to move it into the folder?"):format(animName))
		else
			warn(("[CharacterMovement] Animation '%s' could not be found in Animations.Movement or Animations directly."):format(animName))
		end
	end
	return anim :: Animation
end

-- ── Load Animations ───────────────────────────────────────────────────────

local crouchIdleAnim: AnimationTrack = humanoid.Animator:LoadAnimation(GetMovementAnimation("Crouch_Idle"))
crouchIdleAnim.Looped    = true
crouchIdleAnim.Priority  = if config.useHigherAnimPriority then Enum.AnimationPriority.Action else Enum.AnimationPriority.Idle

local crouchMoveAnim: AnimationTrack = humanoid.Animator:LoadAnimation(GetMovementAnimation("Crouch_Move"))
crouchMoveAnim.Looped    = true
crouchMoveAnim.Priority  = if config.useHigherAnimPriority then Enum.AnimationPriority.Action2 else Enum.AnimationPriority.Movement

local proneIdleAnim: AnimationTrack = humanoid.Animator:LoadAnimation(GetMovementAnimation("Prone_Idle"))
proneIdleAnim.Looped     = true
proneIdleAnim.Priority   = if config.useHigherAnimPriority then Enum.AnimationPriority.Action else Enum.AnimationPriority.Idle

local proneMoveAnim: AnimationTrack = humanoid.Animator:LoadAnimation(GetMovementAnimation("Prone_Move"))
proneMoveAnim.Looped     = true
proneMoveAnim.Priority   = if config.useHigherAnimPriority then Enum.AnimationPriority.Action2 else Enum.AnimationPriority.Movement

local sprintAnimationAsset = Instance.new("Animation")
sprintAnimationAsset.AnimationId = Constants.DEFAULT_SPRINT_ANIMATION_ID

local sprintAnim: AnimationTrack = humanoid.Animator:LoadAnimation(sprintAnimationAsset)
sprintAnim.Looped    = true
sprintAnim.Priority  = Enum.AnimationPriority.Action

-- ── Public API ────────────────────────────────────────────────────────────

local AnimationSetup = {}
AnimationSetup.crouchIdleAnim = crouchIdleAnim
AnimationSetup.crouchMoveAnim = crouchMoveAnim
AnimationSetup.proneIdleAnim  = proneIdleAnim
AnimationSetup.proneMoveAnim  = proneMoveAnim
AnimationSetup.sprintAnim     = sprintAnim

return AnimationSetup