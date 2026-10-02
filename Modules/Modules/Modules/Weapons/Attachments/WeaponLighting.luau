--[[
	WeaponLighting
	Per-source weapon lighting settings (flashlight, laser, laser dot).
	Never use the viewer's equipped weapon for a remote light.
]]

local WeaponLighting = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local WHITE = Color3.new(1, 1, 1)
local DEFAULT_LASER_COLOR = Color3.fromRGB(255, 30, 30)
local DEFAULT_FLASH_COLOR = Color3.new(1, 1, 0.9)
local FALLBACK_SPOT_ANGLE = 25 -- old no-SpotLight blinding-cone fallback

local FACE_DIRECTIONS = {
	[Enum.NormalId.Front] = Vector3.new(0, 0, -1),
	[Enum.NormalId.Back] = Vector3.new(0, 0, 1),
	[Enum.NormalId.Right] = Vector3.new(1, 0, 0),
	[Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Top] = Vector3.new(0, 1, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
}

-- Values that differ between kinds.
local KIND_DEFAULTS = {
	Laser = {
		BlindRange = 80,
		MinBlindOpacity = 0.6,
		FadeSpeed = 10,
		Brightness = 0.5,
		Saturation = 0,
		-- Ocular adaptation: a laser stings instantly and recovers in under a
		-- second; it only blinds when within ~12 degrees of the view axis.
		BlindAttackTime = 0.06,
		BlindReleaseTime = 0.9,
		BlindOffAxisAngleDeg = 12,
	},
	Flashlight = {
		BlindRange = 50,
		MinBlindOpacity = 0,
		FadeSpeed = 9,
		Brightness = 0.65,
		Saturation = -0.4,
		-- A floodlight takes longer to dazzle and leaves a longer tail; the
		-- wide beam tolerates much more off-axis incidence.
		BlindAttackTime = 0.25,
		BlindReleaseTime = 2.5,
		BlindOffAxisAngleDeg = 50,
	},
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local statsCache = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- Sanitizers
--------------------------------------------------------------------------------

local function sanitizeNumber(value, fallback, minimum, maximum)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local function sanitizeColor(value, fallback)
	return if typeof(value) == "Color3" then value else fallback
end

--------------------------------------------------------------------------------
-- Source / stats lookup
--------------------------------------------------------------------------------

local function findSpotLight(source)
	local light = source:FindFirstChild("OuterSpotLight")
		or source:FindFirstChild("InnerSpotLight")
		or source:FindFirstChildOfClass("SpotLight")
	return if light and light:IsA("SpotLight") then light else nil
end

local function getStatsFromTool(tool)
	local weapon = tool and tool:FindFirstChild("SPH_Weapon")
	local module = weapon and weapon:FindFirstChild("WeaponStats")
	if not module or not module:IsA("ModuleScript") then return nil end
	if statsCache[module] then return statsCache[module] end

	local ok, stats = pcall(require, module)
	if ok and type(stats) == "table" then
		statsCache[module] = stats
		return stats
	end
	return nil
end

local function getSourceColor(source, kind)
	if source then
		if kind == "Laser" then
			local color = source:FindFirstChild("Color")
			if color and color:IsA("Color3Value") then return color.Value end
		else
			local light = findSpotLight(source)
			if light then return light.Color end
		end
	end
	return if kind == "Laser" then DEFAULT_LASER_COLOR else DEFAULT_FLASH_COLOR
end

--------------------------------------------------------------------------------
-- Settings resolution
--------------------------------------------------------------------------------

local function resolve(kind, source, weaponStats)
	local stats = weaponStats or WeaponLighting.GetStatsForSource(source)
	local config = stats and stats[kind]
	if type(config) ~= "table" then config = {} end

	local defaults = KIND_DEFAULTS[kind]
	local sourceColor = getSourceColor(source, kind)

	local lightColor
	if kind == "Laser" then
		lightColor = sanitizeColor(config.LaserColor, sourceColor)
	else
		lightColor = sanitizeColor(config.LightColor, sanitizeColor(config.BlindColor, sourceColor))
	end
	local blindColor = sanitizeColor(config.BlindColor, lightColor)
	local correction = if type(config.ColorCorrection) == "table" then config.ColorCorrection else {}

	return {
		-- Colors
		LightColor = lightColor,
		BlindColor = blindColor,

		-- Blind behavior
		BlindIntensity = sanitizeNumber(config.BlindIntensity, 1, 0, 10),
		BlindSize = if typeof(config.BlindSize) == "UDim2" then config.BlindSize else nil,
		BlindOffset = if typeof(config.BlindOffset) == "Vector3" then config.BlindOffset else Vector3.zero,
		BlindTransparency = sanitizeNumber(config.BlindTransparency, 0, 0, 1),
		BlindRange = sanitizeNumber(config.BlindRange, defaults.BlindRange, 0.01, 100000),
		BlindFalloff = sanitizeNumber(config.BlindFalloff, 1.5, 0, 10),
		MinBlindOpacity = sanitizeNumber(config.MinBlindOpacity, defaults.MinBlindOpacity, 0, 1),
		FadeSpeed = sanitizeNumber(config.FadeSpeed, defaults.FadeSpeed, 0.01, 1000),
		-- Flashlight only: how far off-axis (studs) the beam may point and still dazzle. Nil = module default.
		BlindRadius = sanitizeNumber(config.BlindRadius, nil, 0, 100),

		-- Ocular adaptation (GlareMod): attack/release time constants (seconds)
		-- and the off-axis angle (degrees) beyond which the light stops
		-- blinding. Defaults are per-kind (see KIND_DEFAULTS).
		BlindAttackTime = sanitizeNumber(config.BlindAttackTime, defaults.BlindAttackTime, 0.02, 1),
		BlindReleaseTime = sanitizeNumber(config.BlindReleaseTime, defaults.BlindReleaseTime, 0.1, 8),
		BlindOffAxisAngleDeg = sanitizeNumber(config.BlindOffAxisAngleDeg, defaults.BlindOffAxisAngleDeg, 5, 80),

		ColorCorrection = {
			Enabled = config.ColorCorrection ~= false and correction.Enabled ~= false,
			Brightness = sanitizeNumber(correction.Brightness, defaults.Brightness, -1, 1),
			Saturation = sanitizeNumber(correction.Saturation, defaults.Saturation, -1, 1),
			Contrast = sanitizeNumber(correction.Contrast, 0, -1, 1),
			TintColor = sanitizeColor(correction.TintColor, blindColor:Lerp(WHITE, 0.5)),
		},

		-- Nil means retain the model's authored flashlight light value.
		LightRange = sanitizeNumber(config.LightRange, nil, 0, 60),
		LightBrightness = sanitizeNumber(config.LightBrightness, nil, 0, 100),
		OverrideLightColor = typeof(config.LightColor) == "Color3" or typeof(config.BlindColor) == "Color3",

		-- Laser dot
		DotLightRange = sanitizeNumber(config.DotLightRange, 1, 0, 60),
		DotLightBrightness = sanitizeNumber(config.DotLightBrightness, 0.5, 0, 100),
		DotLightSoftness = sanitizeNumber(config.DotLightSoftness, 0.65, 0, 1),
	}
end

--------------------------------------------------------------------------------
-- Public: lookup
--------------------------------------------------------------------------------

function WeaponLighting.GetStatsForSource(source)
	local ancestor = source
	while ancestor do
		if ancestor:IsA("Tool") then
			return getStatsFromTool(ancestor)
		end
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
			for _, child in ipairs(ancestor:GetChildren()) do
				if child:IsA("Tool") then
					local stats = getStatsFromTool(child)
					if stats then return stats end
				end
			end
		end
		ancestor = ancestor.Parent
	end
	return nil
end

function WeaponLighting.GetFlashlight(source, weaponStats)
	return resolve("Flashlight", source, weaponStats)
end

function WeaponLighting.GetLaser(source, weaponStats)
	return resolve("Laser", source, weaponStats)
end

WeaponLighting.GetSpotLight = findSpotLight

function WeaponLighting.GetFaceDirection(face)
	return FACE_DIRECTIONS[face] or FACE_DIRECTIONS[Enum.NormalId.Front]
end

--------------------------------------------------------------------------------
-- Public: apply
--------------------------------------------------------------------------------

function WeaponLighting.ApplyFlashlight(source, weaponStats)
	local settings = WeaponLighting.GetFlashlight(source, weaponStats)
	if not source then return settings end

	local needsLight = settings.LightRange ~= nil or settings.LightBrightness ~= nil
	if needsLight and not source:FindFirstChildWhichIsA("Light", true) then
		local light = Instance.new("SpotLight")
		light.Name = "OuterSpotLight"
		light.Angle = FALLBACK_SPOT_ANGLE
		light.Enabled = false
		light.Parent = source
	end

	for _, light in ipairs(source:GetDescendants()) do
		if light:IsA("Light") then
			if settings.OverrideLightColor then light.Color = settings.LightColor end
			if settings.LightRange ~= nil then light.Range = settings.LightRange end
			if settings.LightBrightness ~= nil then light.Brightness = settings.LightBrightness end
		end
	end
	return settings
end

function WeaponLighting.ApplyLaserSource(source, weaponStats)
	local settings = WeaponLighting.GetLaser(source, weaponStats)
	if source then
		local color = source:FindFirstChild("Color")
		if not color then
			color = Instance.new("Color3Value")
			color.Name = "Color"
			color.Parent = source
		end
		if color:IsA("Color3Value") then color.Value = settings.LightColor end
	end
	return settings
end

function WeaponLighting.ApplyLaserDot(dot, light, settings)
	dot.Color = settings.LightColor
	light.Color = settings.LightColor
	light.Brightness = settings.DotLightBrightness
	light.Range = settings.DotLightRange
	light.Shadows = false

	-- PointLight has no Softness property. A wider, dimmer, shadow-free halo
	-- supplies a controllable soft falloff without changing the core light's values.
	local halo = dot:FindFirstChild("LaserDotHalo")
	if not halo then
		halo = Instance.new("PointLight")
		halo.Name = "LaserDotHalo"
		halo.Parent = dot
	end
	halo.Color = settings.LightColor
	halo.Brightness = settings.DotLightBrightness * settings.DotLightSoftness * 0.25
	halo.Range = math.min(settings.DotLightRange * (1 + settings.DotLightSoftness), 60)
	halo.Shadows = false
	halo.Enabled = light.Enabled and settings.DotLightSoftness > 0
end

function WeaponLighting.SetLaserDotEnabled(dot, light, enabled)
	if light then light.Enabled = enabled end
	local halo = dot and dot:FindFirstChild("LaserDotHalo")
	if halo then halo.Enabled = enabled and halo.Brightness > 0 end
end

return WeaponLighting