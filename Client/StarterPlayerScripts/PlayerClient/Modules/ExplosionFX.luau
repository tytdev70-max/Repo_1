--// ExplosionFX.lua
--// Handles the ExplosionFXRemote OnClientEvent:
--//   • Spawns a positional explosion sound part
--//   • Triggers ring audio + hearing muffle
--//   • Applies camera shake scaled by distance
--// Identical logic to the original explosionRemote handler.

local ExplosionFX = {}

local ServiceRefs           = require(script.Parent.ServiceRefs)
local RingAudio             = require(script.Parent.RingAudio)
local CameraShakeController = require(script.Parent.CameraShakeController)

local Debris               = ServiceRefs.Debris
local HearingMuffleMod     = require(ServiceRefs.modules.Systems.HearingMuffleMod)
local explosionRemote      = ServiceRefs.explosionRemote

local MAX_SHAKE_DISTANCE : number = 50

--// Public

function ExplosionFX.Init(): ()
	explosionRemote.OnClientEvent:Connect(function(payload: any): ()
		if type(payload) ~= "table" then return end
		if payload.isSmoke then return end

		local audioIntensity: number = tonumber(payload.audioIntensity) or 0.5

		-- Positional explosion sound
		if payload.explosionSoundId and payload.origin then
			local soundPart: Part = Instance.new("Part")
			soundPart.Anchored     = true
			soundPart.CanCollide   = false
			soundPart.Transparency = 1
			soundPart.Size         = Vector3.new(1, 1, 1)
			soundPart.CFrame       = CFrame.new(payload.origin)
			soundPart.Parent       = workspace

			local snd: Sound = Instance.new("Sound")
			snd.SoundId              = "rbxassetid://" .. tostring(payload.explosionSoundId)
			snd.Volume               = payload.explosionSoundVolume or 5
			snd.RollOffMode          = Enum.RollOffMode.Linear
			snd.RollOffMinDistance   = 10
			snd.RollOffMaxDistance   = 2000
			snd.Parent               = soundPart
			snd:Play()
			Debris:AddItem(soundPart, 10)
		end

		local flashbangWillOwnMuffle: boolean = payload.isFlashbang == true
			and type(payload.flashIntensity) == "number"
			and payload.flashIntensity > 0

		local effectiveIntensity: number = audioIntensity
		if payload.isFlashbang
			and payload.flashIntensity ~= nil
			and effectiveIntensity <= 0.15
		then
			effectiveIntensity = 0.2
		end

		if effectiveIntensity > 0.15 then
			local preset = RingAudio.GetMufflePreset(payload.explosionType)

			local muffleDuration: number? = payload.isFlashbang and payload.flashDuration or nil
			if not muffleDuration then
				muffleDuration = math.clamp(
					preset.minDuration + (preset.maxDuration - preset.minDuration) * effectiveIntensity,
					preset.minDuration, preset.maxDuration
				)
			end

			RingAudio.PlayLocalRingSound(payload.ringId, effectiveIntensity, muffleDuration)

			if not flashbangWillOwnMuffle then
				pcall(function(): ()
					HearingMuffleMod.PulseMuffle(
						math.clamp(effectiveIntensity * preset.strength, 0, 1),
						muffleDuration
					)
				end)
			end
		end

		-- Camera shake (non-flashbang only)
		if not payload.isFlashbang and not payload.skipCameraShake then
			if payload.distance and payload.distance <= MAX_SHAKE_DISTANCE then
				local scale: number = math.clamp(1 - (payload.distance / MAX_SHAKE_DISTANCE), 0, 1)
				local shakeInstance: any = CameraShakeController.Presets.Explosion
				shakeInstance.magnMod = scale
				CameraShakeController.Shake(shakeInstance)
			end
		end
	end)
end

return ExplosionFX