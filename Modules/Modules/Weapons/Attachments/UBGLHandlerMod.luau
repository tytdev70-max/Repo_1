local module = {}
local Modules = script:FindFirstAncestor("Modules")
local vars = require(Modules.Weapons.Core.WeaponState).get()

local RunService = game:GetService("RunService")

local deps = nil

local active = false
local toggling = false
local reloading = false
local fireOnCooldown = false
local pendingToggle = false
local pendingToggleEpoch = nil
local pendingToggleConn: RBXScriptConnection? = nil

local epoch = 0
local function BumpEpoch()
	epoch += 1
end

local function StopPendingTogglePoll()
	if pendingToggleConn then
		pendingToggleConn:Disconnect()
		pendingToggleConn = nil
	end
end

local function GetWepStats()
	return vars.wepStats
end

local function HasUBGL()
	local wepStats = GetWepStats()
	return wepStats ~= nil and wepStats.UBGL ~= nil and wepStats.UBGL.Enabled == true
end

local function GetAmmoFolder()
	local tool = vars.equipped
	return tool and tool:FindFirstChild("UBGLAmmo")
end

local function SetActive(state)
	active = state
	if deps.character then
		deps.character:SetAttribute("UBGLActive", state)
	end
	if deps.mobileSupport then
		deps.mobileSupport.UpdateMobileButtonVisibility()
		deps.mobileSupport.UpdateLPVOButtonVisibility()
	end
end

function module.IsActive()
	return active
end

function module.IsToggling()
	return toggling
end

function module.GetAmmo()
	local ammo = GetAmmoFolder()
	if not ammo then return 0, 0 end
	return ammo.Loaded.Value, ammo.AmmoPool.Value
end

local function PlayUBGLIdle()
	local wepStats = GetWepStats()
	if not wepStats or not wepStats.UBGLIdle then return end
	deps.playAnimation(wepStats.UBGLIdle, {looped = true, priority = Enum.AnimationPriority.Movement})
end

local function PlayUBGLEquip(wepStats)
	vars.holdingM1 = false

	if vars.aiming then deps.toggleAiming(false) end
	deps.hardStopHoldStance() 
	deps.stopAnimation(wepStats.fireAnim, 0.05)
	if wepStats.boltChamber then deps.stopAnimation(wepStats.boltChamber, 0.05) end
	if wepStats.boltClose then deps.stopAnimation(wepStats.boltClose, 0.05) end

	if wepStats.idleAnim then deps.stopAnimation(wepStats.idleAnim, 0.05) end
	if wepStats.sprintAnim then deps.stopAnimation(wepStats.sprintAnim, 0.05) end
	if wepStats.aimAnim then deps.stopAnimation(wepStats.aimAnim, 0.05) end

	SetActive(true)
	local myEpoch = epoch

	if not wepStats.UBGLEquip then
		toggling = false
		PlayUBGLIdle()
		return
	end

	local track = deps.playAnimation(wepStats.UBGLEquip, {priority = Enum.AnimationPriority.Action2, looped = false})
	if track then
		track.Stopped:Once(function()
			if myEpoch ~= epoch then return end
			toggling = false
			if active then PlayUBGLIdle() end
		end)
	else
		toggling = false
		PlayUBGLIdle()
	end
end

local function PlayUBGLUnequip(wepStats)
	if vars.aiming then deps.toggleAiming(false) end
	deps.hardStopHoldStance()

	if wepStats.UBGLIdle then deps.stopAnimation(wepStats.UBGLIdle, 0.05) end

	local myEpoch = epoch

	if not wepStats.UBGLUnequip then
		SetActive(false)
		toggling = false
		deps.idleAnim()
		return
	end

	local track = deps.playAnimation(wepStats.UBGLUnequip, {priority = Enum.AnimationPriority.Action2, looped = false})
	if track then
		track.Stopped:Once(function()
			if myEpoch ~= epoch then return end
			SetActive(false)
			toggling = false
			deps.idleAnim()
		end)
	else
		SetActive(false)
		toggling = false
		deps.idleAnim()
	end
end

local function IsPrimaryBusy()
	return reloading or vars.reloading or vars.equipping or vars.unequipping
		or (deps.isAnimationBusy and deps.isAnimationBusy())
end

local function BeginToggle(requestEpoch)
	pendingToggle = false
	pendingToggleEpoch = nil
	StopPendingTogglePoll()

	if requestEpoch ~= nil and requestEpoch ~= epoch then
		toggling = false
		return
	end

	if not HasUBGL() then
		toggling = false
		return
	end

	local wepStats = GetWepStats()

	if active then
		PlayUBGLUnequip(wepStats)
	else
		PlayUBGLEquip(wepStats)
	end
end

function module.ToggleUBGL()
	if not HasUBGL() then return end
	if toggling then return end
	toggling = true
	vars.holdingM1 = false

	local requestEpoch = epoch

	if IsPrimaryBusy() then
		pendingToggle = true
		pendingToggleEpoch = requestEpoch

		if not pendingToggleConn then
			pendingToggleConn = RunService.Heartbeat:Connect(function()
				if not pendingToggle then
					StopPendingTogglePoll()
					return
				end
				if not deps then return end
				if IsPrimaryBusy() then return end

				BeginToggle(pendingToggleEpoch)
			end)
		end
		return
	end

	BeginToggle(requestEpoch)
end

local function CanFire()
	if reloading or fireOnCooldown or toggling then return false end
	local loaded = module.GetAmmo()
	return loaded > 0
end

local function Fire()
	if not active or toggling then return end

	if not CanFire() then
		if not reloading and not fireOnCooldown
			and not vars.emptyClickPlaying
			and not vars.emptyClickDebounce then
			deps.playRepSound("Click")
			if deps.playEmptyClickAnimation then
				task.spawn(deps.playEmptyClickAnimation)
			end
		end
		return
	end

	local wepStats = GetWepStats()

	local fireModel
	if vars.firstPerson then
		fireModel = vars.gunModel
	else
		local weaponRig = vars.weaponRig
		fireModel = weaponRig and weaponRig.Weapon:FindFirstChildWhichIsA("Model")
	end
	if not fireModel then return end

	local muzzle = fireModel.Grip:FindFirstChild("UBGLMuzzle") or fireModel.Grip:FindFirstChild("Muzzle")
	if not muzzle then return end

	fireOnCooldown = true
	local cooldown = 60 / (wepStats.UBGL.FireRate or 60)
	task.delay(cooldown, function() fireOnCooldown = false end)

	if wepStats.UBGLFire then
		local myEpoch = epoch
		local track = deps.playAnimation(wepStats.UBGLFire, {priority = Enum.AnimationPriority.Action2, looped = false})
		if track then
			track.Stopped:Once(function()
				if myEpoch ~= epoch then return end
				if active and not toggling and not reloading then
					PlayUBGLIdle()
				end
			end)
		end
	end

	local origin = muzzle.WorldCFrame.Position
	local direction
	if vars.firstPerson then
		direction = workspace.CurrentCamera.CFrame.LookVector
	else
		direction = muzzle.WorldCFrame.LookVector
	end

	deps.bulletHandler.FireFX(deps.player, fireModel, "UBGLMuzzle", 10, nil, false, false, "UBGLFire")

	local velocity = direction * (wepStats.UBGL.MuzzleVelocity or 55) * deps.config.meterMultiplier
	deps.bulletHandler.FireBullet(vars.weaponRig, origin, direction, velocity, vars.equipped, deps.player, nil, false, false, true)

	deps.playerFireUBGL.send({
		FirePointCFrame = muzzle.WorldCFrame,
		Direction = direction,
	})
end

local function StartReload()
	if reloading or not active or toggling then return end

	local wepStats = GetWepStats()
	local loaded, ammoPool = module.GetAmmo()
	if loaded >= (wepStats.UBGL.Capacity or 1) or ammoPool <= 0 then return end

	reloading = true
	local myEpoch = epoch

	if not wepStats.UBGLReload then
		reloading = false
		return
	end

	local track = deps.playAnimation(wepStats.UBGLReload, {priority = Enum.AnimationPriority.Action2, transSpeed = 0.17})
	if track then
		track.Stopped:Once(function()
			if myEpoch ~= epoch then return end
			reloading = false
			if active then PlayUBGLIdle() end
		end)
	else
		reloading = false
	end
end

function module.HandleReloadKeyframe()
	if not active then return end
	deps.ubglReload.send(nil)
end

function module.HandleUBGLInput(actionName, inputState, inputObject)
	local inputBegan = Enum.UserInputState.Begin

	if actionName == "SPH_Trigger" then
		if inputState == inputBegan then
			Fire()
		end
	elseif actionName == "SPH_Reload" then
		if inputState == inputBegan then
			StartReload()
		end
	end
end

function module.Cleanup()
	BumpEpoch()
	active = false
	toggling = false
	reloading = false
	fireOnCooldown = false
	pendingToggle = false
	pendingToggleEpoch = nil
	StopPendingTogglePoll()
	if deps and deps.character then
		deps.character:SetAttribute("UBGLActive", false)
	end
end

function module.ForceUnequip(skipAnimation)
	if not active and not toggling and not pendingToggle then
		return
	end

	BumpEpoch()
	pendingToggle = false
	pendingToggleEpoch = nil
	toggling = false
	StopPendingTogglePoll()

	if not active then
		if deps and deps.character then
			deps.character:SetAttribute("UBGLActive", false)
		end
		return
	end

	if not skipAnimation then
		local wepStats = GetWepStats()
		if wepStats then
			if deps.stopAnimation then
				deps.stopAnimation(wepStats.UBGLIdle, 0)
				deps.stopAnimation(wepStats.UBGLEquip, 0)
				deps.stopAnimation(wepStats.UBGLReload, 0)
				deps.stopAnimation(wepStats.UBGLFire, 0)
			end
			if wepStats.UBGLUnequip then
				local track = deps.playAnimation(wepStats.UBGLUnequip, {
					priority = Enum.AnimationPriority.Action2,
					looped = false,
					transSpeed = 0
				})
				if track then
					track.Stopped:Wait()
				end
			end
		end
	end

	module.Cleanup()
end

function module.Init(dependencies)
	deps = dependencies
	module.Cleanup()
end

return module