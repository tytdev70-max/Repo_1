--!strict
-- BindableEventHandler
-- Creates/finds and connects StanceLower, StanceRaise, WaterEntryForceStand
-- BindableEvents in the MovementEvents folder.

local Constants      = require(script.Parent.Constants)
local SharedState    = require(script.Parent.SharedState)
local StanceSystem   = require(script.Parent.StanceSystem)
local SprintSystem   = require(script.Parent.SprintSystem)
local AnimationSetup = require(script.Parent.AnimationSetup)

local Stance     = Constants.Stance
local StanceName = Constants.StanceName

local config              = SharedState.config
local playerCharacter     = SharedState.playerCharacter
local humanoid            = SharedState.humanoid
local movementEventsFolder= SharedState.movementEventsFolder

local crouchIdleAnim = AnimationSetup.crouchIdleAnim
local proneIdleAnim  = AnimationSetup.proneIdleAnim
local sprintAnim     = AnimationSetup.sprintAnim

local function ensureStanceEvent(name: string): BindableEvent
	local event = movementEventsFolder:FindFirstChild(name)
	if not event then
		event = Instance.new("BindableEvent")
		event.Name   = name
		event.Parent = movementEventsFolder
	end
	return event :: BindableEvent
end

local BindableEventHandler = {}

function BindableEventHandler.init(): ()
	ensureStanceEvent("StanceLower").Event:Connect(function(): ()
		if SharedState.Blocked or humanoid.Sit then return end
		if playerCharacter:GetAttribute("IsSwimming") == true then return end
		if SharedState.stance == Stance.Prone then return end
		if not config.canCrouch and SharedState.stance == Stance.Standing then return end
		if config.proneEnabled and not config.canProne and SharedState.stance == Stance.Crouched then return end
		StanceSystem.ChangeStance(1)
		if playerCharacter:GetAttribute("Sprinting") == true then
			SprintSystem.ToggleSprint(false)
		end
	end)

	ensureStanceEvent("StanceRaise").Event:Connect(function(): ()
		if SharedState.Blocked or SharedState.stance <= Stance.Standing then return end
		if playerCharacter:GetAttribute("IsSwimming") == true then return end
		StanceSystem.ChangeStance(-1)
	end)

	ensureStanceEvent("WaterEntryForceStand").Event:Connect(function(): ()
		if SharedState.stance == Stance.Standing
			and playerCharacter:GetAttribute("Stance") == StanceName[Stance.Standing] then
			return
		end
		SharedState.canChangeStance = true
		if SharedState.moveAnim then SharedState.moveAnim:Stop(0) end
		SharedState.moveAnim = nil
		crouchIdleAnim:Stop(0)
		proneIdleAnim:Stop(0)
		if sprintAnim.IsPlaying then sprintAnim:Stop(0) end
		SharedState.stance = Stance.Standing
		playerCharacter:SetAttribute("Stance", StanceName[Stance.Standing])
		playerCharacter:SetAttribute("Sprinting", false)
		if SharedState.hipHeightTween then
			SharedState.hipHeightTween:Cancel()
			SharedState.hipHeightTween = nil
		end
		humanoid.HipHeight    = 0
		humanoid.CameraOffset = Vector3.zero
	end)
end

return BindableEventHandler