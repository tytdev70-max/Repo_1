--!nonstrict
-- Customize/Preview
-- 3D weapon preview inside a ViewportFrame: orbit camera (drag), zoom (wheel), a
-- near-clip guard that keeps the camera outside the model, and live attachment
-- mounting for ANY slot.
--
-- Camera/bounds/near-clip math is ported unchanged from the legacy controller.
-- Mounting is generic: the mount part comes from attachments:GetSlotPartName(slot)
-- (no hard-coded slot map), attachments are mounted in slot order and parented inside
-- the gun clone — like the real mounting code — so stacked mounts (e.g. a muzzle
-- device on a barrel extension) preview the same way they mount in game.

local UserInputService = game:GetService("UserInputService")

local Preview = {}
Preview.__index = Preview

-- options:
--   viewport      ViewportFrame
--   attachments   GunAttachments system
--   getSourceModel function(tool) -> Model?  (clean model to preview)
--   config        config.preview
function Preview.new(options: { [string]: any })
	local self = setmetatable({}, Preview)
	self._viewport = options.viewport
	self._attachments = options.attachments
	self._getSourceModel = options.getSourceModel
	self._config = options.config
	self._inputConnections = {}
	self:_resetState()
	return self
end

function Preview:_resetState()
	self._worldModel = nil
	self._gun = nil
	self._camera = nil
	self._originalTransparency = {}
	self._mounted = {}
	self._partCache = {}
	self._center = Vector3.zero
	self._radius = 5
	self._maxDim = 2
	self._minRadius = 0
	self._maxRadius = 0
	self._yaw = self._config.yaw
	self._pitch = self._config.pitch
	self._dragging = false
	self._lastInput = nil
end

function Preview:_rebuildPartCache()
	local cache = {}
	if self._worldModel then
		for _, part in ipairs(self._worldModel:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 1 then
				table.insert(cache, part)
			end
		end
	end
	self._partCache = cache
end

-- Smallest camera distance along the current view direction that keeps the camera
-- outside every (slightly expanded) part box. Ray/OBB slab test per part.
function Preview:_dynamicMinRadius(): number
	if not self._worldModel then
		return self._minRadius
	end
	local yaw = math.rad(self._yaw)
	local pitch = math.rad(math.clamp(self._pitch, -80, 80))
	local cosPitch = math.cos(pitch)
	local direction = Vector3.new(math.sin(yaw) * cosPitch, math.sin(pitch), math.cos(yaw) * cosPitch)
	local safe = self._minRadius
	local expand = self._config.nearExpand
	local buffer = self._config.nearBuffer
	for _, part in ipairs(self._partCache) do
		local cf = part.CFrame
		local half = part.Size * 0.5
		local origin = cf:PointToObjectSpace(Vector3.zero)
		local dir = cf:VectorToObjectSpace(direction)
		local tMin, tMax = -math.huge, math.huge
		local hit = true
		for _, axis in ipairs({ "X", "Y", "Z" }) do
			local h = (half :: any)[axis] + expand
			local o = (origin :: any)[axis]
			local d = (dir :: any)[axis]
			if math.abs(d) < 1e-8 then
				if o < -h or o > h then
					hit = false
					break
				end
			else
				local inv = 1 / d
				local t1, t2 = (-h - o) * inv, (h - o) * inv
				if t1 > t2 then
					t1, t2 = t2, t1
				end
				if t1 > tMin then
					tMin = t1
				end
				if t2 < tMax then
					tMax = t2
				end
				if tMin > tMax then
					hit = false
					break
				end
			end
		end
		if hit and tMax > 0 and tMax + buffer > safe then
			safe = tMax + buffer
		end
	end
	return safe
end

function Preview:_updateCamera()
	local camera = self._camera
	if not camera or not camera.Parent then
		return
	end
	local yaw = math.rad(self._yaw)
	local pitch = math.rad(math.clamp(self._pitch, -80, 80))
	local radius = math.max(self._radius, self:_dynamicMinRadius())
	local position = self._center + Vector3.new(
		math.sin(yaw) * math.cos(pitch) * radius,
		math.sin(pitch) * radius,
		math.cos(yaw) * math.cos(pitch) * radius
	)
	camera.CFrame = CFrame.new(position, self._center)
end

function Preview:_disconnectInput()
	for _, connection in ipairs(self._inputConnections) do
		connection:Disconnect()
	end
	table.clear(self._inputConnections)
	self._dragging = false
	self._lastInput = nil
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function Preview:_connectInput()
	self:_disconnectInput()
	local viewport = self._viewport
	local sensitivity = self._config.dragSensitivity
	local connections = self._inputConnections
	table.insert(connections, viewport.InputBegan:Connect(function(input)
		if isPress(input) then
			self._dragging = true
			self._lastInput = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if not self._dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local position = Vector2.new(input.Position.X, input.Position.Y)
			if self._lastInput then
				local delta = position - self._lastInput
				self._yaw -= delta.X * sensitivity
				self._pitch = math.clamp(self._pitch + delta.Y * sensitivity, -80, 80)
				self:_updateCamera()
			end
			self._lastInput = position
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			self._dragging = false
			self._lastInput = nil
		end
	end))
	table.insert(connections, viewport.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self._radius = math.clamp(
				self._radius - input.Position.Z * (self._maxDim * self._config.zoomStep),
				self._minRadius,
				self._maxRadius
			)
			self:_updateCamera()
		end
	end))
end

function Preview:Clear()
	self:_disconnectInput()
	if self._worldModel then
		self._worldModel:Destroy()
	end
	if self._camera then
		self._camera:Destroy()
	end
	self:_resetState()
end

-- Builds the preview for `tool`. Returns false when there is nothing to show.
function Preview:Show(tool: Tool): boolean
	self:Clear()
	if not self._config.enabled or not self._viewport or not tool then
		return false
	end
	local source = self._getSourceModel and self._getSourceModel(tool)
	if not source then
		return false
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = self._viewport
	self._worldModel = worldModel

	local gun = source:Clone()
	gun.Parent = worldModel
	local parts = {}
	for _, part in ipairs(gun:GetDescendants()) do
		if part:IsA("BasePart") then
			self._originalTransparency[part] = part.Transparency
			part.Anchored = true
			part.CanCollide = false
			part.CastShadow = false
			table.insert(parts, part)
		end
	end
	if #parts == 0 then
		return false
	end

	-- World-space bounds from every part corner, then recentre the model on origin.
	local minB = Vector3.new(math.huge, math.huge, math.huge)
	local maxB = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in ipairs(parts) do
		local cf, s = part.CFrame, part.Size * 0.5
		for dx = -1, 1, 2 do
			for dy = -1, 1, 2 do
				for dz = -1, 1, 2 do
					local corner = cf * Vector3.new(s.X * dx, s.Y * dy, s.Z * dz)
					minB = minB:Min(corner)
					maxB = maxB:Max(corner)
				end
			end
		end
	end
	local center = (minB + maxB) / 2
	local extents = maxB - minB
	for _, part in ipairs(parts) do
		part.CFrame = part.CFrame - center
	end

	self._gun = gun
	self._center = Vector3.zero
	self._maxDim = math.max(extents.X, extents.Y, extents.Z)
	local fov = self._config.fov
	self._radius = (extents.Magnitude * 0.5) / math.tan(math.rad(fov * 0.5))
	self._minRadius = self._maxDim * self._config.minRadiusFactor
	self._maxRadius = self._radius * self._config.maxRadiusFactor
	self._yaw = self._config.yaw
	self._pitch = self._config.pitch

	local camera = Instance.new("Camera")
	camera.FieldOfView = fov
	camera.Parent = self._viewport
	self._viewport.CurrentCamera = camera
	self._camera = camera

	self:_rebuildPartCache()
	self:_updateCamera()
	self:_connectInput()
	return true
end

local function resolveRoot(folder: Instance, config: any): Instance?
	if type(config.RootPart) == "string" then
		return folder:FindFirstChild(config.RootPart)
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

-- Mounts `loadout` on the preview gun (replacing the previous preview attachments).
function Preview:SetLoadout(loadout: { [string]: string })
	local gun = self._gun
	if not gun then
		return
	end
	for _, container in ipairs(self._mounted) do
		container:Destroy()
	end
	table.clear(self._mounted)
	for part, transparency in pairs(self._originalTransparency) do
		if part.Parent then
			part.Transparency = transparency
		end
	end

	local attachments = self._attachments
	-- Mount in slot order (stacked mounts need their parent mounted first).
	for _, def in ipairs(attachments:GetSlots()) do
		local name = loadout[def.name]
		if not name then
			continue
		end
		local config = attachments:LoadConfig(def.name, name)
		local folder = attachments:GetContentFolder(def.name, name)
		local slotPart = gun:FindFirstChild(def.mountPart, true)
		local mountPoint = slotPart and slotPart:FindFirstChild(name)
		if not config or not folder or not mountPoint or not mountPoint:IsA("Attachment") then
			continue
		end
		local originalRoot = resolveRoot(folder, config)
		if not originalRoot then
			continue
		end
		local rootCFrame = mountPoint.WorldCFrame * (config.MountOffset or CFrame.new())
		local container = Instance.new("Model")
		container.Name = name .. "_Preview"
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				local clone = child:Clone()
				clone.Anchored = true
				clone.CanCollide = false
				clone.CastShadow = false
				clone.CFrame = if child == originalRoot
					then rootCFrame
					else rootCFrame * (originalRoot.CFrame:Inverse() * child.CFrame)
				clone.Parent = container
			end
		end
		container.Parent = slotPart
		table.insert(self._mounted, container)
		for _, partName in ipairs(config.HideGunParts or {}) do
			local hidden = gun:FindFirstChild(partName, true)
			if hidden and hidden:IsA("BasePart") then
				hidden.Transparency = config.HideTransparency or 1
			end
		end
	end
	self:_rebuildPartCache()
	self:_updateCamera()
end

function Preview:Destroy()
	self:Clear()
end

return Preview
