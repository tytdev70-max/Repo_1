--!strict

--// Modules
local PatcherScript = script.Parent:WaitForChild("Patcher")
local Patcher = require(PatcherScript)

local Detect = {}

Detect.timeout = 5

--// Functions
function Detect.init()
	local elapsed = 0
	local autoDetectMethods: { () -> string? } = {}

	for _, moduleScript in PatcherScript:GetChildren() do
		if moduleScript:IsA("ModuleScript") then
			local method = require(moduleScript) :: { autoDetectMethod: () -> string? }
			table.insert(autoDetectMethods, method.autoDetectMethod)
		end
	end

	task.spawn(function()
		while elapsed < Detect.timeout do
			elapsed += task.wait()

			for _, autoDetect in autoDetectMethods do
				local matchedMethod = autoDetect()
				if matchedMethod then
					Patcher.update(matchedMethod)
					return
				end
			end
		end
	end)
end

return Detect