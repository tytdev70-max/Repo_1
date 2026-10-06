-- Main Server Script
-- Ties all modules together in the exact original execution order.

-- // Phase 1: Services, Assets, Constants, State (no side-effects)
local ServiceRefs = require(script.ServiceRefs)
local AssetRefs   = require(script.AssetRefs)
local Constants   = require(script.Constants)
local ServerState = require(script.ServerState)
local EventRefs   = require(script.EventRefs)

-- Shared BillboardGui templates, also supplied as editable HUD/Billboards assets.
require(AssetRefs.modules.Weapons.Attachments.LightingBillboards).Ensure(AssetRefs.assets)

-- // Phase 2: RagdollServerMod early init (original did this right after requires)
AssetRefs.RagdollServerMod.Init()

-- // Phase 3: Side-effectful setup modules (order matches original)
local CollisionSetup    = require(script.CollisionSetup)
CollisionSetup.init()

local WorkspaceSetup    = require(script.WorkspaceSetup)
WorkspaceSetup.init()

-- // Phase 4: Subsystem init (no order dependency between these)
local ArmLerpSystem     = require(script.ArmLerpSystem)
local ServerHelpers     = require(script.ServerHelpers)
local HolsterSystem     = require(script.HolsterSystem)
local CharacterRigSystem= require(script.CharacterRigSystem)
local GunSetupSystem    = require(script.GunSetupSystem)
local GunDropSystem     = require(script.GunDropSystem)
local PlayerFireSystem  = require(script.PlayerFireSystem)

-- // Phase 5: Event-driven inits (order matches original)
local RagdollEventHandler = require(script.RagdollEventHandler)
RagdollEventHandler.init()

local DoorSetup = require(script.DoorSetup)
DoorSetup.init()

-- // Phase 6: Misc startup (matches original sequence)
local soundService = ServiceRefs.soundService
soundService.RespectFilteringEnabled = true
AssetRefs.magEjection.setup()

local collectionService = ServiceRefs.collectionService
local ignoreParts = collectionService:GetTagged("SPH_NoCollide")
collectionService:GetInstanceAddedSignal("SPH_NoCollide"):Connect(function(newInstance)
	table.insert(ignoreParts, newInstance)
end)

AssetRefs.AssetPreloader.PreloadAllAnimations(AssetRefs.assets.Animations)

HolsterSystem.init()

-- // Phase 7: Player lifecycle and network (last, as they depend on everything above)
local PlayerLifecycle       = require(script.PlayerLifecycle)
local NetworkHandlers       = require(script.NetworkHandlers)
local ProximityPromptHandlers = require(script.ProximityPromptHandlers)

PlayerLifecycle.init()
NetworkHandlers.init()
ProximityPromptHandlers.init()

-- Saved attachment presets per gun type (DataStore). See LoadoutPresets.luau.
require(script.LoadoutPresets).init()

-- Test Loadout from the Gunsmith (test area + temporary gun). See GunsmithTest.luau.
require(script.GunsmithTest).init()
