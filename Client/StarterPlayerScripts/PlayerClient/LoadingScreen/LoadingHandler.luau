local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local ClientLoadingController = require(ReplicatedStorage.SPH_Assets.Modules.Misc.LoadingScreen.ClientLoadingController)

--// Task Registry

local CRITICAL_TASK_FACTORIES = {
	ClientLoadingController.MakeCharacterReadyTask,
}

local function BuildRespawnCriticalTasks()
	local tasks = table.create(#CRITICAL_TASK_FACTORIES)
	for _, makeTask in ipairs(CRITICAL_TASK_FACTORIES) do
		tasks[#tasks + 1] = makeTask()
	end
	return tasks
end

local function OnCharacterAdded()
	ClientLoadingController.BeginCriticalLoading(BuildRespawnCriticalTasks())
	ClientLoadingController.WatchForStreamedInBackgroundAssets()
end

LocalPlayer.CharacterAdded:Connect(OnCharacterAdded)
if LocalPlayer.Character then
	OnCharacterAdded()
end

return true