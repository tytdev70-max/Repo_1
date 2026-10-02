local Workspace = game:GetService("Workspace")

local Visualisation_Manager = {}

local DEFAULT_BEAM = Instance.new("Beam")
DEFAULT_BEAM.LightEmission = 0
DEFAULT_BEAM.LightInfluence = 1
DEFAULT_BEAM.TextureSpeed = 0
DEFAULT_BEAM.FaceCamera = true
DEFAULT_BEAM.Segments = 16
DEFAULT_BEAM.Width0 = 0.05
DEFAULT_BEAM.Width1 = 0.05
DEFAULT_BEAM.Transparency = NumberSequence.new(0)

function Visualisation_Manager.new(motionBlurData, spawnPosition, beamTemplate)
	local camera = Workspace.CurrentCamera
	local camcf = camera.CFrame

	local attach0 = Instance.new("Attachment")
	local attach1 = Instance.new("Attachment")
	attach0.Parent = Workspace.Terrain
	attach1.Parent = Workspace.Terrain

	local beam = (beamTemplate or DEFAULT_BEAM):Clone()
	beam.Attachment0 = attach0
	beam.Attachment1 = attach1
	if motionBlurData.color then
		beam.Color = ColorSequence.new(motionBlurData.color)
	end
	beam.Parent = Workspace.Terrain

	local t0, t1 = nil, os.clock()
	local p0, p1 = nil, camcf:PointToObjectSpace(spawnPosition)
	local v0, v1 = nil, nil

	local self = {}

	function self.Update(worldPosition)
		camcf = camera.CFrame
		local t2 = os.clock()
		local p2 = camcf:PointToObjectSpace(worldPosition)

		local v2
		if t0 then
			v2 = 2 / (t2 - t1) * (p2 - p1) - (p2 - p0) / (t2 - t0)
		else
			v2 = (p2 - p1) / (t2 - t1)
			v1 = v2
		end

		t0, v0, p0 = t1, v1, p1
		t1, v1, p1 = t2, v2, p2

		local dt = t1 - t0
		if dt <= 0 then return end

		local m0 = v0.Magnitude
		local m1 = v1.Magnitude

		attach0.WorldPosition = camcf:PointToWorldSpace(p0)
		attach1.WorldPosition = camcf:PointToWorldSpace(p1)

		if m0 > 1e-8 then attach0.Axis = camcf:VectorToWorldSpace(v0 / m0) end
		if m1 > 1e-8 then attach1.Axis = camcf:VectorToWorldSpace(v1 / m1) end

		local dist0 = math.max(-p0.Z, 0)
		local dist1 = math.max(-p1.Z, 0)

		local w0 = motionBlurData.size + motionBlurData.bloom * dist0
		local w1 = motionBlurData.size + motionBlurData.bloom * dist1

		local l = ((p1 - p0) * Vector3.new(1, 1, 0)).Magnitude
		local tr = 1 - 4 * motionBlurData.size * motionBlurData.size
			/ ((w0 + w1) * (2 * l + w0 + w1)) * motionBlurData.brightness

		beam.CurveSize0 = dt / 3 * m0
		beam.CurveSize1 = dt / 3 * m1
		beam.Width0 = w0
		beam.Width1 = w1
		beam.Transparency = NumberSequence.new(math.clamp(tr, 0, 1))
	end

	function self.Remove()
		if attach0 then attach0:Destroy() end
		if attach1 then attach1:Destroy() end
		if beam then beam:Destroy() end
		attach0, attach1, beam = nil, nil, nil
	end

	attach0.WorldPosition = spawnPosition
	attach1.WorldPosition = spawnPosition

	return self
end

return Visualisation_Manager