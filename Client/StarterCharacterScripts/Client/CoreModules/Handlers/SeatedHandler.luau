-- Handlers/SeatedHandler
-- humanoid.Seated: vehicle seat detection and unequip.

local CharacterRefs = require(script.Parent.Parent.Boot.CharacterRefs)
local StateInit     = require(script.Parent.Parent.Boot.StateInit)

local humanoid = CharacterRefs.humanoid
local vars     = StateInit.vars
local config   = StateInit.config

local SeatedHandler = {}

function SeatedHandler.init()
	humanoid.Seated:Connect(function(seated: boolean, seatPart: BasePart?)
		if seated then
			if seatPart and seatPart:IsA("VehicleSeat") and not config.canEquipInVehicleSeat then
				vars.vehicleSeated = true
				if vars.equipped then humanoid:UnequipTools() end
			else
				vars.vehicleSeated = false
			end
		else
			vars.vehicleSeated = false
		end
	end)
end

return SeatedHandler