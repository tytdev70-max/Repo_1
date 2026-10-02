local wepStats = {}

--< Weapon type >--
wepStats.weaponType = "Grenade"
wepStats.projectile = "M18" -- Projectile models can be put in the Projectiles folder, if a model isn't found then default bullets are used.

--< Gun settings >--
wepStats.gunLength = 2.5 -- How close you can get to a surface before the viewmodel moves back
wepStats.maxPushback = 1 -- How far can the viewmodel move backwards until the gun is blocked

wepStats.holster = false -- Add gun models to the your character when they aren't equipped
wepStats.holsterPart = "Torso" -- The body part to attach the gun model to
wepStats.holsterPosition = CFrame.new(1.244, -0.912, 0.574) * CFrame.Angles(math.rad(-21),math.rad(4),math.rad(6))

-- Viewmodel
wepStats.viewmodelOffset = CFrame.new(0,0,0) -- Where should the viewmodel be placed in reference to the camera
wepStats.serverOffset = CFrame.new(0,0,0) -- Where should the viewmodel be placed in reference to the player's head

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
	throwSpeed       = 100,
	throwUpwardAngle = 20,
	spinVelocity     = Vector3.new(14, 6, 9),
	bounciness       = 0.4,
	friction         = 1,
	density          = 0.5,

	-- Fuse / explosion
	fuseTime      = 1,
	blastRadius   = 0,
	explosionType = "M18",

	disableExplosionSound = true,
	disableCameraShake    = true,

	smoke = {
		-- Voxel simulation
		voxelSize = 2,
		radius = 16,
		growTime = 0.6,
		dissipateStartTime = 25,
		dissipateTime = 5,
		density = 1,
		color = Color3.fromRGB(235, 235, 235),
		canisterFadeTime = 2,
		regrowTime = 0.7,
		growSmoothTime = 0.9,
		maxVoxels = 2000,
		expansionCellsPerSecond = 500,
		maxPuffs = 300,
		puffFadeGrace = 1.5,
		bulletDisturbRadius = 1.5,
		bulletDisturbStrength = 0.75,

		shapePoints = nil,
		shapeVerticalRadius = 10, 
		shapeNoiseScale = 0.18,
		shapeNoiseStrength = 0.45,
		shapeMinRadiusFraction = 0.55,
		shapeSeed = nil,

		explosionDisperseMultiplier = 2.5,
		explosionDisturbRadiusMultiplier = 1,
		explosionFalloffExponent = 1.5,

		insideVisionBlockEnabled = true,
		insideVisionBlockColor = Color3.fromRGB(235, 235, 235),
		insideVisionBlockMaxOpacity = 0.97,
		insideVisionBlockFadeInTime = 0.35,
		insideVisionBlockFadeOutTime = 0.6,

		-- Audio
		expansionSoundId = "rbxassetid://86419611335608",
		expansionSoundVolume = 1,
		hissSoundId = 0,
		hissVolume = 1,
		hissFadeTime = 0.6,
	},

	-- Inventory behavior
	consumeOnThrow = true,
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
	hideables = {
		{
			id = "Grenade",
			keyframeName = "Release",
			parts = {"Grenade"},
		},
	},
	lowThrow = {
		throwSpeed       = 60,
		throwUpwardAngle = 0,
		spinVelocity     = Vector3.new(6, 3, 4),
		fuseTime         = 4,
		blastRadius      = 0,
		explosionType    = "M18",
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