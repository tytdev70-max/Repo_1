--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.SPH_Assets.GameConfig)

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera :: Camera

local CameraManager = {}

local activeCleanup: (() -> ())? = nil

function CameraManager.FollowDeadBody(deadBody: Model): ()
	if not Config.ragdollCameraFollowOwnDeath then
		return
	end

	if activeCleanup then
		activeCleanup()
		activeCleanup = nil
	end

	local waitTimeout: number = Config.ragdollCameraTorsoWaitTimeout or 5

	local subject: BasePart? = nil
	if deadBody:FindFirstChild("Torso") then
		subject = deadBody:WaitForChild("Torso", waitTimeout)
	elseif deadBody:FindFirstChild("UpperTorso") then
		subject = deadBody:WaitForChild("UpperTorso", waitTimeout)
	else
		subject = deadBody:WaitForChild("Torso", waitTimeout)
	end

	if not subject then
		return
	end

	Camera.CameraType = Enum.CameraType.Custom
	Camera.CameraSubject = subject

	local heartbeatConnection: RBXScriptConnection? = nil
	local characterAddedConnection: RBXScriptConnection? = nil

	local function Cleanup(): ()
		if heartbeatConnection then
			heartbeatConnection:Disconnect()
			heartbeatConnection = nil
		end
		if characterAddedConnection then
			characterAddedConnection:Disconnect()
			characterAddedConnection = nil
		end
	end

	local function RestoreCameraToLivingCharacter(): ()
		Camera.CameraType = Enum.CameraType.Custom
		local character = Player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				Camera.CameraSubject = humanoid
			end
		end
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if not deadBody or not deadBody.Parent then
			RestoreCameraToLivingCharacter()
			Cleanup()
		end
	end)

	characterAddedConnection = Player.CharacterAdded:Connect(function()
		Cleanup()
	end)
end

return CameraManager