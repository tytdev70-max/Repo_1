local module = {}
local collectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local bulletVelocity
local PierceMod = require(ReplicatedStorage.SPH_Assets.Modules.Weapons.Fire.PierceMod)
local Visualize = true

local function GetHumanoidFromPart(part)
	while part and part.Parent do
		local hum = part.Parent:FindFirstChildOfClass("Humanoid")
		if hum then
			return hum
		end
		part = part.Parent
	end
	return nil
end

local function IsR6BodyPart(part)
	return part.Name == "Left Arm"
		or part.Name == "Right Arm"
		or part.Name == "Left Leg"
		or part.Name == "Right Leg"
		or part.Name == "Head"
		or part.Name == "Torso"
end

local function VisualizeRay(origin, hitPosition, maxDistance)
	local endPosition = hitPosition or 6000
	local distance = (origin - endPosition).Magnitude

	local rayPart = Instance.new("Part")
	rayPart.Name = "RaycastVisualizer"
	rayPart.Parent = workspace
	rayPart.Anchored = true
	rayPart.CanCollide = false
	rayPart.CanQuery = false
	rayPart.Color = Color3.fromRGB(255, 0, 0)
	rayPart.Transparency = 0.5
	rayPart.Size = Vector3.new(0.1, 0.1, distance) 
	rayPart.CFrame = CFrame.new(origin, endPosition) * CFrame.new(0, 0, -distance / 2)
	game:GetService("Debris"):AddItem(rayPart, 2)
end

module.FireHitscanBullet = function(firePoint: Vector3,direction: Vector3,maxDistance: number,ignoreList: {},player: Player?,weaponTool: Instance?,loop: number)
	loop = loop or 0
	if loop >= 6 then return nil end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignoreList
	rayParams.RespectCanCollide = false

	local rayResult = workspace:Raycast(firePoint, direction * maxDistance, rayParams)
	if not rayResult or not rayResult.Instance then
		return nil
	end
	local hitPart = rayResult.Instance
	local humanoid = GetHumanoidFromPart(hitPart)
	if humanoid then
		return rayResult
	end

	local isBasePart = hitPart:IsA("BasePart")
	if hitPart:HasTag("SPH_NoCollide")
		or (isBasePart and hitPart.Parent:IsA("Accessory"))
		or (isBasePart and hitPart.Transparency >= 1)
		or (isBasePart and not hitPart.CanCollide and not IsR6BodyPart(hitPart)) then
		table.insert(ignoreList, hitPart)
		return module.FireHitscanBullet(rayResult.Position + direction * 0.05, direction, maxDistance, ignoreList, player, weaponTool, loop + 1)
	end

	local wepStats
	if typeof(weaponTool) == "Instance" and weaponTool:FindFirstChild("SPH_Weapon") then
		wepStats = require(weaponTool.SPH_Weapon.WeaponStats)
	elseif typeof(weaponTool) == "table" and weaponTool.model then
		local ok, turretModule = pcall(require, weaponTool.model.Parent.TurretModule)
		wepStats = ok and turretModule.guns[weaponTool.index] or nil
	end

	if wepStats and wepStats.muzzleVelocity then
		local muzzleVel = wepStats.muzzleVelocity
		local gameConfig = require(ReplicatedStorage:FindFirstChild("SPH_Assets").GameConfig)
		bulletVelocity = direction * muzzleVel * gameConfig.meterMultiplier
	else
		bulletVelocity = direction * 1500
	end

	local fakeCast = {
		RayInfo = { CosmeticBulletObject = { CFrame = CFrame.lookAt(firePoint, firePoint + direction) } },
		UserData = { Player = player, Tool = weaponTool, IgnoreModel = player and player.Character or nil },
		GetVelocity = function() return bulletVelocity end,
		SetPosition = function() end,
		SetVelocity = function() end,
	}
	local canPierce = false
	local ok, result = pcall(function()
		return PierceMod.CanPierce(fakeCast, rayResult, bulletVelocity)
	end)
	canPierce = ok and result or false
	if canPierce then
		table.insert(ignoreList, hitPart)
		return module.FireHitscanBullet(rayResult.Position + direction * 0.05, direction, maxDistance, ignoreList, player, weaponTool, loop + 1)
	end

	return rayResult
end

return module