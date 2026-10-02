--// CameraShakeController.lua
--// Creates and starts the CameraShaker instance used by ExplosionFX,
--// DoorShake, and any other system that needs camera shake.
--// Exposes the live `camShake` handle and the upstream Presets table.

local CameraShakeController = {}

local ServiceRefs  = require(script.Parent.ServiceRefs)
local CameraShaker = require(ServiceRefs.modules.ThirdParty.CameraShaker)

local camera: Camera = ServiceRefs.camera

--// Build the shaker bound to Camera render priority

local camShake: any = CameraShaker.new(
	Enum.RenderPriority.Camera.Value,
	function(shakeCf: CFrame): ()
		camera.CFrame = camera.CFrame * shakeCf
	end
)
camShake:Start()

--// Public

CameraShakeController.camShake = camShake
CameraShakeController.Presets  = CameraShaker.Presets

--- Convenience wrapper so callers don't need to hold camShake directly.
function CameraShakeController.Shake(preset: any): ()
	camShake:Shake(preset)
end

return CameraShakeController