--!strict
-- StaminaSystem
-- Handles stamina consumption while running, gradual slowdown when stamina < 30,
-- stamina regeneration, and exhaustion states.

local Constants      = require(script.Parent.Constants)
local SharedState    = require(script.Parent.SharedState)
local SprintSystem   = require(script.Parent.SprintSystem)

local Stance          = Constants.Stance
local config          = SharedState.config
local humanoid        = SharedState.humanoid
local playerCharacter = SharedState.playerCharacter

-- Reference to main script for attributes
local mainScript = script.Parent

-- Configuration constants with fallback defaults
local drainRate: number = if config and config.staminaDrainRate ~= nil
	then config.staminaDrainRate
	else Constants.DEFAULT_STAMINA_DRAIN_RATE

local regenRate: number = if config and config.staminaRegenRate ~= nil
	then config.staminaRegenRate
	else Constants.DEFAULT_STAMINA_REGEN_RATE

local regenDelay: number = if config and config.staminaRegenDelay ~= nil
	then config.staminaRegenDelay
	else Constants.DEFAULT_STAMINA_REGEN_DELAY

local slowdownThreshold: number = if config and config.staminaSlowdownThreshold ~= nil
	then config.staminaSlowdownThreshold
	else Constants.STAMINA_SLOWDOWN_THRESHOLD

local recoveryThreshold: number = if config and config.staminaRecoveryThreshold ~= nil
	then config.staminaRecoveryThreshold
	else Constants.STAMINA_RECOVERY_THRESHOLD

local timeSinceSprint: number = regenDelay

local StaminaSystem = {}

-- Returns true if the player is allowed to begin or maintain sprinting based on stamina
function StaminaSystem.CanSprint(): boolean
	return not SharedState.isExhausted and SharedState.stamina > 0
end

-- Calculates the target running speed.
-- When stamina is below slowdownThreshold (30), speed smoothly scales down
-- towards walking speed instead of suddenly snapping.
function StaminaSystem.CalculateSprintSpeed(walkSpeed: number, sprintSpeed: number): number
	if SharedState.stamina < slowdownThreshold then
		local ratio = math.clamp(SharedState.stamina / slowdownThreshold, 0, 1)
		return walkSpeed + (sprintSpeed - walkSpeed) * ratio
	end
	return sprintSpeed
end

-- Resets stamina to full and clears exhaustion
function StaminaSystem.Reset(): ()
	SharedState.stamina = SharedState.maxStamina
	SharedState.isExhausted = false
	timeSinceSprint = regenDelay
	playerCharacter:SetAttribute("Stamina", SharedState.stamina)
	playerCharacter:SetAttribute("IsExhausted", false)
	mainScript:SetAttribute("Stamina", SharedState.stamina)
end

-- Called every frame by RenderLoop
function StaminaSystem.Update(dt: number): ()
	local isSprinting = playerCharacter:GetAttribute("Sprinting") == true
	local isRunning = isSprinting
		and SharedState.moving
		and humanoid.Health > 0
		and not humanoid.Sit

	if isRunning then
		timeSinceSprint = 0
		SharedState.stamina = math.max(0, SharedState.stamina - drainRate * dt)

		-- When stamina fully runs out, exhaust and stop sprinting.
		-- The running speed will have already smoothly reached walking speed (since stamina < 30 scaled it down).
		if SharedState.stamina <= 0 then
			SharedState.stamina = 0
			SharedState.isExhausted = true
			playerCharacter:SetAttribute("Sprinting", false)
			SprintSystem.ToggleSprint(false)
		end
		print(SharedState.stamina)
	else
		timeSinceSprint += dt
		if timeSinceSprint >= regenDelay and SharedState.stamina < SharedState.maxStamina then
			SharedState.stamina = math.min(SharedState.maxStamina, SharedState.stamina + regenRate * dt)

			-- Recover from exhaustion once stamina reaches the recovery threshold
			if SharedState.isExhausted and SharedState.stamina >= recoveryThreshold then
				SharedState.isExhausted = false

				-- Auto-resume sprint if player is still holding sprint and actively moving
				if playerCharacter:GetAttribute("HoldingSprint") == true
					and SharedState.moving
					and SharedState.stance < Stance.Prone
					and not humanoid.Sit
					and humanoid.Health > 0 then
					playerCharacter:SetAttribute("Sprinting", true)
					SprintSystem.ToggleSprint(true)
				end
			end
		end
	end

	-- Keep character and mainScript attributes synced
	playerCharacter:SetAttribute("Stamina", SharedState.stamina)
	playerCharacter:SetAttribute("IsExhausted", SharedState.isExhausted)
	mainScript:SetAttribute("Stamina", SharedState.stamina)
end

-- Listen for dynamic changes to MaxStamina attribute
mainScript:GetAttributeChangedSignal("MaxStamina"):Connect(function(): ()
	local newMax = mainScript:GetAttribute("MaxStamina")
	if typeof(newMax) == "number" and newMax > 0 then
		SharedState.maxStamina = newMax
		SharedState.stamina = math.clamp(SharedState.stamina, 0, newMax)
		playerCharacter:SetAttribute("MaxStamina", newMax)
		playerCharacter:SetAttribute("Stamina", SharedState.stamina)
	end
end)

return StaminaSystem