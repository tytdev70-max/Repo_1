--[[
	GlareMod
	Screen glare / blinding from flashlights and lasers.

	Physically-motivated model:
	  - The receiver is the viewer's EYE (a small sphere at the head's center),
	    for both kinds. The body and the orbiting camera do not count.
	  - Intensity is driven by the light's INCIDENCE at the eye (how on-axis it
	    is in the viewer's visual field), not by where the viewer is staring
	    relative to the source — a light aimed at the face blinds even when the
	    gaze is elsewhere.
	  - Adaptation is asymmetric: glare attacks fast and releases slow, and a
	    lingering "adaptation" level (afterimage / elevated dark threshold)
	    persists after the light is gone. Per-weapon BlindAttackTime /
	    BlindReleaseTime (see WeaponLighting) tune both.
	  - The local player's own lights (their gun's flashlights/lasers) never
	    blind them, regardless of pose.
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
local FLASH_MAX_HALF_ANGLE = math.rad(80) -- keeps math.tan from exploding

-- The receiver of blinding is the local viewer's EYE: a small sphere at the
-- head's center (the eyes sit on the head's front face). Neither the body nor
-- the orbiting camera counts. Used by both kinds.
local EYE_RADIUS = 0.3

-- Retinal sensitivity: glare falls to zero this many degrees off the view
-- axis (how on-axis the light must be in the viewer's visual field). Overridable
-- per weapon via WeaponStats.BlindOffAxisAngleDeg.
local OFF_AXIS_DEFAULT = { Laser = 12, Flashlight = 50 }

-- Asymmetric adaptation time constants (seconds). Glare ATTACKS at the fast
-- rate and RELEASES at the slow one; the lingering adaptation level also
-- decays at the slow rate. Overridable per weapon via WeaponStats.
local ADAPT_DEFAULT = {
	Laser      = { attack = 0.06, release = 0.9 },
	Flashlight = { attack = 0.25, release = 2.5 },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local deps = {}
local camera
local sharedRayParams

local registries = { Flashlight = {}, Laser = {} } -- [kind][source] = entry
local effects = {} -- [kind] = effect

-- Lingering ocular adaptation per kind (0..1). Rises while a light is in the
-- eye, decays slowly after; drives the afterimage / elevated-threshold tail.
local adaptation = { Flashlight = 0, Laser = 0 } -- [kind] = number

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
	-- Both rigs belong to the local player. Mark them so evaluation never
	-- treats the viewer's own light as a threat: the viewmodel rig is
	-- camera-parented, so a character-ancestor walk alone would miss it.
	for _, source in ipairs({ fpSource, tpSource }) do
		if source and source.Parent and not source:GetAttribute("SPH_LocalLight") then
			source:SetAttribute("SPH_LocalLight", true)
		end
	end

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

-- True when the hit part belongs to the receiver's own body — the beam is
-- then clear of them. Tool- and WeaponRig-ancestored parts are excluded (their
-- own weapon can't block the beam reaching their own head); worn accessories
-- DO count as occluders.
local function isReceiverPart(part, character)
	if not part or not part:IsA("BasePart") or not part:IsDescendantOf(character) then
		return false
	end
	local ancestor = part.Parent
	while ancestor and ancestor ~= character do
		if ancestor:IsA("Tool") or ancestor.Name == "WeaponRig" then
			return false
		end
		ancestor = ancestor.Parent
	end
	return ancestor == character
end

-- The receiver's eye: the head part's position (eyes sit on its front face).
local function getEyePosition(character)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	return head.Position, head
end

-- Is this light the local viewer's own weapon light? Their own beam cannot
-- blind their own eyes — excluding it also stops the camera-parented
-- viewmodel light from self-blinding during inspect poses.
local function isOwnLight(source)
	if source:GetAttribute("SPH_LocalLight") then
		return true
	end
	local target = deps and deps.character
	if not target then
		return false
	end
	for ancestor in source:GetAncestry() do
		if ancestor == target then
			return true
		end
	end
	return false
end

-- Does the beam physically reach the receiver's eye?
--
-- Laser: the eye must sit within EYE_RADIUS of the beam line, in front of the
-- emitter and within range. A ray from the emitter through the eye is
-- occluded only by a blocker in FRONT of where the beam enters the eye
-- cylinder; a hit on the receiver's own head is the beam passing through the
-- volume the eye itself occupies, so it counts as the beam hitting the eye,
-- not as an occluder.
--
-- Flashlight: the eye must be inside the beam volume — the light cone
-- (half-angle, capped so math.tan stays sane) plus the author-tuned
-- BlindRadius plus EYE_RADIUS, so a beam aimed at the head still lands a few
-- studs off it — with an unobstructed line of sight from the emitter. The
-- receiver's own parts never block their own eyes.
local function beamReachesEye(source, kind, frame, eyePos, head, character, settings)
	local origin = frame.Position
	local forward = frame.LookVector
	local range = settings.BlindRange
	local light

	if kind == "Flashlight" then
		light = WeaponLighting.GetSpotLight(source)
		local face = if light then light.Face else Enum.NormalId.Front
		forward = frame:VectorToWorldSpace(WeaponLighting.GetFaceDirection(face))
		range = math.min(range, settings.LightRange or (light and light.Range) or FLASH_RANGE_FALLBACK)
	end
	if range <= 0 then return false end

	local toEye = eyePos - origin
	local along = forward:Dot(toEye)
	if along <= 0 or along > range then return false end

	local params = getRayParams(source)

	if kind == "Laser" then
		local offset = toEye - forward * along
		local offsetSquared = offset:Dot(offset)
		local radiusSquared = EYE_RADIUS * EYE_RADIUS
		if offsetSquared > radiusSquared then return false end

		local distance = toEye.Magnitude
		local hit = workspace:Raycast(origin, forward * (distance + 1), params)
		if hit and hit.Instance == head then
			-- Eye is inside the head volume: the beam hitting the head IS the
			-- beam hitting the eye.
			return true
		end
		-- A blocker only matters if it sits between the emitter and the point
		-- where the beam enters the eye cylinder.
		local entryDistance = math.max(0, along - math.sqrt(radiusSquared - offsetSquared))
		return not hit or (hit.Position - origin).Magnitude > entryDistance + 0.001
	end

	-- Flashlight: eye inside the beam volume, with a clear line of sight.
	local radialOffset = (toEye - forward * along).Magnitude
	local angle = if light then light.Angle else FLASH_FALLBACK_ANGLE
	local halfAngle = math.min(math.rad(angle * 0.5), FLASH_MAX_HALF_ANGLE)
	local maxRadial = along * math.tan(halfAngle) + (settings.BlindRadius or 0) + EYE_RADIUS
	if radialOffset > maxRadial then return false end

	local distance = toEye.Magnitude
	local hit = workspace:Raycast(origin, forward * distance, params)
	if not hit then return true end
	return isReceiverPart(hit.Instance, character)
end

-- Returns 0..1 blind intensity, or nil when the source cannot blind the viewer.
local function evaluateSource(source, kind, camCFrame, settings)
	-- The local player's own lights cannot blind them.
	if isOwnLight(source) then return nil end

	local character = getReceiverCharacter()
	if not character then return nil end
	local eyePos, head = getEyePosition(character)
	if not eyePos then return nil end

	local frame = sourceCFrame(source)
	if not frame then return nil end

	local toSource = frame.Position - eyePos
	local distance = toSource.Magnitude
	if distance <= 0.01 or distance > settings.BlindRange then return nil end

	-- Incidence: how on-axis the light is in the viewer's VISUAL FIELD (angle
	-- between gaze and the eye->source direction). A light aimed at the face
	-- blinds even when the gaze is aimed elsewhere — what matters is where the
	-- light lands, not where the viewer is staring.
	local offAxisDeg = settings.BlindOffAxisAngleDeg or OFF_AXIS_DEFAULT[kind]
	local cosMin = math.cos(math.rad(offAxisDeg))
	local cosInc = camCFrame.LookVector:Dot(toSource / distance)
	if cosInc <= cosMin then return nil end

	if not beamReachesEye(source, kind, frame, eyePos, head, character, settings) then return nil end

	local incidenceIntensity = ((cosInc - cosMin) / (1 - cosMin)) ^ 2
	local distanceIntensity = (1 - distance / settings.BlindRange) ^ settings.BlindFalloff
	return math.clamp(incidenceIntensity * distanceIntensity * settings.BlindIntensity, 0, 1)
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

-- Asymmetric attack/release: the overlay rises at BlindAttackTime and falls
-- at BlindReleaseTime, so removing the light leaves a decaying afterglow
-- tail instead of a symmetric fade.
local function updateOverlay(effect, settings, intensity, dt)
	local current = effect.opacity
	local target = targetOpacity(settings, intensity)
	local tau = if target >= current then math.max(settings.BlindAttackTime, 0.001) else math.max(settings.BlindReleaseTime, 0.001)
	local alpha = 1 - math.exp(-dt / tau)
	current += (target - current) * alpha
	if intensity <= 0 and current <= EPSILON then current = 0 end
	effect.opacity = current
	setImages(effect.images, current, settings.BlindColor)
	effect.billboard.Enabled = intensity > 0 or current > 0
end

-- Driven by veil = max(intensity, adaptation): lingering ocular adaptation
-- keeps a low-threshold afterimage tint even after the light has gone.
local function updateColorCorrection(effect, settings, veil, alpha)
	local cc = effect.correction
	local config = settings.ColorCorrection
	local correcting = veil > 0 and config.Enabled

	local brightness = if correcting then config.Brightness * veil else 0
	local saturation = if correcting then config.Saturation * veil else 0
	local contrast = if correcting then config.Contrast * veil else 0
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

-- Lingering ocular adaptation: rises at the attack time constant while a
-- light is in the eye, decays slowly at the release one afterwards. Its
-- value persists as the afterimage / elevated-threshold tail.
local function stepAdaptation(kind, intensity, settings, dt)
	local level = adaptation[kind]
	local attack = settings.BlindAttackTime or ADAPT_DEFAULT[kind].attack
	local release = settings.BlindReleaseTime or ADAPT_DEFAULT[kind].release
	local tau = if intensity > 0 then math.max(attack, 0.02) else math.max(release, 0.1)
	level += (math.min(intensity, 1) - level) * (1 - math.exp(-dt / tau))
	if level < EPSILON then level = 0 end
	adaptation[kind] = level
	return level
end

local function applyEffect(kind, effect, source, settings, intensity, dt)
	-- Follow the strongest source; keep the last settings (and the billboard's
	-- last world origin) while fading out, so the afterimage lingers at the
	-- position the light last shone from.
	if source then
		effect.settings = settings
		effect.origin.WorldCFrame = sourceCFrame(source)
		effect.billboard.Size = settings.BlindSize or effect.baseSize
		effect.billboard.StudsOffset = settings.BlindOffset
		effect.billboard.MaxDistance = math.max(effect.baseMaxDistance, settings.BlindRange)
	end

	local active = effect.settings
	local veil = math.max(intensity, stepAdaptation(kind, intensity, active, dt))
	local alpha = fadeAlpha(active, dt)
	updateOverlay(effect, active, intensity, dt)
	updateColorCorrection(effect, active, veil, alpha)
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

	applyEffect(kind, effects[kind], bestSource, bestSettings, bestIntensity, dt)
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
		adaptation[kind] = 0
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