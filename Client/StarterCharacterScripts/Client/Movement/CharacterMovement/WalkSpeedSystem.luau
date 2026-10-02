--!strict
-- WalkSpeedSystem
-- Per-frame walk speed lerp, strafe detection, stance-aware speed selection.
-- Update(dt) is called from RenderLoop.

local Constants   = require(script.Parent.Constants)
local SharedState = require(script.Parent.SharedState)
local StaminaSystem = require(script.Parent.Stamina)

local Stance     = Constants.Stance
local StanceName = Constants.StanceName

local WALK_SPEED_LERP_SPEED  = Constants.WALK_SPEED_LERP_SPEED
local STRAFE_DOT_THRESHOLD   = Constants.STRAFE_DOT_THRESHOLD

local config          = SharedState.config
local playerCharacter = SharedState.playerCharacter
local humanoid        = SharedState.humanoid

-- Reference to main script for speed attributes
local mainScript = script.Parent

local function LerpNumber(number: number, target: number, speed: number): number
	return number + (target - number) * speed
end

local function IsCharacterStrafing(character: Model): boolean
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart or not humanoidRootPart:IsA("BasePart") then
		return false
	end
	if SharedState.movementVector.Magnitude > 0 then
		local characterLookVector = humanoidRootPart.CFrame.LookVector
		local dotProduct = SharedState.movementVector:Dot(characterLookVector)
		return dotProduct < STRAFE_DOT_THRESHOLD
	end
	return false
end

local WalkSpeedSystem = {}

function WalkSpeedSystem.Update(dt: number): ()
	if not SharedState.canChangeWalkSpeed then return end

	local targetWalkSpeed = mainScript:GetAttribute("WalkSpeed") :: number
	local stanceAttr      = playerCharacter:GetAttribute("Stance")

	if stanceAttr == StanceName[Stance.Prone] then
		targetWalkSpeed = mainScript:GetAttribute("ProneSpeed") :: number
	elseif stanceAttr == StanceName[Stance.Crouched] then
		targetWalkSpeed = mainScript:GetAttribute("CrouchSpeed") :: number
	elseif playerCharacter:GetAttribute("Sprinting") == true then
		if not SharedState.strafing or (config.canSprintWhileStrafing and SharedState.strafing) then
			local baseSprintSpeed = mainScript:GetAttribute("SprintSpeed") :: number
			local baseWalkSpeed   = mainScript:GetAttribute("WalkSpeed") :: number
			targetWalkSpeed       = StaminaSystem.CalculateSprintSpeed(baseWalkSpeed, baseSprintSpeed)
		end
	end

	if humanoid.Health < 25 and config.lowHealthEffects then
		targetWalkSpeed = targetWalkSpeed * (humanoid.Health / 25)
	end

	SharedState.strafing = IsCharacterStrafing(playerCharacter)
	playerCharacter:SetAttribute("Strafing", SharedState.strafing)
	if SharedState.strafing then
		targetWalkSpeed = targetWalkSpeed * SharedState.strafingMult
	end

	humanoid.WalkSpeed = LerpNumber(
		humanoid.WalkSpeed,
		targetWalkSpeed,
		math.min(WALK_SPEED_LERP_SPEED * dt, 1)
	)
end

WalkSpeedSystem.IsCharacterStrafing = IsCharacterStrafing

return WalkSpeedSystem