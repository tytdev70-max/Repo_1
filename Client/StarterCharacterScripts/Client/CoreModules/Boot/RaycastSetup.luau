-- Bootstrap/RaycastSetup
-- Creates rayParams and wires CollectionService tag handling for SPH_NoCollide.

local CharacterRefs     = require(script.Parent.CharacterRefs)
local CameraSetup       = require(script.Parent.CameraSetup)
local ServiceRefs       = require(script.Parent.ServiceRefs)
local collectionService = ServiceRefs.collectionService

local character = CharacterRefs.character
local camera    = CameraSetup.camera

-- Shell folder (needed for exclusion list)
local sphWorkspace: Folder = workspace:WaitForChild("SPH_Workspace") :: Folder
local shellFolder: Folder  = sphWorkspace:WaitForChild("Shells")     :: Folder

local rayParams = RaycastParams.new()
rayParams.IgnoreWater         = true
rayParams.RespectCanCollide   = true
rayParams.FilterType          = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { character, camera, shellFolder }

-- Pre-populate existing tagged parts
for _, part in ipairs(collectionService:GetTagged("SPH_NoCollide")) do
	if part:IsA("BasePart") then
		table.insert(rayParams.FilterDescendantsInstances, part)
	end
end

-- Wire future additions
collectionService:GetInstanceAddedSignal("SPH_NoCollide"):Connect(function(newInstance: Instance)
	if newInstance:IsA("BasePart") then
		table.insert(rayParams.FilterDescendantsInstances, newInstance)
	end
end)

local RaycastSetup = {}
RaycastSetup.rayParams   = rayParams
RaycastSetup.shellFolder = shellFolder
RaycastSetup.sphWorkspace= sphWorkspace

return RaycastSetup