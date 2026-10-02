--// FireReplication.lua
--// Handles Network packets ReplicateFire and ReplicateFireUBGL:
--// replicates muzzle FX, bullet traces, and UBGL shell visuals for
--// other players.  Local player packets are ignored.

local FireReplication = {}

local ServiceRefs    = require(script.Parent.ServiceRefs)
local WeaponContext  = require(script.Parent.WeaponContext)

local Config         : any    = ServiceRefs.Config
local player         : Player = ServiceRefs.player
local modules                  = ServiceRefs.modules

local bulletHandler  = require(modules.Weapons.Fire.BulletHandler)
local Network        = require(modules.Core.Networking.SPH_Network)

--// Private: UBGL

local function FireUBGLShell(
	shooter    : Player,
	_firePoint : CFrame,
	direction  : Vector3
): ()
	if shooter == player then return end

	local weapon = WeaponContext.ResolveShooterWeapon(shooter, false)
	if not weapon or not weapon.wepStats.UBGL then return end

	bulletHandler.FireFX(
		shooter, weapon.gunModel, "UBGLMuzzle", 10,
		nil, false, false, "UBGLFire"
	)

	local muzzle: Attachment = weapon.gunModel.Grip:FindFirstChild("UBGLMuzzle")
		or weapon.gunModel.Grip.Muzzle

	local bulletVel: Vector3 = direction
		* (weapon.wepStats.UBGL.MuzzleVelocity or 55)
		* Config.meterMultiplier

	bulletHandler.FireBullet(
		weapon.rig, muzzle.WorldCFrame.Position, direction,
		bulletVel, weapon.tool, shooter,
		nil, true, false, true
	)
end

--// Private: Standard Bullet

local function FireBullet(
	shooter          : Player,
	_firePoint       : CFrame,
	isSuppressed     : boolean,
	pelletDirections : { Vector3 }?
): ()
	if shooter == player then return end

	local weapon = WeaponContext.ResolveShooterWeapon(shooter, true)
	if not weapon then return end

	local gunAmmo  : Instance = (weapon.tool :: any).Ammo
	local magAmmo  : IntValue? = gunAmmo:FindFirstChild("MagAmmo")

	local isAutoFire: boolean = weapon.wepStats.fireMode == 2
	bulletHandler.FireFX(
		shooter, weapon.gunModel, "Muzzle",
		weapon.wepStats.muzzleChance, nil,
		isAutoFire, isSuppressed
	)

	local muzzle      : Attachment = (weapon.gunModel :: any).Grip.Muzzle
	local bulletOrigin : Vector3   = muzzle.WorldCFrame.Position

	local tracerColor: any = nil
	if weapon.wepStats.tracers
		and magAmmo
		and magAmmo.Value % weapon.wepStats.tracerTiming == 0
	then
		tracerColor = weapon.wepStats.tracerColor
	end

	if pelletDirections and #pelletDirections > 0 then
		for _, dir: Vector3 in ipairs(pelletDirections) do
			local bulletVel: Vector3 = dir
				* weapon.wepStats.muzzleVelocity
				* Config.meterMultiplier
			bulletHandler.FireBullet(
				weapon.rig, bulletOrigin, dir, bulletVel,
				weapon.tool, shooter, tracerColor, true
			)
		end
	else
		local bulletDir: Vector3 = muzzle.WorldCFrame.LookVector
		local bulletVel: Vector3 = bulletDir
			* weapon.wepStats.muzzleVelocity
			* Config.meterMultiplier
		bulletHandler.FireBullet(
			weapon.rig, bulletOrigin, bulletDir, bulletVel,
			weapon.tool, shooter, tracerColor, true
		)
	end
end

--// Public

function FireReplication.Init(): ()
	Network.packets.ReplicateFireUBGL.listen(function(Data: any): ()
		FireUBGLShell(Data.Player, Data.FirePointCFrame, Data.Direction)
	end)

	Network.packets.ReplicateFire.listen(function(Data: any): ()
		FireBullet(Data.Shooter, Data.MuzzleCFrame, Data.Suppressed, Data.Directions)
	end)
end

return FireReplication