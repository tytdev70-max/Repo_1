--!strict
-- InputBindings
-- BindCharacterInputs, UnbindCharacterInputs, HandleMovementInput.
-- Wires CanChangeWalkSpeed attribute change signal.

local contextActionService = game:GetService("ContextActionService")

local Constants      = require(script.Parent.Constants)
local SharedState    = require(script.Parent.SharedState)
local SprintSystem   = require(script.Parent.SprintSystem)
local StanceSystem   = require(script.Parent.StanceSystem)
local LeanSystem     = require(script.Parent.LeanSystem)
local StaminaSystem  = require(script.Parent.Stamina)

local Stance     = Constants.Stance
local config     = SharedState.config
local playerCharacter = SharedState.playerCharacter
local humanoid        = SharedState.humanoid

-- ── Input Handler ─────────────────────────────────────────────────────────

local function HandleMovementInput(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject): ()
	if not humanoid or humanoid.Health <= 0 then return end
	local inputBegan = Enum.UserInputState.Begin
	local lean       = playerCharacter:GetAttribute("LeanDirection")
	local sprinting  = playerCharacter:GetAttribute("Sprinting") == true

	if actionName == "SPH_Sprint" then
		local sprintHeld = inputState == inputBegan
		playerCharacter:SetAttribute("HoldingSprint", sprintHeld)
		if sprintHeld and SharedState.stance < Stance.Prone and SharedState.moving then
			if StaminaSystem.CanSprint() then
				playerCharacter:SetAttribute("Sprinting", true)
				if SharedState.stance == Stance.Crouched then StanceSystem.ChangeStance(-1, true) end
				SprintSystem.ToggleSprint(true)
				LeanSystem.ChangeLean(0)
			end
		elseif SharedState.stance == Stance.Standing then
			playerCharacter:SetAttribute("Sprinting", false)
			SprintSystem.ToggleSprint(false)
		end

	elseif inputState == inputBegan then
		if actionName == "SPH_StanceLower" and not humanoid.Sit then
			if playerCharacter:GetAttribute("IsSwimming") == true then return end
			if SharedState.stance == Stance.Prone then return end
			if not config.canCrouch and SharedState.stance == Stance.Standing then return end
			if config.proneEnabled and not config.canProne and SharedState.stance == Stance.Crouched then return end

			local changeAmount: number
			if config.proneEnabled then
				changeAmount = 1
			else
				changeAmount = if SharedState.stance == Stance.Standing then 1 else -1
			end

			StanceSystem.ChangeStance(changeAmount)
			if sprinting then
				SprintSystem.ToggleSprint(false)
			end

		elseif actionName == "SPH_StanceRaise" and SharedState.stance > Stance.Standing then
			if playerCharacter:GetAttribute("IsSwimming") == true then return end
			StanceSystem.ChangeStance(-1)

		elseif actionName == "SPH_LeanLeft"
			and SharedState.stance < Stance.Prone
			and not sprinting
			and not humanoid.Sit then
			if lean == -1 then
				LeanSystem.ChangeLean(0)
			else
				LeanSystem.ChangeLean(-1)
			end

		elseif actionName == "SPH_LeanRight"
			and SharedState.stance < Stance.Prone
			and not sprinting
			and not humanoid.Sit then
			if lean == 1 then
				LeanSystem.ChangeLean(0)
			else
				LeanSystem.ChangeLean(1)
			end
		end
	end
end

-- ── Bind / Unbind ─────────────────────────────────────────────────────────

local InputBindings = {}

function InputBindings.BindCharacterInputs(): ()
	SharedState.Blocked = false
	contextActionService:BindActionAtPriority("SPH_Sprint",      HandleMovementInput, false, config.movementInputPriority, unpack(config.keySprint))
	contextActionService:BindActionAtPriority("SPH_StanceLower", HandleMovementInput, false, config.movementInputPriority, unpack(config.lowerStance))
	contextActionService:SetTitle("SPH_StanceLower", "Crouch")
	contextActionService:SetPosition("SPH_StanceLower", UDim2.fromScale(-1, -1))
	contextActionService:BindActionAtPriority("SPH_StanceRaise", HandleMovementInput, false, config.movementInputPriority, unpack(config.raiseStance))
	contextActionService:SetTitle("SPH_StanceRaise", "Stand")
	contextActionService:SetPosition("SPH_StanceRaise", UDim2.fromScale(-1, -1))
	contextActionService:BindActionAtPriority("SPH_LeanLeft",    HandleMovementInput, false, config.movementInputPriority, unpack(config.leanLeft))
	contextActionService:BindActionAtPriority("SPH_LeanRight",   HandleMovementInput, false, config.movementInputPriority, unpack(config.leanRight))
end

function InputBindings.UnbindCharacterInputs(): ()
	SharedState.Blocked = true
	contextActionService:UnbindAction("SPH_Sprint")
	contextActionService:UnbindAction("SPH_StanceLower")
	contextActionService:UnbindAction("SPH_StanceRaise")
	contextActionService:UnbindAction("SPH_LeanLeft")
	contextActionService:UnbindAction("SPH_LeanRight")
end

-- ── Attribute Change ──────────────────────────────────────────────────────

script.Parent:GetAttributeChangedSignal("CanChangeWalkSpeed"):Connect(function(): ()
	SharedState.canChangeWalkSpeed = script.Parent:GetAttribute("CanChangeWalkSpeed") == true
end)

return InputBindings