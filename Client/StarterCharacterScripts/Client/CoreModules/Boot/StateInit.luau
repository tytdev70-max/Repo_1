-- Bootstrap/StateInit
-- Initializes vars (WeaponState), fireModes, shared config-derived state,
-- aimFOVTargetRef, vmArmAccessories, perGunSightIndex, remoteLeanState.

local AssetRefs = require(script.Parent.AssetRefs)
local CameraSetup = require(script.Parent.CameraSetup)
local modules = AssetRefs.modules

local config    = require(AssetRefs.assets.GameConfig) :: any
local camera    = CameraSetup.camera

local StateInit = {}

-- Config
StateInit.config     = config
StateInit.warnPrefix = "[Open-Ballistics] "

-- Config-driven settings
StateInit.defaultFOV                 = config.defaultFOV                 or 85
StateInit.ZOOM_SENSITIVITY_REDUCTION = config.zoomSensitivityReduction   or 0.05
StateInit.scrollZoomInStep           = config.scrollZoomInStep           or 3
StateInit.scrollZoomOutStep          = config.scrollZoomOutStep          or 4
StateInit.gamepadZoomDeadzone        = config.gamepadZoomDeadzone        or 0.15
StateInit.gamepadZoomStep            = config.gamepadZoomStep            or 2.5
StateInit.touchPinchZoomScale        = config.touchPinchZoomScale        or 0.05
StateInit.respawnCameraMaxZoom       = config.cameraMaxZoomDistance      or 10
StateInit.respawnCameraMinZoom       = config.cameraMinZoomDistance      or 0.5
StateInit.leanAngleDegrees           = config.leanAngleDegrees           or 17
StateInit.leanLerpRate               = config.leanLerpRate               or 6
StateInit.storageCFrame              = CFrame.new(config.viewmodelStorageDistance or 1000000, 0, 0)

-- Apply camera FOV
camera.FieldOfView = StateInit.defaultFOV

-- Weapon state
local WeaponState = require(modules.Weapons.Core.WeaponState)
local vars = WeaponState.reset() :: any
StateInit.vars = vars

-- Character attribute
local character = require(script.Parent.CharacterRefs).character
character:SetAttribute("IsUnequippingForArmHiding", false)

-- Fire modes
StateInit.fireModes = {
	Safe   = 0,
	Semi   = 1,
	Auto   = 2,
	Burst  = 3,
	Manual = 4,
}

-- FOV target reference (shared mutable container)
StateInit.aimFOVTargetRef = { value = camera.FieldOfView }

-- Per-gun caches
StateInit.vmArmAccessories  = {} :: { [string]: any }
StateInit.perGunSightIndex  = {} :: { [string]: number }
StateInit.remoteLeanState   = {} :: { [Model]: any }

-- Humanoid walk speed
local humanoid = require(script.Parent.CharacterRefs).humanoid
humanoid.WalkSpeed = config.walkSpeed

-- Aim sensitivity
local players = require(script.Parent.ServiceRefs).players
local player  = players.LocalPlayer
vars.aimSensitivity = player:GetAttribute("SavedAimSensitivity") or config.defaultAimSensitivity

return StateInit