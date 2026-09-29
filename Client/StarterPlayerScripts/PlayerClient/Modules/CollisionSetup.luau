--// CollisionSetup.lua
--// Registers all physics collision groups and configures which pairs
--// should NOT collide.  Identical logic to the original top-of-file block.

local CollisionSetup = {}

local ServiceRefs = require(script.Parent.ServiceRefs)

local PhysicsService = ServiceRefs.PhysicsService :: PhysicsService
local Config            = ServiceRefs.Config :: any

--// Private

local COLLISION_GROUPS: { string } = {
	"Casings", "Players", "RootParts", "Guns", "Debris", "Grenades",
}

local NON_COLLIDING_PAIRS: { { string } } = {
	{ "Casings",   "Casings"   },
	{ "Casings",   "Players"   },
	{ "Guns",      "Guns"      },
	{ "Guns",      "Players"   },
	{ "Casings",   "Guns"      },
	{ "RootParts", "Guns"      },
	{ "RootParts", "Casings"   },
	{ "Debris",    "Casings"   },
	{ "Debris",    "Guns"      },
	{ "Grenades",  "Grenades"  },
	{ "Grenades",  "Players"   },
	{ "Grenades",  "RootParts" },
	{ "Grenades",  "Guns"      },
	{ "Grenades",  "Casings"   },
	{ "Grenades",  "Debris"    },
	{ "Bodies",    "Guns"      },
	{ "Bodies",    "Casings"   },
	{ "Bodies",    "Debris"    },
	{ "Bodies",    "Grenades"  },
	{ "Bodies",    "Players"   },
	{ "Bodies",    "RootParts" },
}

--// Public

function CollisionSetup.Init(): ()
	-- Register standard groups
	for _, groupName: string in ipairs(COLLISION_GROUPS) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(groupName)
		end)
	end

	-- Register Bodies group separately (mirrors original separate pcall)
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Bodies")
	end)

	-- Optional player-debris collision disable
	if Config.disablePlayerDebrisCollision then
		table.insert(NON_COLLIDING_PAIRS, { "Debris", "Players"   })
		table.insert(NON_COLLIDING_PAIRS, { "Debris", "RootParts" })
	end

	-- Apply non-collision pairs
	for _, pair: { string } in ipairs(NON_COLLIDING_PAIRS) do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], false)
		end)
	end
end

return CollisionSetup