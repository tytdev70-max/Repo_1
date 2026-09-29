local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer

local ClientLoadingController = {}

type Callback = (...any) -> ()

local function CreateSignal()
	local connections: {[number]: Callback} = {}
	local nextId = 0
	local signal = {}

	function signal.Connect(_, fn: Callback)
		nextId += 1
		local id = nextId
		connections[id] = fn
		return {
			Disconnect = function()
				connections[id] = nil
			end,
		}
	end

	function signal.Fire(_, ...)
		for _, fn in connections do
			task.spawn(fn, ...)
		end
	end

	return signal
end

local CRITICAL_TIMEOUT_DEFAULT = 8
local ASSET_PRELOAD_TIMEOUT = 5
local BACKGROUND_BATCH_SIZE = 8
local TIMEOUT_POLL_INTERVAL = 0.05

local State = {
	RequestedAssets = {} :: {[string]: boolean},
	CriticalTasks = {} :: {[string]: {Done: boolean, Failed: boolean}},
	CriticalTotal = 0,
	CriticalDone = 0,
	BackgroundTotal = 0,
	BackgroundDone = 0,
	Generation = 0,
	StreamingWatcherConnected = false,
}

ClientLoadingController.CriticalProgressChanged = CreateSignal() 
ClientLoadingController.CriticalReady = CreateSignal()
ClientLoadingController.BackgroundProgressChanged = CreateSignal()

local function RunWithTimeout(timeoutSeconds: number, workFn: () -> ()): (boolean, any)
	local completed = false
	local success, result

	local thread = task.spawn(function()
		success, result = pcall(workFn)
		completed = true
	end)

	local elapsed = 0
	while not completed and elapsed < timeoutSeconds do
		task.wait(TIMEOUT_POLL_INTERVAL)
		elapsed += TIMEOUT_POLL_INTERVAL
	end

	if not completed then
		task.cancel(thread)
		return false, "timeout"
	end

	if not success then
		return false, result
	end

	return true, result
end

local BackgroundClassNames = {
	MeshPart = true,
	SpecialMesh = true,
	Decal = true,
	Texture = true,
	Sound = true,
	ParticleEmitter = true,
}
ClientLoadingController.BackgroundClassNames = BackgroundClassNames

local function GetContentId(inst: Instance): string?
	if inst:IsA("Decal") or inst:IsA("Texture") then
		return inst.ColorMapContent
	elseif inst:IsA("MeshPart") then
		return inst.MeshContent
	elseif inst:IsA("SpecialMesh") then
		return inst.MeshId
	elseif inst:IsA("Sound") then
		return inst.SoundId
	elseif inst:IsA("ParticleEmitter") then
		return inst.Texture
	end
	return nil
end
ClientLoadingController.GetContentId = GetContentId

function ClientLoadingController.BeginCriticalLoading(taskList: {any})
	State.Generation += 1
	local generation = State.Generation

	State.CriticalTasks = {}
	State.CriticalTotal = #taskList
	State.CriticalDone = 0

	if State.CriticalTotal == 0 then
		ClientLoadingController.CriticalReady:Fire()
		return
	end

	for _, taskDef in taskList do
		State.CriticalTasks[taskDef.Name] = {Done = false, Failed = false}

		task.spawn(function()
			local ok, err = RunWithTimeout(taskDef.Timeout or CRITICAL_TIMEOUT_DEFAULT, taskDef.Run)

			if generation ~= State.Generation then
				return
			end

			local rec = State.CriticalTasks[taskDef.Name]
			if not rec or rec.Done then
				return
			end
			rec.Done = true
			rec.Failed = not ok

			if not ok then
				warn(("[ClientLoadingController] Critical task '%s' did not complete (%s) - continuing without blocking further."):format(taskDef.Name, tostring(err)))
			end

			State.CriticalDone += 1
			ClientLoadingController.CriticalProgressChanged:Fire(State.CriticalDone, State.CriticalTotal)

			if State.CriticalDone >= State.CriticalTotal then
				ClientLoadingController.CriticalReady:Fire()
			end
		end)
	end
end

function ClientLoadingController.WaitForCriticalReady()
	if State.CriticalTotal > 0 and State.CriticalDone >= State.CriticalTotal then
		return
	end
	local done = false
	local conn = ClientLoadingController.CriticalReady:Connect(function()
		done = true
	end)
	while not done do
		task.wait(TIMEOUT_POLL_INTERVAL)
	end
	conn.Disconnect()
end

function ClientLoadingController.GetCriticalCounts(): (number, number)
	return State.CriticalDone, State.CriticalTotal
end

function ClientLoadingController.MakeCharacterReadyTask(timeout: number?)
	return {
		Name = "Character",
		Timeout = timeout or 15,
		Run = function()
			local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
			local humanoid = character:WaitForChild("Humanoid", 10)
			local rootPart = character:WaitForChild("HumanoidRootPart", 10)
			if not humanoid or not rootPart then
				error("character parts (Humanoid/HumanoidRootPart) did not appear in time")
			end

			if workspace.StreamingEnabled then
				pcall(function()
					LocalPlayer:RequestStreamAroundAsync(rootPart.Position, 8)
				end)
			end
		end,
	}
end

function ClientLoadingController.MakeModuleReadyTask(name: string, moduleInstance: Instance, timeout: number?)
	return {
		Name = name,
		Timeout = timeout or CRITICAL_TIMEOUT_DEFAULT,
		Run = function()
			require(moduleInstance)
		end,
	}
end

function ClientLoadingController.MakeInstanceReadyTask(name: string, parent: Instance, childName: string, timeout: number?)
	local t = timeout or CRITICAL_TIMEOUT_DEFAULT
	return {
		Name = name,
		Timeout = t,
		Run = function()
			local inst = parent:WaitForChild(childName, t)
			if not inst then
				error(("'%s' did not appear under %s"):format(childName, parent:GetFullName()))
			end
		end,
	}
end

function ClientLoadingController.MakeAssetsReadyTask(name: string, instances: {Instance}, timeout: number?)
	return {
		Name = name,
		Timeout = timeout or CRITICAL_TIMEOUT_DEFAULT,
		Run = function()
			local toLoad = {}
			for _, inst in instances do
				local ok, contentId = pcall(GetContentId, inst)
				if ok and typeof(contentId) == "string" and contentId ~= "" then
					if not State.RequestedAssets[contentId] then
						State.RequestedAssets[contentId] = true
						toLoad[#toLoad + 1] = inst
					end
				end
			end
			if #toLoad > 0 then
				ContentProvider:PreloadAsync(toLoad)
			end
		end,
	}
end

function ClientLoadingController.CollectBackgroundInstances(root: Instance): {Instance}
	local results = {}
	for _, inst in root:GetDescendants() do
		if not BackgroundClassNames[inst.ClassName] then
			continue
		end
		local ok, contentId = pcall(GetContentId, inst)
		if ok and typeof(contentId) == "string" and contentId ~= "" then
			results[#results + 1] = inst
		end
	end
	return results
end

function ClientLoadingController.PreloadInBackground(instances: {Instance})
	local toLoad = {}
	for _, inst in instances do
		local ok, contentId = pcall(GetContentId, inst)
		if ok and typeof(contentId) == "string" and contentId ~= "" then
			if not State.RequestedAssets[contentId] then
				State.RequestedAssets[contentId] = true
				toLoad[#toLoad + 1] = inst
			end
		end
	end

	if #toLoad == 0 then
		return
	end

	State.BackgroundTotal += #toLoad

	task.spawn(function()
		local index = 1
		local total = #toLoad
		while index <= total do
			local batch = {}
			for i = index, math.min(index + BACKGROUND_BATCH_SIZE - 1, total) do
				batch[#batch + 1] = toLoad[i]
			end

			RunWithTimeout(ASSET_PRELOAD_TIMEOUT, function()
				ContentProvider:PreloadAsync(batch)
			end)

			State.BackgroundDone += #batch
			ClientLoadingController.BackgroundProgressChanged:Fire(State.BackgroundDone, State.BackgroundTotal)

			index += BACKGROUND_BATCH_SIZE
			task.wait()
		end
	end)
end

function ClientLoadingController.WatchForStreamedInBackgroundAssets()
	if State.StreamingWatcherConnected then
		return
	end
	State.StreamingWatcherConnected = true
	workspace.DescendantAdded:Connect(function(inst)
		if BackgroundClassNames[inst.ClassName] then
			ClientLoadingController.PreloadInBackground({inst})
		end
	end)
end

return ClientLoadingController