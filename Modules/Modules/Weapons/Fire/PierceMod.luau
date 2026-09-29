local module = {}
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = ReplicatedStorage.SPH_Assets.Modules
local hitFX = require(modules.Effects.Blood.HitFX)
local GetMaterialType = require(modules.Effects.Blood.HitFX.MaterialTypes)
local config = require(ReplicatedStorage.SPH_Assets.GameConfig)
local Network = require(modules.Core.Networking.SPH_Network)

local randomSeed = Random.new()
local function RandomInt(min, max)
	return randomSeed:NextInteger(min, max)
end

local SharedBulletPhysics
do
	local sharedModule = modules:FindFirstChild("BulletPhysics")
	if sharedModule then
		local ok, mod = pcall(require, sharedModule)
		if ok and typeof(mod) == "table" and mod.materialProperties then
			SharedBulletPhysics = mod
		end
	end
end

local FALLBACK_PROPERTIES = {
	RicochetAngle = {70, 90},
	MinRicochetVelocity = 500,
	VelocityMultiplier = {50, 70},
	RicochetDeviation = 100,
	PenetrationDepth = {0.2, 0.3},
	PenetrationVelocityDecrease = {5, 15},
	PenetrationDeviation = 150,
}

local function IsInHumanoid(Inst)
	while Inst and Inst.Parent do
		local hum = Inst.Parent:FindFirstChildOfClass("Humanoid")
		if hum then
			return hum
		end
		Inst = Inst.Parent
	end
	return nil
end

local function ExcludeFromFutureRaycasts(cast, part)
	local rp = cast.RaycastParams
	if typeof(rp) ~= "RaycastParams" then
		return
	end
	local newList = table.clone(rp.FilterDescendantsInstances)
	table.insert(newList, part)
	rp.FilterDescendantsInstances = newList
end

local bulletPhysicsCache = setmetatable({}, { __mode = "k" })

local function GetBulletPhysicsModule(userData)
	local tool = userData.Tool

	if typeof(tool) == "Instance" then
		local cached = bulletPhysicsCache[tool]
		if cached ~= nil then
			if cached == false then
				return SharedBulletPhysics
			end
			return cached
		end

		local sphWeapon = tool:FindFirstChild("SPH_Weapon")
		local physicsModuleScript = sphWeapon and sphWeapon:FindFirstChild("BulletPhysics")

		if physicsModuleScript then
			local ok, mod = pcall(require, physicsModuleScript)
			if ok and typeof(mod) == "table" and mod.materialProperties then
				bulletPhysicsCache[tool] = mod
				return mod
			end
		end

		bulletPhysicsCache[tool] = false
		return SharedBulletPhysics

	elseif typeof(tool) == "table" and tool.model then
		local turretPhysicsScript
		local ok = pcall(function()
			turretPhysicsScript = tool.model.Parent:FindFirstChild("BulletPhysics")
		end)
		if ok and turretPhysicsScript then
			local ok2, mod = pcall(require, turretPhysicsScript)
			if ok2 and typeof(mod) == "table" and mod.materialProperties then
				return mod
			end
		end
		return SharedBulletPhysics
	end

	return SharedBulletPhysics
end

local weaponStatsCache = setmetatable({}, { __mode = "k" })

local function GetWeaponStats(userData)
	local tool = userData.Tool

	if typeof(tool) == "Instance" then
		local cached = weaponStatsCache[tool]
		if cached ~= nil then
			return cached or nil
		end

		local sphWeapon = tool:FindFirstChild("SPH_Weapon")
		local statsModuleScript = sphWeapon and sphWeapon:FindFirstChild("WeaponStats")
		if statsModuleScript then
			local ok, stats = pcall(require, statsModuleScript)
			if ok and typeof(stats) == "table" then
				weaponStatsCache[tool] = stats
				return stats
			end
		end

		weaponStatsCache[tool] = false
		return nil

	elseif typeof(tool) == "table" and tool.model then
		local ok, turretModule = pcall(require, tool.model.Parent.TurretModule)
		if ok and turretModule.guns and turretModule.guns[tool.index] then
			return turretModule.guns[tool.index]
		end
		return nil
	end

	return nil
end

local function GetMaterialProperties(bulletPhysicsModule, category)
	if bulletPhysicsModule and bulletPhysicsModule.materialProperties then
		if category and bulletPhysicsModule.materialProperties[category] then
			return bulletPhysicsModule.materialProperties[category]
		end
		local defaultCategory = bulletPhysicsModule.DefaultCategory or "Stone"
		if bulletPhysicsModule.materialProperties[defaultCategory] then
			return bulletPhysicsModule.materialProperties[defaultCategory]
		end
	end
	return FALLBACK_PROPERTIES
end

local function ResolveMaterialCategory(rayResult, isGlass)
	if isGlass then
		return "Glass"
	end
	return GetMaterialType(rayResult.Material)
end

local function TryRicochet(cast, rayResult, segmentVelocity, materialProps, userData)
	if not materialProps.RicochetAngle or not materialProps.MinRicochetVelocity then
		return false
	end
	if segmentVelocity.Magnitude <= materialProps.MinRicochetVelocity then
		return false
	end

	local lookDirection = segmentVelocity.Magnitude > 0 and segmentVelocity.Unit or Vector3.zAxis
	local incidence = math.deg(math.acos(math.clamp(-lookDirection:Dot(rayResult.Normal.Unit), -1, 1)))

	local angleRange = materialProps.RicochetAngle
	local requiredAngle = RandomInt(angleRange[1] * 10, angleRange[2] * 10) / 10
	requiredAngle = requiredAngle * (1 + segmentVelocity.Magnitude / 100000)

	if incidence <= requiredAngle then
		return false
	end

	hitFX.HitEffect(rayResult.Position, rayResult.Instance, rayResult.Normal)

	local reflected = lookDirection - (2 * lookDirection:Dot(rayResult.Normal) * rayResult.Normal)

	local deviation = materialProps.RicochetDeviation or 0
	local deviationVector = Vector3.new(
		RandomInt(-deviation, deviation) / 5000,
		RandomInt(-deviation, deviation) / 5000,
		RandomInt(-deviation, deviation) / 5000
	)
	reflected = CFrame.fromOrientation(deviationVector.X, deviationVector.Y, deviationVector.Z) * reflected

	local velocityMult = materialProps.VelocityMultiplier or {60, 60}
	local newSpeed = (RandomInt(velocityMult[1], velocityMult[2]) / 100) * segmentVelocity.Magnitude
	local newVelocity = reflected.Unit * newSpeed

	userData.PiercedParts = userData.PiercedParts or {}
	table.insert(userData.PiercedParts, rayResult.Instance)
	userData.PendingRicochet = {
		Position = rayResult.Position + reflected.Unit * 0.05,
		Velocity = newVelocity,
		PiercedParts = userData.PiercedParts,
	}

	return true
end

local function IsThinEnoughToPenetrate(hitPart, entryPosition, direction, maxPierceDepth)
	if maxPierceDepth <= 0 then
		return false
	end

	local farProbeDistance = hitPart.Size.Magnitude + 1

	local probeParams = RaycastParams.new()
	probeParams.FilterType = Enum.RaycastFilterType.Include
	probeParams.FilterDescendantsInstances = {hitPart}
	probeParams.IgnoreWater = true

	local farPoint = entryPosition + direction * farProbeDistance
	local exitProbe = workspace:Raycast(farPoint, -direction * farProbeDistance, probeParams)

	if not exitProbe then
		return false
	end

	local actualThickness = (exitProbe.Position - entryPosition).Magnitude
	return actualThickness <= maxPierceDepth
end

local function TryPenetrate(cast, rayResult, segmentVelocity, materialProps, hitPart, userData)
	if not config.bulletPen then
		return false
	end
	if hitPart:HasTag("SPH_Collide") then
		return false
	end
	if not materialProps.PenetrationDepth then
		return false
	end

	local direction = segmentVelocity.Magnitude > 0 and segmentVelocity.Unit or Vector3.zAxis

	local thinEnough
	if materialProps.Pierceable then
		thinEnough = true
	else
		local depthRange = materialProps.PenetrationDepth
		local pierceDepth = RandomInt(depthRange[1] * 1000, depthRange[2] * 1000) / 1000
		thinEnough = IsThinEnoughToPenetrate(hitPart, rayResult.Position, direction, pierceDepth)
	end

	if not thinEnough then
		return false
	end

	local decreaseRange = materialProps.PenetrationVelocityDecrease or {10, 10}
	local velocityDecreasePct = RandomInt(decreaseRange[1], decreaseRange[2]) / 100

	local deviation = materialProps.PenetrationDeviation or 0
	local deviationVector = Vector3.new(
		RandomInt(-deviation, deviation) / 5000,
		RandomInt(-deviation, deviation) / 5000,
		RandomInt(-deviation, deviation) / 5000
	)

	local newVelocity = CFrame.fromOrientation(deviationVector.X, deviationVector.Y, deviationVector.Z)
		* (segmentVelocity * (1 - velocityDecreasePct))

	userData.PendingVelocity = newVelocity
	if typeof(cast.SetVelocity) == "function" then
		cast:SetVelocity(newVelocity)
	end

	ExcludeFromFutureRaycasts(cast, hitPart)
	return true
end

module.CanPierce = function(cast, rayResult, castVelocity)
	local hitPart = rayResult.Instance
	local userData = cast.UserData or {}
	cast.UserData = userData
	userData.LastHitWasNonDamaging = false

	local segmentVelocity
	if typeof(cast.GetVelocity) == "function" then
		segmentVelocity = cast:GetVelocity()
	elseif castVelocity then
		segmentVelocity = castVelocity
	else
		segmentVelocity = cast.Velocity or Vector3.zero
	end

	local isBasePart = hitPart:IsA("BasePart")
	local isTerrain = hitPart:IsA("Terrain")

	if not isBasePart and not isTerrain then
		return false
	end

	local Humanoid = IsInHumanoid(hitPart)
	local willPierce = false

	if isBasePart and workspace:FindFirstChild("Vehicles") and hitPart:IsDescendantOf(workspace.Vehicles) then
		willPierce = hitPart:GetAttribute("ArmorThickness") ~= nil

	elseif userData.IgnoreModel and hitPart:IsDescendantOf(userData.IgnoreModel) then
		willPierce = true
		userData.LastHitWasNonDamaging = true

	elseif Humanoid then
		local hitPlayer = Players:GetPlayerFromCharacter(Humanoid.Parent)
		if hitPart.Name == "HumanoidRootPart" then
			willPierce = true
			userData.LastHitWasNonDamaging = true
		elseif hitPlayer and userData.Player == hitPlayer then
			willPierce = true
			userData.LastHitWasNonDamaging = true
		elseif hitPart.Parent:IsA("Accoutrement") or (hitPart.Parent:IsA("Model") and hitPart.Parent ~= Humanoid.Parent) then
			willPierce = true
			userData.LastHitWasNonDamaging = true
		end

	elseif CollectionService:HasTag(hitPart, "SPH_Collide") then
		willPierce = false

	elseif (isBasePart and (hitPart.Transparency == 1 or not hitPart.CanCollide or hitPart.Name == "Ignore"))
		or CollectionService:HasTag(hitPart, "SPH_NoCollide") then
		willPierce = true
		userData.LastHitWasNonDamaging = true
	end

	if willPierce then
		ExcludeFromFutureRaycasts(cast, hitPart)
		return true
	end

	if Humanoid then
		return false
	end

	if Humanoid then
		return false
	end

	local isGlass = isBasePart
		and (hitPart.Name == "Glass" or CollectionService:HasTag(hitPart, "BreakableGlass") or hitPart.Material == Enum.Material.Glass)

	local wepStats = GetWeaponStats(userData)
	local isExplosive = (wepStats and wepStats.explosiveAmmo) or userData.IsUBGL

	if isGlass then
		if not userData.IsUBGL and RunService:IsClient() and not userData.FakeBullet then
			hitFX.HitEffect(rayResult.Position, hitPart, rayResult.Normal)
			Network.packets.PierceGlassRequest.send({
				GlassPart = hitPart,
				HitPosition = rayResult.Position,
			})
		end
		if not isExplosive then
			userData.LastHitWasNonDamaging = true
		end
	end

	if isExplosive then
		return false
	end

	local category = ResolveMaterialCategory(rayResult, isGlass)
	local bulletPhysicsModule = GetBulletPhysicsModule(userData)
	local materialProps = GetMaterialProperties(bulletPhysicsModule, category)

	if TryRicochet(cast, rayResult, segmentVelocity, materialProps, userData) then
		return false
	end

	if TryPenetrate(cast, rayResult, segmentVelocity, materialProps, hitPart, userData) then
		return true
	end

	return false
end

return module