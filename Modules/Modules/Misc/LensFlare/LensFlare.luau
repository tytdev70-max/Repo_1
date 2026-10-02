--[[
	LensFlare
	10/20/2025
	@gluGPU

	OOP module for Lens Flare Effects.
	
	Debloated by @TYT
--]]

local CollectionService = game:GetService("CollectionService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local SPH_Assets        = ReplicatedStorage:WaitForChild("SPH_Assets")
local Configuration     = require(SPH_Assets:WaitForChild("GameConfig"))
local flarePresetFolder = SPH_Assets.HUD:WaitForChild("LensFlareEffects")

local TAG_NAME = "IgnoreLensFlare"

local NUM_RAYS               = math.max(1,   Configuration.lensFlareRaycasts              or 5)
local TEST_RADIUS            = math.max(0,   Configuration.lensFlareRaycastRadius          or 7)
local TRANSPARENCY_THRESHOLD = math.clamp(   Configuration.lensFlareTransparencyThreshold  or 0.666, 0, 1)
local FLARES_ENABLED         = Configuration.lensFlareEnabled ~= false
local BASE_RESOLUTION        = Vector2.new(1920, 1080)

local PART_ATTRIBUTES = {
	LensFlareStrength = 1,
	LensFlareDistance = 0,
}

local ATTRIBUTES = {
	ColorBlend       = 0,
	Position         = vector.create(1, 1, 1),
	PositionMult     = 1,
	Rotates          = false,
	SizeFade         = NumberSequence.new(1),
	SquashFade       = NumberSequence.new(0),
	TransparencyFade = NumberSequence.new(0),
}

local PROPERTIES = {
	"Size", "Squash", "Transparency", "LocalTransparencyModifier",
	"Color", "Rotation", "ZOffset", "Lifetime",
}

-- Precompute ray offsets
local pi2       = math.pi * 2
local rayOffsets: { { number } } = table.create(NUM_RAYS)
for i = 1, NUM_RAYS do
	local angle    = pi2 * ((i - 1) / NUM_RAYS)
	rayOffsets[i]  = { math.cos(angle) * TEST_RADIUS, math.sin(angle) * TEST_RADIUS }
end

-- Reuse emit/clear method references
local _pe   = Instance.new("ParticleEmitter")
local emit  = _pe.Emit
local clear = _pe.Clear
_pe:Destroy()

-- Evaluates a NumberSequence at a given time in [0, 1]
local function evalNumberSequence(seq: NumberSequence, t: number): number
	local kps = seq.Keypoints
	if t <= 0 then return kps[1].Value end
	if t >= 1 then return kps[#kps].Value end
	for i = 1, #kps - 1 do
		local a, b = kps[i], kps[i + 1]
		if t >= a.Time and t < b.Time then
			return a.Value + (b.Value - a.Value) * ((t - a.Time) / (b.Time - a.Time))
		end
	end
end

-- ─── LensFlare ────────────────────────────────────────────────────────────────

export type LensFlare = {
	_id:             string,
	Enabled:         boolean,
	Camera:          Camera,
	Part:            BasePart | Attachment,
	Attachments:     { Attachment },
	FlareEmitters:   { ParticleEmitter },
	_attributeCache: { [Instance]: { [string]: any } },
	_attributeConns: { RBXScriptConnection },
	_propertyCache:  { [Instance]: { [string]: any } },
	Alpha:           number,
	_forceRecompute: boolean,
	RaycastParams:   RaycastParams,
	_connections:    { RBXScriptConnection },
}

local LensFlare   = {}
LensFlare.__index = LensFlare

function LensFlare.new(camera: Camera, flareStyle: string, part: BasePart | Attachment): LensFlare?
	if not FLARES_ENABLED then return nil end

	local flareFolder = flarePresetFolder:FindFirstChild(flareStyle)
	assert(flareFolder, `LensFlare: No lens flare folder called '{flareStyle}' under HUD.LensFlareEffects`)

	local assets = flareFolder:GetChildren()
	local self: LensFlare = setmetatable({}, LensFlare)

	self._id            = HttpService:GenerateGUID(false)
	self.Enabled        = true
	self.Camera         = camera
	self.Part           = part
	self.Attachments    = table.create(#assets)
	self.FlareEmitters  = table.create(#assets)
	self.Alpha          = 0
	self._forceRecompute = false

	local cache:      { [Instance]: { [string]: any } } = {}
	local conns:      { RBXScriptConnection }           = {}
	local propsCache: { [Instance]: { [string]: any } } = {}

	-- Cache part attributes
	local partCache: { [string]: any } = {}
	for name, default in PART_ATTRIBUTES do
		partCache[name] = part:GetAttribute(name) or default
		table.insert(conns, part:GetAttributeChangedSignal(name):Connect(function()
			partCache[name]      = part:GetAttribute(name) or default
			self._forceRecompute = true
		end))
	end
	cache[part] = partCache

	-- Build emitters
	local idx = 0
	for _, flareAsset in assets do
		if not flareAsset:IsA("ParticleEmitter") then continue end
		idx += 1

		local attachment      = Instance.new("Attachment")
		attachment.Name       = `LensFlare_{flareStyle}_{flareAsset.Name}`
		attachment.Parent     = camera
		self.Attachments[idx] = attachment

		local emitter         = Instance.fromExisting(flareAsset)
		emitter.ZOffset       = 0
		emitter.Enabled       = false
		emitter.Parent        = attachment
		self.FlareEmitters[idx] = emitter

		-- Attribute cache for this emitter
		local eCache: { [string]: any } = {}
		local partColor = part:IsA("BasePart") and part.Color or Color3.new(1, 1, 1)
		local hue, sat  = partColor:ToHSV()

		local function rebuildColor()
			local blend = eCache.ColorBlend
			if blend and blend > 0 then
				eCache._color = ColorSequence.new(Color3.fromHSV(hue, sat * blend, 1))
			end
		end

		for name, default in ATTRIBUTES do
			eCache[name] = emitter:GetAttribute(name) or default
			table.insert(conns, emitter:GetAttributeChangedSignal(name):Connect(function()
				eCache[name]         = emitter:GetAttribute(name) or default
				self._forceRecompute = true
				if name == "ColorBlend" then rebuildColor() end
			end))
		end

		rebuildColor()

		if part:IsA("BasePart") and eCache.ColorBlend and eCache.ColorBlend > 0 then
			table.insert(conns, part:GetPropertyChangedSignal("Color"):Connect(function()
				local c         = part.Color
				hue, sat        = c:ToHSV()
				rebuildColor()
				self._forceRecompute = true
			end))
		end

		-- Property cache for this emitter
		local pCache: { [string]: any } = {}
		for _, prop in PROPERTIES do
			pCache[prop] = emitter[prop]
		end

		cache[emitter]      = eCache
		propsCache[emitter] = pCache
	end

	self._attributeCache = cache
	self._attributeConns = conns
	self._propertyCache  = propsCache

	-- Raycast params
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { part, table.unpack(CollectionService:GetTagged(TAG_NAME)) }
	rayParams.FilterType  = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	self.RaycastParams    = rayParams

	self._connections = {
		CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(function(obj: Instance)
			self.RaycastParams:AddToFilter(obj)
		end),
	}

	RunService:BindToRenderStep(
		`LensFlare_{self._id}`,
		Enum.RenderPriority.Camera.Value + 10,
		function(delta: number)
			if self.Enabled then self:Update(delta) end
		end
	)

	return self
end

function LensFlare.Destroy(self: LensFlare)
	RunService:UnbindFromRenderStep(`LensFlare_{self._id}`)

	for _, conn in self._connections    do conn:Disconnect() end
	for _, conn in self._attributeConns do conn:Disconnect() end
	for _, emitter    in self.FlareEmitters do emitter:Destroy()    end
	for _, attachment in self.Attachments   do attachment:Destroy() end

	table.clear(self)
	setmetatable(self, nil)
end

function LensFlare.Update(self: LensFlare, delta: number)
	-- Global kill-switch (runtime toggle support)
	if not FLARES_ENABLED then
		self.Enabled = false
		for _, emitter in self.FlareEmitters do emitter.Enabled = false end
		return
	end

	self.Enabled = true

	debug.profilebegin(`LensFlareUpdate_{self._id}`)

	local camera  = self.Camera
	local part    = self.Part
	local partPos = part:IsA("Attachment") and part.WorldPosition or part.Position
	local cameraPos = camera.CFrame.Position

	local dir  = partPos - cameraPos
	local dist = vector.magnitude(dir)

	local cache      = self._attributeCache
	local propsCache = self._propertyCache
	local partCache  = cache[part]

	local strengthSetting: number = partCache.LensFlareStrength
	local distSetting:     number = partCache.LensFlareDistance

	if strengthSetting <= 0 then
		debug.profileend()
		return
	end

	if distSetting > 0 and dist > distSetting then
		debug.profileend()
		return
	end

	local alpha = math.clamp(
		vector.angle(camera.CFrame.LookVector, dir) / math.rad(camera.DiagonalFieldOfView) * 2,
		0, 1
	)
	if distSetting > 0 then alpha += dist / distSetting end
	if alpha >= 1 then
		debug.profileend()
		return
	end

	local screenPos = camera:WorldToViewportPoint(partPos)
	local pos       = camera:ViewportPointToRay(screenPos.X, screenPos.Y, 1).Origin
	local offset    = camera.CFrame:ToObjectSpace(CFrame.new(pos)).Position

	-- Visibility raycasting
	local rayParams      = self.RaycastParams
	local numRaysHit     = 0
	local normalizedPx   = (camera.ViewportSize / BASE_RESOLUTION).Magnitude

	debug.profilebegin(`LensFlareUpdate_{self._id}_RaycastStep`)
	for _, offPts in rayOffsets do
		local ray     = camera:ViewportPointToRay(screenPos.X + offPts[1] * normalizedPx, screenPos.Y + offPts[2] * normalizedPx, 1)
		local raycast = workspace:Raycast(ray.Origin, ray.Direction * dist, rayParams)
		if raycast then
			local inst = raycast.Instance
			if inst:IsA("BasePart")
				and inst.Transparency <= TRANSPARENCY_THRESHOLD
				and inst.LocalTransparencyModifier <= TRANSPARENCY_THRESHOLD
			then
				numRaysHit += 1
			else
				rayParams:AddToFilter(inst)
			end
		end
	end
	debug.profileend()

	local hitAlpha = numRaysHit / NUM_RAYS
	local newAlpha = strengthSetting * (1 - alpha) * (1 - hitAlpha)
	local lastAlpha = self.Alpha

	if hitAlpha >= 1 or alpha >= 1 then
		self.Alpha = newAlpha
		debug.profileend()
		return
	end

	-- Precompute lifetime once per Update call
	local lifetime = NumberRange.new(delta * 3)

	-- Fast path: alpha unchanged and no forced recompute — just re-emit
	if newAlpha == lastAlpha and not self._forceRecompute then
		for _, emitter in self.FlareEmitters do
			clear(emitter)
			local pc = propsCache[emitter]
			if pc.Lifetime ~= lifetime then
				emitter.Lifetime = lifetime
				pc.Lifetime = lifetime
			end
			emit(emitter, 1)
		end
		self.Alpha = newAlpha
		debug.profileend()
		return
	end

	self._forceRecompute = false

	for i, emitter in self.FlareEmitters do
		local attachment = self.Attachments[i]
		local eCache     = cache[emitter]
		local ePropsCache = propsCache[emitter]

		clear(emitter)

		local ePos:      vector         = eCache.Position
		local ePosMult:  number         = eCache.PositionMult
		local eRotates:  boolean        = eCache.Rotates
		local eSizeFade: NumberSequence = eCache.SizeFade
		local eSquashFade: NumberSequence = eCache.SquashFade
		local eTransFade: NumberSequence  = eCache.TransparencyFade
		local eColor:    ColorSequence?   = eCache._color

		-- Position
		local x, y = offset.X * ePos.x * ePosMult, offset.Y * ePos.y * ePosMult
		attachment.Position = vector.create(x, y, offset.Z)

		-- Derived values
		local size         = NumberSequence.new(evalNumberSequence(eSizeFade, alpha))
		local squash       = NumberSequence.new(evalNumberSequence(eSquashFade, alpha))
		local transparency = NumberSequence.new(math.lerp(evalNumberSequence(eTransFade, alpha), 1, hitAlpha))
		local transMod     = 1 - strengthSetting
		local zOffset      = math.min(-attachment.Position.Z * 0.8, 0)

		-- Apply only changed properties
		if ePropsCache.Size ~= size then
			emitter.Size        = size
			ePropsCache.Size    = size
		end
		if ePropsCache.Squash ~= squash then
			emitter.Squash      = squash
			ePropsCache.Squash  = squash
		end
		if ePropsCache.Transparency ~= transparency then
			emitter.Transparency      = transparency
			ePropsCache.Transparency  = transparency
		end
		if ePropsCache.LocalTransparencyModifier ~= transMod then
			emitter.LocalTransparencyModifier      = transMod
			ePropsCache.LocalTransparencyModifier  = transMod
		end
		if eColor and ePropsCache.Color ~= eColor then
			emitter.Color      = eColor
			ePropsCache.Color  = eColor
		end
		if eRotates then
			local rotation = NumberRange.new(math.deg(math.atan2(offset.Y, offset.X)))
			if ePropsCache.Rotation ~= rotation then
				emitter.Rotation      = rotation
				ePropsCache.Rotation  = rotation
			end
		end
		if ePropsCache.ZOffset ~= zOffset then
			emitter.ZOffset      = zOffset
			ePropsCache.ZOffset  = zOffset
		end
		if ePropsCache.Lifetime ~= lifetime then
			emitter.Lifetime      = lifetime
			ePropsCache.Lifetime  = lifetime
		end

		emit(emitter, 1)
	end

	self.Alpha = newAlpha
	debug.profileend()
end

return LensFlare