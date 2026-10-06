-- Weapons/Gunsmith/GunsmithTestSettings
-- Settings for Test Loadout (try a build in a test area without applying it).
-- Read by the server (Server/GunsmithTest).

return {
	enabled = true,

	-- The test area: an object with this name anywhere in Workspace.
	--   A Part: players arrive on top of it.
	--   A Model or Folder: players arrive on top of one of its parts, picked at random
	--   (use several parts as spawn points so players don't stack).
	zoneName = "GunsmithTestZone",

	-- Studs above the part's top surface where the player arrives.
	arrivalHeight = 3,

	-- Seconds before a test ends by itself (the player is brought back and the menu
	-- reopens). nil = no limit.
	maxDuration = nil,

	-- The test gun starts with a full magazine and reserve.
	refillAmmo = true,

	-- Seconds between tests for one player.
	cooldown = 2,
}
