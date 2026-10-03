-- Minimal Roblox doubles for running GunAttachments outside Roblox (Luau CLI).
-- Only what the package touches is implemented.

local Mocks = {}

-- ─── Signal ──────────────────────────────────────────────────────────────────
local function newSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local conn = { Connected = true }
		handlers[conn] = fn
		function conn:Disconnect()
			conn.Connected = false
			handlers[conn] = nil
		end
		return conn
	end
	function signal:Fire(...)
		for conn, fn in pairs(table.clone(handlers)) do
			if conn.Connected then
				fn(...)
			end
		end
	end
	function signal:Count()
		local n = 0
		for _ in pairs(handlers) do
			n += 1
		end
		return n
	end
	return signal
end
Mocks.newSignal = newSignal

-- ─── CFrame (translation-only, enough to verify composition) ────────────────
local CFrameMT = {}
CFrameMT.__index = CFrameMT
local function cf(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, CFrameMT)
end
CFrameMT.__mul = function(a, b)
	return cf(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
CFrameMT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
CFrameMT.__tostring = function(a)
	return ("CFrame(%g,%g,%g)"):format(a.X, a.Y, a.Z)
end
function CFrameMT:Inverse()
	return cf(-self.X, -self.Y, -self.Z)
end
Mocks.CFrame = { new = cf }

-- ─── Instance ────────────────────────────────────────────────────────────────
local SUPER = {
	Part = "BasePart",
	MeshPart = "BasePart",
	UnionOperation = "BasePart",
	SpotLight = "Light",
	PointLight = "Light",
	SurfaceLight = "Light",
	Tool = "BackpackItem",
}

local DEFAULTS = {
	BasePart = { Transparency = 0, CanCollide = true, Anchored = false, Massless = false, CastShadow = true },
	Light = { Enabled = true },
	ParticleEmitter = { Enabled = true },
	Beam = { Enabled = true },
	Attachment = { Visible = false },
	StringValue = { Value = "" },
}

local InstanceMT = {}
local methods = {}

local function isA(className, target)
	local current = className
	while current do
		if current == target then
			return true
		end
		current = SUPER[current]
	end
	return target == "Instance"
end

local function newInstance(className)
	local raw = {
		_class = className,
		_props = { Name = className },
		_children = {},
		_attributes = {},
		_destroyed = false,
	}
	raw._props.Destroying = newSignal()
	local self = setmetatable(raw, InstanceMT)
	for klass, defaults in pairs(DEFAULTS) do
		if isA(className, klass) then
			for key, value in pairs(defaults) do
				raw._props[key] = value
			end
		end
	end
	if className == "Attachment" then
		raw._props.CFrame = cf()
	end
	if isA(className, "BasePart") then
		raw._props.CFrame = cf()
	end
	return self
end

InstanceMT.__index = function(self, key)
	if methods[key] then
		return methods[key]
	end
	if key == "ClassName" then
		return rawget(self, "_class")
	end
	if key == "WorldCFrame" and rawget(self, "_class") == "Attachment" then
		local parent = self._props.Parent
		local base = parent and parent._props.CFrame or cf()
		return base * self._props.CFrame
	end
	local props = rawget(self, "_props")
	local value = props[key]
	if value ~= nil then
		return value
	end
	-- child lookup by name (like inst.Child)
	for _, child in ipairs(rawget(self, "_children")) do
		if child._props.Name == key then
			return child
		end
	end
	return nil
end

InstanceMT.__newindex = function(self, key, value)
	if rawget(self, "_destroyed") and key == "Parent" and value ~= nil then
		error("The Parent property of " .. tostring(self._props.Name) .. " is locked")
	end
	if key == "Parent" then
		local old = self._props.Parent
		if old == value then
			return
		end
		if old then
			local siblings = old._children
			for index = #siblings, 1, -1 do
				if siblings[index] == self then
					table.remove(siblings, index)
				end
			end
		end
		self._props.Parent = value
		if value then
			table.insert(value._children, self)
		end
		return
	end
	self._props[key] = value
end

InstanceMT.__tostring = function(self)
	return self._props.Name
end

function methods:IsA(className)
	return isA(self._class, className)
end

function methods:GetChildren()
	return table.clone(self._children)
end

function methods:GetDescendants()
	local result = {}
	local function walk(node)
		for _, child in ipairs(node._children) do
			table.insert(result, child)
			walk(child)
		end
	end
	walk(self)
	return result
end

function methods:FindFirstChild(name, recursive)
	assert(name ~= nil, "Argument 1 missing or nil")
	for _, child in ipairs(self._children) do
		if child._props.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in ipairs(self._children) do
			local found = child:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function methods:FindFirstChildOfClass(className)
	for _, child in ipairs(self._children) do
		if child._class == className then
			return child
		end
	end
	return nil
end

function methods:FindFirstChildWhichIsA(className)
	for _, child in ipairs(self._children) do
		if child:IsA(className) then
			return child
		end
	end
	return nil
end

function methods:ClearAllChildren()
	for _, child in ipairs(table.clone(self._children)) do
		child:Destroy()
	end
end

function methods:Destroy()
	if rawget(self, "_destroyed") then
		return
	end
	for _, child in ipairs(table.clone(self._children)) do
		child:Destroy()
	end
	self._props.Destroying:Fire()
	self.Parent = nil
	rawset(self, "_destroyed", true)
end

function methods:Clone()
	local copy = newInstance(self._class)
	for key, value in pairs(self._props) do
		if key ~= "Parent" and key ~= "Destroying" then
			copy._props[key] = value
		end
	end
	for key, value in pairs(self._attributes) do
		copy._attributes[key] = value
	end
	for _, child in ipairs(self._children) do
		child:Clone().Parent = copy
	end
	return copy
end

function methods:SetAttribute(name, value)
	self._attributes[name] = value
end

function methods:GetAttribute(name)
	return self._attributes[name]
end

function methods:GetAttributes()
	return table.clone(self._attributes)
end

Mocks.Instance = { new = newInstance }

-- Helper to build trees: make("Part", {Name="X", Parent=p, ...})
function Mocks.make(className, props, children)
	local inst = newInstance(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Fake HttpService with a tiny JSON encoder/decoder sufficient for flat tables.
local function encode(value)
	local kind = type(value)
	if kind == "table" then
		if getmetatable(value) == CFrameMT then
			error("CFrame is not JSON-serialisable")
		end
		local parts = {}
		local keys = {}
		for key in pairs(value) do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, key in ipairs(keys) do
			table.insert(parts, string.format("%q:%s", tostring(key), encode(value[key])))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif kind == "string" then
		return string.format("%q", value)
	elseif kind == "number" or kind == "boolean" then
		return tostring(value)
	elseif kind == "nil" then
		return "null"
	end
	error("cannot encode " .. kind)
end

Mocks.Http = {}
local lastEncoded = {}
function Mocks.Http:JSONEncode(value)
	local json = encode(value)
	lastEncoded[json] = Mocks.deepCopyPlain(value)
	return json
end
function Mocks.Http:JSONDecode(json)
	local value = lastEncoded[json]
	if not value then
		error("unknown json")
	end
	return Mocks.deepCopyPlain(value)
end

function Mocks.deepCopyPlain(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in pairs(value) do
		copy[key] = Mocks.deepCopyPlain(inner)
	end
	return copy
end

return Mocks
