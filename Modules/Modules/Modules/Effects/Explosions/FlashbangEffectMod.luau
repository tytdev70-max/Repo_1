--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local modules = assets:WaitForChild("Modules")
local explosionRemote = assets:WaitForChild("Events")
	:WaitForChild("ExplosionEvents")
	:WaitForChild("ExplosionFXRemote")
local HearingMuffleMod = require(modules.Systems.HearingMuffleMod)

local FlashbangEffectMod = {}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SPH_FlashbangGui"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 50
screenGui.Parent = playerGui

local flashFrame = Instance.new("Frame")
flashFrame.Name = "FlashFrame"
flashFrame.Size = UDim2.new(1, 0, 1, 0)
flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
flashFrame.BorderSizePixel = 0
flashFrame.BackgroundTransparency = 1
flashFrame.ZIndex = 1
flashFrame.Parent = screenGui

local DEFAULT_GLARE_IMAGE = "rbxassetid://17640078650"
local GLARE_ZINDEX = 5

local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "SPH_FlashbangDesaturate"
colorCorrection.Saturation = 0
colorCorrection.Contrast = 0
colorCorrection.Brightness = 0
colorCorrection.TintColor = Color3.new(1, 1, 1)
colorCorrection.Enabled = false
colorCorrection.Parent = Lighting

local blurEffect = Instance.new("BlurEffect")
blurEffect.Name = "SPH_FlashbangBlur"
blurEffect.Size = 0
blurEffect.Enabled = false
blurEffect.Parent = Lighting

local activePulses = {}
local pulseSeq = 0
local renderConn: RBXScriptConnection? = nil

local function ResetVisualsToIdle()
	flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1

	if colorCorrection.Enabled then
		colorCorrection.Saturation = 0
		colorCorrection.Contrast = 0
		colorCorrection.Brightness = 0
		colorCorrection.TintColor = Color3.new(1, 1, 1)
		colorCorrection.Enabled = false
	end

	if blurEffect.Enabled then
		blurEffect.Enabled = false
		blurEffect.Size = 0
	end
end

local function StopRenderLoop()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	ResetVisualsToIdle()
end

local function NewPulse()
	pulseSeq += 1
	local pulse = {
		token = pulseSeq,
		startTime = tick(),
		muffleToken = nil,
		glareLabels = {},
		glareCount = 0,

		frameEnabled = false, frameOpacity = 0, frameDuration = 0,
		whiteFlashEnabled = false, whiteFlashTime = 0,
		blackoutEnabled = false, blackoutFadeIn = 0,

		desatEnabled = false, desatPeak = 0,
		desatMaxContrast = 0, desatMaxBrightness = 0, desatDuration = 0,

		blurEnabled = false, blurTargetSize = 0,
		blurAttack = 0, blurFadeOut = 0,

		lifetime = 0,
	}
	table.insert(activePulses, pulse)

	if not renderConn then
		renderConn = RunService.RenderStepped:Connect(function()
			FlashbangEffectMod._Step()
		end)
	end

	return pulse
end

local function DestroyPulseGlares(pulse)
	for id, label in pairs(pulse.glareLabels) do
		if label and label.Parent then
			label:Destroy()
		end
		pulse.glareLabels[id] = nil
	end
end

local function TweenProp(instance, time, props, style, direction)
	local tween = TweenService:Create(instance, TweenInfo.new(math.max(time, 0.01), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

local function GetFrameEnvelope(pulse, elapsed)
	if elapsed < 0 then return 0, false end

	if pulse.whiteFlashEnabled then
		if elapsed < pulse.whiteFlashTime then
			return elapsed / math.max(pulse.whiteFlashTime, 0.001), true
		end
		local afterWhite = elapsed - pulse.whiteFlashTime
		if pulse.blackoutEnabled and afterWhite < pulse.blackoutFadeIn then
			return 1, false
		end
		local rampEnd = pulse.whiteFlashTime + (pulse.blackoutEnabled and pulse.blackoutFadeIn or 0)
		local fadeDuration = math.max(pulse.frameDuration - rampEnd, 0.001)
		local fadeElapsed = elapsed - rampEnd
		if fadeElapsed >= fadeDuration then return 0, false end
		return math.clamp(1 - fadeElapsed / fadeDuration, 0, 1), false

	elseif pulse.blackoutEnabled then
		if elapsed < pulse.blackoutFadeIn then
			return elapsed / math.max(pulse.blackoutFadeIn, 0.001), false
		end
		local fadeDuration = math.max(pulse.frameDuration - pulse.blackoutFadeIn, 0.001)
		local fadeElapsed = elapsed - pulse.blackoutFadeIn
		if fadeElapsed >= fadeDuration then return 0, false end
		return math.clamp(1 - fadeElapsed / fadeDuration, 0, 1), false
	end

	return 0, false
end

local function GetLinearEnvelope(elapsed, duration)
	if elapsed < 0 or duration <= 0 or elapsed >= duration then return 0 end
	return 1 - (elapsed / duration)
end

local function GetBlurEnvelope(pulse, elapsed)
	if elapsed < 0 then return 0 end
	if elapsed < pulse.blurAttack then
		return elapsed / math.max(pulse.blurAttack, 0.001)
	end
	local fadeElapsed = elapsed - pulse.blurAttack
	if fadeElapsed >= pulse.blurFadeOut then return 0 end
	return math.clamp(1 - fadeElapsed / pulse.blurFadeOut, 0, 1)
end

local function GetGlareLabel(pulse, id)
	local label = pulse.glareLabels[id]
	if label then return label end

	label = Instance.new("ImageLabel")
	label.Name = "Glare_" .. tostring(pulse.token) .. "_" .. id
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.ScaleType = Enum.ScaleType.Fit
	label.Image = DEFAULT_GLARE_IMAGE
	label.ImageTransparency = 1
	label.Size = UDim2.fromScale(0.6, 0.6)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Visible = false
	label.ZIndex = GLARE_ZINDEX
	label.Parent = screenGui

	pulse.glareLabels[id] = label
	return label
end

local function ComputeGlarePosition(origin, positionInfluence, maxOffsetScale)
	local camera = workspace.CurrentCamera
	if not camera or typeof(origin) ~= "Vector3" then
		return UDim2.fromScale(0.5, 0.5)
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 1 or viewportSize.Y <= 1 then
		return UDim2.fromScale(0.5, 0.5)
	end

	local screenPoint = camera:WorldToViewportPoint(origin)
	local screenX, screenY = screenPoint.X, screenPoint.Y

	if screenPoint.Z < 0 then
		screenX = viewportSize.X - screenX
		screenY = viewportSize.Y - screenY
	end

	local normalized = Vector2.new(screenX / viewportSize.X, screenY / viewportSize.Y)
	local offset = normalized - Vector2.new(0.5, 0.5)

	local offsetMagnitude = offset.Magnitude
	if offsetMagnitude > maxOffsetScale and offsetMagnitude > 0 then
		offset = offset * (maxOffsetScale / offsetMagnitude)
	end

	offset = offset * math.clamp(positionInfluence, 0, 1)

	return UDim2.fromScale(0.5 + offset.X, 0.5 + offset.Y)
end

local function IsEnabledAtDistance(maxDistance, distance)
	if maxDistance == nil then return true end
	if type(distance) ~= "number" then return true end
	return distance <= maxDistance
end

local function BuildLegacyGlareList(data)
	if data.flashGlareImage == nil and data.flashGlareHoldFraction == nil and data.flashGlareFadeFraction == nil then
		return {}
	end
	return {
		{
			id = "Legacy",
			image = data.flashGlareImage,
			holdFraction = data.flashGlareHoldFraction,
			fadeFraction = data.flashGlareFadeFraction,
			maxDistance = data.flashGlareMaxDistance,
		},
	}
end

local function PlayGlare(pulse, glareConfig, index, opacityIntensity, sizeIntensity, origin, totalDuration)
	local id = glareConfig.id or ("Glare" .. tostring(index))
	local label = GetGlareLabel(pulse, id)
	pulse.glareCount += 1

	if glareConfig.image and glareConfig.image ~= "" then
		label.Image = glareConfig.image
	end

	local minSize = glareConfig.minSize or 0.35
	local maxSize = glareConfig.maxSize or 0.95
	local sizeScale = minSize + (maxSize - minSize) * math.clamp(sizeIntensity, 0, 1)
	label.Size = UDim2.fromScale(sizeScale, sizeScale)

	local positionInfluence = glareConfig.positionInfluence
	if positionInfluence == nil then positionInfluence = 1 end
	local maxOffsetScale = glareConfig.maxOffsetScale or 0.42
	label.Position = ComputeGlarePosition(origin, positionInfluence, maxOffsetScale)

	local fadeInTime = math.clamp(glareConfig.fadeInTime or 0.12, 0.02, 0.5)
	local fadeOutTime = math.max(totalDuration - fadeInTime, 0.15)

	label.ImageTransparency = 1
	label.Visible = true
	local fadeInTween = TweenProp(label, fadeInTime, {ImageTransparency = 1 - opacityIntensity})
	fadeInTween.Completed:Wait()

	local tween = TweenProp(label, fadeOutTime, {ImageTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween.Completed:Wait()

	label.Visible = false
	label:Destroy()
	pulse.glareLabels[id] = nil
	pulse.glareCount -= 1
end

function FlashbangEffectMod._Step()
	local now = tick()
	local maxFrameOpacity, frameColor = 0, Color3.new(1, 1, 1)
	local maxDesat, desatSource = 0, nil
	local maxBlurSize = 0

	for i = #activePulses, 1, -1 do
		local pulse = activePulses[i]
		local elapsed = now - pulse.startTime
		local stillAlive = pulse.glareCount > 0

		if pulse.frameEnabled then
			local env, isWhite = GetFrameEnvelope(pulse, elapsed)
			if env > 0 then
				stillAlive = true
				local value = pulse.frameOpacity * env
				if value > maxFrameOpacity then
					maxFrameOpacity = value
					frameColor = isWhite and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
				end
			end
		end

		if pulse.desatEnabled then
			local env = GetLinearEnvelope(elapsed, pulse.desatDuration)
			if env > 0 then
				stillAlive = true
				if env > maxDesat then
					maxDesat = env
					desatSource = pulse
				end
			end
		end

		if pulse.blurEnabled then
			local env = GetBlurEnvelope(pulse, elapsed)
			if env > 0 then
				stillAlive = true
				maxBlurSize = math.max(maxBlurSize, pulse.blurTargetSize * env)
			end
		end

		if not stillAlive and elapsed >= pulse.lifetime then
			if pulse.muffleToken then
				HearingMuffleMod.EndMuffle(pulse.muffleToken, 0.05)
				pulse.muffleToken = nil
			end
			DestroyPulseGlares(pulse)
			table.remove(activePulses, i)
		end
	end

	if #activePulses == 0 then
		StopRenderLoop()
		return
	end

	flashFrame.BackgroundColor3 = frameColor
	flashFrame.BackgroundTransparency = 1 - maxFrameOpacity

	if maxDesat > 0 and desatSource then
		local curve = desatSource.desatPeak * maxDesat
		colorCorrection.Saturation = -curve
		colorCorrection.Contrast = desatSource.desatMaxContrast * curve
		colorCorrection.Brightness = desatSource.desatMaxBrightness * curve
		colorCorrection.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(230, 240, 255), curve)
		colorCorrection.Enabled = true
	elseif colorCorrection.Enabled then
		colorCorrection.Enabled = false
	end

	if maxBlurSize > 0.01 then
		blurEffect.Size = maxBlurSize
		blurEffect.Enabled = true
	elseif blurEffect.Enabled then
		blurEffect.Enabled = false
		blurEffect.Size = 0
	end
end

function FlashbangEffectMod.Clear()
	StopRenderLoop()

	for _, pulse in ipairs(activePulses) do
		if pulse.muffleToken then
			HearingMuffleMod.EndMuffle(pulse.muffleToken, 0.05)
			pulse.muffleToken = nil
		end
		DestroyPulseGlares(pulse)
	end
	activePulses = {}
end

function FlashbangEffectMod.TriggerFlash(data)
	local baseIntensity = data.flashIntensity
	if type(baseIntensity) ~= "number" or baseIntensity <= 0 then return end

	local distance = data.distance
	local origin = data.origin

	local facingFactor = 1
	local facingDot = 1
	if typeof(origin) == "Vector3" then
		local camera = workspace.CurrentCamera
		local toOrigin = origin - camera.CFrame.Position
		if toOrigin.Magnitude > 0.01 then
			facingDot = camera.CFrame.LookVector:Dot(toOrigin.Unit)
			local facingAlpha = math.clamp((facingDot + 1) / 2, 0, 1)
			local falloff = math.clamp(data.flashFacingFalloff or 1, 0, 1)
			facingFactor = falloff + (1 - falloff) * facingAlpha
		end
	end

	local opacityIntensity = math.clamp(baseIntensity * facingFactor, 0, 1)
	local sizeIntensity = math.clamp(baseIntensity, 0, 1)
	local totalDuration = math.max(data.flashDuration or 1, 0.15)

	local pulse = NewPulse()

	local muffleEnabled = data.flashMuffleEnabled ~= false
	if muffleEnabled then
		pulse.muffleToken = HearingMuffleMod.BeginMuffle(opacityIntensity, math.clamp(totalDuration * 0.08, 0.08, 0.4))
	end

	local whiteFlashEnabled = data.flashWhiteFlashEnabled ~= false
		and IsEnabledAtDistance(data.flashWhiteFlashMaxDistance, distance)
	local blackoutEnabled = data.flashBlackoutEnabled ~= false
		and IsEnabledAtDistance(data.flashBlackoutMaxDistance, distance)
	local desaturateEnabled = data.flashDesaturateEnabled ~= false
		and IsEnabledAtDistance(data.flashDesaturateMaxDistance, distance)

	local glareSource = data.flashGlares
	if typeof(glareSource) ~= "table" or #glareSource == 0 then
		glareSource = BuildLegacyGlareList(data)
	end

	local glareBackFacingCutoff = data.flashGlareBackFacingCutoff
	if glareBackFacingCutoff == nil then glareBackFacingCutoff = 0 end
	local glareSuppressedByFacing = facingDot < glareBackFacingCutoff

	local glareConfigs = {}
	if data.flashGlareEnabled ~= false and not glareSuppressedByFacing then
		for index, glareConfig in ipairs(glareSource) do
			if glareConfig.enabled ~= false and IsEnabledAtDistance(glareConfig.maxDistance, distance) then
				table.insert(glareConfigs, glareConfig)
			end
		end
	end

	local whiteFlashTime = math.clamp(data.flashWhiteFlashTime or 0.08, 0.02, 0.5)
	local blackoutFadeIn = math.clamp(data.flashBlackoutFadeInTime or 0.25, 0.05, 1.5)

	pulse.frameEnabled = whiteFlashEnabled or blackoutEnabled
	pulse.frameOpacity = opacityIntensity
	pulse.whiteFlashEnabled = whiteFlashEnabled
	pulse.whiteFlashTime = whiteFlashTime
	pulse.blackoutEnabled = blackoutEnabled
	pulse.blackoutFadeIn = blackoutFadeIn
	pulse.frameDuration = totalDuration

	for index, glareConfig in ipairs(glareConfigs) do
		task.spawn(function()
			PlayGlare(pulse, glareConfig, index, opacityIntensity, sizeIntensity, origin, totalDuration)
		end)
	end

	local blurEnabled = data.flashBlurEnabled ~= false
		and IsEnabledAtDistance(data.flashBlurMaxDistance, distance)

	pulse.blurEnabled = blurEnabled
	if blurEnabled then
		pulse.blurAttack = math.clamp(data.flashBlurFadeInTime or 0.15, 0.02, 0.6)
		pulse.blurTargetSize = (data.flashBlurMaxSize or 28) * opacityIntensity
		pulse.blurFadeOut = math.max(totalDuration * (data.flashBlurFadeOutMultiplier or 1.6), 0.3)
	end

	pulse.desatEnabled = desaturateEnabled
	if desaturateEnabled then
		local desatExponent = data.flashDesaturateCurveExponent or 0.5
		pulse.desatPeak = opacityIntensity ^ math.max(desatExponent, 0.01)
		pulse.desatMaxContrast = data.flashDesaturateMaxContrast or 0.6
		pulse.desatMaxBrightness = data.flashDesaturateMaxBrightness or 0.35
		pulse.desatDuration = totalDuration
	end

	pulse.lifetime = totalDuration
	if pulse.blurEnabled then
		pulse.lifetime = math.max(pulse.lifetime, pulse.blurAttack + pulse.blurFadeOut)
	end
end

function FlashbangEffectMod.Init()
	FlashbangEffectMod.Clear()

	explosionRemote.OnClientEvent:Connect(function(data)
		if typeof(data) == "table" and data.isFlashbang then
			FlashbangEffectMod.TriggerFlash(data)
		end
	end)
end

return FlashbangEffectMod