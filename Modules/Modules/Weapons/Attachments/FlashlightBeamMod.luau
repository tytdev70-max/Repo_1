--[[
	FlashlightBeamMod
	Visible light-shaft beam for flashlights.

	Realism:
	  - Cone shape comes from the same WeaponLighting.GetBeamShape the blind test uses,
	    so the visible shaft and the dazzle zone always agree.
	  - The shaft ends at the first opaque surface; glass and invisible parts don't stop it.
	  - The shaft is faint in clear, bright air and strong in haze, fog and darkness.
]]

local FlashlightBeamMod = {}

local WeaponLighting = require(script.Parent.WeaponLighting)

local TERRAIN = workspace.Terrain

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BEAM_TEXTURE = "rbxassetid://901813002"
local SOURCE_ATTACHMENT_NAME = "FlashlightBeamSource"

local MIN_BEAM_LENGTH = 0.5
local START_WIDTH = 0.1
local MIN_END_WIDTH = 0.05
local REFRESH_INTERVAL = 0.5 -- how often stats / light properties are re-applied

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- [flashlightPart] = { settings, shape, nextRefresh, attachment }
local states = setmetatable({}, { __mode = "k" })
local beamVisibility = setmetatable({}, { __mode = "k" }) -- [beam] = last applied visibility

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getOrCreateSourceAttachment(flashlightPart)
	local existing = flashlightPart:FindFirstChild(SOURCE_ATTACHMENT_NAME)
	if existing and existing:IsA("Attachment") then
		return existing
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = SOURCE_ATTACHMENT_NAME
	attachment.Parent = flashlightPart
	return attachment
end

local function syncSourceAttachment(beam, flashlightPart)
	local current = beam.Attachment0
	if current and current.Parent == flashlightPart then
		return current
	end

	local attachment = getOrCreateSourceAttachment(flashlightPart)
	beam.Attachment0 = attachment
	return attachment
end

-- Quantized so the sequence is rarely rebuilt.
local function applyVisibility(beam, visibility)
	visibility = math.floor(visibility * 20 + 0.5) / 20
	if beamVisibility[beam] == visibility then return end
	beamVisibility[beam] = visibility
	beam.Transparency = NumberSequence.new(1 - visibility, 1)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function FlashlightBeamMod.CreateBeam(name)
	local endAttachment = Instance.new("Attachment")
	endAttachment.Name = name .. "_EndProxy"
	endAttachment.Parent = TERRAIN

	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment1 = endAttachment

	-- Look
	beam.Brightness = 0.01
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new(0, 1)
	beam.ZOffset = 0

	-- Texture
	beam.Texture = BEAM_TEXTURE
	beam.TextureLength = 1
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureSpeed = 0

	-- Shape
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.FaceCamera = true
	beam.Segments = 3
	beam.Width0 = START_WIDTH
	beam.Width1 = 3

	beam.Enabled = false
	beam.Parent = TERRAIN
	return beam, endAttachment
end

function FlashlightBeamMod.UpdateBeam(beam, flashlightPart, endAttachment, rayParams, weaponStats)
	if not flashlightPart or not flashlightPart.Parent then return end

	local now = os.clock()
	local state = states[flashlightPart]
	if not state then
		state = { nextRefresh = 0 }
		states[flashlightPart] = state
	end

	-- Aim the source attachment down the light's emission face.
	local attachment = syncSourceAttachment(beam, flashlightPart)
	local refresh = now >= state.nextRefresh

	if refresh then
		state.nextRefresh = now + REFRESH_INTERVAL
		state.settings = WeaponLighting.ApplyFlashlight(flashlightPart, weaponStats)
		state.shape = WeaponLighting.GetBeamShape(flashlightPart, state.settings)
		beam.Color = ColorSequence.new(state.settings.LightColor)
	end
	if refresh or state.attachment ~= attachment then
		state.attachment = attachment
		attachment.CFrame = CFrame.new(Vector3.zero, WeaponLighting.GetFaceDirection(state.shape.Face))
	end

	local shape = state.shape
	local originCFrame = attachment.WorldCFrame
	local origin = originCFrame.Position

	-- Stops at the first opaque surface; glass and invisible parts don't end the shaft.
	local hit = WeaponLighting.Trace(origin, originCFrame.LookVector * shape.Range, rayParams)
	local length = if hit then (hit.Position - origin).Magnitude else shape.Range
	length = math.max(length, MIN_BEAM_LENGTH)

	endAttachment.WorldCFrame = originCFrame * CFrame.new(0, 0, -length)
	beam.Width0 = START_WIDTH
	beam.Width1 = math.max(2 * length * math.tan(math.rad(shape.Angle / 2)), MIN_END_WIDTH)

	-- The shaft is only really visible in dim or hazy air.
	applyVisibility(beam, (WeaponLighting.GetBeamVisibility("Flashlight")))
end

function FlashlightBeamMod.SetEnabled(flashlightPart, toggle, weaponStats)
	if not flashlightPart then return end

	WeaponLighting.ApplyFlashlight(flashlightPart, weaponStats)
	states[flashlightPart] = nil -- re-resolve shape and settings on the next update

	for _, light in ipairs(flashlightPart:GetDescendants()) do
		if light:IsA("SpotLight") then light.Enabled = toggle end
	end

	getOrCreateSourceAttachment(flashlightPart)
end

return FlashlightBeamMod