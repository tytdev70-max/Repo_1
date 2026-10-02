-- Handlers/JumpHandler
-- JumpRequest handling with cooldown and stance guard.

local CharacterRefs = require(script.Parent.Parent.Boot.CharacterRefs)
local StateInit     = require(script.Parent.Parent.Boot.StateInit)
local ServiceRefs   = require(script.Parent.Parent.Boot.ServiceRefs)

local character        = CharacterRefs.character
local humanoid         = CharacterRefs.humanoid
local config           = StateInit.config
local userInputService = ServiceRefs.userInputService

local JumpHandler = {}

function JumpHandler.init()
	local canJump: boolean = true
	character:SetAttribute("ClientCanJump", canJump)
	character.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

	userInputService.JumpRequest:Connect(function()
		if character.Humanoid.Sit then
			character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			return
		end

		local isStanding  = character:GetAttribute("Stance") == "Standing"
		local isNotInAir  = character.Humanoid.FloorMaterial ~= Enum.Material.Air

		if isStanding and isNotInAir and canJump then
			canJump = false
			character:SetAttribute("ClientCanJump", false)
			character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			task.wait(config.jumpCooldown)
			canJump = true
			character:SetAttribute("ClientCanJump", true)
		else
			character.Humanoid.Jump = false
		end
	end)
end

return JumpHandler