-- StanceSystem
-- ChangeStance: manages stance transitions, animations, hip height tweening,
-- sounds, and attribute updates.

local tweenService = game:GetService("TweenService")

local Constants      = require(script.Parent.Constants)
local SharedState    = require(script.Parent.SharedState)
local AnimationSetup = require(script.Parent.AnimationSetup)
local SprintSystem   = require(script.Parent.SprintSystem)
local LeanSystem     = require(script.Parent.LeanSystem)

local Stance     = Constants.Stance
local StanceName = Constants.StanceName

local SPRINT_STANCE_FADE_OUT = Constants.SPRINT_STANCE_FADE_OUT
local PRONE_HIP_HEIGHT       = Constants.PRONE_HIP_HEIGHT
local PRONE_TWEEN_MULTIPLIER = Constants.PRONE_TWEEN_MULTIPLIER

local config          = SharedState.config
local playerCharacter = SharedState.playerCharacter
local humanoid        = SharedState.humanoid

local crouchIdleAnim  = AnimationSetup.crouchIdleAnim
local crouchMoveAnim  = AnimationSetup.crouchMoveAnim
local proneIdleAnim   = AnimationSetup.proneIdleAnim
local proneMoveAnim   = AnimationSetup.proneMoveAnim
local sprintAnim      = AnimationSetup.sprintAnim

-- Reference to the main script for DisableLean attribute
local mainScript = script.Parent

local StanceSystem = {}

function StanceSystem.ChangeStance(change: number, override: boolean?): ()
	if SharedState.canChangeStance or override then
		SharedState.canChangeStance = false
		task.delay(config.stanceChangeTime * 0.7, function()
			SharedState.canChangeStance = true
		end)

		local number = SharedState.stance + change

		if number < Stance.Standing then
			number = Stance.Standing
		elseif number > Stance.Prone then
			number = Stance.Prone
		end

		if not config.proneEnabled and number > Stance.Crouched then
			number = Stance.Crouched
		end

		local preMove = false
		if SharedState.moveAnim then
			preMove = SharedState.moveAnim.IsPlaying
		end

		if number == Stance.Standing then
			mainScript:SetAttribute("DisableLean", false)
			if SharedState.moveAnim then
				SharedState.moveAnim:Stop(config.stanceChangeTime)
			end
			SharedState.moveAnim = nil
			crouchIdleAnim:Stop(config.stanceChangeTime)
			playerCharacter:SetAttribute("Stance", StanceName[Stance.Standing])
			if SharedState.hipHeightTween then SharedState.hipHeightTween:Cancel() end
			SharedState.hipHeightTween = tweenService:Create(
				humanoid, TweenInfo.new(config.stanceChangeTime), { HipHeight = 0 })
			SharedState.hipHeightTween:Play()
			LeanSystem.PlayCharSound("Uncrouch")
			if playerCharacter:GetAttribute("HoldingSprint") == true
				and not SharedState.isExhausted
				and SharedState.stamina > 0 then
				playerCharacter:SetAttribute("Sprinting", true)
				SprintSystem.ToggleSprint(true)
			end

		elseif number == Stance.Crouched then
			mainScript:SetAttribute("DisableLean", false)
			if SharedState.moveAnim then
				SharedState.moveAnim:Stop(config.stanceChangeTime)
			end
			SharedState.moveAnim = crouchMoveAnim
			if SharedState.moving then
				SharedState.moveAnim:Play(config.stanceChangeTime)
			end
			proneIdleAnim:Stop(config.stanceChangeTime)
			crouchIdleAnim:Play(config.stanceChangeTime)
			playerCharacter:SetAttribute("Stance", StanceName[Stance.Crouched])
			playerCharacter:SetAttribute("Sprinting", false)
			if sprintAnim.IsPlaying then sprintAnim:Stop(SPRINT_STANCE_FADE_OUT) end
			if SharedState.hipHeightTween then SharedState.hipHeightTween:Cancel() end
			SharedState.hipHeightTween = tweenService:Create(
				humanoid, TweenInfo.new(config.stanceChangeTime), { HipHeight = 0 })
			SharedState.hipHeightTween:Play()
			if SharedState.stance == Stance.Standing then
				LeanSystem.PlayCharSound("Crouch")
			elseif SharedState.stance == Stance.Prone then
				LeanSystem.PlayCharSound("Unprone")
			end

		elseif number == Stance.Prone then
			LeanSystem.ChangeLean(0)
			mainScript:SetAttribute("DisableLean", true)
			if SharedState.moveAnim then
				SharedState.moveAnim:Stop(config.stanceChangeTime)
			end
			SharedState.moveAnim = proneMoveAnim
			crouchIdleAnim:Stop(config.stanceChangeTime)
			proneIdleAnim:Play(config.stanceChangeTime)
			playerCharacter:SetAttribute("Stance", StanceName[Stance.Prone])
			playerCharacter:SetAttribute("Sprinting", false)
			if sprintAnim.IsPlaying then sprintAnim:Stop(SPRINT_STANCE_FADE_OUT) end
			if SharedState.hipHeightTween then SharedState.hipHeightTween:Cancel() end
			SharedState.hipHeightTween = tweenService:Create(
				humanoid,
				TweenInfo.new(config.stanceChangeTime * PRONE_TWEEN_MULTIPLIER),
				{ HipHeight = PRONE_HIP_HEIGHT }
			)
			SharedState.hipHeightTween:Play()
			LeanSystem.PlayCharSound("Prone")
		end

		if preMove and SharedState.moveAnim then
			SharedState.moveAnim:Play()
		end
		SharedState.stance = number
	end
end

return StanceSystem