--// Main.client.lua
--!strict
--// Entry point for the PlayerClient system.
--// Bootstraps all subsystems in the correct order, preserving the exact
--// startup sequence of the original monolithic script.

--// ── 1. Service + Asset refs (no heavy work, just pointers) ──────────────
local ServiceRefs = require(script.Modules.ServiceRefs)

--// ── 2. Collision groups (physics, must be first) ─────────────────────────
local CollisionSetup = require(script.Modules.CollisionSetup)
CollisionSetup.Init()

--// ── 3. Third-party / shared effect modules ───────────────────────────────
--//    Required early so downstream modules can import them without waiting.
local modules = ServiceRefs.modules

local _hitFX         = require(modules.Effects.Blood.HitFX)        -- side-effect preload
local _shellEjection = require(modules.Weapons.Fire.ShellEjection) -- side-effect preload
local _bulletHandler = require(modules.Weapons.Fire.BulletHandler) -- side-effect preload

--// ── 4. Hearing muffle (Init must run before ExplosionFX) ─────────────────
local HearingMuffleMod = require(modules.Systems.HearingMuffleMod)
HearingMuffleMod.Init()

--// ── 5. Camera shake controller (depends on nothing above) ────────────────
local CameraShakeController = require(script.Modules.CameraShakeController)
-- camShake is started inside the module's top-level code.

--// ── 6. Jump camera offset ────────────────────────────────────────────────
local JumpCameraOffset = require(script.Modules.JumpCameraOffset)
JumpCameraOffset.Init()

--// ── 7. Child modules (spawned async, safe to fire early) ─────────────────
local ChildModuleLoader = require(script.Modules.ChildModuleLoader)
ChildModuleLoader.Init(script)

--// ── 8. Network-driven replication systems ────────────────────────────────
local FireReplication      = require(script.Modules.FireReplication)
local BodyAnimReplication  = require(script.Modules.BodyAnimReplication)
local HitReplication       = require(script.Modules.HitReplication)
local FlashlightReplication = require(script.Modules.FlashlightReplication)
local MagGrabReplication   = require(script.Modules.MagGrabReplication)
local GripHandReplication  = require(script.Modules.GripHandReplication)

FireReplication.Init()
BodyAnimReplication.Init()
HitReplication.Init()
FlashlightReplication.Init()
MagGrabReplication.Init()
GripHandReplication.Init()

--// ── 9. World-event FX ─────────────────────────────────────────────────────
local ExplosionFX = require(script.Modules.ExplosionFX)
local DoorShake   = require(script.Modules.DoorShake)
ExplosionFX.Init()
DoorShake.Init()

--// ── 10. UI / HUD ─────────────────────────────────────────────────────────
local KillFeedHandler = require(script.Modules.KillFeedHandler)
KillFeedHandler.Init()