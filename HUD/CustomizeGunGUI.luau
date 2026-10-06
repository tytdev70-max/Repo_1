-- CustomizeGunGUI (LocalScript)
-- Starts the modular weapon customization menu. All logic lives in
-- SPH_Assets.Modules.Weapons.UI.Customize — see Docs/CustomizeUI/ and its README.
--
-- Customize the menu by editing the options table below (every key is optional;
-- Customize/Config lists them all with defaults). Attachment slots are NOT configured
-- here: they come from the slot list in Weapons/Attachments/SPHAttachments, and the
-- options in each slot come from SPH_Assets/GunAttachments/<Slot>/<Name>.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local CustomizeUI = require(assets:WaitForChild("Modules").Weapons.UI.Customize)

-- Render into the existing CustomizeGunGUI if there is one (legacy template or the
-- ScreenGui this script lives in); otherwise the module creates it. Other systems
-- read PlayerGui.CustomizeGunGUI.Enabled to know whether the menu is open, so the
-- ScreenGui must carry that name.
local gui = playerGui:FindFirstChild("CustomizeGunGUI")
if not gui and script.Parent and script.Parent:IsA("ScreenGui") then
	gui = script.Parent
	gui.Name = "CustomizeGunGUI"
end

print("[CustomizeUI] starting; gui =", gui and gui:GetFullName())
local ok, err = xpcall(function()
	CustomizeUI.start({
		gui = gui,

		-- "template": use the CustomizeGunGUI designed in Studio (default).
		-- "generated": use the UI built in code instead.
		ui = "template",
		template = {
			autoColumns = true, -- new slots (Magazine, Barrel, ...) get a copy of the first column
			autoItems = true, -- attachments with no designed item get a copy of the first item
			hideEmptyColumns = false, -- true: hide columns of slots the equipped gun can't use
		},
		legacyFrames = "hide", -- only used by "generated": hide the Studio frames

		behaviour = {
			showUnavailable = false, -- true: show options this gun can't take, greyed out
			debug = true, -- TEMP: prints each opening step to Output; set false when it works
		},

		-- Per-slot presentation. Keys are slot names from SPHAttachments.
		slots = {
			-- Magazine = { label = "Magazines", order = 0 },
			-- Stock = { hidden = true },
		},

		-- theme = { accent = { 92, 196, 120 } },
		-- layout = { railWidth = 0.21, panelWidth = 0.31 },
	})
end, debug.traceback)
if not ok then
	warn("[CustomizeUI] start failed:", err)
end
print("[CustomizeUI] started:", ok)
