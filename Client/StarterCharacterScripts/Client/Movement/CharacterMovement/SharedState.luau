-- SharedState
-- All mutable top-level state variables shared across CharacterMovement modules.
-- Centralizing them here prevents circular dependencies and allows all modules
-- to read/write the same state by reference.

local players           = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(script.Parent.Constants)

-- ── References ────────────────────────────────────────────────────────────

local CHARACTER_LOAD_TIMEOUT = Constants.CHARACTER_LOAD_TIMEOUT

local localPlayer: Player       = players.LocalPlayer
local playerCharacter: Model    = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local humanoid: Humanoid        = playerCharacter:WaitForChild("Humanoid", CHARACTER_LOAD_TIMEOUT) :: Humanoid
local rootPart: BasePart        = playerCharacter:WaitForChild("HumanoidRootPart", CHARACTER_LOAD_TIMEOUT) :: BasePart
rootPart:WaitForChild("RootJoint", CHARACTER_LOAD_TIMEOUT)

local assets: Folder            = replicatedStorage:WaitForChild("SPH_Assets") :: Folder
local modules: Folder           = assets:WaitForChild("Modules") :: Folder
local eventsFolder: Folder      = assets:WaitForChild("Events") :: Folder
local gunEventsFolder: Folder   = eventsFolder:WaitForChild("GunEvents") :: Folder
local movementEventsFolder: Folder = eventsFolder:WaitForChild("MovementEvents") :: Folder
local toggleViewmodelSprint: BindableEvent =
	gunEventsFolder:WaitForChild("ToggleViewmodelSprint") :: BindableEvent
local playCharacterSoundEvent: RemoteEvent =
	movementEventsFolder:WaitForChild("PlayCharacterSound") :: RemoteEvent

local networkingModules = modules:WaitForChild("Core"):WaitForChild("Networking") :: Folder
local config = require(assets:WaitForChild("GameConfig") :: ModuleScript) :: any

-- ── Mutable Movement State ────────────────────────────────────────────────

local SharedState = {}

-- References (read-only after init)
SharedState.localPlayer              = localPlayer
SharedState.playerCharacter          = playerCharacter
SharedState.humanoid                 = humanoid
SharedState.rootPart                 = rootPart
SharedState.assets                   = assets
SharedState.modules                  = modules
SharedState.eventsFolder             = eventsFolder
SharedState.gunEventsFolder          = gunEventsFolder
SharedState.movementEventsFolder     = movementEventsFolder
SharedState.toggleViewmodelSprint    = toggleViewmodelSprint
SharedState.playCharacterSoundEvent  = playCharacterSoundEvent
SharedState.networkingModules        = networkingModules
SharedState.config                   = config

-- Mutable state (all modules mutate these fields directly)
SharedState.movementVector  = Vector3.zero
SharedState.canChangeWalkSpeed = script.Parent:GetAttribute("CanChangeWalkSpeed") == true
SharedState.strafing        = false
SharedState.hipHeightTween   = nil
SharedState.strafingMult     = config.strafeSpeedMultiplier
SharedState.canChangeStance = true
SharedState.stance           = Constants.Stance.Standing
SharedState.moving          = false
SharedState.moveAnim = nil
SharedState.Blocked         = false

-- Stamina state
local defaultMaxStamina = Constants.DEFAULT_MAX_STAMINA
SharedState.maxStamina      = if config and config.maxStamina ~= nil then config.maxStamina else defaultMaxStamina
SharedState.stamina         = SharedState.maxStamina
SharedState.isExhausted     = false

-- Lean refs (populated by MovementLean)
SharedState.localLeanRefs = nil
SharedState.otherLeanRefs = {}
SharedState.otherLeanRefsByCharacter = {}

-- Render loop connection (written by RenderLoop, read by DeathHandler)
SharedState.renderSteppedConn = nil

return SharedState