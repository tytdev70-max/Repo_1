--!strict

--// Services

local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Assets

local assets = replicatedStorage:WaitForChild("SPH_Assets") :: Folder
local config = require(assets:WaitForChild("GameConfig") :: ModuleScript)
if not config.fallDamage then
	return true
end

--// Config validation

local fallDamageDist = config.fallDamageDist
local fallDamageMultiplier = config.fallDamageMultiplier
if typeof(fallDamageDist) ~= "number" or typeof(fallDamageMultiplier) ~= "number" then
	warn("[FallDamage] config.fallDamageDist/config.fallDamageMultiplier missing or invalid; fall damage disabled for this character.")
	return true
end

--// Character

local function FindOwningCharacter(instance: Instance): Model?
	local current: Instance? = instance
	while current do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local character = FindOwningCharacter(script) :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

--// Network

local Network = require(assets.Modules.Core.Networking.SPH_Network)

--// State

local FOOT_CLEARANCE = 1.5

local dead = false
local cleanedUp = false
local airborne = false
local fallingDist = 0
local maxFallSpeed = 0
local prevHeight = humanoidRootPart.Position.Y
local connections: { RBXScriptConnection } = {}

--// Raycast

local rayParams = RaycastParams.new()
rayParams.IgnoreWater = false
rayParams.RespectCanCollide = false
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { character }

--// Helpers

local function getRayLength(): number
	return -(humanoid.HipHeight + FOOT_CLEARANCE)
end

local function onLanded(): ()
	if not airborne then
		return
	end
	airborne = false
	character:SetAttribute("Airborne", false)
	if fallingDist > fallDamageDist then
		local damage = maxFallSpeed * fallDamageMultiplier
		local ok, err = pcall(function()
			Network.packets.FallDamageRequest.send(damage)
		end)
		if not ok then
			warn("[FallDamage] Failed to fire damage event:", err)
		end
	end
	fallingDist = 0
	maxFallSpeed = 0
end

local function onBecameAirborne(): ()
	if airborne then
		return
	end
	airborne = true
	maxFallSpeed = 0
	character:SetAttribute("Airborne", true)
end

local function pauseTracking(): ()
	fallingDist = 0
	maxFallSpeed = 0
	prevHeight = humanoidRootPart.Position.Y
	if airborne then
		airborne = false
		character:SetAttribute("Airborne", false)
	end
end

local function cleanup(): ()
	if cleanedUp then
		return
	end
	cleanedUp = true
	dead = true
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

--// Connections

connections[#connections + 1] = humanoid.StateChanged:Connect(function(_: Enum.HumanoidStateType, newState: Enum.HumanoidStateType)
	if dead then
		return
	end
	if newState == Enum.HumanoidStateType.Landed
		or newState == Enum.HumanoidStateType.Running
		or newState == Enum.HumanoidStateType.RunningNoPhysics
		or newState == Enum.HumanoidStateType.Swimming
		or newState == Enum.HumanoidStateType.Climbing then
		onLanded()
	elseif newState == Enum.HumanoidStateType.Freefall
		or newState == Enum.HumanoidStateType.Jumping then
		onBecameAirborne()
	end
end)
connections[#connections + 1] = runService.Heartbeat:Connect(function()
	if dead then
		return
	end
	if humanoid.Sit == true then
		pauseTracking()
		return
	end
	if script:GetAttribute("Override") == true then
		pauseTracking()
		return
	end
	local ok, err = pcall(function()
		local rayResult: RaycastResult? = workspace:Raycast(humanoidRootPart.Position, Vector3.new(0, getRayLength(), 0), rayParams)
		if rayResult then
			onLanded()
		else
			onBecameAirborne()
		end
		local curHeight = humanoidRootPart.Position.Y
		if airborne then
			local speed = humanoidRootPart.AssemblyLinearVelocity.Magnitude
			if speed > maxFallSpeed then
				maxFallSpeed = speed
			end
			if curHeight < prevHeight then
				fallingDist += prevHeight - curHeight
			end
		end
		prevHeight = curHeight
	end)
	if not ok then
		warn("[FallDamage] Heartbeat step failed:", err)
	end
end)
connections[#connections + 1] = humanoid.Climbing:Connect(function()
	fallingDist = 0
	maxFallSpeed = 0
end)
connections[#connections + 1] = humanoid.Swimming:Connect(function()
	fallingDist = 0
	maxFallSpeed = 0
end)
connections[#connections + 1] = humanoid.Died:Connect(cleanup)
script.Destroying:Connect(cleanup)

return true