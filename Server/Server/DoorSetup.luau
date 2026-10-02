-- DoorSetup
-- Door collection tag setup, teardown, and day/night cycle start.

local ServiceRefs = require(script.Parent.ServiceRefs)
local AssetRefs   = require(script.Parent.AssetRefs)
local Constants   = require(script.Parent.Constants)
local ServerState = require(script.Parent.ServerState)

local collectionService = ServiceRefs.collectionService
local DoorController    = AssetRefs.DoorController
local DayNightCycle     = AssetRefs.DayNightCycle
local config            = AssetRefs.config

local DOOR_TAG    = Constants.DOOR_TAG
local activeDoors = ServerState.activeDoors

local DoorSetup = {}

local function setupDoor(model)
	if activeDoors[model] then return end
	local ok, controllerOrErr = pcall(DoorController.new, model)
	if ok then
		activeDoors[model] = controllerOrErr
	else
		warn(("[DoorService] Failed to set up %s: %s"):format(
			model:GetFullName(), tostring(controllerOrErr)))
	end
end

local function teardownDoor(model)
	local controller = activeDoors[model]
	if controller then
		controller:Destroy()
		activeDoors[model] = nil
	end
end

function DoorSetup.init()
	for _, model in ipairs(collectionService:GetTagged(DOOR_TAG)) do
		task.spawn(setupDoor, model)
	end
	collectionService:GetInstanceAddedSignal(DOOR_TAG):Connect(setupDoor)
	collectionService:GetInstanceRemovedSignal(DOOR_TAG):Connect(teardownDoor)

	if config.dayNightCycle then
		DayNightCycle.Start(config)
	end
end

return DoorSetup