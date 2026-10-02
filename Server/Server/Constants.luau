-- Constants
-- All numeric constants, lookup tables, and pure helper functions.
-- No dependencies. Pure data.

local Constants = {}

Constants.MAX_WEAPON_PUSHBACK         = 8
Constants.MAX_ARM_C0_DISTANCE         = 25
Constants.DOOR_TAG                    = "SPH_Door"
Constants.ARM_PACKET_IGNORE_DURATION  = 0.35
Constants.ARM_AT_TARGET_EPSILON       = 0.005
Constants.GRIP_TARGET_EPSILON         = 0.05
Constants.HAND_END_LOCAL_OFFSET       = CFrame.new(1.2, -1.2, -0.2)
Constants.MAX_FIRE_MODE               = 4
Constants.FOOTSTEP_REPLICATION_RANGE  = 100
Constants.FALL_SOUND_PITCH_VARIANCE   = 10

Constants.ARM_LERP_HOLD_RATE          = 8
Constants.ARM_LERP_RESTORE_RATE       = 14
Constants.ARM_LERP_HOLD_MAX_ALPHA     = 0.3
Constants.ARM_LERP_RESTORE_MAX_ALPHA  = 0.5

Constants.LPVO_STATES = {
	Enter  = true,
	Update = true,
	Exit   = true,
}

Constants.ATTACHMENT_CATEGORIES = {
	Optics      = true,
	Underbarrel = true,
	Muzzle      = true,
	Stock       = true,
}

Constants.SERVER_SKIPPED_SOUND_NAMES = {
	Fire             = true,
	AutoFire         = true,
	SilencedFire     = true,
	SilencedAutoFire = true,
	Echo             = true,
	SilencedEcho     = true,
	AutoTail         = true,
	SilencedAutoTail = true,
}

Constants.FALL_DAMAGE_SOUND_TIERS = {
	{ maxDamage = 10, soundName = "Fall1" },
	{ maxDamage = 30, soundName = "Fall2" },
	{ maxDamage = 60, soundName = "Fall3" },
}
Constants.FALL_DAMAGE_SOUND_FALLBACK = "Fall4"

Constants.WORKSPACE_SUBFOLDER_NAMES = {
	"Projectiles", "Cache", "SmokeCache", "Shells", "Drops"
}

Constants.COLLISION_GROUPS = {
	"Casings", "Players", "RootParts", "Guns", "Debris", "Grenades"
}

Constants.NON_COLLIDING_GROUP_PAIRS = {
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
	-- Ragdoll collision rules
	{ "Bodies",    "Players"   },
	{ "Bodies",    "RootParts" },
}

-- // Pure helper functions

function Constants.GetFallDamageSoundName(damage: number): string
	for _, tier in ipairs(Constants.FALL_DAMAGE_SOUND_TIERS) do
		if damage <= tier.maxDamage then
			return tier.soundName
		end
	end
	return Constants.FALL_DAMAGE_SOUND_FALLBACK
end

return Constants