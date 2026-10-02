local wepStats = {}

--< Weapon type >--
wepStats.weaponType = "Grenade"
wepStats.projectile = "M67" -- Projectile models can be put in the Projectiles folder, if a model isn't found then default bullets are used.

--< Gun settings >--
wepStats.gunLength = 2.5 -- How close you can get to a surface before the viewmodel moves back
wepStats.maxPushback = 1 -- How far can the viewmodel move backwards until the gun is blocked

wepStats.holster = false -- Add gun models to the your character when they aren't equipped
wepStats.holsterPart = "Torso" -- The body part to attach the gun model to
wepStats.holsterPosition = CFrame.new(1.244, -0.912, 0.574) * CFrame.Angles(math.rad(-21),math.rad(4),math.rad(6))

-- Viewmodel
wepStats.viewmodelOffset = CFrame.new(0,0,0) -- Where should the viewmodel be placed in reference to the camera
wepStats.serverOffset = CFrame.new(0,0,0) -- Where should the viewmodel be placed in reference to the player's head

-- // how much the weapon rotates when walking horizontally // StrafeRoll
wepStats.maxStrafeRoll = 2

-- Animation -------------------------------------------------
wepStats.animFolder = "Grenade" -- Folder in where the anims are
--------------------------------------------------------------
wepStats.idleAnim = "M67_Idle"
wepStats.throwAnim = "M67_Throw"
wepStats.lowThrowAnim = "M67_LowThrow"
wepStats.sprintAnim = "M67_Sprint"
wepStats.equipAnim = "M67_Equip"
wepStats.holdUpAnim = "M67_HoldUp"
wepStats.InspectAnim = "M67_Inspect"
wepStats.unequipAnim = "M67_Unequip"

wepStats.rigParts = {"Lever", "Pull Ring", "Safety Pin"} -- These parts will have their welds replaced with Motor6Ds in case they need to be animated

--< Grenade throw settings >--
wepStats.grenade = {
	-- Physics of the thrown grenade
	throwSpeed       = 100,                    -- studs/sec initial forward speed
	throwUpwardAngle = 20,                    -- degrees added above your look direction, for a natural arc
	spinVelocity     = Vector3.new(14, 6, 9),  -- angular velocity applied on release
	bounciness       = 0.5,
	friction         = 1,
	density          = 0.5,

	-- Fuse / explosion
	fuseTime      = 4,       -- seconds between leaving your hand and detonating
	blastRadius   = 35,
	explosionType = "M67",    -- name of the FX folder under the ExplosionFX module

	-- Inventory behavior
	consumeOnThrow = true,     -- destroys the Tool once thrown (single-use grenade)
	
	releaseKeyframeName = "Release",

	-- Keyframe-driven cosmetic part drops. Supports any number of entries. Each needs a unique
	-- "id", a "keyframeName" (add it to the M67_Throw animation), and a "parts" list.
	detachables = {
		{
			id = "PinPull",
			keyframeName = "PinPull",
			parts = {"Pull Ring", "Safety Pin"},
			fadeDelay = 10,
			fadeTime = 1,
		},
		{
			id = "HandleDrop",
			keyframeName = "HandleDrop",
			parts = {"Lever"},
			fadeDelay = 10,
			fadeTime = 1,
		},
	},
	
	hideables = {
		{
			id = "Grenade",
			keyframeName = "Release", -- add this keyframe to M67_LowThrow
			parts = {"Grenade"},
		},
	},

	-- Low throw (underhand) overrides. Any field left out here falls back to the
	-- values above. releaseKeyframeName/detachables reference keyframes/parts inside
	-- the wepStats.lowThrowAnim animation, so they can differ from the normal throw.
	lowThrow = {
		throwSpeed       = 60,
		throwUpwardAngle = 0,
		spinVelocity     = Vector3.new(6, 3, 4),
		fuseTime         = 4,
		blastRadius      = 35,
		explosionType    = "M67",
		releaseKeyframeName = "Release",
		
		detachables = {
			{
				id = "PinPull",
				keyframeName = "PinPull",
				parts = {"Pull Ring", "Safety Pin"},
				fadeDelay = 10,
				fadeTime = 1,
			},
			{
				id = "HandleDrop",
				keyframeName = "HandleDrop",
				parts = {"Lever"},
				fadeDelay = 10,
				fadeTime = 1,
			},
		},
	},
}
return wepStats