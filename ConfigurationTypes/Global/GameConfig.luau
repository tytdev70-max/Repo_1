local config = {}

--// General

config.thirdPersonFiring = true -- Allow the player to fire from third person (unfinished)
config.arcadeBullets = true -- Gives bullets a faint streak similar to FE Gun Kit, looks pretty bad with tracers enabled

config.leaderboard = true -- Creates a simple kill death leaderboard
config.rblxDamageTags = true -- Include Roblox built in damage tags when counting kills

config.systemChat = true -- Sends messages in chat when players join, leave, and die
config.deathScreen = false -- Displays a screen after death with a respawn counter

config.fallDamage = true -- Should there be fall damage?
config.fallDamageDist = 19 -- Minimum distance to take damage
config.fallDamageMultiplier = 0.7

config.teamKill = false
config.teamSuppression = false -- Should players be suppressed (tunnel vision / crack sounds) by teammate gunfire?

--// Camera & Head

config.firstPersonBody = true -- Should the player's body be visible in first person?
config.headRotationSpeed = 15
config.disableHeadRotation = false -- Disables head rotation entirely for both first and third person (viewmodel will still move up and down)
config.headRotationEventRate = 0.1 -- How often should head rotation be replicated
config.replicatedHeadRotationSpeed = 0.6 -- How quickly should other player's heads be rotated

config.cameraAnimation = true -- Should the camera be animated?

--// Jump & Landing Camera

config.jumpCameraOffset = true -- Should the camera dip/tilt when jumping and landing?
config.jumpDipAngle = -1.5 -- How many degrees the camera tilts down when starting the jump
config.jumpDipTime = 0.075 -- How long it takes the camera to tilt down when starting the jump
config.jumpDipHoldTime = 0.05 -- How long the tilt persists before rising
config.jumpRiseAngle = 8 -- How many degrees the camera tilts upward when mid-air
config.jumpRiseTime = 1.5 -- How long it takes the camera to tilt upward when mid-air

config.landBaseImpulse = -3 -- How many degrees the camera tilts down when landing
config.landImpulseTime = 0.1 -- How long it takes the camera to tilt down when landing
config.landRecoverTime = 0.75 -- How long it takes to return the camera to default after a jump/land dip
config.landMinImpulseFallDistance = 1 -- Minimum fall distance required to impulse
config.landScaleImpulsed = true -- Whether BaseImpulse scales up based on fall distance
config.landMinScaleDistance = 2 -- Minimum distance required to start multiplying BaseImpulse
config.landMaxScaleDistance = 50 -- Maximum distance to stop multiplying BaseImpulse
config.landMaxMultiplier = 5 -- Multiplier of BaseImpulse when fall distance is at its max

--// Explosions

config.explosionRaycast = true -- Check with a raycast if players should be damaged
config.echoDistanceTrigger = 250 -- Distance in studs the echo sound starts to play
config.echoGrenadeTrigger = 250 -- Distance in studs where grenade echo starts

config.explosionDestructibleDamageMultiplier = 1 -- Scales destructible HP damage
config.explosionFalloffExponent = 1 -- 1 = old linear falloff, >1 = sharper edge falloff
config.explosionRaycastDestructibles = true -- LOS gate for destructibles (nil also = true)

config.explosionDebug = false -- Master debug toggle
config.explosionDebugDuration = 6 -- Seconds debug visuals persist

config.smokeVoxelDebug = false -- Draws colored voxel cubes for every active smoke cloud (green = full density, red = empty/regrowing)
config.smokeVoxelDebugUpdateRate = 0.2 -- Seconds between debug redraws, keeps the debug view itself cheap

--// First Person Lock

config.lockFirstPerson = false -- Can the player exit first person with a gun equipped?
-- DO NOT enable this if you want players permanently locked to first person.
-- For that, go to StarterPlayer and change the default CameraMode instead.

--// Scale

config.meterMultiplier = 3.5 -- How many studs count as a meter, used for muzzle velocity and speed of sound

--// Reticle Motion Blur

config.reticleMotionBlur = true -- Should aim reticles smear/blur when the weapon or camera moves quickly?
config.reticleBlurTrailCount = 5 -- Number of ghost images used to build the blur trail
config.reticleBlurSensitivity = 0.7 -- Converts reticle screen-space speed into blur intensity (higher = blurs sooner)
config.reticleBlurMaxOffset = 0.016 -- Max trail spread, in SurfaceGui scale units
config.reticleBlurMaxAlpha = 1 -- Max opacity of the blur trail at full intensity (0-1)

--// Gun Dropping

config.gunDropping = true
config.dropOnDeath = false
config.dropOnLeave = false

-- Which weapon customization menu opens at the customize table:
--   "Gunsmith"        HUD.GunGUIs.Gunsmith
--   "CustomizeGunGUI" HUD.GunGUIs.CustomizeGunGUI (the previous menu)
config.customizeMenu = "Gunsmith"
config.dropDespawnTime = 30 -- How long should guns stay on the ground?
config.maxDroppedGuns = 15 -- How many can be on the ground at once?
config.pickupDistance = 7
config.dropGunAnchorTime = 30 -- Anchor dropped gun models after this amount of time

config.pickupGuns = true -- or false, players can either pick up guns or not

config.canReloadWhileAiming = false -- Can the player reload while aiming?

--// Blood System

config.bloodEnabled = true

config.woundDecalsEnabled = true

config.bloodSplatEnabled = true
config.bloodSplatCooldown = 0.01 -- Minimum seconds between splat raycasts (perf safeguard)
config.bloodSplatSprayDistance = 12 -- Studs the splat raycast travels looking for a surface
config.bloodSplatSizeMin = 20 -- Min pixel size of a placed blood decal
config.bloodSplatSizeMax = 30 -- Max pixel size of a placed blood decal
config.bloodSplatCanvasSize = 10 -- DecalSurface "CanSize" - canvas pixel density multiplier

config.bloodDripEnabled = true
config.bloodDripMin = 1 -- Minimum number of drips spawned per wound
config.bloodDripMax = 1 -- Maximum number of drips spawned per wound
config.bloodDripLength = 0.3
config.bloodDripWidth = 0.05
config.bloodDripSpeed = 0.5
config.bloodDripDelay = 0.15 -- Delay between each successive drip in the same wound
config.bloodDripMaxDistance = 2 -- Max studs a single drip can travel down the surface
config.bloodDripGravity = true
config.bloodDripTexture = "rbxassetid://128422779857709"

config.bloodSoakEnabled = true
config.bloodSoakStartSize = 0.15
config.bloodSoakEndSize = 0.8
config.bloodSoakSpeed = 3.5
config.bloodSoakDelay = 0.3
config.bloodSoakTexture = "rbxassetid://6430908053"
config.bloodSoakColor = Color3.fromRGB(113, 0, 0)

config.bloodDecalColor = Color3.fromRGB(180, 0, 0) -- Shared tint for blood decals

--// Bullet Holes & Decals

config.maxBulletHolesPerSurface = 25 -- Oldest decal is trimmed once a single surface exceeds this
config.bulletHoleSize = 0.25 -- Studs, size of a standard (material-texture) bullet hole
config.bulletHoleFadeDelay = 10 -- Seconds a SurfaceGui-based bullet hole waits before fading
config.bulletHoleFadeTime = 1 -- Fade-out duration for SurfaceGui-based bullet holes
config.partBulletHoleFadeDelay = 3 -- Seconds a part-based (per-material) bullet hole waits before fading
config.partBulletHoleFadeTime = 0.5 -- Fade-out duration for part-based bullet holes
config.decalSurfaceRemoveDelay = 20 -- DecalSurface.lua: seconds before a placed decal is removed
config.decalSurfaceFadeTime = 1 -- DecalSurface.lua: fade-out duration before removal

--// Movement

config.walkSpeed = 9
config.sprintSpeed = 21
config.crouchSpeed = 3
config.proneSpeed = 2
config.strafeSpeedMultiplier = 1 -- Speed is multiplied by this while strafing/moving backwards, set to 1 for no reduction
config.canSprintWhileStrafing = true -- Can the player sprint without moving forward?
-- If other scripts fight with SPH's movement, override them with the attributes under CharacterMovement.

--// Movement Lean

config.movementLeaning = true -- Will players lean into the direction they're moving?
config.replicateMovementLeaning = true -- Also compute lean for other visible players (done client-side from replicated velocity, no extra networking)

config.movementLeanRangeOfMotionDeg = 45 -- Max hip/torso roll angle (degrees) at full sideways speed
config.movementLeanSpeed = 0.005 -- Base for the exponential C0 lerp each frame (lower = snappier)

config.movementLeanPitchEnabled = true -- Lean torso backward/forward based on forward/backward speed
config.movementLeanPitchMaxDeg = 3 -- Max pitch angle (degrees) at full forward/backward speed
config.movementLeanPitchWeightRoot = 1.0 -- Fraction of pitch applied at the RootJoint
config.movementLeanPitchWeightNeck = 0.5 -- Fraction of pitch applied at the Neck (counter-lean)
config.movementLeanPitchTranslateOffset = 0.05 -- Studs of forward/back hip translate at full pitch
config.movementLeanPitchDirection = -1 -- Flip to 1 if pitch leans the wrong way on your rig

config.movementLeanInvertRollWhenMovingForward = true -- Mirror the roll lean when moving forward vs backward

config.movementLeanVelocityClamp = 1.0 -- Clamps normalized lateral/forward speed to +/- this before easing
config.movementLeanSmoothingSpeed = 10 -- How quickly the lean direction smooths toward its target (higher = snappier)
config.movementLeanMaxHipTranslate = 0.5 -- Max studs a hip can translate sideways/forward-back


--// R6 Foot IK (Foot Planting)

config.footIKEnabled = true -- Master toggle for the R6 foot-plant/IK system (CharacterMovement); also gates all foot-IK networking
config.footIKOffsetY = 1.0 -- Studs above the foot anchor the ground raycast starts from
config.footIKRayLength = 2.5 -- Length of the downward raycast used to find the ground
config.footIKBaseOffset = 0.5 -- Base vertical offset subtracted from the raycast hit distance
config.footIKMaxDrop = 0 -- Max studs a foot can be lowered below its resting position
config.footIKMaxHeight = 1 -- Max studs a foot can be raised above its resting position
config.footIKAdjustmentSpeed = 10 -- Exponential-decay rate (per second) feet interpolate toward their target offset
config.footIKForwardShift = -0.2 -- Forward/backward local Z offset applied to both foot anchors
config.footIKLegForwardMultiplier = 0.8 -- How much a foot's height offset shifts the leg forward/back
config.footIKLegPitchMultiplier = -0.4 -- How much a foot's height offset pitches the leg
config.footIKRightFootLocalCFrame = CFrame.new(0.75, -2, config.footIKForwardShift) -- Right foot anchor, relative to Torso
config.footIKLeftFootLocalCFrame = CFrame.new(-0.75, -2, config.footIKForwardShift) -- Left foot anchor, relative to Torso

--// R6 Foot IK: Replication

config.footIKReplicationRate = 0.15 -- Minimum seconds between replicated foot-IK updates per player (ReplicationThrottle minInterval)
config.footIKReplicationThreshold = 0.03 -- Minimum combined offset+normal delta required before an update is sent

--// Stances

config.stanceChangeTime = 1 -- How long it takes to transition between stances

config.canLean = true -- Can the player lean around corners
config.canCrouch = true -- Can the player crouch
config.canProne = true -- Can the player go prone (doesn't matter if canCrouch is false)
config.proneAngle = true -- Adjust prone angle based on ground
config.proneEnabled = true -- Whether prone works at all

--// Jumping

config.jumpCooldown = 1 -- Time between jumps

--// Animation Priority

config.useHigherAnimPriority = true -- Uses higher animation priorities for Crouch/Prone to avoid conflicting with the default tool idle animation
config.firstPersonAimAnim = true -- Should aim animations play in first person?
config.proceduralAimAnim = true -- Used only in first person

config.walkCameraAnimation = true -- Makes the camera move and animate while walking around

--// Keybinds

config.keySprint = {Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3}
config.keyReload = {Enum.KeyCode.R, Enum.KeyCode.ButtonX}
config.keyChamber = {Enum.KeyCode.F, Enum.KeyCode.ButtonR1}
config.sightSwitch = {Enum.KeyCode.T, Enum.KeyCode.DPadRight}
config.freeLook = {Enum.KeyCode.LeftAlt}
config.lowerStance = {Enum.KeyCode.C, Enum.KeyCode.ButtonR3}
config.raiseStance = {Enum.KeyCode.X, Enum.KeyCode.ButtonL1}
config.holdUp = {Enum.KeyCode.Z}
config.holdPatrol = {Enum.KeyCode.J}
config.holdDown = {Enum.KeyCode.B}
config.switchFireMode = {Enum.KeyCode.V, Enum.KeyCode.DPadLeft}
config.leanLeft = {Enum.KeyCode.Q}
config.leanRight = {Enum.KeyCode.E}
config.dropKey = {Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB}
config.pickupKey = {Enum.KeyCode.P, Enum.KeyCode.ButtonY}
config.toggleLaser = {Enum.KeyCode.H, Enum.KeyCode.DPadUp}
config.toggleFlashlight = {Enum.KeyCode.Y, Enum.KeyCode.DPadDown}
config.holdForScrollZoom = {Enum.KeyCode.LeftControl}
config.keyInspect = {Enum.KeyCode.G}
config.fireGun = {Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2}
config.aimGun = {Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2}
config.toggleUBGL = {Enum.KeyCode.N, Enum.KeyCode.ButtonSelect}

--// Input General

config.defaultAimSensitivity = 0.6 -- Scrolling while aiming increases/decreases aim sensitivity
config.gunInputPriority = 100 -- Priority level for gun inputs
config.movementInputPriority = 100 -- Priority level for movement inputs
config.mobileButtons = true -- Adds on-screen buttons on touchscreen devices
config.toggleAiming = false -- Switches all players to toggle-aim instead of hold-to-aim
config.scrollZoomInStep = 3 -- Mouse-wheel FOV step when scrolling in on an LPVO
config.scrollZoomOutStep = 4 -- Mouse-wheel FOV step when scrolling out on an LPVO

--// Performance

config.animDistance = 10000 -- Max distance to see a player's animations
config.fireEffectDistance = 10000 -- Max distance for firing effects to be replicated
config.maxBulletDistance = 4000 -- Bullets flying further than this are deleted
config.maxHitDistance = 10000 -- Max distance to see bullet hit effects

--// Ragdolls & Bodies

config.ragdolls = true -- Should players ragdoll on death? Fully server-authoritative; the corpse is replicated to clients
config.ragdollLifetime = 12 -- How long (in seconds) a ragdoll corpse persists before being removed. 0 disables cleanup
config.ragdollAllowManualToggle = true -- Allow server-authorized manual ragdolling of living players via RagdollEvent/UnragdollEvent (non-lethal knockdowns). Enforced server-side
config.ragdollCameraFollowOwnDeath = true -- Should the local player's camera follow their own server-replicated ragdoll corpse after dying?
config.ragdollCameraTorsoWaitTimeout = 5 -- Seconds CameraManager waits for the corpse's Torso part to appear before giving up

--// Shell Ejection

config.shellEjection = true -- Game-wide override for shell ejection
config.shellDistance = 50 -- Shells won't be ejected beyond this distance
config.shellMaxCount = 30 -- Maximum that can be on the ground at once
config.shellDespawn = 5 -- Shells are auto deleted after this amount of time
config.shellFadeDuration = 0.6

--// Camera Zoom & Lean
config.defaultFOV = 85
config.zoomSensitivityReduction = 0.05
config.scrollZoomInStep = 3
config.scrollZoomOutStep = 4
config.gamepadZoomDeadzone = 0.15
config.gamepadZoomStep = 2.5
config.touchPinchZoomScale = 0.05
config.cameraMaxZoomDistance = 10 -- respawn/death camera max zoom
config.cameraMinZoomDistance = 0.5 -- respawn/death camera min zoom
config.leanAngleDegrees = 17
config.leanLerpRate = 6
config.viewmodelStorageDistance = 1000000 -- how far offscreen stored viewmodels are parked

--// First Person Extras

config.firstPersonHolsters = false -- Should holsters show in first person? (very laggy with too many holsters at once)
config.blurEffects = false -- Experimental depth of field stuff

--// Ammo Boxes

config.despawnEmptyAmmoBoxes = true -- Should empty ammo boxes be destroyed after some time?
config.ammoBoxDespawnTime = 10
config.maxBullets = 300 -- Maximum number of bullets cached (cache size temporarily grows if exceeded)

--// Glass

config.glassShatter = true -- Should glass shatter when shot? (must be named "Glass" or tagged "BreakableGlass")
config.glassShardDespawnTime = 3 -- How long should shards stay on the ground?
config.glassRespawnTime = 15 -- How long until glass is replaced?

--// Aim Camera

config.allowAimTilt = true -- Should the camera tilt when you aim?

--// Physics

config.bulletAcceleration = Vector3.new(0, -workspace.Gravity, 0) -- Used for bullet drop force
config.useBulletForce = true -- Should bullet impacts push things around?
config.bulletPen = true -- Can bullets pierce objects?

--// Viewmodel - Breathing

config.breathingSpeed = 1.4 -- Angular speed of the breathing cycle (rad/sec), ~1.2-1.6 is a realistic resting pace, higher = faster/more agitated
config.breathingPosAmplitude = Vector2.new(0.008, 0.014) -- Independent X (side-to-side) / Y (vertical, chest-rise) translation amplitude in studs, keep small for subtlety
config.breathingRotAmplitude = Vector2.new(0.25, 0.4) -- Independent pitch / roll rotation amplitude in degrees
config.breathingIntensity = 1 -- Global multiplier over both amplitudes above, scale this instead of editing the vectors for quick tuning
config.breathingADSIntensity = 0.3 -- Multiplier on top of breathingIntensity while aiming (0.2-0.4 recommended, never 0 or ADS looks robotic)
config.breathingTransitionSpeed = 0.1 -- How quickly breathing blends between hip-fire and ADS intensity

--// Viewmodel - Bob & Sway

config.bobSpeed = 10 -- How quickly the viewmodel moves back and forth, scaled by walk speed
config.bobDampening = 10 -- Higher number = less bobbing
config.aimBobDampening = 1.5 -- Higher number = less bobbing while aiming
config.cameraMovement = true -- Should the camera bob around?
config.cameraBobDampening = 1 -- Higher number = less bobbing
config.cameraLimitInSeats = true -- Limit camera angle to 180 degrees when sitting in a seat (disabling may cause issues with other camera settings)
config.canEquipInVehicleSeat = false -- Can the player equip guns while in a vehicle? (true may cause input overlaps)

--// Viewmodel - Hipfire

config.hipfireMove = true -- Allows the gun to move off center while hip firing
config.hipfireMoveX = 3 -- Max angle the gun can move horizontally
config.hipfireMoveY = 3 -- Max angle the gun can move vertically
config.hipfireMoveSpeed = 0.1
config.offCenterAiming = false -- Allow the player to move off center while aiming

--// Viewmodel - Wall Avoidance

config.pushBackViewmodel = true -- Should the gun move back when getting close to a wall?
config.raiseGunAtWall = true -- Should the gun raise when too close to a wall?
config.fireWithFreelook = false -- Can the player fire while freelook is active?
config.maxStrafeRoll = 20 -- How much the viewmodel leans left/right when strafing
config.showAccessoriesFP = true -- Should accessories show in first person?

--// Effects

config.lowHealthEffects = true -- Low health visual effects, reduced movement speed, and shake while aiming
config.suppressionEffects = true -- Tunnel vision and crack sounds
config.footstepSounds = true -- Replaces the default walk sound with material based sounds
config.tracerStartDistance = 50 -- Tracers/arcade bullets don't appear until this far away from you
config.fireSoundVariation = 500 -- Lower = more pitch/playback speed variation on fire and echo sounds

--// Destruction

config.destructibleDespawnTime = 30
config.disablePlayerDebrisCollision = true -- Stops players colliding with debris from destroyed objects

--// Day/Night Cycle

config.dayNightCycle = false
config.dayNightAutoClock = true -- Should Lighting.ClockTime advance on its own?
config.dayLengthSeconds = 1000 -- Real seconds for one full in-game day (only used if dayNightAutoClock is true)
config.dayNightTransitionHours = 1.5 -- In-game hours each morning/day/night blend takes
config.dayNightUpdateInterval = 0.05 -- Seconds between lighting/sound recalculations
config.ambienceSoundSmoothing = 0.18 -- Lerp factor (0-1) for ambience volume changes, higher = snappier
config.morningStartHour = 6
config.dayStartHour = 12
config.nightStartHour = 18

config.dayNightPresets = {
	Morning = {
		Brightness = 1.6,
		OutdoorAmbient = Color3.fromRGB(200, 210, 255),
		Ambient = Color3.fromRGB(140, 130, 120),
		FogEnd = 1000,
		FogColor = Color3.fromRGB(190, 200, 230),
		SunIntensity = 1.2,
		SunColor = Color3.fromRGB(255, 200, 160),
	},
	Day = {
		Brightness = 2.6,
		OutdoorAmbient = Color3.fromRGB(255, 255, 255),
		Ambient = Color3.fromRGB(170, 170, 170),
		FogEnd = 2000,
		FogColor = Color3.fromRGB(255, 255, 255),
		SunIntensity = 2.5,
		SunColor = Color3.fromRGB(255, 245, 220),
	},
	Night = {
		Brightness = 0.28,
		OutdoorAmbient = Color3.fromRGB(20, 24, 60),
		Ambient = Color3.fromRGB(20, 22, 36),
		FogEnd = 400,
		FogColor = Color3.fromRGB(8, 12, 35),
		SunIntensity = 0.2,
		SunColor = Color3.fromRGB(120, 140, 200),
	},
}

--// Loading Screen

config.loadingScreenEnabled = false -- Master toggle for the entire custom loading screen
config.loadingScreenBlockCoreGuiDuringIntro = true -- Hides Backpack/CoreGui while the intro sequence plays, then restores it once the loading screen finishes. Has no effect if loadingScreenEnabled is false.

config.loadingScreenMusicEnabled = true -- Should the loading screen background music play?
config.loadingScreenSfxEnabled = true -- Should the "Boom" transition sound effect play between frames?

config.loadingScreenFadeTime = 1 -- Duration of the fade transitions used between/within loading screen frames.

--// Loading Screen: Disclaimers Frame
config.loadingScreenShowDisclaimers = true -- Show the initial disclaimers/warning frame
config.loadingScreenDisclaimersTime = 5 -- How long the disclaimers frame stays up before advancing.

--// Loading Screen: Logotypes Frame
config.loadingScreenShowLogotypes = true -- Show the studio/publisher logotypes frame
config.loadingScreenLogotypesTime = 3 -- How long the logotypes frame stays up before advancing.

--// Loading Screen: Main Logo Frame
config.loadingScreenShowMainLogo = true -- Show the main game logo frame
config.loadingScreenMainLogoTime = 3 -- How long the main logo frame stays up before advancing.

--// Loading Screen: Loading/Composition Frame
config.loadingScreenShowComposition = true -- Cycle through the CompositionData background art while assets load. If false, the frame just stays on a blank/dark background until loading finishes.
config.loadingScreenCompositionFrameTime = 4 -- How long each composition frame is displayed before a new random one is chosen.
config.loadingScreenMinimumTime = 0 -- The minimum amount of time the loading frame must remain visible, even if critical assets finish loading sooner.

--// Lens Flare

config.lensFlareEnabled = true -- Master toggle for the lens flare system

-- General
config.lensFlareRaycasts = 5 -- Number of raycasts used to check if the flare is obstructed
config.lensFlareRaycastRadius = 7 -- Radius around the flare source used for obstruction checks
config.lensFlareTransparencyThreshold = 0.666 -- Transparency required for a part to stop blocking the flare

-- Sun Flare
config.sunFlareEnabled = true -- Enable/disable the sun flare specifically
config.sunFlareAngleThreshold = 30 -- Angle above the horizon where the sun flare begins fading
config.sunFlareBrightnessThreshold = 2.5 -- Lighting.Brightness required for maximum flare strength
config.sunFlareExposureAdjustment = -2.25 -- Exposure adjustment while looking toward the sun
config.sunFlareExposureTime = 1 -- Time used to apply/recover the exposure adjustment

--// Version

config.version = "v0.1.26" -- Used only for debugging and analytics

return config