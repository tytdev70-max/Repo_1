--[[
	GlareMod
	Screen glare / blinding from flashlights and lasers.

	Viewer-facing thresholds and the exponential fade are unchanged. Exposure
	additionally requires the beam to actually reach the receiver:
	  - Laser:      only the head (or the camera's virtual eye) blinds.
	  - Flashlight: the camera only has to be inside the beam volume (cone + aim tolerance).
]]

local Players = game:GetService("Players")

local assets = script:FindFirstAncestor("Modules").Parent
local WeaponLighting = require(script.Parent.WeaponLighting)
local LightingBillboards = require(script.Parent.LightingBillboards)

local GlareMod = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local KINDS = { "Flashlight", "Laser" }
local WHITE = Color3.new(1, 1, 1)
local EPSILON = 0.01

-- Viewer-facing thresholds
local FLASH_FALLBACK_ANGLE = 25
local FLASH_RANGE_FALLBACK = 18
local LASER_BLIND_ANGLE = 0.2 -- dot-product threshold

-- Flashlight: extra tolerance around the beam axis so a light pointed a few
-- studs past your head still blinds you. Override per weapon with BlindRadius.
local FLASH_AIM_RADIUS = 3
local FLASH_MAX_HALF_ANGLE = math.rad(80) -- keeps math.tan from exploding

-- Cameras are not raycastable Instances, so a small virtual eye target on the
-- laser axis stands in for the viewer's eyes.
local LASER_CAMERA_RADIUS = 0.15

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local deps = {}
local camera
local sharedRayParams

local registries = { Flashlight = {}, Laser = {} } -- [kind][source] = entry
local effects = {} -- [kind] = effect

--------------------------------------------------------------------------------
-- Generic helpers
--------------------------------------------------------------------------------

local function sourceCFrame(source)
	if source:IsA("Attachment") then return source.WorldCFrame end
	if source:IsA("BasePart") then return source.CFrame end
	return nil
end

local function getHostPart(source)
	return if source:IsA("BasePart") then source else source:FindFirstAncestorWhichIsA("BasePart")
end

local function resolveSettings(kind, source, weaponStats)
	if kind == "Flashlight" then
		return WeaponLighting.ApplyFlashlight(source, weaponStats)
	end
	return WeaponLighting.ApplyLaserSource(source, weaponStats)
end

local function collectImages(gui)
	local images = {}
	for _, image in ipairs(gui:GetDescendants()) do
		if image:IsA("ImageLabel") or image:IsA("ImageButton") then
			table.insert(images, { image = image, opacity = 1 - image.ImageTransparency })
		end
	end
	return images
end

local function setImages(images, opacity, color)
	for _, data in ipairs(images) do
		data.image.ImageColor3 = color
		data.image.ImageTransparency = 1 - data.opacity * opacity
	end
end

--------------------------------------------------------------------------------
-- Ray params
--------------------------------------------------------------------------------

local function getRayParams(source)
	if not sharedRayParams then
		sharedRayParams = RaycastParams.new()
		sharedRayParams.FilterType = Enum.RaycastFilterType.Exclude
		-- Character limbs may be non-collidable but must still be query targets.
		sharedRayParams.RespectCanCollide = false
	end

	local ignored = {}
	if camera then table.insert(ignored, camera) end -- cosmetic FP rig, not the real body

	-- Find the weapon model that owns this source (stop at a character).
	local weaponModel
	local ancestor = source
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Tool") or ancestor.Name == "WeaponRig" then
			weaponModel = ancestor
			break
		end
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then break end
		if ancestor:IsA("Model") then weaponModel = ancestor end
		ancestor = ancestor.Parent
	end

	local excluded = weaponModel or getHostPart(source)
	if excluded then table.insert(ignored, excluded) end

	-- Do not exclude deps.character: doing so makes self/body hits impossible.
	sharedRayParams.FilterDescendantsInstances = ignored
	return sharedRayParams
end

--------------------------------------------------------------------------------
-- Source registry
--------------------------------------------------------------------------------

local function createSourceEntry(kind, source)
	local billboard = LightingBillboards.Clone(assets, kind, "Indicator")
	billboard.Name = kind .. "GlareIndicator"
	billboard.Adornee = source
	billboard.Enabled = false -- toggle only registers; a verified hit controls visibility

	local host = getHostPart(source)
	billboard.Parent = host or source.Parent

	return { billboard = billboard, images = collectImages(billboard), opacity = 0 }
end

-- True when the weapon's stats explicitly author a color (these beat the legacy `color` argument).
local function hasAuthoredColor(kind, source, weaponStats)
	local stats = weaponStats or WeaponLighting.GetStatsForSource(source)
	local config = stats and stats[kind]
	return type(config) == "table"
		and (typeof(config.LightColor) == "Color3"
			or typeof(config.LaserColor) == "Color3"
			or typeof(config.BlindColor) == "Color3")
end

local function registerSource(kind, source, color, weaponStats)
	if not source or not sourceCFrame(source) then return end

	local registry = registries[kind]
	local entry = registry[source]
	if not entry then
		entry = createSourceEntry(kind, source)
		registry[source] = entry
	end

	entry.weaponStats = weaponStats
	entry.settings = resolveSettings(kind, source, weaponStats)

	local tint = entry.settings.LightColor
	if not hasAuthoredColor(kind, source, weaponStats) and typeof(color) == "Color3" then
		tint = color -- legacy callers
	end
	setImages(entry.images, entry.opacity, tint)
end

local function unregisterSource(kind, source)
	local registry = registries[kind]
	local entry = registry[source]
	if not entry then return end
	entry.billboard:Destroy()
	registry[source] = nil
end

local function setSourceActive(kind, source, active, color, weaponStats)
	if not source then return end
	if active then
		registerSource(kind, source, color, weaponStats)
	else
		unregisterSource(kind, source)
	end
end

local function setModelActive(kind, fpSource, tpSource, firstPerson, active, color, weaponStats)
	-- Deactivate the rig that is not in use, activate the one that is.
	setSourceActive(kind, if firstPerson then tpSource else fpSource, false)
	setSourceActive(kind, if firstPerson then fpSource else tpSource, active, color, weaponStats)
end

--------------------------------------------------------------------------------
-- Effects (full-screen blind overlay + color correction)
--------------------------------------------------------------------------------

local function createEffect(kind)
	-- A retained world anchor lets the billboard finish fading even when the
	-- emitting attachment/model is destroyed or switched out during the fade.
	local origin = Instance.new("Attachment")
	origin.Name = kind .. "BlindOrigin"
	origin.Parent = workspace.Terrain

	local billboard = LightingBillboards.Clone(assets, kind, "Blind")
	billboard.Name = kind .. "BlindBillboard"
	billboard.Adornee = origin
	billboard.Enabled = false
	billboard.Parent = origin

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = kind .. "GlareEffect"
	correction.Enabled = false
	correction.Parent = camera

	local images = collectImages(billboard)
	setImages(images, 0, WHITE)

	return {
		origin = origin,
		billboard = billboard,
		images = images,
		correction = correction,
		opacity = 0,
		baseSize = billboard.Size,
		baseMaxDistance = billboard.MaxDistance,
		settings = if kind == "Flashlight" then WeaponLighting.GetFlashlight() else WeaponLighting.GetLaser(),
	}
end

local function destroyEffect(effect)
	if not effect then return end
	effect.billboard:Destroy()
	effect.origin:Destroy()
	effect.correction:Destroy()
end

--------------------------------------------------------------------------------
-- Fade math
--------------------------------------------------------------------------------

local function fadeAlpha(settings, dt)
	return 1 - math.exp(-settings.FadeSpeed * dt)
end

local function targetOpacity(settings, intensity)
	if intensity <= 0 then return 0 end
	local minimum = settings.MinBlindOpacity * math.min(settings.BlindIntensity, 1)
	return math.max(intensity, minimum) * (1 - settings.BlindTransparency)
end

local function fadeOpacity(current, settings, intensity, alpha)
	current += (targetOpacity(settings, intensity) - current) * alpha
	if intensity <= 0 and current <= EPSILON then return 0 end
	return current
end

--------------------------------------------------------------------------------
-- Beam / receiver tests
--------------------------------------------------------------------------------

local function getReceiverCharacter()
	local character = deps.character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and character.Parent and humanoid and humanoid.Health > 0 then
		return character
	end
	return nil
end

-- A hit on the receiver's real body (not their tools, hats, or weapon rig).
local function isReceiverBodyHit(hit, character)
	local part = hit and hit.Instance
	if not part or not part:IsA("BasePart") or not part:IsDescendantOf(character) then return false end

	local ancestor = part.Parent
	while ancestor and ancestor ~= character do
		if ancestor:IsA("Tool") or ancestor:IsA("Accessory") or ancestor.Name == "WeaponRig" then
			return false
		end
		ancestor = ancestor.Parent
	end
	return ancestor == character
end

local function isReceiverHeadHit(hit, character)
	if not isReceiverBodyHit(hit, character) then return false end
	local head = character:FindFirstChild("Head")
	return head ~= nil and hit.Instance == head
end

-- Returns origin, forward direction, effective range and the SpotLight (flashlight only).
local function getBeamAxis(source, kind, frame, settings)
	local forward = frame.LookVector
	local range = settings.BlindRange
	local light

	if kind == "Flashlight" then
		light = WeaponLighting.GetSpotLight(source)
		local face = if light then light.Face else Enum.NormalId.Front
		forward = frame:VectorToWorldSpace(WeaponLighting.GetFaceDirection(face))
		range = math.min(range, settings.LightRange or (light and light.Range) or FLASH_RANGE_FALLBACK)
	end

	return frame.Position, forward, range, light
end

local function beamReachesReceiver(source, kind, frame, camPosition, settings)
	local character = getReceiverCharacter()
	if not character then return false end

	local origin, forward, range, light = getBeamAxis(source, kind, frame, settings)
	if range <= 0 then return false end

	local params = getRayParams(source)
	local hit = workspace:Raycast(origin, forward * range, params)
	local toCamera = camPosition - origin
	local along = forward:Dot(toCamera)

	-- LASER: head / eyes only. Body hits do NOT blind.
	if kind == "Laser" then
		if isReceiverHeadHit(hit, character) then return true end

		if along <= 0 or along > range then return false end
		local offset = toCamera - forward * along
		local offsetSquared = offset:Dot(offset)
		local radiusSquared = LASER_CAMERA_RADIUS * LASER_CAMERA_RADIUS
		if offsetSquared > radiusSquared then return false end

		-- Empty space beyond the eye is fine; an earlier wall/player/body part is not.
		local entryDistance = math.max(0, along - math.sqrt(radiusSquared - offsetSquared))
		return not hit or (hit.Position - origin).Magnitude > entryDistance
	end

	-- FLASHLIGHT: camera inside the beam volume (cone + aim tolerance) with a clear line of sight.
	if isReceiverBodyHit(hit, character) then return true end
	if along <= 0 or along > range then return false end

	local offset = (toCamera - forward * along).Magnitude
	local angle = if light then light.Angle else FLASH_FALLBACK_ANGLE
	local halfAngle = math.min(math.rad(angle * 0.5), FLASH_MAX_HALF_ANGLE)
	local aimRadius = settings.BlindRadius or FLASH_AIM_RADIUS

	-- Allowed distance from the axis grows with distance (cone) plus a constant tolerance.
	if offset > aimRadius + along * math.tan(halfAngle) then return false end

	local cameraHit = workspace:Raycast(origin, toCamera, params)
	return not cameraHit or isReceiverBodyHit(cameraHit, character)
end

-- Returns 0..1 blind intensity, or nil when the source cannot blind the viewer.
local function evaluateSource(source, kind, camCFrame, settings)
	local frame = sourceCFrame(source)
	if not frame then return nil end

	local toSource = frame.Position - camCFrame.Position
	local distance = toSource.Magnitude
	if distance <= 0.01 or distance > settings.BlindRange then return nil end

	-- Viewer must be looking roughly toward the source.
	local threshold
	if kind == "Flashlight" then
		local light = WeaponLighting.GetSpotLight(source)
		threshold = math.cos(math.rad(if light then light.Angle else FLASH_FALLBACK_ANGLE))
	else
		threshold = LASER_BLIND_ANGLE
	end
	local lookDot = camCFrame.LookVector:Dot(toSource / distance)
	if lookDot <= threshold then return nil end

	if not beamReachesReceiver(source, kind, frame, camCFrame.Position, settings) then return nil end

	local angleIntensity = (lookDot - threshold) / (1 - threshold)
	local distanceIntensity = (1 - distance / settings.BlindRange) ^ settings.BlindFalloff
	return math.clamp(angleIntensity * distanceIntensity * settings.BlindIntensity, 0, 1)
end

--------------------------------------------------------------------------------
-- Per-frame application
--------------------------------------------------------------------------------

local function isCorrectionSettled(cc)
	local tint = cc.TintColor
	return math.abs(cc.Brightness) <= EPSILON
		and math.abs(cc.Saturation) <= EPSILON
		and math.abs(cc.Contrast) <= EPSILON
		and math.abs(tint.R - 1) <= EPSILON
		and math.abs(tint.G - 1) <= EPSILON
		and math.abs(tint.B - 1) <= EPSILON
end

local function updateOverlay(effect, settings, intensity, alpha)
	effect.opacity = fadeOpacity(effect.opacity, settings, intensity, alpha)
	setImages(effect.images, effect.opacity, settings.BlindColor)
	effect.billboard.Enabled = intensity > 0 or effect.opacity > 0
end

local function updateColorCorrection(effect, settings, intensity, alpha)
	local cc = effect.correction
	local config = settings.ColorCorrection
	local correcting = intensity > 0 and config.Enabled

	local brightness = if correcting then config.Brightness * intensity else 0
	local saturation = if correcting then config.Saturation * intensity else 0
	local contrast = if correcting then config.Contrast * intensity else 0
	local tint = if correcting then config.TintColor else WHITE

	cc.Brightness += (brightness - cc.Brightness) * alpha
	cc.Saturation += (saturation - cc.Saturation) * alpha
	cc.Contrast += (contrast - cc.Contrast) * alpha
	cc.TintColor = cc.TintColor:Lerp(tint, alpha)

	if correcting then
		cc.Enabled = true
	elseif isCorrectionSettled(cc) then
		cc.Enabled = false
		cc.Brightness, cc.Saturation, cc.Contrast = 0, 0, 0
		cc.TintColor = WHITE
	end
end

local function applyEffect(effect, source, settings, intensity, dt)
	-- Follow the strongest source; keep the last settings while fading out.
	if source then
		effect.settings = settings
		effect.origin.WorldCFrame = sourceCFrame(source)
		effect.billboard.Size = settings.BlindSize or effect.baseSize
		effect.billboard.StudsOffset = settings.BlindOffset
		effect.billboard.MaxDistance = math.max(effect.baseMaxDistance, settings.BlindRange)
	end

	local active = effect.settings
	local alpha = fadeAlpha(active, dt)
	updateOverlay(effect, active, intensity, alpha)
	updateColorCorrection(effect, active, intensity, alpha)
end

local function updateSources(kind, camCFrame, dt)
	local registry = registries[kind]
	local bestSource, bestSettings
	local bestIntensity = 0

	for source, entry in pairs(registry) do
		if not source.Parent then
			unregisterSource(kind, source)
			continue
		end

		-- Remote Tool replication may finish after the toggle packet arrives.
		-- Retry resolution rather than locking that source to global/viewer values.
		local settings = resolveSettings(kind, source, entry.weaponStats)
		entry.settings = settings

		local intensity = evaluateSource(source, kind, camCFrame, settings) or 0
		entry.opacity = fadeOpacity(entry.opacity, settings, intensity, fadeAlpha(settings, dt))
		setImages(entry.images, entry.opacity, settings.LightColor)
		entry.billboard.Enabled = entry.opacity > 0

		if intensity > bestIntensity then
			bestSource, bestSettings, bestIntensity = source, settings, intensity
		end
	end

	applyEffect(effects[kind], bestSource, bestSettings, bestIntensity, dt)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function GlareMod.Init(dependencies)
	GlareMod.Cleanup()
	deps = dependencies
	camera = deps.camera or workspace.CurrentCamera
	LightingBillboards.Ensure(assets)

	-- Remove an overlay left by an older version; no ScreenGui is created here.
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local legacy = playerGui and playerGui:FindFirstChild("GlareFlareGui")
	if legacy then legacy:Destroy() end

	for _, kind in ipairs(KINDS) do
		effects[kind] = createEffect(kind)
	end
end

function GlareMod.Update(dt: number)
	if not camera or not effects.Flashlight or not effects.Laser then return end

	camera = workspace.CurrentCamera or camera
	for _, kind in ipairs(KINDS) do
		local correction = effects[kind].correction
		if correction.Parent ~= camera then correction.Parent = camera end
	end

	for _, kind in ipairs(KINDS) do
		updateSources(kind, camera.CFrame, dt)
	end
end

function GlareMod.Cleanup()
	for _, kind in ipairs(KINDS) do
		for source in pairs(registries[kind]) do
			unregisterSource(kind, source)
		end
		destroyEffect(effects[kind])
		effects[kind] = nil
	end
	camera = nil
end

function GlareMod.ResolveFlashlightColor(source, weaponStats)
	return WeaponLighting.GetFlashlight(source, weaponStats).LightColor
end

function GlareMod.SetFlashlightActive(source, active, color, weaponStats)
	setSourceActive("Flashlight", source, active, color, weaponStats)
end

function GlareMod.SetLaserActive(source, active, color, weaponStats)
	setSourceActive("Laser", source, active, color, weaponStats)
end

function GlareMod.SetFlashlightModelActive(fpSource, tpSource, firstPerson, active, color, weaponStats)
	setModelActive("Flashlight", fpSource, tpSource, firstPerson, active, color, weaponStats)
end

function GlareMod.SetLaserModelActive(fpSource, tpSource, firstPerson, active, color, weaponStats)
	setModelActive("Laser", fpSource, tpSource, firstPerson, active, color, weaponStats)
end

return GlareMod