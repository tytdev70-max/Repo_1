--// DoorShake.lua
--// Handles DoorCameraShakeEvent: looks up a named CameraShaker preset,
--// optionally scales its magnitude, then fires the shake.

local DoorShake = {}

local ServiceRefs           = require(script.Parent.ServiceRefs)
local CameraShakeController = require(script.Parent.CameraShakeController)

local doorCameraShakeEvent = ServiceRefs.doorCameraShakeEvent

--// Public

function DoorShake.Init(): ()
	doorCameraShakeEvent.OnClientEvent:Connect(
		function(presetName: string, magnitudeScale: number?): ()
			local ok: boolean, shakeInstance: any = pcall(function(): any
				return CameraShakeController.Presets[presetName]
			end)

			if not ok or not shakeInstance then
				warn("[Door] Unknown camera shake preset: " .. tostring(presetName))
				return
			end

			if magnitudeScale then
				shakeInstance:SetScaleMagnitude(magnitudeScale)
			end

			CameraShakeController.Shake(shakeInstance)
		end
	)
end

return DoorShake