-- ServerHelpers
-- Utility/helper functions used across server modules.
-- Depends on ServerState, AssetRefs, ArmLerpSystem, Constants.

local AssetRefs      = require(script.Parent.AssetRefs)
local Constants      = require(script.Parent.Constants)
local ServerState    = require(script.Parent.ServerState)
local ArmLerpSystem  = require(script.Parent.ArmLerpSystem)

local attachmentSystem   = AssetRefs.attachmentSystem
local Network             = AssetRefs.Network
local NetworkRangeUtil    = AssetRefs.NetworkRangeUtil
local config              = AssetRefs.config

local MAX_ARM_C0_DISTANCE        = Constants.MAX_ARM_C0_DISTANCE
local HAND_END_LOCAL_OFFSET      = Constants.HAND_END_LOCAL_OFFSET
local ARM_PACKET_IGNORE_DURATION = Constants.ARM_PACKET_IGNORE_DURATION

local serverGripTargets     = ServerState.serverGripTargets
local lpvoLockedArms        = ServerState.lpvoLockedArms
local lpvoArmTargets        = ServerState.lpvoArmTargets
local lpvoPreGripTarget     = ServerState.lpvoPreGripTarget
local playerLPVOArmMotor    = ServerState.playerLPVOArmMotor
local playerArmIgnoreUntil  = ServerState.playerArmIgnoreUntil
local playerADSVisualStates = ServerState.playerADSVisualStates
local playerAimStates       = ServerState.playerAimStates

local ServerHelpers = {}

function ServerHelpers.IsValidCFrame(cf, maxDistance)
	if typeof(cf) ~= "CFrame" then return false end
	local p = cf.Position
	if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z then return false end
	if math.abs(p.X) == math.huge or math.abs(p.Y) == math.huge or math.abs(p.Z) == math.huge then return false end
	return p.Magnitude <= (maxDistance or MAX_ARM_C0_DISTANCE)
end

function ServerHelpers.FindAnimArmMotor(animBase, armName)
	if type(armName) ~= "string" or #armName == 0 or #armName > 32 then return nil end
	local named = animBase:FindFirstChild(armName)
	if named and named:IsA("Motor6D") then return named end
	for _, child in animBase:GetChildren() do
		if child:IsA("Motor6D") then
			local p0, p1 = child.Part0, child.Part1
			if (p0 and p0.Name == armName) or (p1 and p1.Name == armName) then
				return child
			end
		end
	end
	return nil
end

function ServerHelpers.FindServerLeverRingPart(weapon: Model, leverRingName: string): BasePart?
	if not leverRingName then return nil end
	local activeAttachments = attachmentSystem.GetActive(weapon)
	local opticsAttachment  = activeAttachments and activeAttachments["Optics"]
	if opticsAttachment and opticsAttachment.model then
		local attachmentLever = opticsAttachment.model:FindFirstChild(leverRingName, true)
		if attachmentLever and attachmentLever:IsA("BasePart") then
			return attachmentLever
		end
	end
	local baseLever = weapon:FindFirstChild(leverRingName)
	if baseLever and baseLever:IsA("BasePart") then return baseLever end
	return nil
end

function ServerHelpers.FindServerLeverRingMotor(weapon: Model, leverRingPart: BasePart, leverRingName: string): Motor6D?
	local ownMotor = leverRingPart:FindFirstChildOfClass("Motor6D")
	if ownMotor then return ownMotor end
	local grip      = weapon:FindFirstChild("Grip")
	local gripMotor = grip and grip:FindFirstChild(leverRingName)
	if gripMotor and gripMotor:IsA("Motor6D") then return gripMotor end
	return nil
end

function ServerHelpers.ResolveLPVOZoomConfig(tool: Instance, weapon: Model): any
	-- The attachment system resolves the fitted optic's zoom profile, and
	-- already falls back to the weapon's own LPVOZoom block.
	return attachmentSystem.GetLPVOConfig(weapon, attachmentSystem.LoadWeaponStats(tool))
end

function ServerHelpers.GetEquippedWeaponTool(player)
	local character = player.Character
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end
	local tool = character:FindFirstChildWhichIsA("Tool")
	if tool and tool:FindFirstChild("SPH_Weapon") then return tool end
	return nil
end

function ServerHelpers.RememberArmRestC0(motor: Motor6D)
	if motor and not motor:GetAttribute("OriginalC0_Rest") then
		motor:SetAttribute("OriginalC0_Rest", motor.C0)
	end
end

function ServerHelpers.GetArmRestC0(motor: Motor6D)
	return motor:GetAttribute("OriginalC0_Rest") or motor:GetAttribute("OriginalC0_Grip")
end

function ServerHelpers.GetServerWeaponModel(player)
	local character    = player.Character
	local rig          = character and character:FindFirstChild("WeaponRig")
	local weaponFolder = rig and rig:FindFirstChild("Weapon")
	return weaponFolder and weaponFolder:FindFirstChildWhichIsA("Model"), rig
end

function ServerHelpers.ComputeServerGripC0(rig, animBase, gripData)
	if not (rig and animBase and gripData and gripData.gripWorldCFrame) then return nil end

	local desiredArmCenterWorldCFrame
	if gripData.matchRotation then
		desiredArmCenterWorldCFrame = gripData.gripWorldCFrame * HAND_END_LOCAL_OFFSET:Inverse()
	else
		local armName    = gripData.handToPosition or "Left Arm"
		local armMotor   = ServerHelpers.FindAnimArmMotor(animBase, armName)
		local restC0     = (armMotor and ServerHelpers.GetArmRestC0(armMotor)) or CFrame.new()
		local restWorldCFrame    = animBase.CFrame * restC0
		local restRotationOnly   = restWorldCFrame - restWorldCFrame.Position
		local handEndWorldPosition = gripData.gripWorldCFrame.Position
		local armPart    = rig:FindFirstChild(armName)
		local centerToHandWorld = restRotationOnly:VectorToWorldSpace(
			Vector3.new(0, armPart and -(armPart.Size.Y / 2) or -1, 0))
		desiredArmCenterWorldCFrame = restRotationOnly + (handEndWorldPosition - centerToHandWorld)
	end

	return animBase.CFrame:ToObjectSpace(desiredArmCenterWorldCFrame)
end

function ServerHelpers.ResolveServerGripC0(player)
	local tool = ServerHelpers.GetEquippedWeaponTool(player)
	if not tool then return nil end

	local weapon, rig = ServerHelpers.GetServerWeaponModel(player)
	if not weapon or not rig then return nil end

	local gripData = attachmentSystem.GetGrip(weapon, tool.Name)
	if not gripData then return nil end

	local animBase = rig:FindFirstChild("AnimBase")
	if not animBase then return nil end

	local targetC0 = ServerHelpers.ComputeServerGripC0(rig, animBase, gripData)
	if not targetC0 or not ServerHelpers.IsValidCFrame(targetC0, MAX_ARM_C0_DISTANCE) then return nil end

	return {
		targetC0 = targetC0,
		armName  = gripData.handToPosition or "Left Arm",
		animBase = animBase,
	}
end

function ServerHelpers.BroadcastGripHand(player, armC0, armName)
	local character = player.Character
	local hrp       = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local targets = NetworkRangeUtil.GetPlayersInRange(hrp.Position, config.fireEffectDistance, player)
	Network.packets.GripHandReplicate.sendToList({
		Character = character,
		ArmC0     = armC0,
		ArmName   = armName or "",
	}, targets)
end

function ServerHelpers.ResetPlayerGunReplicationState(player)
	playerADSVisualStates[player]  = nil
	playerAimStates[player]        = nil
	playerLPVOArmMotor[player]     = nil
	playerArmIgnoreUntil[player]   = os.clock() + ARM_PACKET_IGNORE_DURATION

	local character = player.Character
	if not character then return end

	local rig      = character:FindFirstChild("WeaponRig")
	local animBase = rig and rig:FindFirstChild("AnimBase")
	if animBase then
		for _, motor in ipairs(animBase:GetChildren()) do
			if motor:IsA("Motor6D") then
				local rest = motor:GetAttribute("OriginalC0_Rest") or motor:GetAttribute("OriginalC0_Grip")
				if rest then motor.C0 = rest end
				motor:SetAttribute("OriginalC0_Grip", nil)
				motor:SetAttribute("OriginalC0", nil)
				serverGripTargets[motor] = nil
				lpvoLockedArms[motor]    = nil
				lpvoArmTargets[motor]    = nil
				lpvoPreGripTarget[motor] = nil
			end
		end
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local targets = NetworkRangeUtil.GetPlayersInRange(hrp.Position, config.fireEffectDistance, player)
		Network.packets.AimStateReplicate.sendToList({
			Character  = character,
			Aiming     = false,
			SightIndex = 1,
		}, targets)
		Network.packets.GripHandReplicate.sendToList({
			Character = character,
			ArmC0     = nil,
			ArmName   = "",
		}, targets)
	end
end

function ServerHelpers.RefreshPlayerArmReplication(player)
	playerLPVOArmMotor[player] = nil

	local character = player.Character
	local rig       = character and character:FindFirstChild("WeaponRig")
	local animBase  = rig and rig:FindFirstChild("AnimBase")
	if animBase then
		for _, motor in ipairs(animBase:GetChildren()) do
			if motor:IsA("Motor6D") then
				lpvoLockedArms[motor]    = nil
				lpvoArmTargets[motor]    = nil
				lpvoPreGripTarget[motor] = nil
				motor:SetAttribute("OriginalC0", nil)
				local rest = ServerHelpers.GetArmRestC0(motor)
				if rest then motor.C0 = rest end
				serverGripTargets[motor] = nil
				motor:SetAttribute("OriginalC0_Grip", nil)
			end
		end
	end

	local grip = ServerHelpers.ResolveServerGripC0(player)
	if grip then
		local armMotor = ServerHelpers.FindAnimArmMotor(grip.animBase, grip.armName)
		if armMotor then
			ServerHelpers.RememberArmRestC0(armMotor)
			if not armMotor:GetAttribute("OriginalC0_Grip") then
				armMotor:SetAttribute("OriginalC0_Grip",
					ServerHelpers.GetArmRestC0(armMotor) or armMotor.C0)
			end
			serverGripTargets[armMotor] = { target = grip.targetC0, active = true }
			ArmLerpSystem.EnsureArmLerpHeartbeat()
			ServerHelpers.BroadcastGripHand(player, grip.targetC0, grip.armName)
			return
		end
	end

	ServerHelpers.BroadcastGripHand(player, nil, "")
end

return ServerHelpers