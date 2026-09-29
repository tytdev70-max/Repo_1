--// FlashlightReplication.lua
--// Handles ToggleAttachmentReplicate for Flashlight attachments:
--// enables/disables beam + glare, manages per-attachment beam instances,
--// and updates beam geometry each RenderStep via raycasting.

local FlashlightReplication = {}

local ServiceRefs       = require(script.Parent.ServiceRefs)
local RunService        = ServiceRefs.RunService
local modules           = ServiceRefs.modules

local Network           = require(modules.Core.Networking.SPH_Network)
local flashlightBeamMod = require(modules.Weapons.Attachments.FlashlightBeamMod)
local glareMod          = require(modules.Weapons.Attachments.GlareMod)

--// State

local otherFlashlights: {
	[any]: { beam: any, endAtt: any }
} = {}

--// Private: Beam Update Loop

local function StartBeamUpdateLoop(): ()
	RunService.RenderStepped:Connect(function(): ()
		for attachment: any, data: { beam: any, endAtt: any } in pairs(otherFlashlights) do
			-- Prune destroyed attachments
			if not attachment.Parent then
				if data.beam and data.beam.Parent then
					data.beam:Destroy()
				end
				if data.endAtt and data.endAtt.Parent then
					data.endAtt:Destroy()
				end
				otherFlashlights[attachment] = nil
				continue
			end

			if not data.beam.Enabled then continue end

			local rp: RaycastParams = RaycastParams.new()
			rp.FilterType                   = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances   = { attachment:FindFirstAncestorWhichIsA("Model") }
			rp.RespectCanCollide            = true

			flashlightBeamMod.UpdateBeam(data.beam, attachment, data.endAtt, rp)
		end
	end)
end

--// Public

function FlashlightReplication.Init(): ()
	-- Toggle handler
	Network.packets.ToggleAttachmentReplicate.listen(function(Data: any): ()
		local attachment: any    = Data.LaserPart
		local toggle    : boolean = Data.Toggle

		if not attachment or attachment.Name ~= "Flashlight" then return end

		flashlightBeamMod.SetEnabled(attachment, toggle)
		glareMod.SetFlashlightActive(
			attachment,
			toggle,
			glareMod.ResolveFlashlightColor(attachment)
		)

		if toggle then
			if not otherFlashlights[attachment] then
				local beam: any, endAtt: any = flashlightBeamMod.CreateBeam(
					"OtherFlashlight_" .. attachment:GetFullName()
				)
				otherFlashlights[attachment] = { beam = beam, endAtt = endAtt }
			end
			otherFlashlights[attachment].beam.Enabled = true
		else
			local data: { beam: any, endAtt: any }? = otherFlashlights[attachment]
			if data then
				data.beam.Enabled = false
			end
		end
	end)

	-- Per-character cleanup: clear all beam state on respawn
	ServiceRefs.player.CharacterAdded:Connect(function(): ()
		for _, data: { beam: any, endAtt: any } in pairs(otherFlashlights) do
			if data.beam and data.beam.Parent then
				data.beam:Destroy()
			end
			if data.endAtt and data.endAtt.Parent then
				data.endAtt:Destroy()
			end
		end
		otherFlashlights = {}
	end)

	-- Start the continuous render loop
	StartBeamUpdateLoop()
end

return FlashlightReplication