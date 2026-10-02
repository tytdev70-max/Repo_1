local runService = game:GetService("RunService")
local Modules = script:FindFirstAncestor("Modules")
local vars = require(Modules.Weapons.Core.WeaponState).get()

local HeadPoseReplicationMod = {}

local deps
local sendThrottle
local listenerConnected = false
local heartbeatConnected = false

local remoteHeadState = {}

local function ExpAlpha(ratePerSecond, dt)
	return 1 - math.exp(-ratePerSecond * dt)
end

local function GetNeckJoint(character)
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return nil end
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local torso = character:FindFirstChild("Torso")
		return torso and torso:FindFirstChild("Neck")
	else
		local upperTorso = character:FindFirstChild("UpperTorso")
		return upperTorso and upperTorso:FindFirstChild("Neck")
	end
end

function HeadPoseReplicationMod.Init(initDeps)
	deps = initDeps
	sendThrottle = deps.ReplicationThrottle.new(deps.config.headRotationEventRate or 0.05)

	if not listenerConnected then
		listenerConnected = true
		deps.bodyAnimCommand.listen(function(Data)
			local otherCharacter, angle = Data.Character, Data.Angle
			if not otherCharacter or otherCharacter == deps.character then return end
			if typeof(angle) ~= "CFrame" then return end

			local state = remoteHeadState[otherCharacter]
			if not state then
				local neck = GetNeckJoint(otherCharacter)
				if not neck then return end
				state = { neck = neck, target = neck.C1 }
				remoteHeadState[otherCharacter] = state
			end
			state.target = angle
		end)
	end

	if not heartbeatConnected then
		heartbeatConnected = true
		runService.Heartbeat:Connect(function(dt)
			if not next(remoteHeadState) then return end
			local alpha = ExpAlpha(deps.config.headRotationSpeed or 12, dt)
			for otherCharacter, state in pairs(remoteHeadState) do
				local humanoid = otherCharacter:FindFirstChild("Humanoid")
				if not otherCharacter.Parent or not state.neck.Parent or not humanoid or humanoid.Health <= 0 then
					remoteHeadState[otherCharacter] = nil
					continue
				end
				state.neck.C1 = state.neck.C1:Lerp(state.target, alpha)
			end
		end)
	end
end

function HeadPoseReplicationMod.SendLocalPose(neckC1)
	if not deps or not sendThrottle then return end
	if deps.config.disableHeadRotation then return end
	if vars.dead then return end

	local shouldSend = sendThrottle:ShouldSend(neckC1, 0.015, function(a, b)
		local posDelta = (a.Position - b.Position).Magnitude
		local _, rotDelta = (a * b:Inverse()):ToAxisAngle()
		return posDelta + math.abs(rotDelta)
	end)

	if shouldSend then
		deps.bodyAnimRequest.send(neckC1)
	end
end

function HeadPoseReplicationMod.ResetLocalThrottle()
	if sendThrottle then
		sendThrottle:Reset()
	end
end

return HeadPoseReplicationMod