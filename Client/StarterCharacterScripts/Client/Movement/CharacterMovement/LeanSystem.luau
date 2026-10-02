--!strict
-- LeanSystem
-- ChangeLean: updates LeanDirection attribute and replicates to server.
-- PlayCharSound: fires the PlayCharacterSound RemoteEvent.

local SharedState = require(script.Parent.SharedState)

local playerCharacter       = SharedState.playerCharacter
local humanoid              = SharedState.humanoid
local playCharacterSoundEvent = SharedState.playCharacterSoundEvent
local config                = SharedState.config
local networkingModules     = SharedState.networkingModules

local Network = require(networkingModules:WaitForChild("SPH_Network") :: ModuleScript) :: any

local LeanSystem = {}

function LeanSystem.PlayCharSound(soundName: string): ()
	playCharacterSoundEvent:FireServer(soundName)
end

function LeanSystem.ChangeLean(newLean: number): ()
	local lean = playerCharacter:GetAttribute("LeanDirection")
	if not config.canLean then return end
	if not humanoid or humanoid.Health <= 0 then return end
	if newLean ~= lean then
		LeanSystem.PlayCharSound("Lean")
	end
	lean = newLean
	playerCharacter:SetAttribute("LeanDirection", lean)
	Network.packets.PlayerLeanRequest.send(newLean)
end

return LeanSystem