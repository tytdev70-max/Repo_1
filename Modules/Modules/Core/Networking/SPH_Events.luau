--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SPH_Events = {}

local assets = ReplicatedStorage:WaitForChild("SPH_Assets") :: Folder
local eventsRoot = assets:WaitForChild("Events") :: Folder

SPH_Events.Root = eventsRoot

local IS_SERVER = RunService:IsServer()

local LOCAL_EVENT_CLASSES: {[string]: boolean} = {
	BindableEvent = true,
	BindableFunction = true,
}

local folderCache: {[string]: Folder} = {}

local function getFolder(folderName: string): Folder
	local cached = folderCache[folderName]
	if cached and cached.Parent then
		return cached
	end
	local folder = eventsRoot:WaitForChild(folderName, 30) :: Folder
	folderCache[folderName] = folder
	return folder
end

function SPH_Events.Get(folderName: string, eventName: string, timeout: number?): Instance?
	local folder = getFolder(folderName)
	if not folder then return nil end
	return folder:WaitForChild(eventName, timeout) :: Instance?
end

function SPH_Events.Find(folderName: string, eventName: string): Instance?
	local folder = eventsRoot:FindFirstChild(folderName)
	if not folder then return nil end
	return folder:FindFirstChild(eventName)
end

function SPH_Events.WaitFor(folderName: string, eventName: string, timeout: number?): Instance?
	local folder = eventsRoot:WaitForChild(folderName, timeout) :: Folder?
	if not folder then return nil end
	return folder:WaitForChild(eventName, timeout) :: Instance?
end

function SPH_Events.GetOrCreate(folderName: string, eventName: string, className: string): Instance
	local folder = getFolder(folderName)
	local existing = folder:FindFirstChild(eventName)
	if existing then return existing end

	local isLocalClass = LOCAL_EVENT_CLASSES[className] == true
	if not isLocalClass and not IS_SERVER then
		local waited = folder:WaitForChild(eventName, 15) :: Instance?
		if waited then return waited end
		error(("[SPH_Events] Client attempted to create remote '%s.%s' (%s) that the server never registered.")
			:format(folderName, eventName, className))
	end

	local created = Instance.new(className)
	created.Name = eventName
	created.Parent = folder
	return created
end

return SPH_Events