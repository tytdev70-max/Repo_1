-- ModuleInits/SystemModuleInits
-- Calls .Init({...}) on every weapon/system sub-module.
-- This is the largest init file — it mirrors the original init sequence exactly.

local AssetRefs       = require(script.Parent.Parent.Boot.AssetRefs)
local CharacterRefs   = require(script.Parent.Parent.Boot.CharacterRefs)
local CameraSetup     = require(script.Parent.Parent.Boot.CameraSetup)
local StateInit       = require(script.Parent.Parent.Boot.StateInit)
local SpringsAndThrottles = require(script.Parent.Parent.Boot.SpringsAndThrottles)
local ViewmodelSetup  = require(script.Parent.Parent.Boot.ViewmodelSetup)
local RaycastSetup    = require(script.Parent.Parent.Boot.RaycastSetup)
local EffectsSetup    = require(script.Parent.Parent.Boot.EffectsSetup)
local ServiceRefs     = require(script.Parent.Parent.Boot.ServiceRefs)

local modules    = AssetRefs.modules
local assets     = AssetRefs.assets
local config     = StateInit.config
local vars       = StateInit.vars
local character  = CharacterRefs.character
local humanoid   = CharacterRefs.humanoid
local humanoidRootPart = CharacterRefs.humanoidRootPart
local camera     = CameraSetup.camera
local aimDoF     = CameraSetup.aimDoF
local inspectDoF = CameraSetup.inspectDoF
local animBase   = ViewmodelSetup.animBase
local lArm       = ViewmodelSetup.lArm
local rArm       = ViewmodelSetup.rArm
local vmShirt    = ViewmodelSetup.vmShirt
local vmAnimator = ViewmodelSetup.vmAnimator
local players    = ServiceRefs.players
local player     = players.LocalPlayer
local playerGui  = AssetRefs.playerGui
local replicatedStorage = ServiceRefs.replicatedStorage
local userInputService  = ServiceRefs.userInputService
local ContentProvider   = ServiceRefs.ContentProvider
local proxPromptService = ServiceRefs.proxPromptService
local tweenService      = ServiceRefs.tweenService

local swaySpring        = SpringsAndThrottles.swaySpring
local moveSpring        = SpringsAndThrottles.moveSpring
local recoilSpring      = SpringsAndThrottles.recoilSpring
local gunRecoilSpring   = SpringsAndThrottles.gunRecoilSpring
local jumpSpring        = SpringsAndThrottles.jumpSpring
local gunRotSpring      = SpringsAndThrottles.gunRotSpring
local equipConnections  = SpringsAndThrottles.equipConnections
local overheatThrottle  = SpringsAndThrottles.overheatThrottle
local lpvoThrottle      = SpringsAndThrottles.lpvoThrottle
local lpvoArmThrottle   = SpringsAndThrottles.lpvoArmThrottle
local ReplicationThrottle = SpringsAndThrottles.ReplicationThrottle

local defaultFOV          = StateInit.defaultFOV
local storageCFrame       = StateInit.storageCFrame
local fireModes           = StateInit.fireModes
local aimFOVTargetRef     = StateInit.aimFOVTargetRef
local perGunSightIndex    = StateInit.perGunSightIndex
local vmArmAccessories    = StateInit.vmArmAccessories
local warnPrefix          = StateInit.warnPrefix
local ZOOM_SENSITIVITY_REDUCTION = StateInit.ZOOM_SENSITIVITY_REDUCTION
local leanAngleDegrees    = StateInit.leanAngleDegrees
local leanLerpRate        = StateInit.leanLerpRate

local rayParams      = RaycastSetup.rayParams
local depthOfField   = EffectsSetup.depthOfField
local shootBlur      = EffectsSetup.shootBlur

local proceduralWalkCycle = ViewmodelSetup.proceduralWalkCycle
local bulletHandler       = ViewmodelSetup.bulletHandler

-- Sub-modules
local weldMod             = require(modules.Weapons.Core.WeldMod)
local Network             = require(modules.Core.Networking.SPH_Network)
local viewMod             = require(modules.Weapons.Equip.ViewMod)
local springMod           = require(modules.Core.Math.SpringModule)
local shellEjection       = require(modules.Weapons.Fire.ShellEjection)
local attachmentSystem   = require(modules.ThirdParty.AttachmentSystem)
local mobileSupport       = require(modules.Weapons.UI.MobileSupportMod)
local assetPreloader      = require(modules.Systems.AssetPreloader)
local gunModelPreloader   = require(modules.Weapons.Equip.GunModelPreloader)
local fireModeCheckDisplay= require(modules.Weapons.UI.FireModeCheckDisplay)
local magCheckDisplay     = require(modules.Weapons.UI.MagCheckDisplay)
local customizeGunGUI     = require(modules.Weapons.UI.CustomizeGunGUI)
local grenadeClient       = require(modules.Misc.Grenades.GrenadeClient)
local ubglSystem          = require(modules.Weapons.Attachments.UBGLHandlerMod)
local laserSightMod       = require(modules.Weapons.Attachments.LaserSightMod)
local aimingSystemMod     = require(modules.Weapons.Aiming.AimingSystemMod)
local weaponPushbackMod   = require(modules.Weapons.Fire.WeaponPushbackMod)
local headPoseReplicationMod = require(modules.Weapons.Aiming.HeadPoseReplicationMod)
local armPositionMod      = require(modules.Weapons.Aiming.ArmPositionMod)
local weaponFireMod       = require(modules.Weapons.Fire.WeaponFireMod)
local weaponEquipMod      = require(modules.Weapons.Equip.WeaponEquipMod)
local cameraViewmodelMod  = require(modules.Weapons.Aiming.CameraViewmodelMod)
local fireSelectorMod     = require(modules.Weapons.Attachments.FireSelectorMod)
local glareMod            = require(modules.Weapons.Attachments.GlareMod)
local flashbangEffectMod  = require(modules.Effects.Explosions.FlashbangEffectMod)
local hitFX               = require(modules.Effects.Blood.HitFX)
local magEjection         = require(modules.Weapons.Fire.MagEjection)
local PacketRefs          = require(modules.Core.Networking.SPH_ClientPacketRefs) :: any
local clientBridge        = require(modules.Core.Networking.ClientBridge)         :: any
local SPH_Events          = require(modules.Core.Networking.SPH_Events)
local WeaponBindings      = require(modules.Weapons.Client.Input.WeaponBindings)  :: any

local SystemModuleInits = {}

-- Export all sub-modules so other init files and handlers can reference them
SystemModuleInits.weldMod              = weldMod
SystemModuleInits.Network              = Network
SystemModuleInits.attachmentSystem    = attachmentSystem
SystemModuleInits.mobileSupport        = mobileSupport
SystemModuleInits.assetPreloader       = assetPreloader
SystemModuleInits.grenadeClient        = grenadeClient
SystemModuleInits.ubglSystem           = ubglSystem
SystemModuleInits.laserSightMod        = laserSightMod
SystemModuleInits.aimingSystemMod      = aimingSystemMod
SystemModuleInits.weaponPushbackMod    = weaponPushbackMod
SystemModuleInits.headPoseReplicationMod = headPoseReplicationMod
SystemModuleInits.armPositionMod       = armPositionMod
SystemModuleInits.weaponFireMod        = weaponFireMod
SystemModuleInits.weaponEquipMod       = weaponEquipMod
SystemModuleInits.cameraViewmodelMod   = cameraViewmodelMod
SystemModuleInits.fireSelectorMod      = fireSelectorMod
SystemModuleInits.glareMod             = glareMod
SystemModuleInits.flashbangEffectMod   = flashbangEffectMod
SystemModuleInits.customizeGunGUI      = customizeGunGUI
SystemModuleInits.shellEjection        = shellEjection
SystemModuleInits.fireModeCheckDisplay = fireModeCheckDisplay
SystemModuleInits.magCheckDisplay      = magCheckDisplay
SystemModuleInits.clientBridge         = clientBridge
SystemModuleInits.PacketRefs           = PacketRefs
SystemModuleInits.WeaponBindings       = WeaponBindings
SystemModuleInits.SPH_Events           = SPH_Events
SystemModuleInits.bulletHandler        = bulletHandler

function SystemModuleInits.init()
	-- mobileSupport
	mobileSupport.Init({
		attachmentSystem = attachmentSystem,
		playerGui         = playerGui,
		HandleInput       = WeaponBindings.HandleInput,
		character         = character,
		humanoid          = humanoid,
		player            = player,
		Network           = Network,
		assets            = assets,
		proxPromptService = proxPromptService,
		defaultFOV        = defaultFOV,
	})

	-- ubglSystem
	ubglSystem.Init({
		config                    = config,
		character                 = character,
		player                    = player,
		Network                   = Network,
		assets                    = assets,
		isAnimationBusy           = WeaponBindings.IsAnimationBusy,
		playAnimation             = WeaponBindings.PlayAnimation,
		stopAnimation             = WeaponBindings.StopAnimation,
		changeHoldStance          = WeaponBindings.ChangeHoldStance,
		hardStopHoldStance        = WeaponBindings.HardStopHoldStance,
		toggleAiming              = WeaponBindings.ToggleAiming,
		idleAnim                  = WeaponBindings.IdleAnim,
		playRepSound              = WeaponBindings.PlayRepSound,
		playEmptyClickAnimation   = WeaponBindings.PlayEmptyClickAnimation,
		bulletHandler             = bulletHandler,
		playerFireUBGL            = Network.packets.PlayerFireUBGL,
		ubglReload                = Network.packets.UBGLReload,
		mobileSupport             = mobileSupport,
	})

	-- grenadeClient
	grenadeClient.Init({
		character               = character,
		humanoid                = humanoid,
		humanoidRootPart        = humanoidRootPart,
		camera                  = camera,
		rig                     = vars.rig,
		lArm                    = lArm,
		rArm                    = rArm,
		vmShirt                 = vmShirt,
		config                  = config,
		animCache               = vars.animCache,
		inspectDoF              = inspectDoF,
		getThirdPersonGunModel  = WeaponBindings.GetThirdPersonGunModel,
		playAnimation           = WeaponBindings.PlayAnimation,
		changeHoldStance        = WeaponBindings.ChangeHoldStance,
		toggleSprint            = WeaponBindings.ToggleSprint,
		idleAnim                = WeaponBindings.IdleAnim,
		refreshViewmodel        = WeaponBindings.RefreshViewmodel,
		togglePartVisibility    = WeaponBindings.TogglePartVisibility,
		handleInput             = WeaponBindings.HandleInput,
		unequip                 = WeaponBindings.Unequip,
		resetSightCaches        = function()
			vars.fpSights            = {}
			vars.tpSights            = {}
			vars.attachmentFpSights  = {}
			vars.sights              = {}
		end,
		mobileSupport           = mobileSupport,
		aimFOVTargetRef         = aimFOVTargetRef,
	})

	-- aimingSystemMod
	aimingSystemMod.Init({
		character               = character,
		camera                  = camera,
		player                  = player,
		userInputService        = userInputService,
		config                  = config,
		defaultFOV              = defaultFOV,
		attachmentSystem       = attachmentSystem,
		mobileSupport           = mobileSupport,
		aimDoF                  = aimDoF,
		gunRecoilSpring         = gunRecoilSpring,
		swaySpring              = swaySpring,
		getThirdPersonGunModel  = WeaponBindings.GetThirdPersonGunModel,
		playAnimation           = WeaponBindings.PlayAnimation,
		stopAnimation           = WeaponBindings.StopAnimation,
		playRepSound            = WeaponBindings.PlayRepSound,
		changeDoF               = WeaponBindings.ChangeDoF,
		changeHoldStance        = WeaponBindings.ChangeHoldStance,
		playerAimStateRequest   = PacketRefs.playerAimStateRequest,
		cancelFOVTween          = WeaponBindings.CancelFOVTween,
	})

	-- weaponPushbackMod
	weaponPushbackMod.Init({
		weaponPushbackRequest = Network.packets.WeaponPushbackRequest,
	})

	-- armPositionMod
	armPositionMod.Init({
		animBase          = animBase,
		rig               = vars.rig,
		camera            = camera,
		defaultFOV        = defaultFOV,
		attachmentSystem = attachmentSystem,
		ubglSystem        = ubglSystem,
		playRepSound      = WeaponBindings.PlayRepSound,
		repLPVORing       = PacketRefs.repLPVORing,
		repGripHand       = PacketRefs.repGripHand,
		lpvoThrottle      = lpvoThrottle,
		lpvoArmThrottle   = lpvoArmThrottle,
	})

	-- weaponEquipMod
	weaponEquipMod.Init({
		character                        = character,
		humanoid                         = humanoid,
		assets                           = assets,
		weldMod                          = weldMod,
		storageCFrame                    = storageCFrame,
		camera                           = camera,
		assetPreloader                   = assetPreloader,
		rig                              = vars.rig,
		lArm                             = lArm,
		rArm                             = rArm,
		vmShirt                          = vmShirt,
		player                           = player,
		config                           = config,
		perGunSightIndex                 = perGunSightIndex,
		animCache                        = vars.animCache,
		equipConnections                 = equipConnections,
		bulletHandler                    = bulletHandler,
		overheatThrottle                 = overheatThrottle,
		lpvoThrottle                     = lpvoThrottle,
		headPoseReplicationMod           = headPoseReplicationMod,
		ubglSystem                       = ubglSystem,
		switchWeapon                     = PacketRefs.switchWeapon,
		replicatedStorage                = replicatedStorage,
		armPositionMod                   = armPositionMod,
		aimFOVTargetRef                  = aimFOVTargetRef,
		defaultFOV                       = defaultFOV,
		userInputService                 = userInputService,
		ContentProvider                  = ContentProvider,
		grenadeClient                    = grenadeClient,
		attachmentSystem                = attachmentSystem,
		mobileSupport                    = mobileSupport,
		warnPrefix                       = warnPrefix,
		recoilSpring                     = recoilSpring,
		gunRecoilSpring                  = gunRecoilSpring,
		clearThirdPersonGunCache         = WeaponBindings.ClearThirdPersonGunCache,
		unequip                          = WeaponBindings.Unequip,
		unbindAiming                     = WeaponBindings.UnbindAiming,
		collectAndManageSights           = WeaponBindings.CollectAndManageSights,
		applySavedAttachmentsToViewmodel = WeaponBindings.ApplySavedAttachmentsToViewmodel,
		refreshViewmodel                 = WeaponBindings.RefreshViewmodel,
		bindGunInputs                    = WeaponBindings.BindGunInputs,
		equipAnim                        = WeaponBindings.EquipAnim,
		idleAnim                         = WeaponBindings.IdleAnim,
		moveBoltAction                   = WeaponBindings.MoveBolt,
		syncThirdPersonProjectile        = WeaponBindings.SyncThirdPersonProjectile,
		getThirdPersonGunModel           = WeaponBindings.GetThirdPersonGunModel,
		playAnimation                    = WeaponBindings.PlayAnimation,
		aimingSystemMod                  = aimingSystemMod,
	})

	-- laserSightMod
	laserSightMod.Init({
		character               = character,
		storageCFrame           = storageCFrame,
		attachmentSystem       = attachmentSystem,
		getThirdPersonGunModel  = WeaponBindings.GetThirdPersonGunModel,
		isAnimationBusy         = WeaponBindings.IsAnimationBusy,
		playAnimation           = WeaponBindings.PlayAnimation,
		playRepSound            = WeaponBindings.PlayRepSound,
		playerToggleAttachment  = PacketRefs.playerToggleAttachment,
		glareMod                = glareMod,
	})

	-- glareMod
	glareMod.Init({
		character = character,
		camera    = camera,
	})

	-- headPoseReplicationMod
	headPoseReplicationMod.Init({
		character           = character,
		config              = config,
		ReplicationThrottle = ReplicationThrottle,
		bodyAnimRequest     = PacketRefs.bodyAnimRequest,
		bodyAnimCommand     = Network.packets.BodyAnimCommand,
	})

	-- fireModeCheckDisplay
	fireModeCheckDisplay.Init({
		player         = player,
		playAnimation  = WeaponBindings.PlayAnimation,
		toggleAiming   = WeaponBindings.ToggleAiming,
	})

	-- magCheckDisplay
	magCheckDisplay.Init({
		player         = player,
		playAnimation  = WeaponBindings.PlayAnimation,
		toggleAiming   = WeaponBindings.ToggleAiming,
	})

	-- weaponFireMod
	weaponFireMod.Init({
		character               = character,
		camera                  = camera,
		defaultFOV              = defaultFOV,
		rayParams               = rayParams,
		config                  = config,
		tweenService            = tweenService,
		shootBlur               = shootBlur,
		attachmentSystem       = attachmentSystem,
		bulletHandler           = bulletHandler,
		player                  = player,
		playerGui               = playerGui,
		ubglSystem              = ubglSystem,
		fireModes               = fireModes,
		playerFire              = PacketRefs.playerFire,
		repChamber              = PacketRefs.repChamber,
		repChamberSmoke         = PacketRefs.repChamberSmoke,
		repOverheat             = PacketRefs.repOverheat,
		overheatThrottle        = overheatThrottle,
		recoilSpring            = recoilSpring,
		gunRecoilSpring         = gunRecoilSpring,
		gunRotSpring            = gunRotSpring,
		ejectShell              = WeaponBindings.EjectShell,
		moveBoltAction          = WeaponBindings.MoveBolt,
		chamberAnim             = WeaponBindings.ChamberAnim,
		isLoaded                = WeaponBindings.IsLoaded,
		playAnimation           = WeaponBindings.PlayAnimation,
		playRepSound            = WeaponBindings.PlayRepSound,
		aimToFOV                = WeaponBindings.AimToFOV,
		updateBulletTransparency= WeaponBindings.UpdateBulletTransparency,
		findProjectilePart      = WeaponBindings.FindProjectilePart,
		getThirdPersonGunModel  = WeaponBindings.GetThirdPersonGunModel,
	})

	-- cameraViewmodelMod
	cameraViewmodelMod.Init({
		character               = character,
		humanoid                = humanoid,
		humanoidRootPart        = humanoidRootPart,
		rootJoint               = CharacterRefs.rootJoint,
		neckJoint               = CharacterRefs.neckJoint,
		leftHipJoint            = CharacterRefs.leftHipJoint,
		rightHipJoint           = CharacterRefs.rightHipJoint,
		defaultLeftHipC0        = CharacterRefs.defaultLeftHipC0,
		defaultRightHipC0       = CharacterRefs.defaultRightHipC0,
		camera                  = camera,
		animBase                = animBase,
		config                  = config,
		defaultFOV              = defaultFOV,
		storageCFrame           = storageCFrame,
		headPoseReplicationMod  = headPoseReplicationMod,
		attachmentSystem       = attachmentSystem,
		grenadeClient           = grenadeClient,
		laserSightMod           = laserSightMod,
		glareMod                = glareMod,
		aimingSystemMod         = aimingSystemMod,
		proceduralWalkCycle     = proceduralWalkCycle,
		ubglSystem              = ubglSystem,
		userInputService        = userInputService,
		armPositionMod          = armPositionMod,
		aimFOVTargetRef         = aimFOVTargetRef,
		ZOOM_SENSITIVITY_REDUCTION = ZOOM_SENSITIVITY_REDUCTION,
		moveSpring              = moveSpring,
		player                  = player,
		expAlpha                = WeaponBindings.ExpAlpha,
		lerpNumber              = WeaponBindings.LerpNumber,
		getRotationBetween      = WeaponBindings.GetRotationBetween,
		bindAiming              = WeaponBindings.BindAiming,
		unbindAiming            = WeaponBindings.UnbindAiming,
		resetHead               = WeaponBindings.ResetHead,
		refreshViewmodel        = WeaponBindings.RefreshViewmodel,
		updateViewmodelPosition = WeaponBindings.UpdateViewmodelPosition,
		updateGrenadeViewmodelPosition = WeaponBindings.UpdateGrenadeViewmodelPosition,
		toggleSprint            = WeaponBindings.ToggleSprint,
		playAnimation           = WeaponBindings.PlayAnimation,
		stopAnimation           = WeaponBindings.StopAnimation,
		getThirdPersonGunModel  = WeaponBindings.GetThirdPersonGunModel,
		findProjectilePart      = WeaponBindings.FindProjectilePart,
		syncThirdPersonProjectile = WeaponBindings.SyncThirdPersonProjectile,
		aimToFOV                = WeaponBindings.AimToFOV,
	})

	-- customizeGunGUI
	customizeGunGUI.Init({
		player                  = player,
		replicatedStorage       = replicatedStorage,
		assets                  = assets,
		character               = character,
		humanoid                = humanoid,
		attachmentSystem       = attachmentSystem,
		mobileSupport           = mobileSupport,
		recoilSpring            = recoilSpring,
		gunRecoilSpring         = gunRecoilSpring,
		aimFOVTargetRef         = aimFOVTargetRef,
		gameConfig              = config,
		defaultFOV              = defaultFOV,
		playerToggleAttachment  = PacketRefs.playerToggleAttachment,
		collectAndManageSights  = WeaponBindings.CollectAndManageSights,
		glareMod                = glareMod,
		getThirdPersonGunModel  = WeaponBindings.GetThirdPersonGunModel,
		aimingSystemMod         = aimingSystemMod,
	})

	-- mobileSupport movement buttons
	mobileSupport.SetupMovementButtons(
		playerGui, character, assets, Network)
end

return SystemModuleInits