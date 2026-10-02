--[[
	WeaponLighting
	Per-source weapon lighting settings (flashlight, laser, laser dot), environment
	estimation, and the shared light-transport trace.
	Never use the viewer's equipped weapon for a remote light.
]]

local Lighting = game:GetService("Lighting")

local WeaponLighting = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local WHITE = Color3.new(1, 1, 1)
local DEFAULT_LASER_COLOR = Color3.fromRGB(255, 30, 30)
local DEFAULT_FLASH_COLOR = Color3.new(1, 1, 0.9)
local FALLBACK_SPOT_ANGLE = 25 -- angle of the SpotLight created when a flashlight has none
local FALLBACK_SPOT_RANGE = 18

local ENV_REFRESH = 0.25 -- seconds between environment re-reads

-- Beam visibility in clear air (rises with scatter and darkness).
local LASER_BEAM_BASE = 0.2
local FLASHLIGHT_BEAM_BASE = 0.25

-- Light transport
local GLASS_MIN_TRANSPARENCY = 0.3 -- below this a part is opaque
local INVISIBLE_TRANSPARENCY = 0.95 -- at/above this a part is ignored entirely
local MAX_PASS_THROUGH = 6
local PASS_EPSILON = 0.05

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
		FadeSpeed = 10, -- indicator glow on the source only
		Brightness = 0.5,
		Saturation = 0,
		Contrast = 0,
		BlindFalloff = 0.75, -- collimated: barely decays
		HalfDistanceFraction = 0.6,
		AttackSpeed = 30,
		RecoverySpeed = 2.5,
		HoldTime = 0.15,
		DaylightResistance = 0.3,
		BlindRadius = 0.5, -- studs around the eye the beam must pass through
		Bloom = { Intensity = 0.5, Size = 16, Threshold = 0.85 },
	},
	Flashlight = {
		BlindRange = 50,
		MinBlindOpacity = 0,
		FadeSpeed = 9,
		Brightness = 0.65,
		Saturation = -0.4,
		Contrast = -0.2, -- veiling glare washes out contrast
		BlindFalloff = 2, -- inverse-square
		HalfDistanceFraction = 0.25,
		AttackSpeed = 14,
		RecoverySpeed = 1.6,
		HoldTime = 0.35,
		DaylightResistance = 0.7,
		BlindRadius = 3, -- aim tolerance around the cone (studs)
		Bloom = { Intensity = 1, Size = 30, Threshold = 0.7 },
	},
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local statsCache = setmetatable({}, { __mode = "k" })

local envTime = -math.huge
local envDarkness = 0.5
local envScatter = 0

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
	if not source then return nil end
	local light = source:FindFirstChild("OuterSpotLight")
		or source:FindFirstChild("InnerSpotLight")
		or source:FindFirstChildWhichIsA("SpotLight", true)
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
-- Environment (cached)
--------------------------------------------------------------------------------

local function luminance(c)
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

local function refreshEnvironment()
	local now = os.clock()
	if now - envTime < ENV_REFRESH then return end
	envTime = now

	-- Darkness: 0 = bright, 1 = dark. Rough estimate; it cannot tell indoors from outdoors.
	local override = Lighting:GetAttribute("GlareDarkness")
	if type(override) == "number" then
		envDarkness = math.clamp(override, 0, 1)
	else
		local sun = math.clamp(math.sin((Lighting.ClockTime - 6) / 12 * math.pi) * 1.5, 0, 1)
		local daylight = sun * math.clamp(Lighting.Brightness / 3, 0, 1)
		envDarkness = 1 - math.clamp(daylight + luminance(Lighting.Ambient) * 1.25, 0, 1)
	end

	-- Scatter: how much particulate there is for a beam to light up.
	local scatterOverride = Lighting:GetAttribute("GlareScatter")
	if type(scatterOverride) == "number" then
		envScatter = math.clamp(scatterOverride, 0, 1)
	else
		local scatter = 0
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			scatter = atmosphere.Density * 1.2 + (atmosphere.Haze / 10) * 0.3
		end
		if Lighting.FogEnd < 5000 then
			scatter = math.max(scatter, (1 - Lighting.FogEnd / 5000) * 0.8)
		end
		envScatter = math.clamp(scatter, 0, 1)
	end
end

-- 0 = bright, 1 = dark. Set Lighting:SetAttribute("GlareDarkness", n) to override
-- (e.g. from interior zones).
function WeaponLighting.GetDarkness()
	refreshEnvironment()
	return envDarkness
end

-- Returns darkness, scatter.
function WeaponLighting.GetEnvironment()
	refreshEnvironment()
	return envDarkness, envScatter
end

-- Returns 0..1 visibility of a beam / light shaft, plus the air scatter value.
-- Beams show up in haze and fog, and in the dark.
-- Set Lighting:SetAttribute("GlareScatter", n) to override scatter.
function WeaponLighting.GetBeamVisibility(kind)
	refreshEnvironment()
	local base = if kind == "Laser" then LASER_BEAM_BASE else FLASHLIGHT_BEAM_BASE
	local visibility = (base + (1 - base) * envScatter) * (0.4 + 0.6 * envDarkness)
	return math.clamp(visibility, 0, 1), envScatter
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
	local bloom = if type(config.Bloom) == "table" then config.Bloom else {}
	local blindRange = sanitizeNumber(config.BlindRange, defaults.BlindRange, 0.01, 100000)

	return {
		-- Colors
		LightColor = lightColor,
		BlindColor = blindColor,

		-- Blind behavior
		BlindIntensity = sanitizeNumber(config.BlindIntensity, 1, 0, 10),
		BlindSize = if typeof(config.BlindSize) == "UDim2" then config.BlindSize else nil,
		BlindOffset = if typeof(config.BlindOffset) == "Vector3" then config.BlindOffset else Vector3.zero,
		BlindTransparency = sanitizeNumber(config.BlindTransparency, 0, 0, 1),
		BlindRange = blindRange,
		-- Exponent of the distance falloff: 2 = inverse-square, <1 = collimated.
		BlindFalloff = sanitizeNumber(config.BlindFalloff, defaults.BlindFalloff, 0, 10),
		-- Studs at which the strength is halved.
		BlindHalfDistance = sanitizeNumber(
			config.BlindHalfDistance, defaults.HalfDistanceFraction * blindRange, 0.1, 100000
		),
		-- Flashlight: aim tolerance around the cone. Laser: radius around the eye. Studs.
		BlindRadius = sanitizeNumber(config.BlindRadius, defaults.BlindRadius, 0, 100),
		MinBlindOpacity = sanitizeNumber(config.MinBlindOpacity, defaults.MinBlindOpacity, 0, 1),
		FadeSpeed = sanitizeNumber(config.FadeSpeed, defaults.FadeSpeed, 0.01, 1000),

		-- Flash blindness dynamics
		AttackSpeed = sanitizeNumber(config.AttackSpeed, defaults.AttackSpeed, 0.01, 1000),
		RecoverySpeed = sanitizeNumber(config.RecoverySpeed, defaults.RecoverySpeed, 0.01, 1000),
		HoldTime = sanitizeNumber(config.HoldTime, defaults.HoldTime, 0, 5),
		DaylightResistance = sanitizeNumber(config.DaylightResistance, defaults.DaylightResistance, 0, 1),

		ColorCorrection = {
			Enabled = config.ColorCorrection ~= false and correction.Enabled ~= false,
			Brightness = sanitizeNumber(correction.Brightness, defaults.Brightness, -1, 1),
			Saturation = sanitizeNumber(correction.Saturation, defaults.Saturation, -1, 1),
			Contrast = sanitizeNumber(correction.Contrast, defaults.Contrast, -1, 1),
			TintColor = sanitizeColor(correction.TintColor, blindColor:Lerp(WHITE, 0.5)),
		},

		Bloom = {
			Enabled = config.Bloom ~= false and bloom.Enabled ~= false,
			Intensity = sanitizeNumber(bloom.Intensity, defaults.Bloom.Intensity, 0, 10),
			Size = sanitizeNumber(bloom.Size, defaults.Bloom.Size, 0, 56),
			Threshold = sanitizeNumber(bloom.Threshold, defaults.Bloom.Threshold, 0, 4),
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

-- One description of the flashlight cone, shared by the visible shaft and the blind test.
function WeaponLighting.GetBeamShape(source, settings)
	local light = findSpotLight(source)
	return {
		Light = light,
		Range = (settings and settings.LightRange) or (light and light.Range) or FALLBACK_SPOT_RANGE,
		Angle = if light then light.Angle else FALLBACK_SPOT_ANGLE,
		Face = if light then light.Face else Enum.NormalId.Front,
	}
end

--------------------------------------------------------------------------------
-- Public: light transport
--------------------------------------------------------------------------------

--[[
	Traces light from `origin` along `vector`.
	  - Invisible parts (Transparency >= 0.95) are skipped.
	  - Semi-transparent parts (glass) attenuate and are passed through.
	  - Opaque parts stop the trace.
	  - `ignore(part)` may return true to skip a part entirely (e.g. the receiver's gear).
	Returns the stopping RaycastResult (nil when the light reaches the end of
	`vector`) and the transmission (0..1) accumulated through glass.
]]
function WeaponLighting.Trace(origin, vector, params, ignore)
	local length = vector.Magnitude
	if length < 0.001 then return nil, 1 end

	local unit = vector / length
	local remaining = length
	local transmission = 1
	local lastHit

	for _ = 1, MAX_PASS_THROUGH do
		local hit = workspace:Raycast(origin, unit * remaining, params)
		if not hit then return nil, transmission end
		lastHit = hit

		local part = hit.Instance
		if not (ignore and ignore(part)) then
			local transparency = if part:IsA("Terrain") then 0 else part.Transparency
			if transparency < GLASS_MIN_TRANSPARENCY then
				return hit, transmission
			end
			if transparency < INVISIBLE_TRANSPARENCY then
				transmission *= (1 - transparency)
			end
		end

		remaining -= (hit.Position - origin).Magnitude + PASS_EPSILON
		if remaining <= 0 then return nil, transmission end
		origin = hit.Position + unit * PASS_EPSILON
	end

	-- Too many layers: treat the last one as the stopping surface.
	return lastHit, 0
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
			if settings.OverrideLightColor and light.Color ~= settings.LightColor then
				light.Color = settings.LightColor
			end
			if settings.LightRange ~= nil and light.Range ~= settings.LightRange then
				light.Range = settings.LightRange
			end
			if settings.LightBrightness ~= nil and light.Brightness ~= settings.LightBrightness then
				light.Brightness = settings.LightBrightness
			end
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
		if color:IsA("Color3Value") and color.Value ~= settings.LightColor then
			color.Value = settings.LightColor
		end
	end
	return settings
end

function WeaponLighting.ApplyLaserDot(dot, light, settings)
	-- A laser dot's glow is much less noticeable in daylight.
	local ambientScale = 0.35 + 0.65 * WeaponLighting.GetDarkness()

	dot.Color = settings.LightColor
	light.Color = settings.LightColor
	light.Brightness = settings.DotLightBrightness * ambientScale
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
	halo.Brightness = light.Brightness * settings.DotLightSoftness * 0.25
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