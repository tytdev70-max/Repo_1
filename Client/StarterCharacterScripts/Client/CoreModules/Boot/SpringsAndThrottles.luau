-- Bootstrap/SpringsAndThrottles
-- Creates all spring instances, connection managers, and replication throttles.

local AssetRefs = require(script.Parent.AssetRefs)
local modules   = AssetRefs.modules

local springMod           = require(modules.Core.Math.SpringModule)
local ConnectionManager   = require(modules.Core.Utility.ConnectionManager)
local ReplicationThrottle = require(modules.Core.Networking.ReplicationThrottle)

local ST = {}

-- Springs
ST.swaySpring      = springMod.new() :: any
ST.moveSpring      = springMod.new() :: any
ST.recoilSpring    = springMod.new() :: any
ST.gunRecoilSpring = springMod.new() :: any
ST.jumpSpring      = springMod.new() :: any
ST.gunRotSpring    = springMod.new() :: any

ST.jumpSpring.Damping = 5
ST.jumpSpring.Speed   = 1

-- Connection managers
ST.equipConnections = ConnectionManager.new() :: any

-- Replication throttles
ST.overheatThrottle = ReplicationThrottle.new(0)        :: any
ST.lpvoThrottle     = ReplicationThrottle.new(1 / 20)   :: any
ST.lpvoArmThrottle  = ReplicationThrottle.new(1 / 20)   :: any

-- Expose the classes for handlers that need to instantiate more
ST.ReplicationThrottle = ReplicationThrottle

return ST