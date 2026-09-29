--!strict

--[[
	WeaponBindings

	Usage in Client:
		local WeaponBindings = require(modules.Weapons.Client.WeaponBindings)
		WeaponBindings.MoveBolt(...)
		WeaponBindings.ToggleSprint(...)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local modules = ReplicatedStorage:WaitForChild("SPH_Assets"):WaitForChild("Modules")

local weaponActions = require(modules.Weapons.Client.Actions.WeaponActions) :: any
local weaponAnimation = require(modules.Weapons.Client.Animation.WeaponAnimation) :: any
local weaponSequences = require(modules.Weapons.Client.Actions.WeaponSequences) :: any
local weaponViewmodel = require(modules.Weapons.Client.Viewmodel.WeaponViewmodel) :: any
local weaponAiming = require(modules.Weapons.Client.Aiming.WeaponAiming) :: any
local weaponMath = require(modules.Weapons.Math.WeaponMath) :: any
local weaponFrame = require(modules.Weapons.Client.Viewmodel.WeaponFrame) :: any
local weaponInput = require(modules.Weapons.Client.Input.WeaponInput) :: any
local weaponLifecycle = require(modules.Weapons.Client.Lifecycle.WeaponLifecycle) :: any

return {
	-- WeaponActions
	GetThirdPersonGunModel = weaponActions.GetThirdPersonGunModel,
	ClearThirdPersonGunCache = weaponActions.ClearThirdPersonGunCache,
	IsLoaded = weaponActions.IsLoaded,
	MoveBolt = weaponActions.MoveBolt,
	EjectShell = weaponActions.EjectShell,
	FindProjectilePart = weaponActions.FindProjectilePart,
	SwitchFireMode = weaponActions.SwitchFireMode,
	UpdateAllBulletTransparency = weaponActions.UpdateAllBulletTransparency,
	UpdateBulletTransparency = weaponActions.UpdateBulletTransparency,

	-- WeaponAnimation
	IsAnimationBusy = weaponAnimation.IsAnimationBusy,
	PlayRepSound = weaponAnimation.PlayRepSound,
	StopAnimation = weaponAnimation.StopAnimation,
	PlayAnimation = weaponAnimation.PlayAnimation,
	StopConflictingAnimations = weaponAnimation.StopConflictingAnimations,

	-- WeaponSequences
	PlayEmptyClickAnimation = weaponSequences.PlayEmptyClickAnimation,
	ChamberAnim = weaponSequences.ChamberAnim,
	IdleAnim = weaponSequences.IdleAnim,
	EquipAnim = weaponSequences.EquipAnim,
	ReloadAnim = weaponSequences.ReloadAnim,

	-- WeaponViewmodel
	TogglePartVisibility = weaponViewmodel.TogglePartVisibility,
	SyncThirdPersonProjectile = weaponViewmodel.SyncThirdPersonProjectile,
	CollectAndManageSights = weaponViewmodel.CollectAndManageSights,
	ApplySavedAttachmentsToViewmodel = weaponViewmodel.ApplySavedAttachmentsToViewmodel,
	CleanupVMAccessories = weaponViewmodel.CleanupVMAccessories,
	SyncArmAccessoriesToViewmodel = weaponViewmodel.SyncArmAccessoriesToViewmodel,
	RefreshViewmodel = weaponViewmodel.RefreshViewmodel,
	SetAllSightSurfaceGuis = weaponViewmodel.SetAllSightSurfaceGuis,
	ResetHead = weaponViewmodel.ResetHead,

	-- WeaponAiming
	ChangeHoldStance = weaponAiming.ChangeHoldStance,
	HardStopHoldStance = weaponAiming.HardStopHoldStance,
	ChangeDoF = weaponAiming.ChangeDoF,
	ToggleSprint = weaponAiming.ToggleSprint,
	ToggleAiming = weaponAiming.ToggleAiming,
	BindAiming = weaponAiming.BindAiming,
	UnbindAiming = weaponAiming.UnbindAiming,
	AimToFOV = weaponAiming.AimToFOV,
	CancelFOVTween = weaponAiming.CancelFOVTween,
	ToggleADS = weaponAiming.ToggleADS,

	-- WeaponMath
	LerpNumber = weaponMath.LerpNumber,
	ExpAlpha = weaponMath.ExpAlpha,
	GetRotationBetween = weaponMath.GetRotationBetween,
	GetSineOffset = weaponMath.GetSineOffset,

	-- WeaponFrame
	UpdateViewmodelPosition = weaponFrame.UpdateViewmodelPosition,
	UpdateGrenadeViewmodelPosition = weaponFrame.UpdateGrenadeViewmodelPosition,

	-- WeaponInput
	HandleInput = weaponInput.HandleInput,
	BindGunInputs = weaponInput.BindGunInputs,
	UnbindGunInputs = weaponInput.UnbindGunInputs,

	-- WeaponLifecycle
	Unequip = weaponLifecycle.Unequip,
	onCharacterAdded = weaponLifecycle.onCharacterAdded,
}