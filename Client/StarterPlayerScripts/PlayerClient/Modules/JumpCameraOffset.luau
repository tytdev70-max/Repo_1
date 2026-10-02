--// JumpCameraOffset.lua
--// Animates a vertical camera tilt offset for jump dip, rise, and landing
--// impact.  Guarded by Config.jumpCameraOffset.  Exact copy of original logic.

local JumpCameraOffset = {}

local ServiceRefs  = require(script.Parent.ServiceRefs)
local RunService   = ServiceRefs.RunService
local Config 	   = ServiceRefs.Config	  :: any
local player       = ServiceRefs.player :: Player
local camera       = ServiceRefs.camera :: Camera

--// Easing Functions

local function QuadOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function SineOut(t: number): number
	return math.sin(t * (math.pi / 2))
end

local function BackOut(t: number): number
	local c1: number = 1.70158
	local c3: number = c1 + 1
	return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
end

--// State

local jumpOffset    : number                   = 0
local jumpTarget    : number                   = 0
local jumpStart     : number                   = 0
local jumpStartTime : number                   = 0
local jumpDuration  : number                   = 0.001
local jumpEasing       						   = nil :: ((number) -> number)? 
local jumpSeqId     : number                   = 0
local jumpLastOffset : number                  = 0

--// Animation Sequencer

local function AnimateJumpOffset(
	target         : number,
	time           : number,
	easing         : ((number) -> number)?,
	delayedTarget  : number?,
	delayTime      : number?,
	delayedEasing  : ((number) -> number)?,
	delayedTime    : number?
): ()
	jumpSeqId += 1
	local currentSeq: number = jumpSeqId

	jumpStart     = jumpOffset
	jumpTarget    = target
	jumpDuration  = math.max(time, 0.001)
	jumpStartTime = os.clock()
	jumpEasing    = easing or QuadOut

	if delayedTarget then
		task.delay(delayTime :: number, function(): ()
			if jumpSeqId == currentSeq then
				AnimateJumpOffset(
					delayedTarget,
					delayedTime or 0.1,
					delayedEasing or QuadOut
				)
			end
		end)
	end
end

--// Per-Character Setup

local function SetupJumpCamera(character: Model): ()
	local humanoid : Humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root     : BasePart = character:WaitForChild("HumanoidRootPart") :: BasePart

	local peakY    	  = 0	:: number
	local peakConn    = nil :: RBXScriptConnection?

	humanoid.StateChanged:Connect(function(_oldState: any, newState: Enum.HumanoidStateType): ()
		if newState == Enum.HumanoidStateType.Jumping
			or newState == Enum.HumanoidStateType.Freefall
		then
			peakY = root.Position.Y

			if not peakConn then
				peakConn = RunService.Heartbeat:Connect(function(): ()
					if root.Position.Y > peakY then
						peakY = root.Position.Y
					end
				end)
			end

			if newState == Enum.HumanoidStateType.Jumping then
				AnimateJumpOffset(
					Config.jumpDipAngle,
					Config.jumpDipTime,
					QuadOut,
					Config.jumpRiseAngle,
					Config.jumpDipTime + Config.jumpDipHoldTime,
					SineOut,
					Config.jumpRiseTime
				)
			end

		elseif newState == Enum.HumanoidStateType.Landed then
			if peakConn then
				peakConn:Disconnect()
				peakConn = nil
			end

			local fallDistance: number = math.max(0, peakY - root.Position.Y)

			if fallDistance < Config.landMinImpulseFallDistance then
				AnimateJumpOffset(0, Config.landRecoverTime, QuadOut)
				return
			end

			local impulse: number = Config.landBaseImpulse

			if Config.landScaleImpulsed then
				local alpha: number = math.clamp(
					(fallDistance - Config.landMinScaleDistance)
						/ (Config.landMaxScaleDistance - Config.landMinScaleDistance),
					0, 1
				)
				impulse *= 1 + (alpha * (Config.landMaxMultiplier - 1))
			end

			AnimateJumpOffset(
				impulse,
				Config.landImpulseTime,
				QuadOut,
				0,
				Config.landImpulseTime,
				BackOut,
				Config.landRecoverTime
			)
		end
	end)
end

--// Public

function JumpCameraOffset.Init(): ()
	if not Config.jumpCameraOffset then
		return
	end

	-- Apply to existing character and future spawns
	if player.Character then
		SetupJumpCamera(player.Character)
	end
	player.CharacterAdded:Connect(SetupJumpCamera)

	-- RenderStep integration
	RunService:BindToRenderStep(
		"JumpCameraOffset",
		Enum.RenderPriority.Camera.Value + 1,
		function(): ()
			if jumpDuration > 0 and jumpEasing then
				local alpha: number = math.clamp(
					(os.clock() - jumpStartTime) / jumpDuration,
					0, 1
				)
				jumpOffset = jumpStart + (jumpTarget - jumpStart) * jumpEasing(alpha)
			end

			local delta: number = jumpOffset - jumpLastOffset
			if delta ~= 0 then
				camera.CFrame *= CFrame.Angles(math.rad(delta), 0, 0)
			end
			jumpLastOffset = jumpOffset
		end
	)
end

return JumpCameraOffset