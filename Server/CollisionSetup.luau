-- CollisionSetup
-- Registers collision groups and sets non-colliding pairs.

local ServiceRefs  = require(script.Parent.ServiceRefs)
local AssetRefs    = require(script.Parent.AssetRefs)
local Constants    = require(script.Parent.Constants)

local physicsService = ServiceRefs.physicsService
local config         = AssetRefs.config

local CollisionSetup = {}

function CollisionSetup.init()
	for _, groupName in ipairs(Constants.COLLISION_GROUPS) do
		physicsService:RegisterCollisionGroup(groupName)
	end

	pcall(physicsService.RegisterCollisionGroup, physicsService, "Bodies")

	local pairs = table.clone(Constants.NON_COLLIDING_GROUP_PAIRS)

	if config.disablePlayerDebrisCollision then
		table.insert(pairs, { "Debris", "Players"   })
		table.insert(pairs, { "Debris", "RootParts" })
	end

	for _, pair in ipairs(pairs) do
		physicsService:CollisionGroupSetCollidable(pair[1], pair[2], false)
	end
end

return CollisionSetup