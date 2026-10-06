-- Weapons/Presets/PresetSettings
-- Settings for loadout presets (saved attachment setups per gun type).
-- Read by the server (LoadoutPresets) and the client (the customize menu).

return {
	enabled = true,

	-- DataStore that keeps presets between sessions. Change the name to start fresh.
	-- In Studio, presets are only saved if "Enable Studio Access to API Services" is on
	-- (Game Settings > Security); otherwise they last for the session only.
	dataStoreName = "SPH_LoadoutPresets_v1",

	-- Max presets per gun type. nil = no limit (a hidden safety limit on the total
	-- saved size still applies, because a DataStore key holds at most 4 MB).
	maxPresetsPerGun = nil,

	maxNameLength = 24,

	-- Seconds between background saves of changed data (it is also saved on leave
	-- and on server shutdown).
	autosaveInterval = 120,

	-- Requests per second a player may send (list/save/rename/delete).
	maxRequestsPerSecond = 6,
}
