--!strict

--[[
	SPH_ClientPacketRefs

	Usage in Client:
		local PacketRefs = require(modules.Core.Networking.SPH_ClientPacketRefs)
		PacketRefs.playerFire:FireServer(...)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local modules = ReplicatedStorage:WaitForChild("SPH_Assets"):WaitForChild("Modules")
local Network = require(modules.Core.Networking.SPH_Network)

return {
	bodyAnimRequest = Network.packets.BodyAnimRequest,
	switchWeapon = Network.packets.SwitchWeaponRequest,
	playerFire = Network.packets.PlayerFire,
	playSound = Network.packets.PlaySoundRequest,
	repReload = Network.packets.ReloadRequest,
	repChamber = Network.packets.PlayerChamberRequest,
	moveBolt = Network.packets.MoveBoltRequest,
	switchFireMode = Network.packets.SwitchFireModeRequest,
	playerDropGun = Network.packets.PlayerDropGunRequest,
	playerToggleAttachment = Network.packets.PlayerToggleAttachmentRequest,
	playerAimStateRequest = Network.packets.PlayerAimStateRequest,
	repAimStateReplicate = Network.packets.AimStateReplicate,
	repBoltOpen = Network.packets.RepBoltOpenRequest,
	repChamberSmoke = Network.packets.ReplicateChamberSmokeRequest,
	repOverheat = Network.packets.ReplicateOverheatRequest,
	repLPVORing = Network.packets.ReplicateLPVORingRequest,
	repMagGrab = Network.packets.ReplicateMagGrab,
	repMagEject = Network.packets.ReplicateMagEjectRequest,
	repBolt = Network.packets.ReplicateBolt,
	repGripHand = Network.packets.ReplicateGripHandRequest,
	repPartVisibilityRequest = Network.packets.PartVisibilityRequest,
	repPartVisibilityReplicate = Network.packets.PartVisibilityReplicate,
	repToggleAttachment = Network.packets.ToggleAttachmentReplicate,
	repShellEjectRequest = Network.packets.ShellEjectRequest,
	repShellEjectReplicate = Network.packets.ShellEjectReplicate,
	repLeanReplicate = Network.packets.ReplicateLean,
	magGrab = Network.packets.MagGrabRequest,
}