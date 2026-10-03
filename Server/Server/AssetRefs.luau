-- AssetRefs
-- All asset/module lookups from ReplicatedStorage.
-- Also requires all sub-modules used across the server.

local ServiceRefs       = require(script.Parent.ServiceRefs)
local replicatedStorage = ServiceRefs.replicatedStorage

local AssetRefs = {}

-- Folders
local assets  = replicatedStorage.SPH_Assets
local modules = assets.Modules

AssetRefs.assets   = assets
AssetRefs.modules  = modules
AssetRefs.mainui   = assets.HUD.GunGUIs.SPH_UI
AssetRefs.config   = require(assets.GameConfig)
AssetRefs.warnPrefix = "[Open-Ballistics] "

-- Sub-modules (required once here, shared everywhere)
AssetRefs.SPH_Events          = require(modules.Core.Networking.SPH_Events)
AssetRefs.weldMod             = require(modules.Weapons.Core.WeldMod)
AssetRefs.Network             = require(modules.Core.Networking.SPH_Network)
AssetRefs.NetworkRangeUtil    = require(modules.Core.Networking.NetworkRangeUtil)
AssetRefs.MaterialCodec       = require(modules.Core.Networking.MaterialCodec)
AssetRefs.viewMod             = require(modules.Weapons.Equip.ViewMod)
AssetRefs.fractureGlass       = require(modules.Effects.Environment.FractureGlass)
AssetRefs.Attachments         = require(modules.Weapons.Attachments.SPHAttachments) -- standalone GunAttachments system (per-VM singleton)
AssetRefs.hitscan             = require(modules.Weapons.Fire.Hitscan)
AssetRefs.magEjection         = require(modules.Weapons.Fire.MagEjection)
AssetRefs.grenadeHandler      = require(modules.Misc.Grenades.GrenadeHandler)
AssetRefs.glassShatterMod     = require(modules.Effects.Environment.GlassShatterMod)
AssetRefs.ubglHandler         = require(modules.Weapons.Attachments.UBGLSystemMod)
AssetRefs.HitResolutionMod    = require(modules.Systems.HitResolutionMod)
AssetRefs.PlayerDeathMod      = require(modules.Systems.PlayerDeathMod)
AssetRefs.DoorController      = require(modules.Misc.DoorSystem.DoorController)
AssetRefs.AssetPreloader      = require(modules.Systems.AssetPreloader)
AssetRefs.DayNightCycle       = require(modules.Systems.DayNightCycle)
AssetRefs.RagdollServerMod    = require(modules.Systems.RagdollServerMod)

return AssetRefs