-- ArmLerpSystem
-- Server-side arm motor interpolation for grip hand and LPVO ring.
-- Exposes EnsureArmLerpHeartbeat() and StepArmLerps(dt).

local ServiceRefs = require(script.Parent.ServiceRefs)
local Constants   = require(script.Parent.Constants)
local ServerState = require(script.Parent.ServerState)

local runService  = ServiceRefs.runService

local ARM_LERP_HOLD_RATE         = Constants.ARM_LERP_HOLD_RATE
local ARM_LERP_RESTORE_RATE      = Constants.ARM_LERP_RESTORE_RATE
local ARM_LERP_HOLD_MAX_ALPHA    = Constants.ARM_LERP_HOLD_MAX_ALPHA
local ARM_LERP_RESTORE_MAX_ALPHA = Constants.ARM_LERP_RESTORE_MAX_ALPHA
local ARM_AT_TARGET_EPSILON      = Constants.ARM_AT_TARGET_EPSILON

local serverGripTargets = ServerState.serverGripTargets
local lpvoArmTargets    = ServerState.lpvoArmTargets
local lpvoLockedArms    = ServerState.lpvoLockedArms

local armLerpHeartbeatConn: RBXScriptConnection? = nil

local ArmLerpSystem = {}

local function StepArmLerps(dt: number)
	local holdAlpha    = math.clamp(dt * ARM_LERP_HOLD_RATE,    0, ARM_LERP_HOLD_MAX_ALPHA)
	local restoreAlpha = math.clamp(dt * ARM_LERP_RESTORE_RATE, 0, ARM_LERP_RESTORE_MAX_ALPHA)

	for armMotor, data in pairs(lpvoArmTargets) do
		if not armMotor or not armMotor.Parent then
			lpvoArmTargets[armMotor] = nil
			continue
		end
		if not lpvoLockedArms[armMotor] and serverGripTargets[armMotor] then
			lpvoArmTargets[armMotor] = nil
			continue
		end
		local remaining = (armMotor.C0.Position - data.target.Position).Magnitude
		if remaining < ARM_AT_TARGET_EPSILON then
			if not data.active then
				armMotor.C0 = data.target
				lpvoArmTargets[armMotor] = nil
			end
			continue
		end
		armMotor.C0 = armMotor.C0:Lerp(data.target, data.active and holdAlpha or restoreAlpha)
	end

	for armMotor, data in pairs(serverGripTargets) do
		if not armMotor or not armMotor.Parent then
			serverGripTargets[armMotor] = nil
			continue
		end
		if lpvoLockedArms[armMotor] then
			continue
		end
		local remaining = (armMotor.C0.Position - data.target.Position).Magnitude
		if remaining < ARM_AT_TARGET_EPSILON then
			if not data.active then
				armMotor.C0 = data.target
				serverGripTargets[armMotor] = nil
			end
			continue
		end
		armMotor.C0 = armMotor.C0:Lerp(data.target, data.active and holdAlpha or restoreAlpha)
	end

	if not next(lpvoArmTargets) and not next(serverGripTargets) then
		if armLerpHeartbeatConn then
			armLerpHeartbeatConn:Disconnect()
			armLerpHeartbeatConn = nil
		end
	end
end

function ArmLerpSystem.EnsureArmLerpHeartbeat()
	if not armLerpHeartbeatConn then
		armLerpHeartbeatConn = runService.Heartbeat:Connect(StepArmLerps)
	end
end

ArmLerpSystem.StepArmLerps = StepArmLerps

return ArmLerpSystem