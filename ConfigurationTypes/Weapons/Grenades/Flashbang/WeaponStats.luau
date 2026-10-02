local wepStats = {}

--< Weapon type >--
wepStats.weaponType = "Grenade"
wepStats.projectile = "M84" -- Projectile models can be put in the Projectiles folder, if a model isn't found then default bullets are used.

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

wepStats.rigParts = {"Pull Ring"} -- These parts will have their welds replaced with Motor6Ds in case they need to be animated

--< Grenade throw settings >--
wepStats.grenade = {
	-- Physics of the thrown grenade
	throwSpeed       = 100,
	throwUpwardAngle = 20,
	spinVelocity     = Vector3.new(14, 6, 9),
	bounciness       = 0.35,
	friction         = 1,
	density          = 1,
	fuseTime      = 1.5,
	blastRadius   = 0,
	explosionType = "M84",

	flashRadius           = 200,
	flashMaxDuration       = 12,
	flashMinDuration       = 4,
	flashFacingFalloff     = 0.15, -- floor multiplier when NOT facing it
	flashCoreFraction      = 0.35,
	flashFalloffExponent   = 1.3,

	-- White flash
	flashWhiteFlashEnabled     = true,
	flashWhiteFlashTime        = 0.08,
	flashWhiteFlashMaxDistance = nil,

	-- Blackout
	flashBlackoutEnabled     = true,
	flashBlackoutFadeInTime  = 0.40,
	flashBlackoutMaxDistance = nil,

	-- Black & white / desaturation
	flashDesaturateEnabled       = true,
	flashDesaturateMaxDistance   = nil,
	flashDesaturateCurveExponent = 0.5,
	flashDesaturateMaxContrast   = 0.6,
	flashDesaturateMaxBrightness = 0.35,

	-- Lens glare
	flashGlareEnabled          = true,
	flashGlareBackFacingCutoff = 0,
	flashGlares = {
		{
			id                = "Main",
			image             = "rbxassetid://17640078650",
			enabled           = true,
			maxDistance       = nil,
			minSize           = 0.45,
			maxSize           = 1.10,
			positionInfluence = 1,
			maxOffsetScale    = 0.42,
			fadeInTime        = 0.12,
		},
	},

	-- Screen blur
	flashBlurEnabled           = true,
	flashBlurMaxSize           = 28,
	flashBlurMaxDistance       = nil,
	flashBlurFadeInTime        = 0.15,
	flashBlurFadeOutMultiplier = 1.6, -- multiplies flashDuration; >1 means it clears slower than everything else

	-- Hearing muffle toggle
	flashMuffleEnabled = true,

	-- Inventory behavior
	consumeOnThrow = true,

	releaseKeyframeName = "Release",
	detachables = {
		{
			id = "PinPull",
			keyframeName = "PinPull",
			parts = {"Pull Ring"},
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
		fuseTime         = 1.5,
		blastRadius      = 0,
		explosionType    = "M84",
		releaseKeyframeName = "Release",

		detachables = {
			{
				id = "PinPull",
				keyframeName = "PinPull",
				parts = {"Pull Ring"},
				fadeDelay = 10,
				fadeTime = 1,
			},
		},
	},
}

return wepStats