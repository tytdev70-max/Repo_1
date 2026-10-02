--// KillFeedHandler.lua
--// Listens to the KillFeed remote event and delegates to WeaponModule
--// (KillFeedModule) exactly as in the original script.

local KillFeedHandler = {}

local ServiceRefs    = require(script.Parent.ServiceRefs)
local player         : Player = ServiceRefs.player
local killFeedRemote           = ServiceRefs.killFeedRemote
local modules                  = ServiceRefs.modules

local WeaponModule = require(modules.Misc.KillFeed.KillFeedModule)

--// Public

function KillFeedHandler.Init(): ()
	killFeedRemote.OnClientEvent:Connect(function(target: any): ()
		WeaponModule.KillFeed(player, target)
	end)
end

return KillFeedHandler