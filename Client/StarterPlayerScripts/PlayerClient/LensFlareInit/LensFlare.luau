local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SPH_Assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local Config = require(SPH_Assets:WaitForChild("GameConfig"))
local LensFlare = require(SPH_Assets.Modules.Misc.LensFlare.LensFlare)

if Config.lensFlareEnabled == false or Config.sunFlareEnabled == false then
	return true
end

local camera = workspace.CurrentCamera
local SUN_DISTANCE = 5000

local SUN_EXPOSURE_ADJUST = Config.sunFlareExposureAdjustment
local SUN_EXPOSURE_SMOOTH_TIME = Config.sunFlareExposureTime
local SUN_BRIGHTNESS_THRESHOLD = Config.sunFlareBrightnessThreshold
local SUN_ANGLE_THRESHOLD = Config.sunFlareAngleThreshold

local sunPart = Instance.new("Part")
sunPart.Anchored = true
sunPart.CanCollide = false
sunPart.CanQuery = false
sunPart.CanTouch = false
sunPart.Transparency = 1
sunPart.Size = Vector3.one
sunPart.Name = "SunFlareSourcePart"
sunPart.Parent = workspace
sunPart:SetAttribute("LensFlareStrength", 1)

local sunFlare = LensFlare.new(camera, "Default", sunPart)

if sunFlare._dummy then
	sunPart:Destroy()
	return true
end

local function updateColor()
	sunPart.Color = Lighting.ColorShift_Top
end
updateColor()
Lighting:GetPropertyChangedSignal("ColorShift_Top"):Connect(updateColor)

local function updateStrength()
	local sunAngle = Lighting:GetSunDirection().Y * 90
	local sunAlpha = math.clamp(sunAngle / SUN_ANGLE_THRESHOLD, 0, 1)
	local brightnessAlpha = math.clamp(Lighting.Brightness / SUN_BRIGHTNESS_THRESHOLD, 0, 1)
	local totalAlpha = sunAlpha * brightnessAlpha

	sunFlare.Enabled = totalAlpha > 0
	sunPart:SetAttribute("LensFlareStrength", totalAlpha)
end
updateStrength()
Lighting:GetPropertyChangedSignal("Brightness"):Connect(updateStrength)
Lighting:GetPropertyChangedSignal("ClockTime"):Connect(updateStrength)

RunService:BindToRenderStep("UpdateLensFlarePart", Enum.RenderPriority.Camera.Value + 9, function()
	sunPart.Position = camera.CFrame.Position + (Lighting:GetSunDirection() * SUN_DISTANCE)
end)

local alpha, vel = 0, 0
RunService:BindToRenderStep("UpdateExposure", Enum.RenderPriority.Camera.Value + 11, function(delta: number)
	Lighting.ExposureCompensation -= (alpha * SUN_EXPOSURE_ADJUST)
	alpha, vel = TweenService:SmoothDamp(alpha, sunFlare.Alpha ^ 2, vel, SUN_EXPOSURE_SMOOTH_TIME, nil, delta)
	Lighting.ExposureCompensation += (alpha * SUN_EXPOSURE_ADJUST)
end)

-- Tagged flares (custom lights, character lights, etc.)
local parts: { [Instance]: any } = {}

local function makeTaggedFlare(part: Instance)
	if parts[part] then
		return
	end
	if not (part:IsA("BasePart") or part:IsA("Attachment")) then
		return
	end
	parts[part] = LensFlare.new(camera, part:GetAttribute("LensFlareStyle") or "Default", part)
end

for _, part in CollectionService:GetTagged("LensFlare") do
	makeTaggedFlare(part)
end

CollectionService:GetInstanceAddedSignal("LensFlare"):Connect(makeTaggedFlare)
CollectionService:GetInstanceRemovedSignal("LensFlare"):Connect(function(part: Instance)
	local flare = parts[part]
	if flare then
		flare:Destroy()
		parts[part] = nil
	end
end)

return true