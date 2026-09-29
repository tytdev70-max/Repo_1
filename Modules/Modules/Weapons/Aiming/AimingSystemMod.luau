local Modules = script:FindFirstAncestor("Modules")
local vars = require(Modules.Weapons.Core.WeaponState).get()
local aimVignette = require(script.Parent.AimVignetteMod)

local tweenService = game:GetService("TweenService")

local AimingSystemMod = {}

local deps
local lastSentAiming = nil
local lastSentSightIndex = nil

local DEFAULT_TP_AIM_OFFSET = CFrame.new(0, 0.03, 0.08)
local TP_AIM_LERP_SPEED = 8

local remoteAimVisuals = {}

AimingSystemMod.ZOOM_SENSITIVITY_REDUCTION = 0.05

function AimingSystemMod.Init(dependencies)
	deps = dependencies
	lastSentAiming = nil
	lastSentSightIndex = nil
end

function AimingSystemMod.ApplyADSVisual(gunModel, toggle, wepStats, attachmentSystem)
	if not gunModel or not wepStats or not wepStats.ADSEnabled then return end

	local ADSTween
	if wepStats.aimTime then
		ADSTween = TweenInfo.new(wepStats.aimTime / 20, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, wepStats.aimTime / 20)
	else
		ADSTween = TweenInfo.new(0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.2)
	end

	for _, child in ipairs(gunModel:GetDescendants()) do
		if child:IsA("BasePart") then
			if child.Name == "REG" then
				tweenService:Create(child, ADSTween, {Transparency = toggle and 1 or 0}):Play()
			elseif child.Name == "ADS" then
				tweenService:Create(child, ADSTween, {Transparency = toggle and 0 or 1}):Play()
			end
		end
	end
end

function AimingSystemMod.UpdateADSVisual(gunModel, wepStats, sightIndex, aiming, attachmentSystem)
	if not gunModel or not wepStats then return end
	if wepStats.ADSEnabled and wepStats.ADSEnabled[sightIndex] then
		AimingSystemMod.ApplyADSVisual(gunModel, aiming, wepStats, attachmentSystem)
	else
		AimingSystemMod.ApplyADSVisual(gunModel, false, wepStats, attachmentSystem)
	end

	if attachmentSystem and attachmentSystem.ApplyADSVisibility then
		attachmentSystem.ApplyADSVisibility(gunModel, aiming, wepStats)
	end
end

local function SetAllSightSurfaceGuis(enabled)
	local gunModel = vars.gunModel
	local attachmentSystem = deps.attachmentSystem

	if gunModel then
		for _, part in ipairs(gunModel:GetDescendants()) do
			if part.Name == "SightReticle" then
				local sg = part:FindFirstChildWhichIsA("SurfaceGui")
				if sg then sg.Enabled = enabled end
			end
		end
	end

	local activeAttachments = attachmentSystem.GetActive(gunModel)
	for _, data in pairs(activeAttachments or {}) do
		if data and data.model then
			for _, part in ipairs(data.model:GetDescendants()) do
				if part.Name == "SightReticle" then
					local sg = part:FindFirstChildWhichIsA("SurfaceGui")
					if sg then sg.Enabled = enabled end
				end
			end
		end
	end

	local tpGunModel = deps.getThirdPersonGunModel()
	if tpGunModel and tpGunModel ~= gunModel then
		for _, part in ipairs(tpGunModel:GetDescendants()) do
			if part.Name == "SightReticle" then
				local sg = part:FindFirstChild("SurfaceGui")
				if sg then sg.Enabled = false end
			end
		end
	end
end

local function SendAimState(isAiming, sightIndex)
	if not deps or not deps.playerAimStateRequest then return end
	deps.playerAimStateRequest.send({
		Aiming = isAiming,
		SightIndex = sightIndex,
	})
end

function AimingSystemMod.ReplicateAimState(force)
	if not deps then return end
	local isAiming = vars.aiming
	local sightIndex = vars.sightIndex

	if not force and isAiming == lastSentAiming and sightIndex == lastSentSightIndex then
		return
	end

	lastSentAiming = isAiming
	lastSentSightIndex = sightIndex
	SendAimState(isAiming, sightIndex)
end

local function ResolveRemoteEntry(targetCharacter)
	if not targetCharacter or targetCharacter == deps.character then return nil end

	local rig = targetCharacter:FindFirstChild("WeaponRig")
	if not rig then return nil end

	local tool = targetCharacter:FindFirstChildWhichIsA("Tool")
	if not tool or not tool:FindFirstChild("SPH_Weapon") then return nil end

	local ok, wepStats = pcall(require, tool.SPH_Weapon.WeaponStats)
	if not ok or not wepStats then return nil end

	local baseWeld = rig:FindFirstChild("BaseWeld")
	if not baseWeld or not baseWeld:IsA("JointInstance") then return nil end

	local entry = remoteAimVisuals[baseWeld]
	if not entry then
		entry = {aiming = false, pushback = 0}
		remoteAimVisuals[baseWeld] = entry
	end

	entry.restC0 = wepStats.serverOffset or CFrame.new()
	entry.centerX = wepStats.tpAimCenterX or 0
	entry.aimOffset = wepStats.tpAimOffset or DEFAULT_TP_AIM_OFFSET
	return entry
end

local function RefreshTargetC0(entry)
	local restC0 = entry.restC0 or CFrame.new()
	local target

	if entry.aiming then
		local rotationOnly = restC0 - restC0.Position
		local centeredPos = Vector3.new(entry.centerX or 0, restC0.Position.Y, restC0.Position.Z)
		target = CFrame.new(centeredPos) * rotationOnly * entry.aimOffset
	else
		target = restC0
	end

	entry.targetC0 = target * CFrame.new(0, 0, entry.pushback or 0)
end

function AimingSystemMod.HandleAimStateReplicate(Data)
	if not deps then return end

	local entry = ResolveRemoteEntry(Data.Character)
	if not entry then return end

	entry.aiming = Data.Aiming == true
	RefreshTargetC0(entry)
end

function AimingSystemMod.HandleWeaponPushbackReplicate(Data)
	if not deps then return end

	local entry = ResolveRemoteEntry(Data.Character)
	if not entry then return end

	local pushback = Data.Pushback
	if type(pushback) ~= "number" or pushback ~= pushback then
		pushback = 0
	end

	entry.pushback = math.max(pushback, 0)
	RefreshTargetC0(entry)
end

function AimingSystemMod.UpdateRemoteAimVisuals(dt)
	aimVignette.Update(dt)

	for gunMotor, entry in pairs(remoteAimVisuals) do
		if not gunMotor or not gunMotor.Parent then
			remoteAimVisuals[gunMotor] = nil
		elseif entry.targetC0 then
			local alpha = math.clamp(dt * TP_AIM_LERP_SPEED, 0, 1)
			gunMotor.C0 = gunMotor.C0:Lerp(entry.targetC0, alpha)
		end
	end
end

function AimingSystemMod.ToggleAiming(toggle)
	if not deps then return end
	local equipped = vars.equipped
	if not equipped then return end
	if vars.freeLook and toggle then return end
	if vars.reloading and toggle and not deps.config.canReloadWhileAiming then return end

	deps.character:SetAttribute("Aiming", toggle)

	local wepStats = vars.wepStats
	local gunModel = vars.gunModel
	local sightIndex = vars.sightIndex

	if toggle then
		if not vars.firstPerson then
			return
		end

		deps.changeHoldStance(0)
		vars.aiming = true
		aimVignette.SetAiming(true)
		deps.mobileSupport.UpdateLPVOButtonVisibility()

		AimingSystemMod.UpdateADSVisual(gunModel, wepStats, sightIndex, true, deps.attachmentSystem)
		SetAllSightSurfaceGuis(true)

		deps.userInputService.MouseDeltaSensitivity = vars.aimSensitivity
		deps.playRepSound("AimUp")

		if vars.firstPerson then
			deps.player.CameraMaxZoomDistance = 0.5
			deps.player.CameraMinZoomDistance = 0.5
		end

		if wepStats.aimAnim then
			local transTime = math.max(wepStats.aimTime / 4, 0.05)
			deps.playAnimation(wepStats.aimAnim, {looped = true, priority = Enum.AnimationPriority.Action, transSpeed = transTime}, "AimAnim")
		end

		if deps.config.proceduralAimAnim then
			vars.tempCameraRoll = 5
			deps.gunRecoilSpring:shove(Vector3.new(0.1, 0.03, 0.35))
			deps.swaySpring:shove(Vector3.new(0, -0.7, 0.12))
			task.delay(0.06, function()
				if vars.aiming == toggle then
					vars.tempCameraRoll = 0
					deps.swaySpring:shove(Vector3.new(0, 0.25, 0))
				end
			end)
		end

		if deps.aimDoF then
			vars.isAimDoFActive = true
			deps.aimDoF.Enabled = true

			local opticDOF = deps.attachmentSystem.GetDepthOfFieldConfig(gunModel)
			local dofConfig = opticDOF or wepStats.DOF

			if dofConfig then
				deps.changeDoF(
					dofConfig.FarIntensity or 0,
					dofConfig.FocusDistance or 5,
					dofConfig.InFocusRadius or 1,
					dofConfig.NearIntensity or 1,
					true
				)
			end
		end
	else
		vars.aiming = false
		aimVignette.SetAiming(false)
		AimingSystemMod.UpdateADSVisual(gunModel, wepStats, sightIndex, false, deps.attachmentSystem)
		deps.mobileSupport.UpdateLPVOButtonVisibility()
		deps.userInputService.MouseDeltaSensitivity = 1
		deps.playRepSound("AimDown")

		SetAllSightSurfaceGuis(false)

		local aimOutTime = wepStats and (wepStats.aimTime / 2) or 0.3

		if vars.fireFovActive then
			vars.storedAimFOV = nil
			if vars.fireFovReturnTask then
				task.cancel(vars.fireFovReturnTask)
				vars.fireFovReturnTask = nil
			end
			vars.fireFovActive = false
		end

		if deps.cancelFOVTween then
			deps.cancelFOVTween()
		end

		tweenService:Create(deps.camera, TweenInfo.new(aimOutTime), {FieldOfView = deps.defaultFOV}):Play()

		if vars.firstPerson then
			deps.player.CameraMaxZoomDistance = 10
			deps.player.CameraMinZoomDistance = 0.5
		end

		if wepStats then
			deps.stopAnimation(wepStats.aimAnim, math.max(wepStats.aimTime / 6, 0.05))
		end

		if deps.config.proceduralAimAnim then
			vars.tempCameraRoll = 4
			deps.gunRecoilSpring:shove(Vector3.new(-0.06, -0.02, -0.2))
			deps.swaySpring:shove(Vector3.new(0, 0.5, -0.1))
			task.delay(0.06, function()
				if vars.aiming == toggle then
					vars.tempCameraRoll = 0
				end
			end)
		end

		if deps.aimDoF and vars.isAimDoFActive then
			vars.isAimDoFActive = false
			deps.changeDoF(0, 0, 0, 0, true)
			task.delay(0.2, function()
				if not vars.isAimDoFActive and deps.aimDoF then
					deps.aimDoF.Enabled = false
				end
			end)
		end
	end

	AimingSystemMod.ReplicateAimState()
end

function AimingSystemMod.ResetAiming()
	aimVignette.Reset()
	if not deps then return end
	vars.aiming = false
	pcall(function() deps.character:SetAttribute("Aiming", false) end)
	lastSentAiming = nil
	lastSentSightIndex = nil
	AimingSystemMod.ReplicateAimState(true)
end

return AimingSystemMod