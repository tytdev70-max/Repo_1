--!strict
-- DeathHandler
-- humanoid.Died: unbind inputs, reset attributes, disable foot IK,
-- disconnect render loop, reset stamina.

local Constants      = require(script.Parent.Constants)
local SharedState    = require(script.Parent.SharedState)
local InputBindings  = require(script.Parent.InputBindings)
local FootIK         = require(script.Parent.FootIK)
local StaminaSystem  = require(script.Parent.Stamina)

local humanoid        = SharedState.humanoid
local playerCharacter = SharedState.playerCharacter

local DeathHandler = {}

function DeathHandler.init(): ()
	humanoid.Died:Connect(function(): ()
		InputBindings.UnbindCharacterInputs()
		playerCharacter:SetAttribute("LeanDirection",   0)
		playerCharacter:SetAttribute("Sprinting",       false)
		playerCharacter:SetAttribute("HoldingSprint",   false)
		
		StaminaSystem.Reset()

		local localLeanRefs = SharedState.localLeanRefs
		if localLeanRefs then
			FootIK.DisableFootIK(localLeanRefs, true)
		end

		if SharedState.renderSteppedConn then
			SharedState.renderSteppedConn:Disconnect()
		end
	end)
end

return DeathHandler