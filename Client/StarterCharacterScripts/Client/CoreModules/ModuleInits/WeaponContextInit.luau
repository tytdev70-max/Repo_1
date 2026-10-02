-- ModuleInits/WeaponContextInit
-- Calls WeaponContext.set({...}) and require(WeaponClient).init().
-- Must run after all system module inits.

local AssetRefs       = require(script.Parent.Parent.Boot.AssetRefs)
local CharacterRefs   = require(script.Parent.Parent.Boot.CharacterRefs)
local CameraSetup     = require(script.Parent.Parent.Boot.CameraSetup)
local StateInit       = require(script.Parent.Parent.Boot.StateInit)
local SpringsAndThrottles = require(script.Parent.Parent.Boot.SpringsAndThrottles)
local ViewmodelSetup  = require(script.Parent.Parent.Boot.ViewmodelSetup)
local RaycastSetup    = require(script.Parent.Parent.Boot.RaycastSetup)
local SystemInits     = require(script.Parent.SystemModuleInits)

local modules = AssetRefs.modules

local WeaponContext  = require(modules.Weapons.Core.WeaponContext)
local WeaponClient   = require(modules.Weapons.Client.WeaponClient)
local WeaponBindings = SystemInits.WeaponBindings
local PacketRefs     = SystemInits.PacketRefs
local Network        = SystemInits.Network
local vars           = StateInit.vars
local config         = StateInit.config
local character      = CharacterRefs.character
local humanoid       = CharacterRefs.humanoid
local humanoidRootPart = CharacterRefs.humanoidRootPart
local camera         = CameraSetup.camera
local inspectDoF     = CameraSetup.inspectDoF
local aimDoF         = CameraSetup.aimDoF
local animBase       = ViewmodelSetup.animBase
local lArm           = ViewmodelSetup.lArm
local rArm           = ViewmodelSetup.rArm
local vmShirt        = ViewmodelSetup.vmShirt
local vmAnimator     = ViewmodelSetup.vmAnimator
local rayParams      = RaycastSetup.rayParams
local defaultFOV     = StateInit.defaultFOV
local storageCFrame  = StateInit.storageCFrame
local fireModes      = StateInit.fireModes
local aimFOVTargetRef    = StateInit.aimFOVTargetRef
local perGunSightIndex   = StateInit.perGunSightIndex
local vmArmAccessories   = StateInit.vmArmAccessories
local warnPrefix         = StateInit.warnPrefix

local swaySpring       = SpringsAndThrottles.swaySpring
local moveSpring       = SpringsAndThrottles.moveSpring
local recoilSpring     = SpringsAndThrottles.recoilSpring
local gunRecoilSpring  = SpringsAndThrottles.gunRecoilSpring
local jumpSpring       = SpringsAndThrottles.jumpSpring
local gunRotSpring     = SpringsAndThrottles.gunRotSpring
local equipConnections = SpringsAndThrottles.equipConnections
local lpvoThrottle     = SpringsAndThrottles.lpvoThrottle
local lpvoArmThrottle  = SpringsAndThrottles.lpvoArmThrottle
local overheatThrottle = SpringsAndThrottles.overheatThrottle

local players = require(script.Parent.Parent.Boot.ServiceRefs).players
local player  = players.LocalPlayer

local WeaponContextInit = {}

function WeaponContextInit.init()
	WeaponContext.set({
		vmAnimator                   = vmAnimator,
		playSound                    = PacketRefs.playSound,
		repBoltOpen                  = PacketRefs.repBoltOpen,
		repChamber                   = PacketRefs.repChamber,
		repMagEject                  = PacketRefs.repMagEject,
		repReload                    = PacketRefs.repReload,
		EjectShell                   = WeaponBindings.EjectShell,
		FindProjectilePart           = WeaponBindings.FindProjectilePart,
		GetThirdPersonGunModel       = WeaponBindings.GetThirdPersonGunModel,
		MoveBolt                     = WeaponBindings.MoveBolt,
		SyncThirdPersonProjectile    = WeaponBindings.SyncThirdPersonProjectile,
		UpdateAllBulletTransparency  = WeaponBindings.UpdateAllBulletTransparency,
		UpdateBulletTransparency     = WeaponBindings.UpdateBulletTransparency,
		ChangeHoldStance             = WeaponBindings.ChangeHoldStance,
		CollectAndManageSights       = WeaponBindings.CollectAndManageSights,
		ToggleAiming                 = WeaponBindings.ToggleAiming,
		ToggleSprint                 = WeaponBindings.ToggleSprint,
		animBase                     = animBase,
		character                    = character,
		fireModes                    = fireModes,
		gunRecoilSpring              = gunRecoilSpring,
		gunRotSpring                 = gunRotSpring,
		warnPrefix                   = warnPrefix,
		player                       = player,
		PlayAnimation                = WeaponBindings.PlayAnimation,
		StopAnimation                = WeaponBindings.StopAnimation,
		defaultFOV                   = defaultFOV,
		humanoid                     = humanoid,
		humanoidRootPart             = humanoidRootPart,
		jumpSpring                   = jumpSpring,
		rayParams                    = rayParams,
		recoilSpring                 = recoilSpring,
		storageCFrame                = storageCFrame,
		swaySpring                   = swaySpring,
		moveSpring                   = moveSpring,
		ExpAlpha                     = WeaponBindings.ExpAlpha,
		LerpNumber                   = WeaponBindings.LerpNumber,
		BindAiming                   = WeaponBindings.BindAiming,
		ChamberAnim                  = WeaponBindings.ChamberAnim,
		IsAnimationBusy              = WeaponBindings.IsAnimationBusy,
		IsLoaded                     = WeaponBindings.IsLoaded,
		PlayEmptyClickAnimation      = WeaponBindings.PlayEmptyClickAnimation,
		ReloadAnim                   = WeaponBindings.ReloadAnim,
		SwitchFireMode               = WeaponBindings.SwitchFireMode,
		Unequip                      = WeaponBindings.Unequip,
		UnbindGunInputs              = WeaponBindings.UnbindGunInputs,
		aimFOVTargetRef              = aimFOVTargetRef,
		inspectDoF                   = inspectDoF,
		perGunSightIndex             = perGunSightIndex,
		playerDropGun                = PacketRefs.playerDropGun,
		playerToggleAttachment       = PacketRefs.playerToggleAttachment,
		ChangeDoF                    = WeaponBindings.ChangeDoF,
		CleanupVMAccessories         = WeaponBindings.CleanupVMAccessories,
		ClearThirdPersonGunCache     = WeaponBindings.ClearThirdPersonGunCache,
		equipConnections             = equipConnections,
		lpvoArmThrottle              = lpvoArmThrottle,
		lpvoThrottle                 = lpvoThrottle,
		overheatThrottle             = overheatThrottle,
		switchWeapon                 = PacketRefs.switchWeapon,
		IdleAnim                     = WeaponBindings.IdleAnim,
		lArm                         = lArm,
		rArm                         = rArm,
		repPartVisibilityRequest     = PacketRefs.repPartVisibilityRequest,
		vmArmAccessories             = vmArmAccessories,
		vmShirt                      = vmShirt,
		HandleInput                  = WeaponBindings.HandleInput,
		aimDoF                       = aimDoF,
		depthOfField                 = require(script.Parent.Parent.Boot.EffectsSetup).depthOfField,
		PlayRepSound                 = WeaponBindings.PlayRepSound,
		moveBolt                     = PacketRefs.moveBolt,
		switchFireMode               = PacketRefs.switchFireMode,
		repShellEjectRequest         = PacketRefs.repShellEjectRequest,
	})

	WeaponClient.init()
end

return WeaponContextInit