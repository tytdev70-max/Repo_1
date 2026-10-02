--[[
	FlashlightBeamMod
	Visible light-shaft beam for flashlights.
]]

local FlashlightBeamMod = {}

local WeaponLighting = require(script.Parent.WeaponLighting)

local TERRAIN = workspace.Terrain

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BEAM_TEXTURE = "rbxassetid://901813002"
local SOURCE_ATTACHMENT_NAME = "FlashlightBeamSource"

local RANGE_FALLBACK = 18
local ANGLE_FALLBACK = 45
local MIN_BEAM_LENGTH = 0.5
local START_WIDTH = 0.1
local MIN_END_WIDTH = 0.05

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

	local settings = WeaponLighting.ApplyFlashlight(flashlightPart, weaponStats)
	beam.Color = ColorSequence.new(settings.LightColor)

	local light = WeaponLighting.GetSpotLight(flashlightPart)
	local range = settings.LightRange or (light and light.Range) or RANGE_FALLBACK
	local angle = if light then light.Angle else ANGLE_FALLBACK
	local face = if light then light.Face else Enum.NormalId.Front

	-- Aim the source attachment down the light's emission face.
	local sourceAttachment = syncSourceAttachment(beam, flashlightPart)
	sourceAttachment.CFrame = CFrame.new(Vector3.zero, WeaponLighting.GetFaceDirection(face))

	local originCFrame = sourceAttachment.WorldCFrame
	local origin = originCFrame.Position
	local hit = workspace:Raycast(origin, originCFrame.LookVector * range, rayParams)

	local length = if hit then (hit.Position - origin).Magnitude else range
	length = math.max(length, MIN_BEAM_LENGTH)

	endAttachment.WorldCFrame = originCFrame * CFrame.new(0, 0, -length)
	beam.Width0 = START_WIDTH
	beam.Width1 = math.max(2 * length * math.tan(math.rad(angle / 2)), MIN_END_WIDTH)
end

function FlashlightBeamMod.SetEnabled(flashlightPart, toggle, weaponStats)
	if not flashlightPart then return end

	WeaponLighting.ApplyFlashlight(flashlightPart, weaponStats)

	local inner = flashlightPart:FindFirstChild("InnerSpotLight")
	local outer = flashlightPart:FindFirstChild("OuterSpotLight")
	if inner then inner.Enabled = toggle end
	if outer then outer.Enabled = toggle end

	getOrCreateSourceAttachment(flashlightPart)
end

return FlashlightBeamMod