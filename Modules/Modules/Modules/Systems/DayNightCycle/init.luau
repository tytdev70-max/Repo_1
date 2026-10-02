

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local DayNightCycle = {}

local connection: RBXScriptConnection? = nil

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function smoothstep(x)
	x = clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

function DayNightCycle.Start(config)
	if connection then
		warn("[DayNightCycle] Start() called while already running - ignoring.")
		return
	end

	local presets = config.dayNightPresets
	local dayLength = config.dayLengthSeconds
	local transitionHours = config.dayNightTransitionHours
	local updateInterval = config.dayNightUpdateInterval
	local soundSmooth = config.ambienceSoundSmoothing
	local morningStart = config.morningStartHour
	local dayStart = config.dayStartHour
	local nightStart = config.nightStartHour
	local autoClock = config.dayNightAutoClock

	local ambienceFolder = script:FindFirstChild("Ambience")

	local daySound, nightSound, morningSound
	local ambienceSounds = {}
	local originalVolumes = {
		day = 1,
		night = 1,
		morning = 1,
		ambience = {},
	}

	if ambienceFolder then
		daySound = ambienceFolder:FindFirstChild("daySound")
		nightSound = ambienceFolder:FindFirstChild("nightSound")
		morningSound = ambienceFolder:FindFirstChild("morningSound")

		for _, obj in ipairs(ambienceFolder:GetChildren()) do
			if obj:IsA("Sound") and string.find(string.lower(obj.Name), "ambience") then
				table.insert(ambienceSounds, obj)
			end
		end

		if daySound then originalVolumes.day = clamp(daySound.Volume or 1, 0, 1) end
		if nightSound then originalVolumes.night = clamp(nightSound.Volume or 1, 0, 1) end
		if morningSound then
			originalVolumes.morning = clamp(morningSound.Volume or 1, 0, 1)
		end
		for _, sound in ipairs(ambienceSounds) do
			originalVolumes.ambience[sound] = clamp(sound.Volume or 1, 0, 1)
		end

		if daySound then daySound.Looped = true end
		if nightSound then nightSound.Looped = true end
		if morningSound then morningSound.Looped = true end
		for _, sound in ipairs(ambienceSounds) do
			sound.Looped = true
			if not sound.IsPlaying then
				pcall(function() sound:Play() end)
			end
		end
	else
		warn("[DayNightCycle] Ambience folder not found under DayNightCycle module; continuing without ambience sounds.")
	end

	local sun = Lighting:FindFirstChildOfClass("DirectionalLight")

	local function getClockTime()
		return (Lighting.ClockTime or 0) % 24
	end

	local function computePhaseWeights(clock)
		clock = clock % 24
		local wM, wD, wN = 0, 0, 0

		local function inRange(t, a, b)
			a = a % 24; b = b % 24
			if a <= b then
				return t >= a and t < b
			else
				return t >= a or t < b
			end
		end

		if inRange(clock, morningStart, dayStart) then
			wM = 1
		elseif inRange(clock, dayStart, nightStart) then
			wD = 1
		else
			wN = 1
		end

		local function blendAround(centerHour)
			local half = transitionHours
			local startBlend = (centerHour - half) % 24
			local endBlend = (centerHour + half) % 24
			local inBlend
			if startBlend <= endBlend then
				inBlend = (clock >= startBlend and clock <= endBlend)
			else
				inBlend = (clock >= startBlend or clock <= endBlend)
			end
			if inBlend then
				local duration = 2 * half
				local relative
				if startBlend <= endBlend then
					relative = clock - startBlend
				elseif clock >= startBlend then
					relative = clock - startBlend
				else
					relative = clock + 24 - startBlend
				end
				local t = clamp(relative / duration, 0, 1)
				local s = smoothstep(t)
				return 1 - s, s
			end
			return nil
		end

		do
			local a, b = blendAround(dayStart)
			if a and b then wM, wD, wN = a, b, 0 end
		end
		do
			local a, b = blendAround(nightStart)
			if a and b then wD, wN, wM = a, b, 0 end
		end
		do
			local a, b = blendAround(morningStart)
			if a and b then wN, wM, wD = a, b, 0 end
		end

		local total = wM + wD + wN
		if total <= 0 then
			return 1, 0, 0
		end
		return wM / total, wD / total, wN / total
	end

	local function mixNumber(key, wM, wD, wN)
		local a, b, c = presets.Morning[key] or 0, presets.Day[key] or 0, presets.Night[key] or 0
		return a * wM + b * wD + c * wN
	end
	local function mixColor(key, wM, wD, wN)
		local a = presets.Morning[key] or Color3.new(0, 0, 0)
		local b = presets.Day[key] or Color3.new(0, 0, 0)
		local c = presets.Night[key] or Color3.new(0, 0, 0)
		return Color3.new(
			a.R * wM + b.R * wD + c.R * wN,
			a.G * wM + b.G * wD + c.G * wN,
			a.B * wM + b.B * wD + c.B * wN
		)
	end

	local function applyLightingFromWeights(wM, wD, wN)
		Lighting.Brightness = mixNumber("Brightness", wM, wD, wN)
		Lighting.OutdoorAmbient = mixColor("OutdoorAmbient", wM, wD, wN)
		Lighting.Ambient = mixColor("Ambient", wM, wD, wN)
		Lighting.FogEnd = mixNumber("FogEnd", wM, wD, wN)
		if Lighting:GetAttribute("CustomFogColor") == nil then
			Lighting.FogColor = mixColor("FogColor", wM, wD, wN)
		end
		if sun then
			sun.Intensity = mixNumber("SunIntensity", wM, wD, wN)
			pcall(function() sun.Color = mixColor("SunColor", wM, wD, wN) end)
		end
	end

	local function applySoundVolumes(wM, wD, wN)
		local function ensurePlaying(s)
			if not s then return end
			if not s.IsPlaying then
				s.Volume = 0
				pcall(function() s:Play() end)
			end
		end

		if morningSound then
			local target = originalVolumes.morning * wM
			if target > 0.001 then ensurePlaying(morningSound) end
			morningSound.Volume = lerp(morningSound.Volume or 0, target, soundSmooth)
		end

		if daySound then
			local targetDay = originalVolumes.day * wD
			ensurePlaying(daySound)
			daySound.Volume = lerp(daySound.Volume or 0, targetDay, soundSmooth)
		end

		if nightSound then
			local targetNight = originalVolumes.night * wN
			ensurePlaying(nightSound)
			nightSound.Volume = lerp(nightSound.Volume or 0, targetNight, soundSmooth)
		end

		local function stopIfSilent(s)
			if s and s.IsPlaying and (s.Volume or 0) <= 0.001 then
				pcall(function() s:Stop() end)
			end
		end
		stopIfSilent(morningSound)
		stopIfSilent(daySound)
		stopIfSilent(nightSound)

		for _, sound in ipairs(ambienceSounds) do
			local target = originalVolumes.ambience[sound]
			if target > 0.001 and not sound.IsPlaying then
				sound.Volume = 0
				pcall(function() sound:Play() end)
			end
			sound.Volume = lerp(sound.Volume or 0, target, soundSmooth)
		end
	end

	local accumulator = 0
	local function step(dt)
		if autoClock and dayLength > 0 then
			local hoursPerSecond = 24 / dayLength
			Lighting.ClockTime = ((Lighting.ClockTime or 0) + dt * hoursPerSecond) % 24
		end

		accumulator += dt
		if accumulator < updateInterval then return end
		accumulator = 0

		local wM, wD, wN = computePhaseWeights(getClockTime())
		applyLightingFromWeights(wM, wD, wN)
		applySoundVolumes(wM, wD, wN)
	end

	do
		local wM, wD, wN = computePhaseWeights(getClockTime())
		applyLightingFromWeights(wM, wD, wN)
		applySoundVolumes(wM, wD, wN)
	end

	connection = RunService.Heartbeat:Connect(step)
end

function DayNightCycle.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return DayNightCycle