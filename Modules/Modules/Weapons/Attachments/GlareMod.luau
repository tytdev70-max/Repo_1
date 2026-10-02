--[[
	GlareMod
	Screen glare / flash blindness from flashlights and lasers.

	Model:
	  - Eye: camera in first person; the face of the head in third person.
	  - Gaze: sources far outside the field of view do nothing; ones near the
	    centre of view dazzle fully.
	  - Beam: laser must pass through a small volume around the eye; flashlight
	    uses the cone volume plus an aim tolerance, with smooth hotspot-to-edge falloff.
	  - Transport: invisible parts and the receiver's gear are ignored, glass
	    attenuates, anything else (including the receiver's torso) shields the eyes.
	  - Dynamics: fast attack, short hold, slow recovery (harder hits recover
	    slower), screen-locked afterimage, multiple sources stack.
	  - Environment: daylight and protective gear (character attribute
	    "GlareProtection", 0..1) reduce the effect.
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
local MAX_DT = 0.1

-- Gaze: dot-product thresholds between the eye's forward axis and the source.
local FLASH_GAZE_THRESHOLD = math.cos(math.rad(70))
local LASER_GAZE_THRESHOLD = 0.2
local GAZE_CORE = math.cos(math.rad(12)) -- full effect inside this

-- Flashlight beam volume
local FLASH_MAX_HALF_ANGLE = math.rad(80) -- keeps math.tan from exploding
local FLASH_CORE_FRACTION = 0.35 -- inside this fraction of the allowed offset = full strength

-- Laser: fraction of the eye radius that is full strength before the edge falls off
local LASER_EDGE_FRACTION = 0.6

-- Eye model
local FIRST_PERSON_HEAD_DISTANCE = 2 -- camera closer than this to the head = first person

-- Distance
local FALLOFF_WINDOW_START = 0.7 -- smooth cutoff begins here (fraction of BlindRange)

-- Settings cache
local SETTINGS_REFRESH = 0.5
local SETTINGS_RETRY = 0.2 -- while the weapon's stats haven't replicated yet

local AFTERIMAGE_DISTANCE = 6

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local deps = {}
local camera

local registries = { Flashlight = {}, Laser = {} } -- [kind][source] = entry
local effects = {} -- [kind] = effect

local eyeState = { Position = Vector3.zero, Look = Vector3.zAxis, Character = nil, Protection = 1 }
local traceCharacter -- receiver character used by the trace ignore callback

--------------------------------------------------------------------------------
-- Generic helpers
--------------------------------------------------------------------------------

local function smoothstep(edge0, edge1, x)
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

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
-- Ray params (one object per source; the filter is rebuilt on settings refresh)
--------------------------------------------------------------------------------

local function newRayParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = false -- limbs may be non-collidable but must be query targets
	params.IgnoreWater = true
	return params
end

local function buildFilter(source)
	local ignored = {}
	if camera then table.insert(ignored, camera) end -- cosmetic FP rig, not the real body

	-- Weapon model that owns the source, and the character holding it.
	local weaponModel, owner
	local pinned = false
	local ancestor = source
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
			owner = ancestor
			break
		end
		if not pinned then
			if ancestor:IsA("Tool") or ancestor.Name == "WeaponRig" then
				weaponModel = ancestor
				pinned = true
			elseif ancestor:IsA("Model") then
				weaponModel = ancestor
			end
		end
		ancestor = ancestor.Parent
	end

	local excluded = weaponModel or getHostPart(source)
	if excluded then table.insert(ignored, excluded) end

	-- The shooter's own limbs shouldn't shadow their muzzle. The receiver is never excluded.
	if owner then table.insert(ignored, owner) end
	return ignored
end

--------------------------------------------------------------------------------
-- Source registry
--------------------------------------------------------------------------------

local function createSourceEntry(kind, source)
	local billboard = LightingBillboards.Clone(assets, kind, "Indicator")
	billboard.Name = kind .. "GlareIndicator"
	billboard.Adornee = source
	billboard.Enabled = false

	local host = getHostPart(source)
	billboard.Parent = host or source.Parent

	return {
		billboard = billboard,
		images = collectImages(billboard),
		opacity = 0,
		tint = WHITE,
		rayParams = newRayParams(),
	}
end

-- True when the weapon's stats explicitly author a color (these beat the legacy `color` argument).
local function hasAuthoredColor(kind, stats)
	local config = stats and stats[kind]
	return type(config) == "table"
		and (typeof(config.LightColor) == "Color3"
			or typeof(config.LaserColor) == "Color3"
			or typeof(config.BlindColor) == "Color3")
end

-- Cached settings. Re-resolved on a timer so late-replicating tools are still picked up.
local function getSettings(kind, source, entry, now)
	local interval = if entry.statsResolved then SETTINGS_REFRESH else SETTINGS_RETRY
	if entry.settings and entry.settingsTime and now - entry.settingsTime < interval then
		return entry.settings
	end

	local stats = entry.weaponStats or WeaponLighting.GetStatsForSource(source)
	local settings = resolveSettings(kind, source, stats)

	entry.settings = settings
	entry.settingsTime = now
	entry.statsResolved = stats ~= nil
	entry.rayParams.FilterDescendantsInstances = buildFilter(source)
	entry.shape = if kind == "Flashlight" then WeaponLighting.GetBeamShape(source, settings) else nil

	local tint = settings.LightColor
	if not hasAuthoredColor(kind, stats) and typeof(entry.legacyColor) == "Color3" then
		tint = entry.legacyColor
	end
	entry.tint = tint
	return settings
end

local function registerSource(kind, source, color, weaponStats)
	if not source or not sourceCFrame(source) then return end

	local registry = registries[kind]
	local entry = registry[source]
	if not entry then
		entry = createSourceEntry(kind, source)
		registry[source] = entry
	end

	if entry.weaponStats ~= weaponStats or entry.legacyColor ~= color then
		entry.settingsTime = nil -- force a re-resolve
	end
	entry.weaponStats = weaponStats
	entry.legacyColor = color

	getSettings(kind, source, entry, os.clock())
	setImages(entry.images, entry.opacity, entry.tint)
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
-- Effects (full-screen blind overlay + color correction + bloom)
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

	local bloom = Instance.new("BloomEffect")
	bloom.Name = kind .. "GlareBloom"
	bloom.Enabled = false
	bloom.Intensity = 0
	bloom.Parent = camera

	local images = collectImages(billboard)
	setImages(images, 0, WHITE)

	return {
		origin = origin,
		billboard = billboard,
		images = images,
		correction = correction,
		bloom = bloom,
		level = 0, -- smoothed dazzle, 0..1
		peak = 0, -- strongest dazzle of the current episode (slows recovery)
		hold = 0, -- seconds before recovery starts
		afterimageDir = nil, -- camera-space direction of the last light seen
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
	effect.bloom:Destroy()
end

--------------------------------------------------------------------------------
-- Indicator fade (the glow other players see on the source)
--------------------------------------------------------------------------------

local function fadeAlpha(settings, dt)
	return 1 - math.exp(-settings.FadeSpeed * dt)
end

local function indicatorTarget(settings, intensity)
	if intensity <= 0 then return 0 end
	local minimum = settings.MinBlindOpacity * math.min(settings.BlindIntensity, 1)
	return math.max(intensity, minimum) * (1 - settings.BlindTransparency)
end

local function fadeIndicator(current, settings, intensity, alpha)
	current += (indicatorTarget(settings, intensity) - current) * alpha
	if intensity <= 0 and current <= EPSILON then return 0 end
	return current
end

--------------------------------------------------------------------------------
-- Receiver / eye model
--------------------------------------------------------------------------------

local function getReceiverCharacter()
	local character = deps.character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and character.Parent and humanoid and humanoid.Health > 0 then
		return character
	end
	return nil
end

-- First person: the camera is the eye. Third person: the face of the head.
local function getEye(camCFrame)
	local character = getReceiverCharacter()
	if not character then return nil end

	local protection = character:GetAttribute("GlareProtection")
	eyeState.Protection = 1 - math.clamp(if type(protection) == "number" then protection else 0, 0, 1)
	eyeState.Character = character

	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart")
		and (camCFrame.Position - head.Position).Magnitude > FIRST_PERSON_HEAD_DISTANCE then
		local face = head:FindFirstChild("FaceFrontAttachment")
		eyeState.Position = if face and face:IsA("Attachment")
			then face.WorldPosition
			else head.Position + head.CFrame.LookVector * 0.4
		eyeState.Look = head.CFrame.LookVector
	else
		eyeState.Position = camCFrame.Position
		eyeState.Look = camCFrame.LookVector
	end
	return eyeState
end

local function isOwnSource(source, eye)
	return (camera ~= nil and source:IsDescendantOf(camera)) or source:IsDescendantOf(eye.Character)
end

-- "head", "body", "gear" (tool/accessory/weapon rig) or nil when the part is not the receiver's.
local function classifyReceiverPart(part, character)
	if not part:IsDescendantOf(character) then return nil end

	local ancestor = part.Parent
	while ancestor and ancestor ~= character do
		if ancestor:IsA("Tool") or ancestor:IsA("Accessory") or ancestor.Name == "WeaponRig" then
			return "gear"
		end
		ancestor = ancestor.Parent
	end
	return if part.Name == "Head" and part.Parent == character then "head" else "body"
end

local function ignoreReceiverGear(part)
	return traceCharacter ~= nil and classifyReceiverPart(part, traceCharacter) == "gear"
end

--------------------------------------------------------------------------------
-- Beam tests
--------------------------------------------------------------------------------

-- Traces source -> eye. Invisible parts and the receiver's gear are ignored,
-- glass attenuates, everything else blocks. Reaching the face counts as clear.
-- Returns clear, transmission.
local function traceToEye(origin, eye, params)
	traceCharacter = eye.Character
	local hit, transmission = WeaponLighting.Trace(origin, eye.Position - origin, params, ignoreReceiverGear)
	if not hit then return true, transmission end
	if classifyReceiverPart(hit.Instance, eye.Character) == "head" then return true, transmission end
	return false, 0 -- walls, other players, or the receiver's torso/limbs
end

-- 0..~1.5: how squarely the eye sits in the beam, times transmission. 0 = not reached.
local function beamExposure(entry, kind, frame, eye, settings)
	local origin = frame.Position
	local forward, range, shape

	if kind == "Laser" then
		forward = frame.LookVector
		range = settings.BlindRange
	else
		shape = entry.shape
		if shape.Light and not shape.Light.Enabled then return 0 end -- switched off
		forward = frame:VectorToWorldSpace(WeaponLighting.GetFaceDirection(shape.Face))
		range = math.min(settings.BlindRange, shape.Range)
	end
	if range <= 0 then return 0 end

	local toEye = eye.Position - origin
	local along = forward:Dot(toEye)
	if along <= 0 or along > range then return 0 end

	local offset = (toEye - forward * along).Magnitude
	local axial
	local brightness = 1

	if kind == "Laser" then
		local radius = math.max(settings.BlindRadius, 0.01)
		axial = 1 - smoothstep(LASER_EDGE_FRACTION, 1, offset / radius)
	else
		local half = math.min(math.rad(shape.Angle * 0.5), FLASH_MAX_HALF_ANGLE)
		-- Allowed offset grows with distance (cone) plus a constant aim tolerance.
		local allowed = settings.BlindRadius + along * math.tan(half)
		axial = 1 - smoothstep(FLASH_CORE_FRACTION, 1, offset / math.max(allowed, 0.01))
		if shape.Light then
			brightness = math.clamp(math.sqrt(shape.Light.Brightness), 0.5, 1.5)
		end
	end
	if axial <= 0 then return 0 end

	local clear, transmission = traceToEye(origin, eye, entry.rayParams)
	if not clear then return 0 end

	return axial * transmission * brightness
end

local function distanceFactors(settings, distance, range)
	local falloff = 1 / (1 + (distance / settings.BlindHalfDistance) ^ settings.BlindFalloff)
	local window = 1 - smoothstep(FALLOFF_WINDOW_START, 1, distance / range)
	return falloff, window
end

-- Returns intensity (0..1), distance, floorScale. Returns nil when the source cannot blind the viewer.
local function evaluateSource(entry, source, kind, eye, settings, darkness)
	if isOwnSource(source, eye) then return end

	local frame = sourceCFrame(source)
	if not frame then return nil end
	
	local range = settings.BlindRange
	if kind == "Flashlight" and entry.shape then
		range = math.min(range, entry.shape.Range)
	end

	local toSource = frame.Position - eye.Position
	local distance = toSource.Magnitude
	if distance <= 0.01 or distance > range then return nil end

	-- Gaze: the source must be in the field of view; the centre of view is worst.
	local threshold = if kind == "Flashlight" then FLASH_GAZE_THRESHOLD else LASER_GAZE_THRESHOLD
	local lookDot = eye.Look:Dot(toSource / distance)
	if lookDot <= threshold then return nil end
	local gaze = smoothstep(threshold, GAZE_CORE, lookDot)

	-- Bright daylight and protective gear reduce the effect.
	local adaptation = eye.Protection * (1 - settings.DaylightResistance * (1 - darkness))
	if adaptation <= 0 then return nil end

	local falloff, window = distanceFactors(settings, distance, range)
	if window <= 0 then return nil end

	local exposure = beamExposure(entry, kind, frame, eye, settings)
	if exposure <= 0 then return nil end

	-- floorScale lets the MinBlindOpacity floor fade in with gaze/exposure/range,
	-- so the edge of a cone or the edge of range never pops.
	local floorScale = adaptation * gaze * exposure * window
	local intensity = floorScale * falloff * settings.BlindIntensity
	return math.clamp(intensity, 0, 1), distance, floorScale
end

--------------------------------------------------------------------------------
-- Per-frame application
--------------------------------------------------------------------------------

local function targetLevel(settings, intensity, floorScale)
	if intensity <= 0 then return 0 end
	local minimum = settings.MinBlindOpacity * math.min(settings.BlindIntensity, 1) * floorScale
	return math.clamp(math.max(intensity, minimum), 0, 1)
end

-- Fast attack, short hold, slow recovery (harder hits recover more slowly).
local function updateLevel(effect, settings, intensity, floorScale, dt)
	local target = targetLevel(settings, intensity, floorScale)
	local level = effect.level

	if target > 0 then
		effect.peak = math.max(effect.peak, target)
		effect.hold = settings.HoldTime * effect.peak
	else
		effect.hold = math.max(0, effect.hold - dt)
	end

	if target > level then
		level += (target - level) * (1 - math.exp(-settings.AttackSpeed * dt))
	elseif target > 0 or effect.hold <= 0 then
		local rate = settings.RecoverySpeed / (1 + effect.peak)
		level += (target - level) * (1 - math.exp(-rate * dt))
	end

	if target <= 0 and level <= EPSILON then
		level = 0
		effect.peak = 0
		effect.hold = 0
	end
	effect.level = level
end

local function updateOverlay(effect, settings)
	setImages(effect.images, effect.level * (1 - settings.BlindTransparency), settings.BlindColor)
	effect.billboard.Enabled = effect.level > 0
end

local function updateColorCorrection(effect, settings)
	local cc = effect.correction
	local config = settings.ColorCorrection
	local level = effect.level

	if level <= 0 or not config.Enabled then
		if cc.Enabled then
			cc.Enabled = false
			cc.Brightness, cc.Saturation, cc.Contrast = 0, 0, 0
			cc.TintColor = WHITE
		end
		return
	end

	cc.Enabled = true
	cc.Brightness = config.Brightness * level
	cc.Saturation = config.Saturation * level
	cc.Contrast = config.Contrast * level
	cc.TintColor = WHITE:Lerp(config.TintColor, level)
end

local function updateBloom(effect, settings)
	local bloom = effect.bloom
	local config = settings.Bloom
	local level = effect.level

	if level <= 0 or not config.Enabled then
		if bloom.Enabled then
			bloom.Enabled = false
			bloom.Intensity = 0
		end
		return
	end

	bloom.Enabled = true
	bloom.Intensity = config.Intensity * level
	bloom.Size = config.Size
	bloom.Threshold = 2 + (config.Threshold - 2) * level -- low levels bloom only the brightest pixels
end

local function applyEffect(effect, source, settings, intensity, floorScale, distance, camCFrame, dt)
	if source then
		-- Follow the strongest source; keep the last settings while fading out.
		effect.settings = settings

		local frame = sourceCFrame(source)
		effect.origin.WorldCFrame = frame

		local offset = frame.Position - camCFrame.Position
		if offset.Magnitude > 0.01 then
			effect.afterimageDir = camCFrame:VectorToObjectSpace(offset.Unit)
		end

		-- Glare blooms as the source gets closer.
		local proximity = 1 - math.clamp(distance / settings.BlindRange, 0, 1)
		local scale = 0.5 + 0.5 * proximity
		local size = settings.BlindSize or effect.baseSize
		effect.billboard.Size = UDim2.new(
			size.X.Scale, size.X.Offset * scale, size.Y.Scale, size.Y.Offset * scale
		)
		effect.billboard.StudsOffset = settings.BlindOffset
		effect.billboard.MaxDistance = math.max(effect.baseMaxDistance, settings.BlindRange)
	elseif effect.level > 0 and effect.afterimageDir then
		-- Retinal afterimage: stays where the light was on screen, not in the world.
		local direction = camCFrame:VectorToWorldSpace(effect.afterimageDir)
		effect.origin.WorldCFrame = CFrame.new(camCFrame.Position + direction * AFTERIMAGE_DISTANCE)
	end

	local active = effect.settings
	updateLevel(effect, active, intensity, floorScale, dt)
	updateOverlay(effect, active)
	updateColorCorrection(effect, active)
	updateBloom(effect, active)
end

local function updateSources(kind, eye, camCFrame, darkness, dt)
	local registry = registries[kind]
	local now = os.clock()

	local bestSource, bestSettings, bestDistance
	local bestIntensity, bestFloor = 0, 0
	local unblocked = 1 -- product of (1 - I): sources stack

	for source, entry in pairs(registry) do
		if not source.Parent then
			unregisterSource(kind, source)
			continue
		end

		local settings = getSettings(kind, source, entry, now)

		local intensity, distance, floorScale = 0, nil, 0
		if eye then
			intensity, distance, floorScale = evaluateSource(entry, source, kind, eye, settings, darkness)
			intensity = intensity or 0
		end

		entry.opacity = fadeIndicator(entry.opacity, settings, intensity, fadeAlpha(settings, dt))
		setImages(entry.images, entry.opacity, entry.tint)
		entry.billboard.Enabled = entry.opacity > 0

		if intensity > 0 then
			unblocked *= (1 - intensity)
			if intensity > bestIntensity then
				bestSource, bestSettings = source, settings
				bestIntensity, bestFloor, bestDistance = intensity, floorScale, distance
			end
		end
	end

	-- The strongest source positions the sprite; all sources contribute to the level.
	applyEffect(
		effects[kind], bestSource, bestSettings, 1 - unblocked, bestFloor, bestDistance, camCFrame, dt
	)
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

	dt = math.min(dt, MAX_DT) -- a hitch shouldn't snap the effect
	camera = workspace.CurrentCamera or camera
	for _, kind in ipairs(KINDS) do
		local effect = effects[kind]
		if effect.correction.Parent ~= camera then effect.correction.Parent = camera end
		if effect.bloom.Parent ~= camera then effect.bloom.Parent = camera end
	end

	local camCFrame = camera.CFrame
	local eye = getEye(camCFrame)
	local darkness = WeaponLighting.GetDarkness()

	for _, kind in ipairs(KINDS) do
		updateSources(kind, eye, camCFrame, darkness, dt)
	end
end

-- Current dazzle 0..1 (strongest of flashlight and laser). Useful for audio, aim sway, HUD.
function GlareMod.GetDazzle()
	local level = 0
	for _, kind in ipairs(KINDS) do
		local effect = effects[kind]
		if effect then level = math.max(level, effect.level) end
	end
	return level
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