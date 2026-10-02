--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local modules = assets.Modules
local config = require(assets.GameConfig)
local explosionFXScript = modules.Effects.Explosions:WaitForChild("ExplosionFX")
local partCache = require(modules.Core.Utility.PartCache)
local module = {}
local eventsFolder = assets:WaitForChild("Events")
local explosionEvents = eventsFolder:WaitForChild("ExplosionEvents")
local smokeCloudFinishedRemote = explosionEvents:WaitForChild("SmokeCloudFinishedRequest", 10)
if RunService:IsServer() then
	warn("[SmokeVoxelMod] This module is client-only; do not require it from server scripts.")
	return module
end
local DEFAULTS = {
	voxelSize                   = 2,
	radius                      = 16,
	growTime                    = 1.5,
	dissipateStartTime           = 12,
	dissipateTime                = 4,
	density                      = 0.85,
	color                        = Color3.fromRGB(235, 235, 235),
	canisterFadeTime             = 2,
	bulletDisturbRadius          = 3.5,
	bulletDisturbStrength        = 0.75,
	explosionDisperseMultiplier  = 1,
	regrowTime                   = 2.5,
	maxVoxels                    = 2000,
	maxPuffs                     = 300,
	expansionCellsPerSecond      = 500,
	puffFadeGrace                = 1.5,
	expansionSoundId             = "rbxassetid://86419611335608",
	expansionSoundVolume         = 1,
	shapeNoiseScale              = 0.18,
	shapeNoiseStrength           = 0.45,
	shapeMinRadiusFraction       = 0.55,
	shapeSeed                    = nil,
	growSmoothTime               = 1.2,
	explosionDisturbRadiusMultiplier = 1,
	explosionFalloffExponent     = 1.5,
	insideVisionBlockEnabled     = true,
	insideVisionBlockColor       = Color3.fromRGB(235, 235, 235),
	insideVisionBlockMaxOpacity  = 0.97,
	insideVisionBlockFadeInTime  = 0.35,
	insideVisionBlockFadeOutTime = 0.6,
}
local MAX_CONCURRENT_SMOKES     = 4
local SIM_HZ                    = 10
local SIM_INTERVAL              = 1 / SIM_HZ
local POOL_MAX_PUFFS_PER_CLOUD  = 300
local MAX_VOXELS_PER_CLOUD      = 2200
local POOL_MAX_PUFFS_PER_CLOUD_CACHE = MAX_CONCURRENT_SMOKES * POOL_MAX_PUFFS_PER_CLOUD
local DEBUG_MAX_DISTANCE        = 150
local DEBUG_POOL_SIZE           = 400
local activeSmokes = {}
local nextSmokeId = 0
local puffTemplateCache = {}
local debugEnabled = config.smokeVoxelDebug == true
local debugUpdateRate = config.smokeVoxelDebugUpdateRate or 0.2
local debugPool = {}
local NEIGHBOR_OFFSETS = {
	Vector3.new( 1, 0, 0), Vector3.new(-1, 0, 0),
	Vector3.new( 0, 1, 0), Vector3.new( 0,-1, 0),
	Vector3.new( 0, 0, 1), Vector3.new( 0, 0,-1),
}
local function CellKey(cx, cy, cz)
	return cx .. "_" .. cy .. "_" .. cz
end
local function MergeConfig(userCfg)
	local merged = {}
	for k, v in pairs(DEFAULTS) do merged[k] = v end
	if userCfg then
		for k, v in pairs(userCfg) do merged[k] = v end
	end
	merged.maxPuffs = math.clamp(merged.maxPuffs, 1, POOL_MAX_PUFFS_PER_CLOUD)
	merged.maxVoxels = math.clamp(merged.maxVoxels, 1, MAX_VOXELS_PER_CLOUD)
	merged.shapeNoiseScale = merged.shapeNoiseScale or DEFAULTS.shapeNoiseScale
	merged.shapeNoiseStrength = math.clamp(merged.shapeNoiseStrength or DEFAULTS.shapeNoiseStrength, 0, 0.95)
	merged.shapeMinRadiusFraction = math.clamp(merged.shapeMinRadiusFraction or DEFAULTS.shapeMinRadiusFraction, 0.1, 1)
	merged.bulletDisturbStrength = math.clamp(merged.bulletDisturbStrength or DEFAULTS.bulletDisturbStrength, 0, 1)
	merged.growSmoothTime = math.max(merged.growSmoothTime or DEFAULTS.growSmoothTime, 0.05)
	merged.explosionDisturbRadiusMultiplier = math.max(merged.explosionDisturbRadiusMultiplier or 1, 0.05)
	merged.explosionFalloffExponent = math.max(merged.explosionFalloffExponent or 1, 0.1)
	merged.insideVisionBlockMaxOpacity = math.clamp(merged.insideVisionBlockMaxOpacity or 0.97, 0, 1)
	return merged
end
local voxelRayParams = RaycastParams.new()
voxelRayParams.FilterType = Enum.RaycastFilterType.Exclude
voxelRayParams.IgnoreWater = true
voxelRayParams.RespectCanCollide = true
local function BuildVoxelIgnoreList()
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(list, plr.Character) end
	end
	local sphWorkspace = workspace:FindFirstChild("SPH_Workspace")
	if sphWorkspace then table.insert(list, sphWorkspace) end
	return list
end
local function VoxelPathClear(fromPos, toPos)
	local dir = toPos - fromPos
	if dir.Magnitude < 0.01 then return true end
	return workspace:Raycast(fromPos, dir, voxelRayParams) == nil
end
local function GetSmokeTemplate(explosionTypeName)
	local key = explosionTypeName or "M18"
	if puffTemplateCache[key] then return puffTemplateCache[key] end
	local folder = explosionFXScript:FindFirstChild(key)
	local emitter = folder and folder:FindFirstChildWhichIsA("ParticleEmitter")
	if emitter then puffTemplateCache[key] = emitter end
	return emitter
end
local function PlayExpansionSound(cfg, position)
	if not cfg.expansionSoundId or cfg.expansionSoundId == 0 or cfg.expansionSoundId == "" then
		return
	end
	local soundPart = Instance.new("Part")
	soundPart.Name = "SmokeExpansionSound"
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.CanQuery = false
	soundPart.CanTouch = false
	soundPart.CastShadow = false
	soundPart.Transparency = 1
	soundPart.Size = Vector3.new(0.2, 0.2, 0.2)
	soundPart.CFrame = CFrame.new(position)
	soundPart.Parent = workspace
	local sound = Instance.new("Sound")
	local id = cfg.expansionSoundId
	sound.SoundId = (typeof(id) == "number") and ("rbxassetid://" .. tostring(id)) or tostring(id)
	sound.Volume = cfg.expansionSoundVolume or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = math.max(cfg.radius * 12, 150)
	sound.Parent = soundPart
	sound:Play()
	Debris:AddItem(soundPart, (sound.TimeLength > 0 and sound.TimeLength or 5) + 0.5)
end
local function ClosestPointOnSegment(a, dir, len, p)
	if len <= 0.001 then return a end
	local unit = dir.Unit
	local t = math.clamp((p - a):Dot(unit), 0, len)
	return a + unit * t
end
local function ComputeShapeFraction(cfg, worldPos, seedOffset)
	local scale = cfg.shapeNoiseScale
	local n = math.noise(
		worldPos.X * scale + seedOffset.X,
		worldPos.Y * scale + seedOffset.Y,
		worldPos.Z * scale + seedOffset.Z
	)
	local alpha = math.clamp(n * 0.5 + 0.5, 0, 1)
	local strength = cfg.shapeNoiseStrength
	local fraction = (1 - strength) + strength * alpha
	return math.max(fraction, cfg.shapeMinRadiusFraction)
end

local function RayPolygonRadius(points, dx, dz)
	local n = #points
	local best = nil
	for i = 1, n do
		local a = points[i]
		local b = points[(i % n) + 1]
		local ex, ez = b.x - a.x, b.z - a.z
		local det = -dx * ez + ex * dz
		if math.abs(det) > 1e-8 then
			local t = (-a.x * ez + ex * a.z) / det
			local s = (dx * a.z - dz * a.x) / det
			if t >= 0 and s >= -1e-6 and s <= 1 + 1e-6 then
				if not best or t < best then
					best = t
				end
			end
		end
	end
	return best
end

local function ComputeEffectiveRadius(cfg, dirUnit)
	if not (cfg.shapePoints and #cfg.shapePoints >= 3) then
		return cfg.radius
	end
	local horizLen = math.sqrt(dirUnit.X * dirUnit.X + dirUnit.Z * dirUnit.Z)
	local vertRadius = cfg.shapeVerticalRadius or cfg.radius
	if horizLen < 0.0001 then
		return vertRadius
	end
	local dx, dz = dirUnit.X / horizLen, dirUnit.Z / horizLen
	local polyRadius = RayPolygonRadius(cfg.shapePoints, dx, dz) or cfg.radius
	local hComponent = horizLen
	local vComponent = math.abs(dirUnit.Y)
	local denom = (hComponent * hComponent) / math.max(polyRadius * polyRadius, 0.0001)
		+ (vComponent * vComponent) / math.max(vertRadius * vertRadius, 0.0001)
	if denom <= 0 then
		return cfg.radius
	end
	return 1 / math.sqrt(denom)
end
local function CreatePuffPart()
	local part = Instance.new("Part")
	part.Name = "SmokePuff"
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end
local puffCacheContainer = workspace:WaitForChild("SPH_Workspace"):WaitForChild("SmokeCache")
local puffStreamRoot = Instance.new("Model")
puffStreamRoot.Name = "SmokePuffStreamRoot"
puffStreamRoot.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
puffStreamRoot.Parent = puffCacheContainer
local smokePuffProvider = partCache.new(CreatePuffPart(), POOL_MAX_PUFFS_PER_CLOUD_CACHE, puffStreamRoot)
local function AcquirePuff(templateEmitter)
	local part = smokePuffProvider:GetPart()
	if not part then return nil, nil end
	part.Parent = puffStreamRoot
	local emitter = part:FindFirstChildWhichIsA("ParticleEmitter")
	if not emitter and templateEmitter then
		emitter = templateEmitter:Clone()
		emitter.Parent = part
	end
	if emitter then
		emitter.Enabled = true
		emitter.Transparency = NumberSequence.new(0.98)
	end
	return part, emitter
end
local function ReleasePuff(part)
	if not part then return end
	local emitter = part:FindFirstChildWhichIsA("ParticleEmitter")
	if emitter then emitter.Enabled = false end
	pcall(function() smokePuffProvider:ReturnPart(part) end)
end
local function BeginFloodFill(cloud)
	voxelRayParams.FilterDescendantsInstances = BuildVoxelIgnoreList()
	local originKey = CellKey(0, 0, 0)
	cloud.voxels[originKey] = {
		cx = 0, cy = 0, cz = 0, pos = cloud.origin,
		targetDensity = cloud.config.density, currentDensity = 0, disturbedUntil = 0,
	}
	cloud.frontier = { {cx = 0, cy = 0, cz = 0} }
	cloud.voxelCount = 1
	cloud.createdIndex = 1
	local part, emitter = AcquirePuff(cloud.template)
	if part then
		part.CFrame = CFrame.new(cloud.origin)
		cloud.puffs[originKey] = { part = part, emitter = emitter }
		cloud.assignedPuffCount = 1
	else
		cloud.assignedPuffCount = 0
	end
end
local function StepFloodFill(cloud)
	local cfg = cloud.config
	local voxelSize = cfg.voxelSize
	local maxCells = cfg.maxVoxels
	local budget = math.max(1, math.floor((cfg.expansionCellsPerSecond or 400) * SIM_INTERVAL))
	local newFrontier = {}
	for _, cell in ipairs(cloud.frontier) do
		if budget <= 0 or cloud.voxelCount >= maxCells then break end
		local baseVoxel = cloud.voxels[CellKey(cell.cx, cell.cy, cell.cz)]
		if baseVoxel then
			for _, offset in ipairs(NEIGHBOR_OFFSETS) do
				if budget <= 0 or cloud.voxelCount >= maxCells then break end
				local ncx, ncy, ncz = cell.cx + offset.X, cell.cy + offset.Y, cell.cz + offset.Z
				local nKey = CellKey(ncx, ncy, ncz)
				if not cloud.voxels[nKey] then
					local nPos = cloud.origin + Vector3.new(ncx, ncy, ncz) * voxelSize
					local relVec = nPos - cloud.origin
					local distFromOrigin = relVec.Magnitude
					local dirUnit = distFromOrigin > 0.001 and relVec.Unit or Vector3.new(0, 1, 0)
					local shapeFraction = ComputeShapeFraction(cfg, nPos, cloud.shapeSeedOffset)
					local baseRadius = ComputeEffectiveRadius(cfg, dirUnit)
					local effectiveRadius = baseRadius * shapeFraction
					if distFromOrigin <= effectiveRadius then
						budget -= 1
						if VoxelPathClear(baseVoxel.pos, nPos) then
							cloud.voxels[nKey] = {
								cx = ncx, cy = ncy, cz = ncz, pos = nPos,
								targetDensity = cfg.density * (1 - (distFromOrigin / math.max(effectiveRadius, 0.01)) * 0.35),
								currentDensity = 0, disturbedUntil = 0,
							}
							cloud.voxelCount += 1
							cloud.createdIndex += 1
							if cloud.assignedPuffCount < cfg.maxPuffs
								and (cloud.createdIndex % cloud.puffStride == 0) then
								local part, emitter = AcquirePuff(cloud.template)
								if part then
									part.CFrame = CFrame.new(nPos)
									cloud.puffs[nKey] = { part = part, emitter = emitter }
									cloud.assignedPuffCount += 1
								end
							end
							table.insert(newFrontier, {cx = ncx, cy = ncy, cz = ncz})
						end
					end
				end
			end
		end
	end
	cloud.frontier = newFrontier
	if #newFrontier == 0 or cloud.voxelCount >= maxCells then
		cloud.floodFillDone = true
	end
end
local function TopUpPuffs(cloud)
	local cfg = cloud.config
	if cloud.assignedPuffCount >= cfg.maxPuffs then return end
	for key, voxel in pairs(cloud.voxels) do
		if cloud.assignedPuffCount >= cfg.maxPuffs then break end
		if not cloud.puffs[key] then
			local part, emitter = AcquirePuff(cloud.template)
			if not part then break end
			part.CFrame = CFrame.new(voxel.pos)
			cloud.puffs[key] = { part = part, emitter = emitter }
			cloud.assignedPuffCount += 1
		end
	end
end
local function TickCloud(cloud, now)
	local cfg = cloud.config
	local age = now - cloud.spawnTime

	if cloud.fading then
		local fadeAlpha = math.clamp((now - cloud.fadeStartTime) / math.max(cfg.puffFadeGrace or 1.5, 0.05), 0, 1)
		for _, voxel in pairs(cloud.voxels) do
			voxel.currentDensity = voxel.currentDensity * (1 - fadeAlpha)
		end
		for key, puffData in pairs(cloud.puffs) do
			local voxel = cloud.voxels[key]
			if voxel and puffData.emitter then
				local d = math.clamp(voxel.currentDensity, 0, 1)
				puffData.emitter.Transparency = NumberSequence.new(math.clamp(1 - d, 0.05, 0.98))
				if d <= 0.015 then
					puffData.emitter.Enabled = false
				end
			end
		end
		if fadeAlpha >= 1 then
			cloud.dead = true
			if cloud.onFinished then
				cloud.onFinished(cloud)
			end
		end
		return
	end

	if not cloud.floodFillDone then
		StepFloodFill(cloud)
	elseif not cloud.toppedUp then
		cloud.toppedUp = true
		TopUpPuffs(cloud)
	end

	local growAlpha = math.clamp(age / cfg.growTime, 0, 1)
	local dissipateAlpha = 0
	if age > cfg.growTime + cfg.dissipateStartTime then
		dissipateAlpha = math.clamp((age - cfg.growTime - cfg.dissipateStartTime) / cfg.dissipateTime, 0, 1)
	end
	cloud.lifecycleScale = growAlpha * (1 - dissipateAlpha)

	if dissipateAlpha >= 1 then
		cloud.fading = true
		cloud.fadeStartTime = now
		return
	end

	for _, voxel in pairs(cloud.voxels) do
		local goal = voxel.targetDensity * cloud.lifecycleScale
		if now < voxel.disturbedUntil then
			voxel.currentDensity += (0 - voxel.currentDensity) * cfg.bulletDisturbStrength
		else
			local smoothTime = cfg.growSmoothTime or cfg.regrowTime
			local rate = 1 - math.exp(-SIM_INTERVAL / math.max(smoothTime, 0.1))
			voxel.currentDensity += (goal - voxel.currentDensity) * rate
		end
	end
	for key, puffData in pairs(cloud.puffs) do
		local voxel = cloud.voxels[key]
		if voxel and puffData.part and puffData.emitter then
			local d = math.clamp(voxel.currentDensity, 0, 1)
			puffData.emitter.Transparency = NumberSequence.new(math.clamp(1 - d, 0.05, 0.98))
			puffData.emitter.Color = ColorSequence.new(cfg.color)
			puffData.emitter.Enabled = d > 0.02
		end
	end
end
function module.Spawn(position, smokeConfig, explosionTypeName, finishedToken)
	local elapsedTime = math.max((smokeConfig and smokeConfig.__elapsedTime) or 0, 0)

	nextSmokeId += 1
	local cfg = MergeConfig(smokeConfig)

	local fullLifetime = cfg.growTime + cfg.dissipateStartTime + cfg.dissipateTime + (cfg.puffFadeGrace or 1.5)
	if elapsedTime >= fullLifetime then
		return nil
	end

	local shapeSeedOffset
	if cfg.shapeSeed then
		local rng = Random.new(cfg.shapeSeed)
		shapeSeedOffset = Vector3.new(rng:NextNumber(0, 1000), rng:NextNumber(0, 1000), rng:NextNumber(0, 1000))
	else
		shapeSeedOffset = Vector3.new(math.random() * 1000, math.random() * 1000, math.random() * 1000)
	end
	local estimatedMaxCells = cfg.maxVoxels
	local puffStride = math.max(1, math.floor(estimatedMaxCells / math.max(cfg.maxPuffs, 1)))
	local cloud = {
		id = nextSmokeId,
		origin = position,
		config = cfg,
		template = GetSmokeTemplate(explosionTypeName),
		voxels = {}, puffs = {},
		spawnTime = os.clock() - elapsedTime,
		floodFillDone = false, toppedUp = false,
		dead = false, fading = false, fadeStartTime = nil,
		lifecycleScale = 0,
		createdIndex = 0, puffStride = puffStride, assignedPuffCount = 0,
		shapeSeedOffset = shapeSeedOffset,
		onFinished = nil,
	}
	if finishedToken ~= nil and smokeCloudFinishedRemote then
		cloud.onFinished = function()
			smokeCloudFinishedRemote:FireServer(finishedToken)
		end
	end
	BeginFloodFill(cloud)
	if elapsedTime <= 0.05 then
		PlayExpansionSound(cfg, position)
	end
	table.insert(activeSmokes, cloud)
	if #activeSmokes > MAX_CONCURRENT_SMOKES then
		module.KillCloud(table.remove(activeSmokes, 1))
	end
	return cloud.id
end
function module.KillCloud(cloud)
	for _, puffData in pairs(cloud.puffs) do
		ReleasePuff(puffData.part)
	end
	cloud.puffs = {}
	cloud.dead = true
end
function module.DisturbSegment(segmentOrigin, segmentDirection, length)
	if #activeSmokes == 0 or length <= 0 then return end
	local now = os.clock()
	for _, cloud in ipairs(activeSmokes) do
		if not cloud.dead then
			local cfg = cloud.config
			local closest = ClosestPointOnSegment(segmentOrigin, segmentDirection, length, cloud.origin)
			if (closest - cloud.origin).Magnitude <= cfg.radius + cfg.bulletDisturbRadius then
				local rSq = cfg.bulletDisturbRadius * cfg.bulletDisturbRadius
				local dip = cfg.bulletDisturbStrength
				for key, puffData in pairs(cloud.puffs) do
					local voxel = cloud.voxels[key]
					if voxel then
						local p = ClosestPointOnSegment(segmentOrigin, segmentDirection, length, voxel.pos)
						local d = (p - voxel.pos).Magnitude
						if d * d <= rSq then
							voxel.disturbedUntil = now + cfg.regrowTime
							voxel.currentDensity *= (1 - dip)
						end
					end
				end
			end
		end
	end
end
function module.DisturbExplosion(originPos, blastRadius)
	if #activeSmokes == 0 or blastRadius <= 0 then return end
	local now = os.clock()
	for _, cloud in ipairs(activeSmokes) do
		if not cloud.dead then
			local cfg = cloud.config
			if (originPos - cloud.origin).Magnitude <= blastRadius + cfg.radius then
				local effectiveDisturbRadius = math.max(blastRadius * (cfg.explosionDisturbRadiusMultiplier or 1), 0.1)
				local exponent = cfg.explosionFalloffExponent or 1
				for _, voxel in pairs(cloud.voxels) do
					local vDist = (originPos - voxel.pos).Magnitude
					if vDist <= effectiveDisturbRadius then
						local falloff = math.clamp(1 - (vDist / effectiveDisturbRadius), 0, 1) ^ exponent
						local strength = falloff * cfg.explosionDisperseMultiplier
						if strength > 0.05 then
							voxel.disturbedUntil = math.max(voxel.disturbedUntil, now + cfg.regrowTime * strength)
						end
					end
				end
			end
		end
	end
end

local visionBlockGui = nil
local visionBlockFrame = nil
local currentVisionOpacity = 0

local function EnsureVisionBlockGui()
	if visionBlockFrame and visionBlockFrame.Parent then return end
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end
	local playerGui = localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui")
	visionBlockGui = playerGui:FindFirstChild("SPH_SmokeVisionBlock")
	if not visionBlockGui then
		visionBlockGui = Instance.new("ScreenGui")
		visionBlockGui.Name = "SPH_SmokeVisionBlock"
		visionBlockGui.ResetOnSpawn = false
		visionBlockGui.IgnoreGuiInset = true
		visionBlockGui.DisplayOrder = 50
		visionBlockGui.Parent = playerGui
	end
	visionBlockFrame = visionBlockGui:FindFirstChild("Block")
	if not visionBlockFrame then
		visionBlockFrame = Instance.new("Frame")
		visionBlockFrame.Name = "Block"
		visionBlockFrame.Size = UDim2.fromScale(1, 1)
		visionBlockFrame.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
		visionBlockFrame.BackgroundTransparency = 1
		visionBlockFrame.BorderSizePixel = 0
		visionBlockFrame.ZIndex = 10
		visionBlockFrame.Parent = visionBlockGui
	end
end

local function SampleLocalSmokeDensity(camPos)
	local bestNormalized, bestColor, bestOpacity, bestFadeIn, bestFadeOut = 0, nil, 0.97, 0.35, 0.6
	for _, cloud in ipairs(activeSmokes) do
		if not cloud.dead then
			local cfg = cloud.config
			if cfg.insideVisionBlockEnabled ~= false then
				local rel = camPos - cloud.origin
				if rel.Magnitude <= cfg.radius + cfg.voxelSize * 2 then
					local voxelSize = cfg.voxelSize
					local cx = math.round(rel.X / voxelSize)
					local cy = math.round(rel.Y / voxelSize)
					local cz = math.round(rel.Z / voxelSize)
					local voxel = cloud.voxels[CellKey(cx, cy, cz)]
					if voxel then
						local d = math.clamp(voxel.currentDensity, 0, 1)
						local ratio = cfg.density > 0 and (d / cfg.density) or d
						local normalized = math.clamp(ratio / 0.6, 0, 1)
						if normalized > bestNormalized then
							bestNormalized = normalized
							bestColor = cfg.insideVisionBlockColor or cfg.color
							bestOpacity = cfg.insideVisionBlockMaxOpacity or 0.97
							bestFadeIn = cfg.insideVisionBlockFadeInTime or 0.35
							bestFadeOut = cfg.insideVisionBlockFadeOutTime or 0.6
						end
					end
				end
			end
		end
	end
	return bestNormalized, bestColor, bestOpacity, bestFadeIn, bestFadeOut
end

RunService.RenderStepped:Connect(function(dt)
	if #activeSmokes == 0 and currentVisionOpacity <= 0.001 then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	EnsureVisionBlockGui()
	if not visionBlockFrame then return end
	local normalized, color, maxOpacity, fadeInTime, fadeOutTime = SampleLocalSmokeDensity(camera.CFrame.Position)
	local targetOpacity = normalized * maxOpacity
	local fadingIn = targetOpacity > currentVisionOpacity
	local speed = 1 / math.max(fadingIn and fadeInTime or fadeOutTime, 0.01)
	currentVisionOpacity += (targetOpacity - currentVisionOpacity) * math.clamp(dt * speed, 0, 1)
	if color then
		visionBlockFrame.BackgroundColor3 = color
	end
	visionBlockFrame.BackgroundTransparency = 1 - math.clamp(currentVisionOpacity, 0, 1)
end)

function module.SetDebugEnabled(enabled)
	debugEnabled = enabled
end
local function GetDebugPart(i)
	local part = debugPool[i]
	if not part then
		part = Instance.new("Part")
		part.Name = "SmokeVoxelDebug"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		debugPool[i] = part
	end
	return part
end
local function HideDebugFrom(startIndex)
	for i = startIndex, #debugPool do
		debugPool[i].Parent = nil
	end
end
local lastDebugUpdate = 0
local function UpdateDebugVisuals(now)
	if now - lastDebugUpdate < debugUpdateRate then return end
	lastDebugUpdate = now
	if not debugEnabled or #activeSmokes == 0 then
		HideDebugFrom(1)
		return
	end
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	local used = 0
	for _, cloud in ipairs(activeSmokes) do
		if not cloud.dead and (camPos - cloud.origin).Magnitude <= DEBUG_MAX_DISTANCE + cloud.config.radius then
			for _, voxel in pairs(cloud.voxels) do
				if used >= DEBUG_POOL_SIZE then break end
				if (camPos - voxel.pos).Magnitude <= DEBUG_MAX_DISTANCE then
					used += 1
					local part = GetDebugPart(used)
					part.Parent = puffCacheContainer
					part.Size = Vector3.one * cloud.config.voxelSize * 0.9
					part.CFrame = CFrame.new(voxel.pos)
					local d = math.clamp(voxel.currentDensity, 0, 1)
					part.Color = Color3.new(1 - d, d, 0)
					part.Transparency = 0.4
				end
			end
		end
	end
	HideDebugFrom(used + 1)
end
local simAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	simAccumulator += dt
	local now = os.clock()
	if simAccumulator >= SIM_INTERVAL then
		simAccumulator = 0
		for i = #activeSmokes, 1, -1 do
			local cloud = activeSmokes[i]
			TickCloud(cloud, now)
			if cloud.dead then
				module.KillCloud(cloud)
				table.remove(activeSmokes, i)
			end
		end
	end
	UpdateDebugVisuals(now)
end)
local smokeSpawnRemote = explosionEvents:WaitForChild("SmokeSpawnRequest", 10)
if smokeSpawnRemote then
	smokeSpawnRemote.OnClientEvent:Connect(function(position, smokeConfig, finishedToken)
		module.Spawn(position, smokeConfig, nil, finishedToken)
	end)
end
local explosionRemote = explosionEvents:WaitForChild("ExplosionFXRemote", 10)
if explosionRemote then
	explosionRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and payload.SmokeDisturbOrigin then
			module.DisturbExplosion(payload.SmokeDisturbOrigin, payload.SmokeDisturbRadius or 0)
		end
	end)
end

local smokeCatchUpRequestRemote = explosionEvents:WaitForChild("SmokeCatchUpRequest", 10)
if smokeCatchUpRequestRemote then
	smokeCatchUpRequestRemote:FireServer()
end

return module