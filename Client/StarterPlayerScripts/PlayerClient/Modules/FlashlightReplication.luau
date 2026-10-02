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
local WeaponLighting    = require(modules.Weapons.Attachments.WeaponLighting)

--// State

local otherFlashlights: {
	[any]: { beam: any, endAtt: any, weaponStats: any }
} = {}

--// Private: Beam Update Loop

local function StartBeamUpdateLoop(): ()
	RunService.RenderStepped:Connect(function(): ()
		for attachment: any, data: { beam: any, endAtt: any, weaponStats: any } in pairs(otherFlashlights) do
			-- Prune destroyed attachments
			if not attachment.Parent then
				if data.beam and data.beam.Parent then
					data.beam:Destroy()
				end
				if data.endAtt and data.endAtt.Parent then
					data.endAtt:Destroy()
				end
				glareMod.SetFlashlightActive(attachment, false)
				otherFlashlights[attachment] = nil
				continue
			end

			if not data.beam.Enabled then continue end

			local rp: RaycastParams = RaycastParams.new()
			rp.FilterType                   = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances   = { attachment:FindFirstAncestorWhichIsA("Model") }
			rp.RespectCanCollide            = true

			data.weaponStats = data.weaponStats or WeaponLighting.GetStatsForSource(attachment)
			flashlightBeamMod.UpdateBeam(data.beam, attachment, data.endAtt, rp, data.weaponStats)
			glareMod.SetFlashlightActive(attachment, true, nil, data.weaponStats)
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

		local weaponStats = WeaponLighting.GetStatsForSource(attachment)
		flashlightBeamMod.SetEnabled(attachment, toggle, weaponStats)
		glareMod.SetFlashlightActive(
			attachment,
			toggle,
			glareMod.ResolveFlashlightColor(attachment, weaponStats),
			weaponStats
		)

		if toggle then
			if not otherFlashlights[attachment] then
				local beam: any, endAtt: any = flashlightBeamMod.CreateBeam(
					"OtherFlashlight_" .. attachment:GetFullName()
				)
				otherFlashlights[attachment] = { beam = beam, endAtt = endAtt, weaponStats = weaponStats }
			end
			otherFlashlights[attachment].beam.Enabled = true
		else
			local data: { beam: any, endAtt: any, weaponStats: any }? = otherFlashlights[attachment]
			if data then
				data.beam.Enabled = false
			end
		end
	end)

	-- Per-character cleanup: clear all beam state on respawn
	ServiceRefs.player.CharacterAdded:Connect(function(): ()
		for attachment, data: { beam: any, endAtt: any, weaponStats: any } in pairs(otherFlashlights) do
			glareMod.SetFlashlightActive(attachment, false)
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