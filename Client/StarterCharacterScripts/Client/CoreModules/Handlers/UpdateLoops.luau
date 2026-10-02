-- Handlers/UpdateLoops
-- Heartbeat and RenderStepped update loops for weaponFireMod and cameraViewmodelMod.
-- Also handles script.Destroying cleanup.

local ServiceRefs = require(script.Parent.Parent.Boot.ServiceRefs)
local SystemInits = require(script.Parent.Parent.ModuleInits.SystemModuleInits)

local runService       = ServiceRefs.runService
local weaponFireMod    = SystemInits.weaponFireMod
local cameraViewmodelMod = SystemInits.cameraViewmodelMod

local UpdateLoops = {}

function UpdateLoops.init(scriptRef: Script)
	local fireHeartbeatConn = runService.Heartbeat:Connect(function(dt: number)
		weaponFireMod.Update(dt)
	end)

	local viewmodelRenderConn = runService.RenderStepped:Connect(function(dt: number)
		cameraViewmodelMod.Update(dt)
	end)

	scriptRef.Destroying:Connect(function()
		if fireHeartbeatConn    then fireHeartbeatConn:Disconnect() end
		if viewmodelRenderConn  then viewmodelRenderConn:Disconnect() end
	end)
end

return UpdateLoops