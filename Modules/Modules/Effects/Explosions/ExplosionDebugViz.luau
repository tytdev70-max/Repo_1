local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local config = require(ReplicatedStorage.SPH_Assets.GameConfig)

local module = {}

module.Colors = {
	Hit             = Color3.fromRGB(60, 255, 90),   -- ray reached its target unobstructed
	Blocked         = Color3.fromRGB(255, 60, 60),   -- ray was blocked by world geometry
	ValidTarget     = Color3.fromRGB(60, 180, 255),  -- object accepted as an explosion target
	EffectiveRadius = Color3.fromRGB(255, 200, 60),  -- the radius damage/LOS checks actually use
	QueryRadius     = Color3.fromRGB(120, 120, 120), -- the larger broad-phase spatial query radius
}

local function getDebugFolder()
	local sphWorkspace = workspace:FindFirstChild("SPH_Workspace")
	if not sphWorkspace then
		sphWorkspace = Instance.new("Folder")
		sphWorkspace.Name = "SPH_Workspace"
		sphWorkspace.Parent = workspace
	end
	local debugFolder = sphWorkspace:FindFirstChild("Debug")
	if not debugFolder then
		debugFolder = Instance.new("Folder")
		debugFolder.Name = "Debug"
		debugFolder.Parent = sphWorkspace
	end
	return debugFolder
end

local function getLifetime()
	return (type(config.explosionDebugDuration) == "number" and config.explosionDebugDuration > 0)
		and config.explosionDebugDuration or 6
end

local function newDebugPart()
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Parent = getDebugFolder()
	Debris:AddItem(part, getLifetime())
	return part
end

function module.DrawRay(origin, target, color)
	local distance = (target - origin).Magnitude
	if distance < 0.05 then return end

	local part = newDebugPart()
	part.Size = Vector3.new(0.05, 0.05, distance)
	part.Transparency = 0.2
	part.Color = color

	local midpoint = origin:Lerp(target, 0.5)
	part.CFrame = CFrame.new(midpoint, target)
end

function module.DrawRadius(origin, radius, color)
	if radius <= 0 then return end
	local part = newDebugPart()
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	part.CFrame = CFrame.new(origin)
	part.Transparency = 0.88
	part.Color = color
end

function module.MarkTarget(position, color)
	local part = newDebugPart()
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.6, 0.6, 0.6)
	part.CFrame = CFrame.new(position)
	part.Transparency = 0.1
	part.Color = color
end

return module