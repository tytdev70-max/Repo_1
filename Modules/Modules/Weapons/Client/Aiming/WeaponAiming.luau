--!strict

local Modules = script:FindFirstAncestor("Modules")
local Assets = Modules.Parent

local WeaponContext = require(Modules.Weapons.Core.WeaponContext)
local vars = require(Modules.Weapons.Core.WeaponState).get()
local config = require(Assets.GameConfig)
local aimingSystemMod = require(Modules.Weapons.Aiming.AimingSystemMod)
local Attachments = require(Modules.Weapons.Attachments.SPHAttachments)
local ubglSystem = require(Modules.Weapons.Attachments.UBGLHandlerMod)
local camera = workspace.CurrentCamera
local tweenService = game:GetService("TweenService")
local contextActionService = game:GetService("ContextActionService")
local userInputService = game:GetService("UserInputService")

local WeaponAiming = {}

local HandleInput, PlayAnimation, StopAnimation, aimDoF
local depthOfField
local activeFOVTween: Tween? = nil

local ToggleADS, ChangeHoldStance, HardStopHoldStance, ChangeDoF, ToggleSprint, ToggleAiming, BindAiming, UnbindAiming, AimToFOV

ToggleADS = function(toggle)
	if vars.wepStats and vars.wepStats.ADSEnabled then
		aimingSystemMod.ApplyADSVisual(vars.gunModel, toggle, vars.wepStats)
	end
end

ChangeHoldStance = function(newStance)
	if vars.aiming then return end
	if vars.holdStance == newStance and vars.holdAnim then
		StopAnimation(vars.holdAnim.Name, 0.3)
		vars.holdAnim = nil
		vars.holdStance = 0
	else
		vars.holdStance = newStance

		if vars.holdAnim then
			StopAnimation(vars.holdAnim.Name, 0.3)
		end

		local animToPlay
		if vars.holdStance == 1 and vars.wepStats.holdUpAnim then
			animToPlay = vars.wepStats.holdUpAnim
		elseif vars.holdStance == 2 and vars.wepStats.patrolAnim then
			animToPlay = vars.wepStats.patrolAnim
		elseif vars.holdStance == 3 and vars.wepStats.holdDownAnim then
			animToPlay = vars.wepStats.holdDownAnim
		end

		if animToPlay then
			vars.holdAnim = PlayAnimation(animToPlay,{looped = true, priority = Enum.AnimationPriority.Action,transSpeed = 0.3})
			if vars.holdAnim then
				vars.holdAnim:Play()
			end
		elseif vars.holdAnim then
			vars.holdAnim = nil
		end
	end
end

HardStopHoldStance = function()
	if vars.holdAnim then
		StopAnimation(vars.holdAnim.Name, 0)
		vars.holdAnim = nil
	end
	vars.holdStance = 0
end

ChangeDoF = function(fInt, fDist, fRad, nInt, isAimDoF)
	local targetDoF = isAimDoF and aimDoF or depthOfField
	if not targetDoF then return end

	tweenService:Create(targetDoF, TweenInfo.new(0.2), {
		FarIntensity = fInt,
		FocusDistance = fDist,
		InFocusRadius = fRad,
		NearIntensity = nInt
	}):Play()
end

ToggleSprint = function(toggle:boolean)
	if vars.equipping then return end
	if ubglSystem.IsActive() or ubglSystem.IsToggling() then return end
	if toggle then
		if vars.aiming then ToggleAiming(false) end
		ChangeHoldStance(0)
		userInputService.MouseDeltaSensitivity = 1
		vars.holdingM1 = false
		if vars.wepStats then
			if vars.wepStats.fireAnim then
				StopAnimation(vars.wepStats.fireAnim, 0.1)
			end
			PlayAnimation(vars.wepStats.sprintAnim,{looped = true, priority = Enum.AnimationPriority.Action, transSpeed = 0.25})
		end

		if depthOfField then
			ChangeDoF(0,0,0,0)
		end
	elseif vars.wepStats then
		if vars.wepStats then
			StopAnimation(vars.wepStats.sprintAnim,0.25)
		end

		if depthOfField then
			ChangeDoF(0,0,0,0)
		end
	end
end

ToggleAiming = function(toggle)
	aimingSystemMod.ToggleAiming(toggle)
end

BindAiming = function()
	contextActionService:BindActionAtPriority("SPH_HoldAim", HandleInput, false, config.gunInputPriority, unpack(config.aimGun))
end

UnbindAiming = function()
	contextActionService:UnbindAction("SPH_HoldAim")
end

local function CancelFOVTween()
	if activeFOVTween then
		activeFOVTween:Cancel()
		activeFOVTween = nil
	end
end

AimToFOV = function(targetFOV)
	local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

	CancelFOVTween()

	local tween = tweenService:Create(camera, tweenInfo, { FieldOfView = targetFOV })
	activeFOVTween = tween
	tween:Play()
end

function WeaponAiming.init()
	local ctx = WeaponContext.get()
	HandleInput = ctx.HandleInput
	PlayAnimation = ctx.PlayAnimation
	StopAnimation = ctx.StopAnimation
	aimDoF = ctx.aimDoF
	depthOfField = ctx.depthOfField
end

WeaponAiming.ToggleADS = ToggleADS
WeaponAiming.ChangeHoldStance = ChangeHoldStance
WeaponAiming.HardStopHoldStance = HardStopHoldStance
WeaponAiming.ChangeDoF = ChangeDoF
WeaponAiming.ToggleSprint = ToggleSprint
WeaponAiming.ToggleAiming = ToggleAiming
WeaponAiming.BindAiming = BindAiming
WeaponAiming.UnbindAiming = UnbindAiming
WeaponAiming.AimToFOV = AimToFOV
WeaponAiming.CancelFOVTween = CancelFOVTween

return WeaponAiming