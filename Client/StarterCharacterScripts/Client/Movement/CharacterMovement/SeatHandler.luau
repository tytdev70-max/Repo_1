--!strict
-- SeatHandler
-- humanoid.Seated connection: unbind/rebind inputs, reset lean and sprint,
-- force-stand from crouched or prone when sitting.

local Constants      = require(script.Parent.Constants)
local SharedState    = require(script.Parent.SharedState)
local InputBindings  = require(script.Parent.InputBindings)
local SprintSystem   = require(script.Parent.SprintSystem)
local LeanSystem     = require(script.Parent.LeanSystem)
local StanceSystem   = require(script.Parent.StanceSystem)

local Stance         = Constants.Stance
local StanceName     = Constants.StanceName
local humanoid       = SharedState.humanoid
local playerCharacter= SharedState.playerCharacter

local SeatHandler = {}

function SeatHandler.init(): ()
	humanoid.Seated:Connect(function(seated: boolean, seatPart: BasePart?): ()
		if seated then
			InputBindings.UnbindCharacterInputs()
			SprintSystem.ToggleSprint(false)
			LeanSystem.ChangeLean(0)
			local currentStance = playerCharacter:GetAttribute("Stance")
			if currentStance == StanceName[Stance.Crouched] then
				StanceSystem.ChangeStance(-1, true)
			elseif currentStance == StanceName[Stance.Prone] then
				StanceSystem.ChangeStance(-1, true)
				StanceSystem.ChangeStance(-1, true)
			end
		else
			InputBindings.BindCharacterInputs()
		end
	end)
end

return SeatHandler