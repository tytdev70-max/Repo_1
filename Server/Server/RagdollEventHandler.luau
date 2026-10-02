-- RagdollEventHandler
-- ragdollEvent / unragdollEvent server forwarding.

local AssetRefs = require(script.Parent.AssetRefs)
local EventRefs = require(script.Parent.EventRefs)

local config         = AssetRefs.config
local ragdollEvent   = EventRefs.ragdollEvent
local unragdollEvent = EventRefs.unragdollEvent

local RagdollEventHandler = {}

function RagdollEventHandler.init()
	ragdollEvent.OnServerEvent:Connect(function(plr, dropWeapon)
		if not config.ragdollAllowManualToggle then return end
		local character = plr.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		ragdollEvent:FireAllClients(character, dropWeapon == true)
	end)

	unragdollEvent.OnServerEvent:Connect(function(plr)
		if not config.ragdollAllowManualToggle then return end
		local character = plr.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		unragdollEvent:FireAllClients(character)
	end)
end

return RagdollEventHandler