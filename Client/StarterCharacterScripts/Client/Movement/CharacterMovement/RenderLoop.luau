--!strict
-- RenderLoop
-- runService.RenderStepped connection.
-- Orchestrates: movement lean, foot IK, stamina, walk speed, sprint animation,
-- movement state (moving/not moving).

local runService = game:GetService("RunService")

local Constants        = require(script.Parent.Constants)
local SharedState      = require(script.Parent.SharedState)
local AnimationSetup   = require(script.Parent.AnimationSetup)
local MovementLean     = require(script.Parent.MovementLean)
local FootIK           = require(script.Parent.FootIK)
local SprintSystem     = require(script.Parent.SprintSystem)
local WalkSpeedSystem  = require(script.Parent.WalkSpeedSystem)
local StaminaSystem    = require(script.Parent.Stamina)

local Stance     = Constants.Stance
local StanceName = Constants.StanceName

local SPRINT_FADE_IN  = Constants.SPRINT_FADE_IN
local SPRINT_FADE_OUT = Constants.SPRINT_FADE_OUT

local config          = SharedState.config
local playerCharacter = SharedState.playerCharacter
local humanoid        = SharedState.humanoid
local sprintAnim      = AnimationSetup.sprintAnim

-- Reference to main script for speed attributes
local mainScript = script.Parent

local RenderLoop = {}

function RenderLoop.init(): ()
	local renderSteppedConn
	renderSteppedConn = runService.RenderStepped:Connect(function(deltaTime: number): ()
		SharedState.movementVector = humanoid.MoveDirection.Unit

		-- Movement Lean
		if config.movementLeaning then
			if SharedState.localLeanRefs then
				MovementLean.ApplyMovementLean(deltaTime, SharedState.localLeanRefs)
			end
			if config.replicateMovementLeaning then
				for _, refs in pairs(SharedState.otherLeanRefs) do
					MovementLean.ApplyMovementLean(deltaTime, refs)
				end
			end
		end

		-- Foot IK
		if config.footIKEnabled then
			if SharedState.localLeanRefs then
				FootIK.UpdateLocalFootIKTarget(SharedState.localLeanRefs)
				FootIK.StepFootIK(deltaTime, SharedState.localLeanRefs)
				FootIK.ReplicateFootIKIfNeeded(SharedState.localLeanRefs)
			end
			for _, refs in pairs(SharedState.otherLeanRefs) do
				FootIK.StepFootIK(deltaTime, refs)
			end
		end
		
		-- Stamina
		StaminaSystem.Update(deltaTime)

		-- Walk Speed
		WalkSpeedSystem.Update(deltaTime)

		-- Move anim speed adjustment
		if SharedState.moveAnim then
			SharedState.moveAnim:AdjustSpeed(humanoid.WalkSpeed / 6)
		end
		
		-- Sprint anim speed adjustment (proportional to running speed when stamina < 30)
		if sprintAnim.IsPlaying then
			local baseSprintSpeed = mainScript:GetAttribute("SprintSpeed") :: number?
			if baseSprintSpeed and baseSprintSpeed > 0 then
				sprintAnim:AdjustSpeed(math.clamp(humanoid.WalkSpeed / baseSprintSpeed, 0.6, 1.5))
			end
		end

		-- Moving state
		local isSprinting  = playerCharacter:GetAttribute("Sprinting") == true
		local currentStance= playerCharacter:GetAttribute("Stance")

		if humanoid.MoveDirection.Magnitude > 0 and not SharedState.moving then
			SharedState.moving = true
			if SharedState.moveAnim then
				SharedState.moveAnim:Play(config.stanceChangeTime)
			end

			if playerCharacter:GetAttribute("HoldingSprint") == true
				and not isSprinting
				and SharedState.stance < Stance.Prone
				and StaminaSystem.CanSprint() then
				playerCharacter:SetAttribute("Sprinting", true)
				SprintSystem.ToggleSprint(true)
				isSprinting = true
			end

			if isSprinting and currentStance == StanceName[Stance.Standing] and not sprintAnim.IsPlaying then
				sprintAnim:Play(SPRINT_FADE_IN)
			end

		elseif humanoid.MoveDirection.Magnitude <= 0 then
			SharedState.moving = false
			if isSprinting then
				SprintSystem.ToggleSprint(false)
				playerCharacter:SetAttribute("Sprinting", false)
			end
			if sprintAnim.IsPlaying then
				sprintAnim:Stop(SPRINT_FADE_OUT)
			end
			if SharedState.moveAnim then
				SharedState.moveAnim:Stop(config.stanceChangeTime)
			end
		end

		-- Sprint anim sync
		if isSprinting and currentStance == StanceName[Stance.Standing] and SharedState.moving then
			if not sprintAnim.IsPlaying then
				sprintAnim:Play(SPRINT_FADE_IN)
			end
		elseif sprintAnim.IsPlaying
			and (not isSprinting
				or currentStance ~= StanceName[Stance.Standing]
				or not SharedState.moving) then
			sprintAnim:Stop(SPRINT_FADE_OUT)
		end
	end)

	SharedState.renderSteppedConn = renderSteppedConn
end

return RenderLoop