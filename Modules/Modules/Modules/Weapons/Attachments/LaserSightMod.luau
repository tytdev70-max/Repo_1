--[[
	LaserSightMod
	Local + remote laser sights: beam, surface dot, and glare registration.
]]

local LaserSightMod = {}

local Modules = script:FindFirstAncestor("Modules")
local vars = require(Modules.Weapons.Core.WeaponState).get()
local WeaponLighting = require(script.Parent.WeaponLighting)

local TERRAIN = workspace.Terrain

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BEAM_LENGTH = 1.8
local RAY_LENGTH = 600
local DEFAULT_COLOR = Color3.fromRGB(255, 30, 30)

local BEAM_BASE_WIDTH = 0.022
local BEAM_TIP_WIDTH = 0.004
local BEAM_MIN_WIDTH = 0.008
local BEAM_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),
	NumberSequenceKeypoint.new(0.55, 0.60),
	NumberSequenceKeypoint.new(1, 1.0),
})

local DOT_SIZE = Vector3.new(0.045, 0.045, 0.045)
local DOT_SURFACE_OFFSET = 0.04

-- Names used to sweep leftovers from a previous session.
local WORKSPACE_INSTANCE_NAMES = {
	LocalLaserDot = true,
	OtherPlayerLaserDot = true,
}
local TERRAIN_INSTANCE_NAMES = {
	LaserSourceProxy = true,
	LaserBeamEndProxy = true,
	FirstPersonLaser = true,
	ThirdPersonLaser = true,
	OtherLaserBeamEnd = true,
	OtherPlayerLaser = true,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local deps = {}

-- Local player's laser
local laserDotPart, laserDotLight
local laserSourceProxy, laserBeamEndProxy
local laserBeamFP, laserBeamTP

-- Remote players' lasers, keyed by character
local otherPlayerLasers = {}

local localRayParams = RaycastParams.new()
localRayParams.FilterType = Enum.RaycastFilterType.Exclude
localRayParams.RespectCanCollide = true

local remoteRayParams = RaycastParams.new()
remoteRayParams.FilterType = Enum.RaycastFilterType.Exclude
remoteRayParams.RespectCanCollide = true

--------------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------------

local function destroyInstance(instance)
	if instance and instance.Parent then instance:Destroy() end
end

local function hideDot(dot, light)
	if dot then dot.CFrame = deps.storageCFrame end
	WeaponLighting.SetLaserDotEnabled(dot, light, false)
end

local function getBeamWidth()
	local t = os.clock()
	return math.max(BEAM_MIN_WIDTH, BEAM_BASE_WIDTH + math.sin(t * 58) * 0.003 + math.sin(t * 31) * 0.002)
end

local function getThirdPersonLaserSource()
	local getModel = deps.getThirdPersonGunModel
	local model = getModel and getModel()
	return model and deps.attachmentManager.GetLaserSource(model)
end

local function createDot(name, color)
	local dot = Instance.new("Part")
	dot.Name = name
	dot.Shape = Enum.PartType.Ball
	dot.Size = DOT_SIZE
	dot.Material = Enum.Material.Neon
	dot.Color = color
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.CastShadow = false
	dot.CFrame = deps.storageCFrame

	local light = Instance.new("PointLight")
	light.Name = "LaserDotLight"
	light.Enabled = false
	light.Parent = dot

	dot.Parent = workspace
	return dot, light
end

local function createBeam(name, attachment0, attachment1, color)
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1
	beam.LightInfluence = 0
	beam.Brightness = 3
	beam.Segments = 4
	beam.Width0 = BEAM_BASE_WIDTH
	beam.Width1 = BEAM_TIP_WIDTH
	beam.FaceCamera = true
	beam.Transparency = BEAM_TRANSPARENCY
	beam.Color = ColorSequence.new(color)
	beam.Enabled = false
	beam.Parent = TERRAIN
	return beam
end

-- Shortens the visible beam to the hit point and places the surface dot.
local function aimBeamAtSurface(source, beamEnd, dot, dotLight, rayParams)
	local frame = source.WorldCFrame
	local origin = frame.Position
	local hit = workspace:Raycast(origin, frame.LookVector * RAY_LENGTH, rayParams)

	if hit then
		local distance = (hit.Position - origin).Magnitude
		beamEnd.WorldCFrame = frame * CFrame.new(0, 0, -math.min(distance, BEAM_LENGTH))
		dot.CFrame = CFrame.new(hit.Position + hit.Normal * DOT_SURFACE_OFFSET)
		WeaponLighting.SetLaserDotEnabled(dot, dotLight, true)
	else
		beamEnd.WorldCFrame = frame * CFrame.new(0, 0, -BEAM_LENGTH)
		hideDot(dot, dotLight)
	end
end

--------------------------------------------------------------------------------
-- Cleanup helpers
--------------------------------------------------------------------------------

local function destroyEntry(data)
	if not data then return end
	if deps.glareMod and data.laserPart then
		deps.glareMod.SetLaserActive(data.laserPart, false)
	end
	destroyInstance(data.beam)
	destroyInstance(data.beamEnd)
	destroyInstance(data.dot)
end

local function isEntryStale(otherChar, data)
	if not otherChar or not otherChar.Parent then return true end
	local laserPart = data.laserPart
	if not laserPart or not laserPart.Parent then return true end
	return not laserPart:IsDescendantOf(otherChar)
end

local function isEntryDead(otherChar, data)
	if isEntryStale(otherChar, data) then return true end
	local humanoid = otherChar:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health <= 0
end

local function removeRemoteLaser(otherChar)
	destroyEntry(otherPlayerLasers[otherChar])
	otherPlayerLasers[otherChar] = nil
end

local function clearOtherPlayerLasers()
	for otherChar in pairs(otherPlayerLasers) do
		removeRemoteLaser(otherChar)
	end
end

local function sweepOrphanedInstances()
	for _, child in ipairs(workspace:GetChildren()) do
		if WORKSPACE_INSTANCE_NAMES[child.Name] then child:Destroy() end
	end
	for _, child in ipairs(TERRAIN:GetChildren()) do
		if TERRAIN_INSTANCE_NAMES[child.Name] then child:Destroy() end
	end
end

local function destroyLocalLaserInstances()
	destroyInstance(laserDotPart)
	destroyInstance(laserSourceProxy)
	destroyInstance(laserBeamEndProxy)
	destroyInstance(laserBeamFP)
	destroyInstance(laserBeamTP)

	laserDotPart, laserDotLight = nil, nil
	laserSourceProxy, laserBeamEndProxy = nil, nil
	laserBeamFP, laserBeamTP = nil, nil
end

--------------------------------------------------------------------------------
-- Local laser
--------------------------------------------------------------------------------

local function createLocalLaserInstances()
	laserDotPart, laserDotLight = createDot("LocalLaserDot", DEFAULT_COLOR)
	WeaponLighting.ApplyLaserDot(laserDotPart, laserDotLight, WeaponLighting.GetLaser(nil, vars.wepStats))

	laserSourceProxy = Instance.new("Attachment")
	laserSourceProxy.Name = "LaserSourceProxy"
	laserSourceProxy.Parent = TERRAIN

	laserBeamEndProxy = Instance.new("Attachment")
	laserBeamEndProxy.Name = "LaserBeamEndProxy"
	laserBeamEndProxy.Parent = TERRAIN

	laserBeamFP = createBeam("FirstPersonLaser", laserSourceProxy, laserBeamEndProxy, DEFAULT_COLOR)
	laserBeamTP = createBeam("ThirdPersonLaser", laserSourceProxy, laserBeamEndProxy, DEFAULT_COLOR)
end

local function hideLocalLaser()
	laserBeamFP.Enabled = false
	laserBeamTP.Enabled = false
	hideDot(laserDotPart, laserDotLight)
end

local function applyLocalLaserLighting(source)
	local settings = WeaponLighting.ApplyLaserSource(source, vars.wepStats)
	WeaponLighting.ApplyLaserDot(laserDotPart, laserDotLight, settings)
	laserBeamFP.Color = ColorSequence.new(settings.LightColor)
	laserBeamTP.Color = ColorSequence.new(settings.LightColor)
	return settings.LightColor
end

local function applyLaserGlareState(fpSource, enabled, color)
	if not deps.glareMod then return end
	deps.glareMod.SetLaserModelActive(
		fpSource, getThirdPersonLaserSource(), vars.firstPerson, enabled, color, vars.wepStats
	)
end

local function isToggleBlocked()
	local stats = vars.wepStats
	local fireTrack = stats and stats.fireAnim and vars.loadedAnims[stats.fireAnim]
	local firing = fireTrack and fireTrack.IsPlaying

	return vars.togglingAttachment
		or deps.isAnimationBusy()
		or vars.sprinting
		or vars.holdStance ~= 0
		or firing
end

-- Flip state, notify the server, refresh visuals and glare registration.
local function performToggle(laserSource)
	vars.laserEnabled = not vars.laserEnabled
	deps.playRepSound("Button")
	deps.playerToggleAttachment.send({ AttachmentType = 1, Enabled = vars.laserEnabled })

	local color = applyLocalLaserLighting(laserSource)
	applyLaserGlareState(laserSource, vars.laserEnabled, color)
end

function LaserSightMod.Init(dependencies)
	deps = dependencies
	destroyLocalLaserInstances()
	clearOtherPlayerLasers()
	sweepOrphanedInstances()
	createLocalLaserInstances()
end

function LaserSightMod.ToggleLocalLaser()
	if not laserDotPart then return end
	if isToggleBlocked() then return end

	local wepStats = vars.wepStats
	local laserSource = deps.attachmentManager.GetLaserSource(vars.gunModel)

	-- No toggle animation: flip immediately.
	if not (wepStats and wepStats.activateFlashlightLaser) then
		performToggle(laserSource)
		return
	end

	vars.togglingAttachment = true
	local track = deps.playAnimation(wepStats.activateFlashlightLaser, {
		priority = Enum.AnimationPriority.Action2,
	})

	-- Animation failed to load: flip immediately.
	if not track then
		if not vars.firstPerson then laserBeamTP.Enabled = true end
		performToggle(laserSource)
		vars.togglingAttachment = false
		return
	end

	-- Flip when the animation hits its "Button" keyframe.
	local connection
	connection = track.KeyframeReached:Connect(function(keyframeName)
		if keyframeName ~= "Button" then return end
		performToggle(laserSource)
		connection:Disconnect()
	end)
	track.Stopped:Once(function()
		vars.togglingAttachment = false
	end)
end

function LaserSightMod.UpdateLocalLaser()
	if not laserDotPart or not laserBeamFP or not laserBeamTP then return end

	local gunModel = vars.gunModel

	-- The laser attachment was removed from the gun while it was on.
	if vars.equipped and vars.laserEnabled then
		local stillPresent = gunModel.Grip:FindFirstChild("Laser")
			or deps.attachmentManager.HasLaserAttachment(gunModel)
		if not stillPresent then
			vars.laserEnabled = false
			hideLocalLaser()
			laserBeamTP.Attachment0 = nil
		end
	end

	-- Not active: make sure everything is hidden.
	if not (vars.equipped and vars.laserEnabled) then
		if laserBeamFP.Enabled or laserBeamTP.Enabled then hideLocalLaser() end
		return
	end

	-- Keep lighting + glare registration in sync with whichever rig is live.
	local fpSource = deps.attachmentManager.GetLaserSource(gunModel)
	local tpSource = getThirdPersonLaserSource()
	local color = applyLocalLaserLighting(fpSource or tpSource)
	if deps.glareMod and (fpSource or tpSource) then
		deps.glareMod.SetLaserModelActive(fpSource, tpSource, vars.firstPerson, true, color, vars.wepStats)
	end

	local laserPoint = if vars.firstPerson then fpSource else tpSource
	if not (laserPoint and laserPoint:IsA("Attachment")) then
		hideLocalLaser()
		return
	end

	-- Beam visuals
	laserSourceProxy.WorldCFrame = laserPoint.WorldCFrame
	local width = getBeamWidth()
	laserBeamFP.Width0 = width
	laserBeamTP.Width0 = width

	if vars.firstPerson then
		laserBeamFP.Enabled = true
		laserBeamTP.Enabled = false
	else
		laserBeamTP.Attachment0 = laserPoint
		laserBeamTP.Enabled = true
		laserBeamFP.Enabled = false
	end

	-- Beam end + surface dot
	localRayParams.FilterDescendantsInstances = { gunModel, deps.character }
	aimBeamAtSurface(laserPoint, laserBeamEndProxy, laserDotPart, laserDotLight, localRayParams)
end

function LaserSightMod.Reset()
	if deps.glareMod and deps.attachmentManager then
		local fpSource = deps.attachmentManager.GetLaserSource(vars.gunModel)
		deps.glareMod.SetLaserModelActive(fpSource, getThirdPersonLaserSource(), vars.firstPerson, false)
	end

	hideDot(laserDotPart, laserDotLight)

	if laserBeamFP then laserBeamFP.Enabled = false end
	if laserBeamTP then
		laserBeamTP.Enabled = false
		laserBeamTP.Attachment0 = laserSourceProxy
	end
end

--------------------------------------------------------------------------------
-- Remote lasers
--------------------------------------------------------------------------------

local function createRemoteLaser(otherCharacter, laserPart)
	local weaponStats = WeaponLighting.GetStatsForSource(laserPart)
	local lighting = WeaponLighting.ApplyLaserSource(laserPart, weaponStats)
	local color = lighting.LightColor

	if deps.glareMod then
		deps.glareMod.SetLaserActive(laserPart, true, color, weaponStats)
	end

	local dot, dotLight = createDot("OtherPlayerLaserDot", color)
	WeaponLighting.ApplyLaserDot(dot, dotLight, lighting)

	local beamEnd = Instance.new("Attachment")
	beamEnd.Name = "OtherLaserBeamEnd"
	beamEnd.Parent = TERRAIN

	local beam = createBeam("OtherPlayerLaser", laserPart, beamEnd, color)
	beam.Enabled = true

	otherPlayerLasers[otherCharacter] = {
		beam = beam,
		beamEnd = beamEnd,
		dot = dot,
		dotLight = dotLight,
		laserPart = laserPart,
		weaponStats = weaponStats,
	}
end

local function updateRemoteLaser(otherChar, data)
	data.weaponStats = data.weaponStats or WeaponLighting.GetStatsForSource(data.laserPart)
	local lighting = WeaponLighting.ApplyLaserSource(data.laserPart, data.weaponStats)

	WeaponLighting.ApplyLaserDot(data.dot, data.dotLight, lighting)
	data.beam.Color = ColorSequence.new(lighting.LightColor)
	data.beam.Width0 = getBeamWidth()

	if deps.glareMod then
		deps.glareMod.SetLaserActive(data.laserPart, true, lighting.LightColor, data.weaponStats)
	end

	remoteRayParams.FilterDescendantsInstances = { otherChar }
	aimBeamAtSurface(data.laserPart, data.beamEnd, data.dot, data.dotLight, remoteRayParams)
end

function LaserSightMod.HandleToggleAttachmentReplicate(Data)
	local laserPart, toggle, otherCharacter = Data.LaserPart, Data.Toggle, Data.OtherCharacter
	if not otherCharacter or otherCharacter == deps.character then return end
	if not laserPart or laserPart.Name ~= "Laser" then return end

	if not toggle then
		removeRemoteLaser(otherCharacter)
		if deps.glareMod then deps.glareMod.SetLaserActive(laserPart, false) end
		return
	end

	local existing = otherPlayerLasers[otherCharacter]
	if existing then
		local alreadyShowing = existing.laserPart == laserPart and existing.beam and existing.beam.Parent
		if alreadyShowing then return end
		removeRemoteLaser(otherCharacter)
	end

	createRemoteLaser(otherCharacter, laserPart)
end

function LaserSightMod.UpdateOtherPlayerLasers()
	for otherChar, data in pairs(otherPlayerLasers) do
		if isEntryDead(otherChar, data) then
			removeRemoteLaser(otherChar)
		else
			updateRemoteLaser(otherChar, data)
		end
	end
end

--------------------------------------------------------------------------------
-- Teardown
--------------------------------------------------------------------------------

function LaserSightMod.Destroy()
	destroyLocalLaserInstances()
	clearOtherPlayerLasers()
	sweepOrphanedInstances()
end

return LaserSightMod