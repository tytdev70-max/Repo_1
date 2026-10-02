-- Handlers/RemoteLeanHandler
-- repLean clientBridge binding + per-frame lean update for other characters.

local StateInit   = require(script.Parent.Parent.Boot.StateInit)
local ServiceRefs = require(script.Parent.Parent.Boot.ServiceRefs)
local SystemInits = require(script.Parent.Parent.ModuleInits.SystemModuleInits)

local vars             = StateInit.vars
local leanAngleDegrees = StateInit.leanAngleDegrees
local leanLerpRate     = StateInit.leanLerpRate
local character        = require(script.Parent.Parent.Boot.CharacterRefs).character
local runService       = ServiceRefs.runService

local clientBridge   = SystemInits.clientBridge
local PacketRefs     = SystemInits.PacketRefs
local WeaponBindings = SystemInits.WeaponBindings

local remoteLeanState: { [Model]: any } = StateInit.remoteLeanState

local RemoteLeanHandler = {}

function RemoteLeanHandler.init()
	clientBridge.bind("repLean", PacketRefs.repLeanReplicate, function(Data: any)
		local otherCharacter: Model? = Data.Character
		local leanDirection: number? = Data.LeanDirection
		if not otherCharacter or otherCharacter == character then return end

		local otherHumanoid = otherCharacter:FindFirstChild("Humanoid")
		if not otherHumanoid or otherHumanoid.RigType ~= Enum.HumanoidRigType.R6 then return end

		local state = remoteLeanState[otherCharacter]
		if not state then
			local otherTorso = otherCharacter:FindFirstChild("Torso")
			if not otherTorso then return end
			local otherHrp = otherCharacter:FindFirstChild("HumanoidRootPart")
			if not otherHrp then return end
			local rootJoint = otherHrp:FindFirstChild("RootJoint")
			local lHip = otherTorso:FindFirstChild("Left Hip")
			local rHip = otherTorso:FindFirstChild("Right Hip")
			if not rootJoint or not lHip or not rHip then return end

			state = {
				rootJoint    = rootJoint,
				leftHip      = lHip,
				rightHip     = rHip,
				defaultRootC0= rootJoint.C0,
				defaultLeftC0= lHip.C0,
				defaultRightC0= rHip.C0,
				targetLean   = 0,
			}
			remoteLeanState[otherCharacter] = state
		end

		state.targetLean = leanDirection or 0
	end)

	-- Per-frame lean update
	runService.Heartbeat:Connect(function(dt: number)
		if not next(remoteLeanState) then return end
		local alpha = WeaponBindings.ExpAlpha(leanLerpRate, dt)
		for otherCharacter, state in pairs(remoteLeanState) do
			if not otherCharacter.Parent
				or not state.rootJoint.Parent
				or not state.leftHip.Parent
				or not state.rightHip.Parent then
				remoteLeanState[otherCharacter] = nil
				continue
			end
			local leanRotation    = CFrame.Angles(0, 0, math.rad(leanAngleDegrees * state.targetLean))
			local counterRotation = CFrame.Angles(0, 0, math.rad(-leanAngleDegrees * state.targetLean))
			state.rootJoint.C0 = state.rootJoint.C0:Lerp(leanRotation * state.defaultRootC0, alpha)
			state.leftHip.C0   = state.leftHip.C0:Lerp(counterRotation * state.defaultLeftC0, alpha)
			state.rightHip.C0  = state.rightHip.C0:Lerp(counterRotation * state.defaultRightC0, alpha)
		end
	end)
end

return RemoteLeanHandler