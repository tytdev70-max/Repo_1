--!strict

local Modules = script:FindFirstAncestor("Modules")
local Assets = Modules.Parent

local WeaponContext = require(Modules.Weapons.Core.WeaponContext)
local vars = require(Modules.Weapons.Core.WeaponState).get()
local config = require(Assets.GameConfig)
local bulletHandler = require(Modules.Weapons.Fire.BulletHandler)
local shellEjection = require(Modules.Weapons.Fire.ShellEjection)
local ModelQueryCache = require(Modules.Weapons.Core.ModelQueryCache)

local WeaponActions = {}

local player, PlayAnimation, PlayRepSound
local moveBolt, switchFireMode, repShellEjectRequest
local cachedTPGunModel = nil

local GetThirdPersonGunModel, ClearThirdPersonGunCache, IsLoaded, MoveBolt, EjectShell, FindProjectilePart, SwitchFireMode, UpdateAllBulletTransparency, UpdateBulletTransparency

GetThirdPersonGunModel = function()
	if cachedTPGunModel and cachedTPGunModel.Parent then
		return cachedTPGunModel
	end

	if vars.weaponRig and vars.weaponRig:FindFirstChild("Weapon") then
		cachedTPGunModel = vars.weaponRig.Weapon:FindFirstChildWhichIsA("Model")
		return cachedTPGunModel
	end

	return nil
end

ClearThirdPersonGunCache = function()
	cachedTPGunModel = nil
end

IsLoaded = function()
	if not vars.equipped or not vars.wepStats or not vars.gunAmmo then return false end
	local magAmmo = vars.gunAmmo:FindFirstChild("MagAmmo")
	if vars.wepStats.openBolt then
		return magAmmo ~= nil and magAmmo.Value > 0
	end
	local chambered = vars.equipped:FindFirstChild("Chambered")
	return chambered ~= nil and chambered.Value
end

MoveBolt = function(direction:CFrame,silent:boolean)
	if not vars.gunAmmo or not vars.gunAmmo:FindFirstChild("MagAmmo") then return end
	local magAmmoValue = vars.gunAmmo.MagAmmo.Value

	if vars.gunModel then
		bulletHandler.MoveBolt(vars.gunModel, vars.wepStats, direction, magAmmoValue)
	end

	local tpGunModel = GetThirdPersonGunModel()
	if tpGunModel then
		bulletHandler.MoveBolt(tpGunModel, vars.wepStats, direction, magAmmoValue)
	end

	if magAmmoValue <= 0 and not silent then
		PlayRepSound("Empty")
	end

	local sendDirection = typeof(direction) == "CFrame" and direction or CFrame.new(0, 0, -direction)

	moveBolt.send({
		Direction = sendDirection,
		MagAmmo = magAmmoValue,
	})
end

EjectShell = function()
	if not vars.equipped or not vars.wepStats then return end
	vars.ejected = true
	if vars.wepStats.shellEject and config.shellEjection then
		if vars.firstPerson then
			shellEjection.ejectShell(player, vars.equipped, vars.gunModel)
		else
			shellEjection.ejectShell(player, vars.equipped, GetThirdPersonGunModel())
		end
		repShellEjectRequest.send(nil)
	end
end

-- Uncached tree search (original logic). Only runs on a cache miss.
local function computeProjectilePart(model: Instance, projectileName: string?): BasePart?
	if projectileName and projectileName ~= "Bullet" then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") and desc.Name == projectileName then
				return desc
			end
		end
	end
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == "" then
			return desc
		end
	end
	return nil
end

-- Pre-built cache keys so per-frame calls don't concatenate strings
local projectileKeys: { [string]: string } = {}
local PROJECTILE_KEY_NONE = "projectile:<nil>"

FindProjectilePart = function(model, projectileName)
	if not model then return nil end
	local key = PROJECTILE_KEY_NONE
	if projectileName then
		key = projectileKeys[projectileName]
		if not key then
			key = "projectile:" .. projectileName
			projectileKeys[projectileName] = key
		end
	end
	return ModelQueryCache.get(model, key, computeProjectilePart, projectileName)
end

SwitchFireMode = function()
	if vars.switchingFireMode or vars.magCheckDebounce or vars.reloading then return end
	vars.switchingFireMode = true

	vars.curFireMode = vars.curFireMode or (vars.equipped and vars.equipped:FindFirstChild("FireMode") and vars.equipped.FireMode.Value) or 0

	local repitions = 0
	repeat
		repitions += 1
		vars.curFireMode += 1
		if vars.curFireMode > 4 then
			if vars.wepStats.noSafety or true then
				vars.curFireMode = 1
			else
				vars.curFireMode = 0
				break
			end
		end
	until vars.wepStats.fireSwitch[vars.curFireMode] or repitions > 10

	switchFireMode.send(vars.curFireMode)

	if vars.wepStats.switchAnim then
		local animToPlay
		if vars.switchAnimIndex == 1 then
			animToPlay = vars.wepStats.switchAnim
		elseif vars.wepStats.switchAnim2 then
			animToPlay = vars.wepStats.switchAnim2
		else
			animToPlay = vars.wepStats.switchAnim 
		end

		PlayAnimation(animToPlay, {
			priority = Enum.AnimationPriority.Action2,
			transSpeed = 0.05
		})

		vars.switchAnimIndex = vars.switchAnimIndex == 1 and 2 or 1
	end

	task.delay(0.25, function()
		vars.switchingFireMode = false
	end)
end

UpdateAllBulletTransparency = function(bulletHolderPart:BasePart, transparency:number)
	for _, child in bulletHolderPart:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 30) == "Bullet" then
			child.Transparency = transparency
		end
	end
end

UpdateBulletTransparency = function(bulletHolderPart:BasePart, bulletNumber:number, transparency:number)
	local bulletName = "Bullet"..bulletNumber

	for _, child in bulletHolderPart:GetChildren() do
		if child:IsA("BasePart") and child.Name == bulletName then
			child.Transparency = transparency
		end
	end
end

function WeaponActions.init()
	local ctx = WeaponContext.get()
	player = ctx.player
	PlayAnimation = ctx.PlayAnimation
	PlayRepSound = ctx.PlayRepSound
	moveBolt = ctx.moveBolt
	switchFireMode = ctx.switchFireMode
	repShellEjectRequest = ctx.repShellEjectRequest
	cachedTPGunModel = nil
end
WeaponActions.GetThirdPersonGunModel = GetThirdPersonGunModel
WeaponActions.ClearThirdPersonGunCache = ClearThirdPersonGunCache
WeaponActions.IsLoaded = IsLoaded
WeaponActions.MoveBolt = MoveBolt
WeaponActions.EjectShell = EjectShell
WeaponActions.FindProjectilePart = FindProjectilePart
WeaponActions.SwitchFireMode = SwitchFireMode
WeaponActions.UpdateAllBulletTransparency = UpdateAllBulletTransparency
WeaponActions.UpdateBulletTransparency = UpdateBulletTransparency

return WeaponActions
