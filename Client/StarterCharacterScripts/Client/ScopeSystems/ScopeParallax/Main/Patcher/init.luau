--!strict

--// Types
type PatcherMethodModule = {
	aimpartZOffset: number,
	autoDetectMethod: () -> string?,
	modelDetectionPath: () -> Instance,
	modelDetectionMethod: (obj: Instance) -> Model?,
	parentingMethod: (scopeFocusPart: Instance) -> (),
}

type ConnectionState = {
	childAdded: RBXScriptConnection?,
	childRemoved: RBXScriptConnection?,
}

--// Modules
local Activate = require(script.Parent:WaitForChild("Activate"))

--// Constants
local DEFAULT_METHOD_NAME = "Default"

--// Functions
local function noopParentingMethod(_scopeFocusPart: Instance) end

local Patcher = {}

--// State
Patcher.modelDetectionMethod = nil :: ((obj: Instance) -> Model?)?
Patcher.modelDetectionPath = nil :: Instance?
Patcher.connections = {
	childAdded = nil,
	childRemoved = nil,
} :: ConnectionState
Patcher.parentingMethod = noopParentingMethod :: (scopeFocusPart: Instance) -> ()
Patcher.aimpartZOffset = 0.5
Patcher.currentRootModel = nil :: Instance?
Patcher.cleanupParts = {} :: { Instance }
Patcher.interval = 0
Patcher.timeout = 100

--// Functions
function Patcher.init()
	Patcher.update(DEFAULT_METHOD_NAME)
end

function Patcher.update(method: string)
	local moduleScript = script:FindFirstChild(method)
	if not moduleScript then
		warn(("[ScopeParallax] Unknown patch method \"%s\""):format(method))
		return
	end

	local detectionModule = require(moduleScript) :: PatcherMethodModule

	if Patcher.connections.childAdded then
		Patcher.connections.childAdded:Disconnect()
	end
	if Patcher.connections.childRemoved then
		Patcher.connections.childRemoved:Disconnect()
	end

	local detectionPath = detectionModule.modelDetectionPath()

	Patcher.modelDetectionPath = detectionPath
	Patcher.modelDetectionMethod = detectionModule.modelDetectionMethod
	Patcher.parentingMethod = detectionModule.parentingMethod
	Patcher.aimpartZOffset = detectionModule.aimpartZOffset

	Patcher.connections.childAdded = detectionPath.ChildAdded:Connect(Patcher.onChildAdded)
	Patcher.connections.childRemoved = detectionPath.ChildRemoved:Connect(Patcher.onChildRemoved)
end

function Patcher.onChildAdded(obj: Instance)
	local gunModel: Model? = nil

	for _ = 1, Patcher.timeout do
		if Patcher.modelDetectionMethod then
			gunModel = Patcher.modelDetectionMethod(obj)
		end

		if gunModel then
			break
		end

		task.wait(Patcher.interval)
	end

	if gunModel then
		Patcher.currentRootModel = obj
		Patcher.cleanupParts = {}
		Patcher.cleanupParts = Activate.start(gunModel, Patcher)
	end
end

function Patcher.onChildRemoved(obj: Instance)
	if obj == Patcher.currentRootModel then
		Activate.stop(true)
		for _, part in Patcher.cleanupParts do
			part:Destroy()
		end
		Patcher.cleanupParts = {}
		Patcher.currentRootModel = nil
	end
end

return Patcher