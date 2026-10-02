-- EventRefs
-- All event lookups/creates used across the server.

local ServiceRefs = require(script.Parent.ServiceRefs)
local AssetRefs   = require(script.Parent.AssetRefs)

local assets     = AssetRefs.assets
local SPH_Events = AssetRefs.SPH_Events

local EventRefs = {}

EventRefs.npcHitEvent        = SPH_Events.GetOrCreate("CombatEvents",     "NPC_HitEvent",       "BindableEvent")
EventRefs.glassRestoredEvent = SPH_Events.GetOrCreate("EnvironmentEvents","SPH_GlassRestored",   "RemoteEvent")
EventRefs.showHolsterRemote  = SPH_Events.GetOrCreate("GunEvents",        "SPH_ShowHolster",     "RemoteEvent")

local deathEventsFolder = assets.Events:WaitForChild("DeathEvents") :: Folder
EventRefs.ragdollEvent   = deathEventsFolder:WaitForChild("RagdollEvent")   :: RemoteEvent
EventRefs.unragdollEvent = deathEventsFolder:WaitForChild("UnragdollEvent") :: RemoteEvent

EventRefs.applyAttachmentsEvent = assets.Events:WaitForChild("GunEvents"):WaitForChild("ApplyWeaponAttachments") :: RemoteEvent
EventRefs.dropGunEvent          = assets.Events.GunEvents.DropGun :: BindableEvent
EventRefs.playCharacterSoundEvent = assets.Events.MovementEvents.PlayCharacterSound :: RemoteEvent

return EventRefs