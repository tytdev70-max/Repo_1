--// MagGrabReplication.lua
--// Handles Network packet ReplicateMagGrab: makes the dropped mag part
--// visible to the local client by zeroing LocalTransparencyModifier.

local MagGrabReplication = {}

local ServiceRefs = require(script.Parent.ServiceRefs)
local modules           = ServiceRefs.modules
local Network           = require(modules.Core.Networking.SPH_Network)

--// Public

function MagGrabReplication.Init(): ()
	Network.packets.ReplicateMagGrab.listen(function(Data: any): ()
		local magPart: any = Data.MagPart
		if not magPart then return end

		magPart.LocalTransparencyModifier = 0
		for _, part: Instance in ipairs(magPart:GetDescendants()) do
			if part:IsA("BasePart") then
				(part :: BasePart).LocalTransparencyModifier = 0
			end
		end
	end)
end

return MagGrabReplication