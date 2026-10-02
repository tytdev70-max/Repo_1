--!strict
-- // CharacterMovement (main ModuleScript)
-- // Initializes the entire CharacterMovement system in the exact original order.
-- // Required via: task.spawn(function() require(script.Movement.CharacterMovement) end)

-- // Bootstrap (order matters — each requires the previous)

local Constants            = require(script.Constants)
local SharedState          = require(script.SharedState)

-- // Initial Attributes (mirroring original top-level SetAttribute calls)

local mainScript = script  -- // This is the CharacterMovement ModuleScript
local config = SharedState.config

mainScript:SetAttribute("WalkSpeed",   config.walkSpeed)
mainScript:SetAttribute("SprintSpeed", config.sprintSpeed)
mainScript:SetAttribute("CrouchSpeed", config.crouchSpeed)
mainScript:SetAttribute("ProneSpeed",  config.proneSpeed)
mainScript:SetAttribute("MaxStamina",  SharedState.maxStamina)
mainScript:SetAttribute("Stamina",     SharedState.stamina)

local playerCharacter = SharedState.playerCharacter
local StanceName      = Constants.StanceName
local Stance          = Constants.Stance

playerCharacter:SetAttribute("Stance",        StanceName[Stance.Standing])
playerCharacter:SetAttribute("LeanDirection", 0)
playerCharacter:SetAttribute("MaxStamina",    SharedState.maxStamina)
playerCharacter:SetAttribute("Stamina",       SharedState.stamina)
playerCharacter:SetAttribute("IsExhausted",   false)

-- // Load Sub-Systems 

-- // AnimationSetup must come before systems that use animations
local AnimationSetup        = require(script.AnimationSetup)

-- // MovementLean must come before FootIK (builds localLeanRefs into SharedState)
local MovementLean          = require(script.MovementLean)

-- // FootIK must come after MovementLean (needs localLeanRefs to exist)
local FootIK                = require(script.FootIK)

-- // Remaining systems (no strict inter-dependency ordering after the above)
local SprintSystem          = require(script.SprintSystem)
local LeanSystem            = require(script.LeanSystem)
local StanceSystem          = require(script.StanceSystem)
local WalkSpeedSystem       = require(script.WalkSpeedSystem)
local InputBindings         = require(script.InputBindings)
local SeatHandler           = require(script.SeatHandler)
local BindableEventHandler  = require(script.BindableEventHandler)
local RenderLoop            = require(script.RenderLoop)
local DeathHandler          = require(script.DeathHandler)
local StaminaSystem         = require(script.Stamina)

-- // Initialize Event Connections 

InputBindings.BindCharacterInputs()   -- // mirrors original BindCharacterInputs() call
SeatHandler.init()
BindableEventHandler.init()
RenderLoop.init()
DeathHandler.init()

-- // Return 

return true