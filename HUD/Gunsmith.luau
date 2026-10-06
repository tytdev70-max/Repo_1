-- Gunsmith (LocalScript)
-- Put this LocalScript directly inside the Gunsmith ScreenGui (SPH_Assets.HUD.GunGUIs.Gunsmith).
-- It replaces any script that only referenced the frames: all logic lives in
-- SPH_Assets.Modules.Weapons.UI.Customize (View/Gunsmith shows the menu).
--
-- GameConfig.customizeMenu = "Gunsmith" makes the customize table open this menu.
-- Expected frames: see the top of Customize/View/Gunsmith. Every option below is optional
-- (Customize/Config lists them all).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local CustomizeUI = require(assets:WaitForChild("Modules").Weapons.UI.Customize)

local gui = script.Parent

local ok, err = xpcall(function()
	CustomizeUI.start({
		gui = gui,
		ui = "gunsmith",

		gunsmith = {
			noneItem = true, -- "None" at the top of each list (clears the slot)
			uppercaseCategories = true, -- "OPTICS" instead of "Optics"
			-- selectedColor = { 100, 200, 100 },
		},

		behaviour = {
			showUnavailable = false, -- true: also list attachments this gun can't take (dimmed)
			debug = false, -- true: prints each opening step to Output
		},

		-- Per-slot presentation. Keys are slot names from SPHAttachments.
		slots = {
			-- Optics = { label = "Optic", order = 1 },
			-- Stock = { hidden = true },
		},

		-- test = { enabled = true },  -- Test Loadout (server settings: Weapons/Gunsmith/GunsmithTestSettings)
	})
end, debug.traceback)
if not ok then
	warn("[Gunsmith] start failed:", err)
end
