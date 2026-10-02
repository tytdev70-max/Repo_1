-- Bootstrap/CameraSetup
-- Camera initialization: subject, type, cleanup, DOF effects.
-- Returns camera and effect references.

local CharacterRefs = require(script.Parent.CharacterRefs)
local AssetRefs     = require(script.Parent.AssetRefs)
local humanoid      = CharacterRefs.humanoid

local CameraSetup = {}

local camera: Camera = workspace.CurrentCamera :: Camera

if camera.CameraSubject ~= humanoid then
	camera.CameraSubject = humanoid
end
camera.CameraType = Enum.CameraType.Custom

if camera:FindFirstChild("WeaponRig") then
	camera.WeaponRig:Destroy()
end

CameraSetup.camera = camera

-- DOF Effects
CameraSetup.aimDoF     = game.Lighting:FindFirstChild("AimDOF")     :: DepthOfFieldEffect?
CameraSetup.inspectDoF = game.Lighting:FindFirstChild("InspectDOF") :: DepthOfFieldEffect?

return CameraSetup