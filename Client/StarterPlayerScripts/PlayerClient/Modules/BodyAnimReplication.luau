--// BodyAnimReplication.lua
--// Handles Network packets BodyAnimCommand (head rotation) and
--// ReplicateLean (root joint lean tween) for remote characters.

local BodyAnimReplication = {}

local ServiceRefs    = require(script.Parent.ServiceRefs)
local TweenService   = ServiceRefs.TweenService
local Config         : any = ServiceRefs.Config
local modules              = ServiceRefs.modules
local Network              = require(modules.Core.Networking.SPH_Network)

--// Public

function BodyAnimReplication.Init(): ()
	-- Head / body tilt replication
	Network.packets.BodyAnimCommand.listen(function(Data: any): ()
		local character : Model    = Data.Character
		local angle     : CFrame   = Data.Angle

		local humanoid: Humanoid? = character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		local joint: Motor6D? = nil

		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			local torso: Instance? = character:FindFirstChild("Torso")
			joint = torso and torso:FindFirstChild("Neck")
		else
			local upperTorso: Instance? = character:FindFirstChild("UpperTorso")
			joint = upperTorso and upperTorso:FindFirstChild("Neck")
		end

		if not joint then return end

		TweenService:Create(
			joint,
			TweenInfo.new(
				Config.replicatedHeadRotationSpeed,
				Enum.EasingStyle.Quad
			),
			{ C1 = angle }
		):Play()
	end)

	-- Lean replication
	Network.packets.ReplicateLean.listen(function(Data: any): ()
		local character      : Model  = Data.Character
		local leanDirection  : number = Data.LeanDirection

		if not character:FindFirstChild("HumanoidRootPart") then return end

		local baseJoint: Motor6D? = character.HumanoidRootPart:FindFirstChild("RootJoint")
		if not baseJoint then return end

		TweenService:Create(baseJoint, TweenInfo.new(0.5), {
			C1 = CFrame.new(-leanDirection / 2, 0, 0)
				* CFrame.Angles(
					math.rad(90),
					math.rad(180) + math.rad(17 * leanDirection),
					0
				),
		}):Play()
	end)
end

return BodyAnimReplication