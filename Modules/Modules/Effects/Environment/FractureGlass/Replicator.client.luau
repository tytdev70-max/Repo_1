local SPH_Events = require(game.ReplicatedStorage.SPH_Assets.Modules.Core.Networking.SPH_Events)
local module = require(script.Parent)
local renderGlass = SPH_Events.Get("EnvironmentEvents", "RenderGlass")

renderGlass.OnClientEvent:Connect(function(part, origin, force)
	module(part, origin, force, true)
end)