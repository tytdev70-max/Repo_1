local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local GlareMod = {}

local deps = {}
local camera

-- Flashlight glare
local FLASH_MAX_BRIGHTNESS   = 0.65
local FLASH_MAX_SATURATION   = -0.4
local FLASH_FACING_THRESHOLD = 0.85
local FLASH_MAX_DISTANCE     = 50
local FLASH_FALLBACK_ANGLE   = 25       -- degrees; used if no SpotLight is found to read a real cone from
local FLASH_FLARE_MAX_ALPHA  = 1        -- fully opaque at intensity 1 (dead-center, point-blank)
local FLASH_SMOOTH_RATE      = 9        -- higher = snappier tween in/out, lower = more gradual

-- Laser glare
local LASER_MAX_BRIGHTNESS   = 0.5
local LASER_BLIND_ANGLE      = 0.2
local LASER_FACING_THRESHOLD = 0.9
local LASER_MAX_DISTANCE     = 80
local LASER_FLARE_MAX_ALPHA  = 1        -- fully opaque at intensity 1 (dead-center, point-blank)
local LASER_FLARE_MIN_ALPHA  = 0.6      -- flare never drops below this once the laser is "visible" at all, regardless of distance
local LASER_SMOOTH_RATE      = 10
local LASER_DEFAULT_COLOR    = Color3.fromRGB(255, 30, 30)

-- Billboard base indicator
local BILLBOARD_SIZE     = UDim2.fromScale(0.6, 0.6) -- stud-relative so it stays a visible, consistent size at any distance
local BILLBOARD_OFFSET   = Vector3.new(0, 0, 0) -- toward the mount/base, opposite LookVector - tune to taste
local BILLBOARD_MAX_DIST = 250
local BILLBOARD_IMAGE    = "rbxassetid://17640078650" -- soft radial glow; swap for your own texture
local FLARE_IMAGE         = "rbxassetid://105715385829652" -- full-screen glow/bloom texture; swap for your own

local flashlightCC, laserCC
local flashFlare, laserFlare

local flashlightSources = {}
local laserSources = {}

local rayParams

local function GetRayParams()
	if not rayParams then
		rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.RespectCanCollide = true
	end
	rayParams.FilterDescendantsInstances = { deps.character }
	return rayParams
end

local function CreateBillboard(part, color)
	local gui = Instance.new("BillboardGui")
	gui.Name = "GlareIndicator"
	gui.Adornee = part
	gui.Size = BILLBOARD_SIZE
	gui.StudsOffset = BILLBOARD_OFFSET
	gui.MaxDistance = BILLBOARD_MAX_DIST
	gui.AlwaysOnTop = false 
	gui.LightInfluence = 0

	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.Image = BILLBOARD_IMAGE
	glow.ImageColor3 = color
	glow.Size = UDim2.fromScale(1, 1)
	glow.Parent = gui

	local hostPart = part:IsA("BasePart") and part or part:FindFirstAncestorWhichIsA("BasePart")
	gui.Parent = hostPart or part.Parent
	return gui
end

local function RegisterSource(registry, part, color)
	if registry[part] then return end
	registry[part] = { billboard = CreateBillboard(part, color) }
end

local function UnregisterSource(registry, part)
	local entry = registry[part]
	if not entry then return end
	if entry.billboard and entry.billboard.Parent then entry.billboard:Destroy() end
	registry[part] = nil
end

function GlareMod.ResolveFlashlightColor(part)
	local light = part:FindFirstChild("OuterSpotLight") or part:FindFirstChild("InnerSpotLight") or part:FindFirstChildOfClass("SpotLight")
	return (light and light.Color) or Color3.new(1, 1, 0.9)
end

function GlareMod.SetFlashlightActive(part, active, color)
	if not part then return end
	if active then
		RegisterSource(flashlightSources, part, color or GlareMod.ResolveFlashlightColor(part))
	else
		UnregisterSource(flashlightSources, part)
	end
end

function GlareMod.SetLaserActive(part, active, color)
	if not part then return end
	if active then
		RegisterSource(laserSources, part, color or LASER_DEFAULT_COLOR)
	else
		UnregisterSource(laserSources, part)
	end
end

function GlareMod.SetFlashlightModelActive(fpPart, tpPart, firstPerson, active, color)
	if firstPerson then
		if tpPart then UnregisterSource(flashlightSources, tpPart) end
		if active and fpPart then
			RegisterSource(flashlightSources, fpPart, color or GlareMod.ResolveFlashlightColor(fpPart))
		elseif fpPart then
			UnregisterSource(flashlightSources, fpPart)
		end
	else
		if fpPart then UnregisterSource(flashlightSources, fpPart) end
		if active and tpPart then
			RegisterSource(flashlightSources, tpPart, color or GlareMod.ResolveFlashlightColor(tpPart))
		elseif tpPart then
			UnregisterSource(flashlightSources, tpPart)
		end
	end
end

function GlareMod.SetLaserModelActive(fpPart, tpPart, firstPerson, active, color)
	if firstPerson then
		if tpPart then UnregisterSource(laserSources, tpPart) end
		if active and fpPart then
			RegisterSource(laserSources, fpPart, color or LASER_DEFAULT_COLOR)
		elseif fpPart then
			UnregisterSource(laserSources, fpPart)
		end
	else
		if fpPart then UnregisterSource(laserSources, fpPart) end
		if active and tpPart then
			RegisterSource(laserSources, tpPart, color or LASER_DEFAULT_COLOR)
		elseif tpPart then
			UnregisterSource(laserSources, tpPart)
		end
	end
end

local function MakeFlareImage(name)
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = FLARE_IMAGE
	img.ScaleType = Enum.ScaleType.Stretch
	img.AnchorPoint = Vector2.new(0, 0)
	img.Position = UDim2.fromScale(0, 0)
	img.Size = UDim2.fromScale(1, 1)
	img.ImageTransparency = 1
	img.Visible = false
	return img
end

function GlareMod.Init(dependencies)
	deps = dependencies
	camera = deps.camera or workspace.CurrentCamera

	for part in pairs(flashlightSources) do UnregisterSource(flashlightSources, part) end
	for part in pairs(laserSources) do UnregisterSource(laserSources, part) end

	if flashlightCC and flashlightCC.Parent then flashlightCC:Destroy() end
	if laserCC and laserCC.Parent then laserCC:Destroy() end

	flashlightCC = Instance.new("ColorCorrectionEffect")
	flashlightCC.Name = "FlashlightGlareEffect"
	flashlightCC.Enabled = false
	flashlightCC.Brightness = 0
	flashlightCC.Saturation = 0
	flashlightCC.Parent = camera

	laserCC = Instance.new("ColorCorrectionEffect")
	laserCC.Name = "LaserGlareEffect"
	laserCC.Enabled = false
	laserCC.Brightness = 0
	laserCC.Parent = camera

	local playerGui = player:WaitForChild("PlayerGui")
	local existingGui = playerGui:FindFirstChild("GlareFlareGui")
	if existingGui then existingGui:Destroy() end

	local glareGui = Instance.new("ScreenGui")
	glareGui.Name = "GlareFlareGui"
	glareGui.IgnoreGuiInset = true
	glareGui.ResetOnSpawn = false
	glareGui.DisplayOrder = 5
	glareGui.Parent = playerGui

	flashFlare = MakeFlareImage("FlashlightFlare")
	flashFlare.Parent = glareGui

	laserFlare = MakeFlareImage("LaserFlare")
	laserFlare.Parent = glareGui
end

local function GetSpotAngleThreshold(part)
	local outer = part:FindFirstChild("OuterSpotLight") or part:FindFirstChildOfClass("SpotLight")
	local angleDeg = (outer and outer.Angle) or FLASH_FALLBACK_ANGLE
	return math.cos(math.rad(angleDeg))
end

local function EvaluateSource(part, camCFrame, blindAngleThreshold, facingThreshold, maxDistance)
	if not part or not part.Parent then return nil end

	local partPos = part.WorldPosition
	local toSource = partPos - camCFrame.Position
	local dist = toSource.Magnitude
	if dist <= 0.01 or dist > maxDistance then return nil end

	local dirToSource = toSource / dist
	local dotCamToSource = camCFrame.LookVector:Dot(dirToSource)
	if dotCamToSource <= blindAngleThreshold then return nil end

	local sourceForward = part.WorldCFrame.LookVector
	local dotSourceToCam = sourceForward:Dot(-dirToSource)
	if dotSourceToCam <= facingThreshold then return nil end

	local hit = workspace:Raycast(camCFrame.Position, dirToSource * dist, GetRayParams())
	if hit then return nil end

	local angleIntensity = (dotCamToSource - blindAngleThreshold) / (1 - blindAngleThreshold)
	local distanceIntensity = (1 - (dist / maxDistance)) ^ 1.5

	return angleIntensity * distanceIntensity, dist, partPos
end

local function ApplyGlareEffect(cc, flare, intensity, color, maxBrightness, maxSaturation, maxFlareAlpha, smoothRate, dt, minFlareAlpha)
	local alpha = 1 - math.exp(-smoothRate * dt)

	if intensity and intensity > 0 then
		if not cc.Enabled then cc.Enabled = true end
		flare.Visible = true
		flare.ImageColor3 = color

		local targetBrightness = maxBrightness * intensity
		local targetTint = color:Lerp(Color3.new(1, 1, 1), 0.5)
		cc.Brightness = cc.Brightness + (targetBrightness - cc.Brightness) * alpha
		cc.TintColor = cc.TintColor:Lerp(targetTint, alpha)
		if maxSaturation ~= 0 then
			local targetSaturation = maxSaturation * intensity
			cc.Saturation = cc.Saturation + (targetSaturation - cc.Saturation) * alpha
		end

		local flareAlpha = maxFlareAlpha * intensity
		if minFlareAlpha and minFlareAlpha > 0 then
			flareAlpha = math.max(flareAlpha, minFlareAlpha)
		end
		local targetTransparency = 1 - flareAlpha
		flare.ImageTransparency = flare.ImageTransparency + (targetTransparency - flare.ImageTransparency) * alpha
	else
		if cc.Enabled then
			cc.Brightness = cc.Brightness + (0 - cc.Brightness) * alpha
			cc.Saturation = cc.Saturation + (0 - cc.Saturation) * alpha
			cc.TintColor = cc.TintColor:Lerp(Color3.new(1, 1, 1), alpha)
			if cc.Brightness <= 0.01 and math.abs(cc.Saturation) <= 0.01 then
				cc.Enabled = false
				cc.Brightness = 0
				cc.Saturation = 0
				cc.TintColor = Color3.new(1, 1, 1)
			end
		end
		if flare.Visible then
			flare.ImageTransparency = flare.ImageTransparency + (1 - flare.ImageTransparency) * alpha
			if flare.ImageTransparency >= 0.99 then
				flare.Visible = false
				flare.ImageTransparency = 1
			end
		end
	end
end

function GlareMod.Update(dt: number)
	if not camera then return end
	local camCFrame = camera.CFrame

	local bestFlashIntensity, bestFlashColor = 0, nil
	for part in pairs(flashlightSources) do
		if not part.Parent then
			UnregisterSource(flashlightSources, part)
		else
			local blindAngle = GetSpotAngleThreshold(part)
			local intensity = EvaluateSource(part, camCFrame, blindAngle, FLASH_FACING_THRESHOLD, FLASH_MAX_DISTANCE)
			if intensity and intensity > bestFlashIntensity then
				bestFlashIntensity = intensity
				bestFlashColor = GlareMod.ResolveFlashlightColor(part)
			end
		end
	end
	ApplyGlareEffect(flashlightCC, flashFlare, bestFlashIntensity, bestFlashColor or Color3.new(1, 1, 0.9),
		FLASH_MAX_BRIGHTNESS, FLASH_MAX_SATURATION, FLASH_FLARE_MAX_ALPHA, FLASH_SMOOTH_RATE, dt)

	local bestLaserIntensity, bestLaserColor = 0, nil
	for part in pairs(laserSources) do
		if not part.Parent then
			UnregisterSource(laserSources, part)
		else
			local intensity = EvaluateSource(part, camCFrame, LASER_BLIND_ANGLE, LASER_FACING_THRESHOLD, LASER_MAX_DISTANCE)
			if intensity and intensity > bestLaserIntensity then
				bestLaserIntensity = intensity
				local colorVal = part:FindFirstChild("Color")
				bestLaserColor = (colorVal and colorVal.Value) or LASER_DEFAULT_COLOR
			end
		end
	end
	ApplyGlareEffect(laserCC, laserFlare, bestLaserIntensity, bestLaserColor or LASER_DEFAULT_COLOR,
		LASER_MAX_BRIGHTNESS, 0, LASER_FLARE_MAX_ALPHA, LASER_SMOOTH_RATE, dt, LASER_FLARE_MIN_ALPHA)
end

function GlareMod.Cleanup()
	for part in pairs(flashlightSources) do UnregisterSource(flashlightSources, part) end
	for part in pairs(laserSources) do UnregisterSource(laserSources, part) end
	if flashlightCC then flashlightCC.Enabled = false; flashlightCC.Brightness = 0 end
	if laserCC then laserCC.Enabled = false; laserCC.Brightness = 0 end
	if flashFlare then flashFlare.ImageTransparency = 1; flashFlare.Visible = false end
	if laserFlare then laserFlare.ImageTransparency = 1; laserFlare.Visible = false end
end

return GlareMod