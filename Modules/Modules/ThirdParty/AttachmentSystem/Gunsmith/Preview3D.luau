--[[
	AttachmentSystem.Gunsmith.Preview3D
	────────────────────────────────────
	The rotating weapon preview shown beside the attachment columns.

	Note what this module *doesn't* do: it does not contain its own copy of
	the mounting maths. The original preview re-implemented `EquipAttachment`'s
	root resolution, `MountOffset` application, relative transforms and
	`HideGunParts` handling in a second place, and the two copies could (and
	did) drift. Here the layout is computed by `Mounter.ComputeLayout` — the
	same function the live rig uses — and `Mounter.Build` is called with
	`welded = false` so parts are simply positioned instead of Motor6D'd.
]]

local UserInputService = game:GetService("UserInputService")

local Config     = require(script.Parent.Parent.Config)
local ConfigLoader = require(script.Parent.Parent.ConfigLoader)
local Mounter    = require(script.Parent.Parent.Mounter)

local Preview3D = {}

Preview3D.__index = Preview3D

local NEAR_EXPAND = 0.28
local BUFFER      = 0.04

function Preview3D.new(options)
	return setmetatable({
		viewport = options.viewport,
		weapon   = options.weapon,
		system   = options.system,

		worldModel = nil,
		gunModel   = nil,
		camera     = nil,

		origTransparency = {},
		partCache       = {},

		yaw   = options.yaw   or -30,
		pitch = options.pitch or 15,
		radius = options.radius or 5,
		minRadius = 0,
		maxRadius = 0,
		maxDimension = 2,

		center = Vector3.zero,
		dragging = false,
		lastInput = nil,
		connections = {},
	}, Preview3D)
end

-- ─── Camera framing ─────────────────────────────────────────────────────────

--[[
	Work out how far back the camera must sit for every visible part of the
	model to stay in frame. Uses a slab test against each part's oriented box
	along the view direction, so an optic that extends the silhouette forward
	widens the shot automatically.
]]
function Preview3D:_computeMinRadius()
	local safe = self.minRadius
	local yaw   = math.rad(self.yaw)
	local pitch = math.rad(math.clamp(self.pitch, -80, 80))
	local cosPitch = math.cos(pitch)

	local dir = Vector3.new(
		math.sin(yaw) * cosPitch,
		math.sin(pitch),
		math.cos(yaw) * cosPitch
	)

	for _, part in ipairs(self.partCache) do
		local cf = part.CFrame
		local half = part.Size * 0.5

		local lo = cf:PointToObjectSpace(Vector3.zero)
		local ld = cf:VectorToObjectSpace(dir)

		local hx = half.X + NEAR_EXPAND
		local hy = half.Y + NEAR_EXPAND
		local hz = half.Z + NEAR_EXPAND

		local tMin, tMax = -math.huge, math.huge
		local hit = true

		for axis = 1, 3 do
			if not hit then break end
			local o = (axis == 1) and lo.X or (axis == 2) and lo.Y or lo.Z
			local d = (axis == 1) and ld.X or (axis == 2) and ld.Y or ld.Z
			local h = (axis == 1) and hx  or (axis == 2) and hy  or hz

			if math.abs(d) < 1e-8 then
				if o < -h or o > h then
					hit = false
				end
			else
				local inv = 1 / d
				local t1, t2 = (-h - o) * inv, (h - o) * inv
				if t1 > t2 then t1, t2 = t2, t1 end
				if t1 > tMin then tMin = t1 end
				if t2 < tMax then tMax = t2 end
				if tMin > tMax then hit = false end
			end
		end

		if hit and tMax > 0 then
			local needed = tMax + BUFFER
			if needed > safe then
				safe = needed
			end
		end
	end

	return safe
end

function Preview3D:_updateCamera()
	if not self.camera or not self.camera.Parent then
		return
	end

	local effective = math.max(self.radius, self:_computeMinRadius())
	local yaw   = math.rad(self.yaw)
	local pitch = math.rad(math.clamp(self.pitch, -80, 80))

	local position = self.center + Vector3.new(
		math.sin(yaw) * math.cos(pitch) * effective,
		math.sin(pitch) * effective,
		math.cos(yaw) * math.cos(pitch) * effective
	)

	self.camera.CFrame = CFrame.new(position, self.center)
end

function Preview3D:_rebuildCache()
	self.partCache = {}
	if not self.worldModel then
		return
	end
	for _, part in ipairs(self.worldModel:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			table.insert(self.partCache, part)
		end
	end
end

function Preview3D:_computeBounds()
	local minB = Vector3.new(math.huge, math.huge, math.huge)
	local maxB = Vector3.new(-math.huge, -math.huge, -math.huge)
	local any = false

	for _, part in ipairs(self.partCache) do
		any = true
		local cf = part.CFrame
		local s  = part.Size * 0.5
		for _, dx in ipairs({ -1, 1 }) do
			for _, dy in ipairs({ -1, 1 }) do
				for _, dz in ipairs({ -1, 1 }) do
					local corner = cf * Vector3.new(s.X * dx, s.Y * dy, s.Z * dz)
					minB = Vector3.new(math.min(minB.X, corner.X), math.min(minB.Y, corner.Y), math.min(minB.Z, corner.Z))
					maxB = Vector3.new(math.max(maxB.X, corner.X), math.max(maxB.Y, corner.Y), math.max(maxB.Z, corner.Z))
				end
			end
		end
	end

	if not any then
		self.center = Vector3.zero
		return
	end
	self.center = (minB + maxB) * 0.5

	local span = (maxB - minB)
	self.maxDimension = math.max(span.X, span.Y, span.Z, 0.5)
end

-- ─── Attachment display ─────────────────────────────────────────────────────

--[[
	Redraw the fitted attachments for a selection map. Any previously previewed
	attachment is removed first, and every part the preview hid is restored to
	exactly what it was before — including genuine transparency, which the
	original preview flattened to 0.
]]
function Preview3D:ApplySelection(selection: { [string]: string }?)
	if not self.gunModel then
		return
	end

	for _, child in ipairs(self.worldModel:GetChildren()) do
		if child ~= self.gunModel then
			child:Destroy()
		end
	end

	for part, transparency in pairs(self.origTransparency) do
		if part and part.Parent then
			part.Transparency = transparency
		end
	end
	table.clear(self.origTransparency)

	if type(selection) ~= "table" then
		self:_rebuildCache()
		return
	end

	for _, category in ipairs(Config.GetCategoryList()) do
		local name = selection[category]
		if type(name) == "string" and name ~= "" then
			local source = ConfigLoader.GetAttachmentFolder(name, category)
			if source then
				local layout = Mounter.ComputeLayout(self.gunModel, source, {
					category       = category,
					attachmentName = name,
				})
				if layout then
					local holder = Mounter.Build(layout, self.worldModel, false)
					if holder then
						-- Keep the previewed attachment out of the way of the
						-- next one so names stay unique and teardown is simple.
						holder.Name = name .. "_Preview"
						for _, child in ipairs(holder:GetChildren()) do
							if child:IsA("BasePart") then
								child.Anchored   = true
								child.CanCollide = false
								child.CastShadow = false
							end
						end
					end
				end
			end
		end
	end

	for _, category in ipairs(Config.GetCategoryList()) do
		local source = selection[category]
		if type(source) == "string" and source ~= "" then
			local config = ConfigLoader.Load(source, category)
			for _, partName in ipairs((config and config.HideGunParts) or {}) do
				local part = self.gunModel:FindFirstChild(partName, true)
				if part and part:IsA("BasePart") then
					self.origTransparency[part] = part.Transparency
					part.Transparency = (config and config.HideTransparency) or 1
				end
			end
		end
	end

	self:_rebuildCache()
	self:_updateCamera()
end

-- ─── Setup / teardown ───────────────────────────────────────────────────────

function Preview3D:_connectInput()
	self:ClearInput()
	local viewport = self.viewport
	if not viewport then
		return
	end

	table.insert(self.connections, viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			self.dragging  = true
			self.lastInput = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))

	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		if not self.dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if self.lastInput then
				local delta = pos - self.lastInput
				self.yaw   = self.yaw - delta.X * 0.5
				self.pitch = math.clamp(self.pitch + delta.Y * 0.5, -80, 80)
				self:_updateCamera()
			end
			self.lastInput = pos
		end
	end))

	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			self.dragging  = false
			self.lastInput = nil
		end
	end))

	table.insert(self.connections, viewport.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self.radius = math.clamp(
				self.radius - input.Position.Z * (self.maxDimension * 0.15),
				self.minRadius,
				self.maxRadius
			)
			self:_updateCamera()
		end
	end))
end

function Preview3D:ClearInput()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.dragging  = false
	self.lastInput = nil
end

function Preview3D:Clear()
	self:ClearInput()

	if self.viewport then
		for _, child in ipairs(self.viewport:GetChildren()) do
			if child.Name ~= "title" then
				child:Destroy()
			end
		end
	end

	self.worldModel = nil
	self.gunModel   = nil
	self.camera     = nil
	table.clear(self.origTransparency)
	table.clear(self.partCache)
end

--[[
	Build the preview for a weapon.

	@param sourceModel the gun model template to clone (may be supplied by the
	                   host, since where weapon models live is the host's
	                   business, not the attachment system's)
	@return true when a preview was created
]]
function Preview3D:Build(sourceModel: Instance?, weaponName: string?, fieldOfView: number?)
	self:Clear()
	if not self.viewport or not sourceModel then
		return false
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = self.viewport
	self.worldModel = worldModel

	local gunClone = sourceModel:Clone()
	gunClone.Parent = worldModel
	self.gunModel = gunClone

	for _, part in ipairs(gunClone:GetDescendants()) do
		if part:IsA("BasePart") then
			self.origTransparency[part] = part.Transparency
			part.Anchored   = true
			part.CanCollide = false
			part.CastShadow = false
		end
	end

	self:_rebuildCache()
	if #self.partCache == 0 then
		worldModel:Destroy()
		self.worldModel = nil
		self.gunModel   = nil
		return false
	end

	self:_computeBounds()

	local camera = Instance.new("Camera")
	camera.FieldOfView = fieldOfView or 50
	self.viewport.CurrentCamera = camera
	camera.Parent = self.viewport
	self.camera = camera

	self:_rebuildCache()
	self:_updateCamera()
	self:_connectInput()
	return true
end

-- Keep the framing correct as attachments come and go.
function Preview3D:Refresh()
	self:_rebuildCache()
	self:_computeBounds()
	self:_updateCamera()
end

Preview3D.defaultFieldOfView = 50

return Preview3D
