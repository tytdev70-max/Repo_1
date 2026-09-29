local FlashlightBeamMod = {}
local TERRAIN = workspace.Terrain
local BEAM_TEXTURE = "rbxassetid://901813002"
local BEAM_RANGE_FALLBACK = 18
local MIN_BEAM_LENGTH = 0.5
local FACE_DIRECTIONS = {
	[Enum.NormalId.Front]  = Vector3.new(0, 0, -1),
	[Enum.NormalId.Back]   = Vector3.new(0, 0, 1),
	[Enum.NormalId.Right]  = Vector3.new(1, 0, 0),
	[Enum.NormalId.Left]   = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Top]    = Vector3.new(0, 1, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
}
local function getOrCreateSourceAttachment(flashlightPart)
	local existing = flashlightPart:FindFirstChild("FlashlightBeamSource")
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local sourceAtt = Instance.new("Attachment")
	sourceAtt.Name = "FlashlightBeamSource"
	sourceAtt.Parent = flashlightPart
	return sourceAtt
end
local function syncSourceAttachment(beam, flashlightPart)
	local current = beam.Attachment0
	if current and current.Parent == flashlightPart then
		return current
	end
	local sourceAtt = getOrCreateSourceAttachment(flashlightPart)
	beam.Attachment0 = sourceAtt
	return sourceAtt
end
function FlashlightBeamMod.CreateBeam(name)
	local endAtt = Instance.new("Attachment")
	endAtt.Name = name .. "_EndProxy"
	endAtt.Parent = TERRAIN
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment1 = endAtt
	beam.Brightness    = 0.01
	beam.Color          = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	beam.LightEmission  = 1
	beam.LightInfluence = 0
	beam.Texture        = BEAM_TEXTURE
	beam.TextureLength  = 1
	beam.TextureMode    = Enum.TextureMode.Stretch
	beam.TextureSpeed   = 0
	beam.Transparency   = NumberSequence.new(0, 1)
	beam.ZOffset        = 0
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.FaceCamera = true
	beam.Segments   = 3
	beam.Width0     = 0.1
	beam.Width1     = 3
	beam.Enabled = false
	beam.Parent = TERRAIN
	return beam, endAtt
end
function FlashlightBeamMod.UpdateBeam(beam, flashlightPart, endAtt, rayParams)
	if not flashlightPart or not flashlightPart.Parent then return end
	local sourceAtt = syncSourceAttachment(beam, flashlightPart)
	local outer = flashlightPart:FindFirstChild("OuterSpotLight")
	local range = (outer and outer.Range) or BEAM_RANGE_FALLBACK
	local angle = (outer and outer.Angle) or 45
	local face  = (outer and outer.Face) or Enum.NormalId.Front
	local localDir = FACE_DIRECTIONS[face] or FACE_DIRECTIONS[Enum.NormalId.Front]
	sourceAtt.CFrame = CFrame.new(Vector3.new(), localDir)
	local originCFrame = sourceAtt.WorldCFrame
	local originPosition = originCFrame.Position
	local direction = originCFrame.LookVector
	local hit = workspace:Raycast(originPosition, direction * range, rayParams)
	local hitDistance = range
	if hit then
		hitDistance = (hit.Position - originPosition).Magnitude
	end
	hitDistance = math.max(hitDistance, MIN_BEAM_LENGTH)
	endAtt.WorldCFrame = originCFrame * CFrame.new(0, 0, -hitDistance)
	beam.Width0 = 0.1
	beam.Width1 = math.max(2 * hitDistance * math.tan(math.rad(angle / 2)), 0.05)
end
function FlashlightBeamMod.SetEnabled(flashlightPart, toggle)
	if not flashlightPart then return end
	local inner = flashlightPart:FindFirstChild("InnerSpotLight")
	local outer = flashlightPart:FindFirstChild("OuterSpotLight")
	if inner then inner.Enabled = toggle end
	if outer then outer.Enabled = toggle end
	getOrCreateSourceAttachment(flashlightPart)
end
return FlashlightBeamMod