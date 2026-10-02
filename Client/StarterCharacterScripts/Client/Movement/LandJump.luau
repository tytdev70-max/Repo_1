--// Services

local Players: Players = game:GetService("Players")

--// Player Reference

local player: Player = Players.LocalPlayer

--// Sounds

local jumpSound = script:WaitForChild("JumpSound") :: Sound
local landSound = script:WaitForChild("LandSound") :: Sound

--// Water Check

local WATER_CHECK_DEPTH = 5

local function isOnWater(character: Model, humanoid: Humanoid, raycastParams: RaycastParams): boolean
	if humanoid.FloorMaterial == Enum.Material.Water then
		return true
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false
	end

	local result = workspace:Raycast(rootPart.Position, Vector3.new(0, -WATER_CHECK_DEPTH, 0), raycastParams)
	return result ~= nil and result.Material == Enum.Material.Water
end

--// Character Setup

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local hasJumped = false
	local stateConn: RBXScriptConnection
	local removedConn: RBXScriptConnection

	stateConn = humanoid.StateChanged:Connect(function(_: Enum.HumanoidStateType, newState: Enum.HumanoidStateType)
		if newState == Enum.HumanoidStateType.Jumping then
			if hasJumped then
				return
			end
			hasJumped = true
			jumpSound:Play()
			return
		end

		if newState ~= Enum.HumanoidStateType.Landed then
			return
		end

		if hasJumped and not isOnWater(character, humanoid, raycastParams) then
			landSound:Play()
		end
		hasJumped = false
	end)

	removedConn = character.AncestryChanged:Connect(function(_: Instance, parent: Instance?)
		if parent ~= nil then
			return
		end
		stateConn:Disconnect()
		removedConn:Disconnect()
	end)
end

--// Initialization

if player.Character ~= nil then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

return true