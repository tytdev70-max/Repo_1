local wepStats = {}

--< Weapon type >--
wepStats.weaponType = "Gun"
wepStats.projectile = "Bullet"
wepStats.magType = 1
--[[ Ammo 
1 = This gun is magazine fed.
2 = This gun must have bullets inserted manually. (Shotguns, revolvers, etc)
3 = This gun can have bullets inserted manually, but also has clips.
If you want the gun's capacity to be higher than its clip size, add a setting called wepStats.clipSize.
2 and 3 will use their reload anim for shell insertion.
3 requires a clipReloadAnim animation setting.
]]

wepStats.operationType = 1
--[[ V Operation Type Guide V
1 = Gun can be reloaded with the bolt closed, chambering is only necessary when there's no round in the chamber.
2 = The bolt should be opened before reloading if the gun is empty.
3 = The bolt should always be opened before reloading.
4 = This gun doesn't have a bolt, it's a rocket launcher or a laser gun or smth.
]]

--< Gun settings >--
wepStats.fireRate = 700
wepStats.muzzleChance = 5 -- Number from 0-10 that determines how often the muzzle will flash when firing
wepStats.muzzleVelocity = 900 -- this stat uses meters per second
wepStats.aimSpeed = 0.9 -- 0-1 how much should the aim speed be multiplied by
wepStats.gunLength = 5 -- How close you can get to a surface before the viewmodel moves back
wepStats.maxPushback = 0.2 -- How far can the viewmodel move backwards until the gun is blocked

wepStats.fireSwitch = {
	true, -- Semi
	true, -- Auto
	true, -- Burst
	false -- Manual (bolt/pump action)
}
wepStats.fireMode = 2 -- Default mode from the above table
wepStats.burstNumber = 3 -- If this gun can fire in bursts, what should the shot limit be?
wepStats.burstFireRate = nil -- Use this if you want a separate burst fire rate, leave it as nil if you want to use the regular fire rate

wepStats.spread = 0 -- Adds some random variation to the bullet direction
wepStats.shotgun = false
wepStats.shotgunPellets = 10 -- If shotgun is true, how many pellets should be fired at once?

wepStats.aimFovMin = 85
wepStats.aimFovMax = 85
wepStats.aimTime = 1.6
wepStats.aimFovDefault = 85

wepStats.suppressionLevel = 2 -- How much should this gun suppress people?

wepStats.holster = true -- Add gun models to the your character when they aren't equipped
wepStats.holsterPart = "Left Leg" -- The body part to attach the gun model to
wepStats.holsterPosition = CFrame.new(-0.8, 0.45, 0) * CFrame.Angles(math.rad(-90),math.rad(-4),math.rad(6)) 

wepStats.calcEjectionForce = function()
	return Vector3.new(
		math.random(50,100)/ 1.5, -- Side to side
		math.random(100,150) / 45, -- Up
		math.random(40,80) / 45 -- Front
	)
end

wepStats.ADSEnabled = { -- Ignore this setting if not using an ADS Mesh
	true, -- Enabled for primary sight
	false -- Enabled for secondary sight (T)
}

-- Damage
wepStats.damage = {
	Head = 100,
	Torso = 45,
	Other = 35, -- Default damage if body part is not included
}

wepStats.damageFalloff = {
	StartDistance = 210,
	EndDistance = 700,
	MinMultiplier = 0.55,
}

-- depth of field when aiming in
wepStats.DOF = {
	FocusDistance  = 1.2,
	InFocusRadius  = 1,
	NearIntensity  = 1,
	FarIntensity   = 0,
}

-- Tracers
wepStats.tracers = true
wepStats.tracerTiming = 3 -- Every x number of shots will be a tracer
wepStats.tracerColor = Color3.fromRGB(225, 64, 67)

-- Ammo
wepStats.ammoType = "5.45x39mm" -- Gun shell models can be found in ReplicatedStorage > SPH_Assets > Shells
wepStats.shellEject = true -- Should this gun eject shells?
wepStats.magazineCapacity = 30 -- Max ammo that can go in a mag
wepStats.startAmmoPool = 90 -- How much ammo should the gun start with?
wepStats.maxAmmoPool = 120 -- How much ammo can this gun hold?

wepStats.infiniteAmmo = false
wepStats.startChambered = true -- Start with a round in the chamber?

-- Physics
wepStats.bulletDrop = true -- Bullet drop based on workspace.Gravity
wepStats.bulletForce = 100 -- If a bullet hits something unanchored, this force is applied

-- Viewmodel
wepStats.viewmodelOffset = CFrame.new(0,0,0.35) -- Where should the viewmodel be placed in reference to the camera
wepStats.serverOffset = CFrame.new(0,0,0) -- Where should the viewmodel be placed in reference to the player's head

-- Animation -------------------------------------------------
wepStats.animFolder = "AK-12" -- Folder in where the anims are
--------------------------------------------------------------
wepStats.idleAnim = "AK-12_Idle"
wepStats.fireAnim = "AK-12_Fire" -- Animations are located in ReplicatedStorage > SPH_Assets > Animations
wepStats.sprintAnim = "AK-12_Sprint"
wepStats.reloadAnim = "AK-12_Reload"
wepStats.emptyReloadAnim = "AK-12_Reload"
wepStats.boltChamber = "AK-12_Chamber" -- Plays if the bolt is closed
wepStats.boltClose = "AK-12_BoltClose" -- Plays if the bolt is open
wepStats.equipAnim = "AK-12_Equip"
wepStats.InspectAnim = "AK-12_Inspect"
wepStats.unequipAnim = "AK-12_Unequip"
wepStats.emptyInspect = "AK-12_Inspect"
wepStats.switchAnim = "AK-12_Switch1"
wepStats.switchAnim2 = "AK-12_Switch2"
wepStats.holdUpAnim = "AK-12_HoldUp"
wepStats.patrolAnim = "AK-12_Patrol"
wepStats.holdDownAnim = "AK-12_HoldDown"
wepStats.equipFirst = "AK-12_EquipFirst"
wepStats.activateFlashlightLaser = "AK-12_ActivateFlashlightLaser"
wepStats.magCheck = "AK-12_MagCheck"
wepStats.firemodeCheck = "AK-12_FiremodeCheck"

wepStats.equipFirstSpeedModifier = 0.8 -- 1 = Normal speed, higher = faster, lower = slower
wepStats.reloadSpeedModifier = 0.9 -- 1 = Normal speed, higher = faster, lower = slower

wepStats.autoFireSoundDuration = 0.2 -- this makes it so that after 0.1 seconds the autofire sound stops (this is an example)

-- Empty Click Animation
wepStats.emptyClick = true -- or false to disable the empty click animation when your gun is empty.

wepStats.MagDropName = "MagazineDrop" -- The name of the magazine drop mesh/part/etc.
wepStats.MagDropFolderSounds = "MagSounds"

-- Chamber Smoke Effects
wepStats.chamberEffectEnabled = true  -- or false to disable
wepStats.chamberEffectDuration = 0.010  -- duration in seconds

-- Overheating Stat
wepStats.overHeating = {
	Enabled = true,           -- Toggle overheating system
	heatEffectName = "Overheat", -- Name of the heat effect to look for on the gun model inside the Muzzle attachment which is in the grip of the gun.
	MaxHeat = 100,            -- Max heat before overheat triggers
	HeatPerShot = 5,          -- Heat gained per shot
	CoolRate = 50,             -- Heat loss per second when idle
	OverheatCooldown = 1,   -- Delay before cooling starts after overheating
	HeatDissipationDelay = 0.5, -- Small delay before cooling begins after firing
}

wepStats.fireSelector = {
	Enabled = true,
	TweenTime = 0.1, -- seconds; use 0 for an instant snap instead of a tween
	EasingStyle = Enum.EasingStyle.Quad,
	EasingDirection = Enum.EasingDirection.Out,

	Positions = {
		[1] = CFrame.Angles(0, 0, math.rad(0)),   -- Semi
		[2] = CFrame.Angles(0.05, 0, math.rad(0)), -- Auto
		[3] = CFrame.Angles(0.1, 0, math.rad(0)), -- Burst
		[4] = CFrame.Angles(0, 0, math.rad(0)), -- Manual
	},
}

wepStats.rigParts = {"Mag", "Slide", "FireSelector", "ADSRing"} -- These parts will have their welds replaced with Motor6Ds in case they need to be animated
wepStats.fireMoveParts = {"Slide"} -- These parts will move when firing

wepStats.boltDist = CFrame.new(0,0,-.45) -- Distance the bolt will move when firing (Make this number negative for open bolt guns!)
wepStats.emptyLockBolt = false -- Lock the bolt back after firing last round
wepStats.emptyCloseBolt = false -- Close the bolt if the player tries to fire with no bullet in the chamber
wepStats.autoChamber = true -- Chamber the gun after reloading if needed

-- Camera recoil
wepStats.recoil = {
	vertical = 4, -- Vertical recoil
	horizontal = 4, -- Horizontal recoil
	camShake = 3, -- Camera shake
	damping = 2, -- How "springy" should the recoil be
	speed = 10, -- How quickly the recoil force will be recovered from
	aimReduction = 1.5 -- Recoil is divided by this when aiming
}

wepStats.gunRecoil = {
	vertical = 0, -- Vertical recoil
	horizontal = 0, -- Horizontal recoil
	damping = 5, -- How "springy" should the recoil be
	speed = 10, -- How quickly the recoil force will be recovered from
	punchMultiplier = -0.9, -- How much the gun moves back during recoil
}

wepStats.rotationalRecoil = {
	pitch = 5,          -- Upward rotation (degrees)
	yaw = 5,            -- Left/right rotation (degrees)
	roll = 20,           -- Tilt rotation (degrees)
	damping = 4,          -- Spring damping
	speed = 5,            -- Spring speed
	aimReduction = 2    -- Divide rotation by this when aiming
}

wepStats.fireBlur = 1

-- // how much the weapon rotates when walking horizontally
wepStats.maxStrafeRoll = 45

return wepStats