--!nonstrict
-- CustomizeUI
-- Modular weapon customization menu for SPH. Entry point.
--
--   local CustomizeUI = require(SPH_Assets.Modules.Weapons.UI.Customize)
--   local controller = CustomizeUI.start({
--       -- every key is optional; see Customize/Config for all of them
--       behaviour = { showUnavailable = true },
--       slots = { Magazine = { label = "Mags", order = 0 } },
--       theme = { accent = { 255, 170, 60 } },
--       layout = { railWidth = 0.18 },
--   })
--
-- Slots and options are data-driven (attachment system slot list + content folders),
-- so new attachment types need no UI changes. See Docs/CustomizeUI/ and README.md.
--
-- start() is safe to call repeatedly (e.g. from a script inside a ScreenGui that
-- resets on spawn): the previous controller is destroyed first.

local Players = game:GetService("Players")

local Config = require(script.Config)
local Controller = require(script.Controller)
local Environment = require(script.Environment)
local Preview = require(script.Preview)
local View = require(script.View)
local Bridge = require(script.Bridge)

local CustomizeUI = {}

CustomizeUI.Config = Config
CustomizeUI.Controller = Controller
CustomizeUI.View = View
CustomizeUI.Bridge = Bridge

local GUI_NAME = "CustomizeGunGUI" -- other scripts read PlayerGui.CustomizeGunGUI.Enabled
local LEGACY_FRAMES = { "AttachmentsFrame", "MainDisplayFrame" }

local current: any = nil
local uninstall: (() -> ())? = nil

-- Exactly one ScreenGui named CustomizeGunGUI must exist (WeaponInput/WeaponFireMod
-- look it up by name). Reuse it if present (legacy template, or the ScreenGui this
-- script lives in); otherwise create it.
local function prepareGui(explicit: ScreenGui?, legacyMode: string): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = explicit or playerGui:FindFirstChild(GUI_NAME)
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = GUI_NAME
		gui.ResetOnSpawn = false
		gui.Parent = playerGui
	end
	gui = gui :: ScreenGui
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	for _, name in ipairs(LEGACY_FRAMES) do
		local frame = gui:FindFirstChild(name)
		if frame and frame:IsA("GuiObject") then
			if legacyMode == "destroy" then
				frame:Destroy()
			elseif legacyMode ~= "keep" then
				frame.Visible = false
			end
		end
	end
	local stale = gui:FindFirstChild("CustomizeRoot")
	if stale then
		stale:Destroy()
	end
	return gui
end

local function findSound(gui: Instance, name: string): Sound?
	local sound = gui:FindFirstChild(name)
	return if sound and sound:IsA("Sound") then sound else nil
end

-- options: any Config keys, plus
--   gui          ScreenGui to render into (default: PlayerGui.CustomizeGunGUI / created)
--   legacyFrames "hide" (default) | "destroy" | "keep"  — legacy template frames
--   attachments  GunAttachments system (default: SPHAttachments)
--   hooks        { getEquippedWeapon?, resolveGunModel?, getSourceModel?, submit?,
--                  onConfirmed? }  — override any Bridge behaviour
--   install      false to skip SPH event wiring (tests / custom hosts)
function CustomizeUI.start(options: { [string]: any }?)
	local opts = options or {}
	CustomizeUI.stop()

	local config = Config.resolve(opts)
	local attachments = opts.attachments
		or require(script:FindFirstAncestor("Modules").Weapons.Attachments.SPHAttachments)
	local hooks = opts.hooks or {}
	local gui = prepareGui(opts.gui, opts.legacyFrames or "hide")

	local viewFactory = config.view or View.new
	local view = viewFactory({
		gui = gui,
		config = config,
		sounds = {
			hover = findSound(gui, "Hover"),
			select = findSound(gui, "Select"),
			deselect = findSound(gui, "Deselect"),
		},
	})

	local viewport = view.GetViewport and view:GetViewport() or nil
	local preview = if viewport
		then Preview.new({
			viewport = viewport,
			attachments = attachments,
			getSourceModel = hooks.getSourceModel or Bridge.getSourceModel,
			config = config.preview,
		})
		else nil

	local environmentOptions = table.clone(config.environment)
	environmentOptions.setPromptsEnabled = hooks.setPromptsEnabled or Bridge.setPromptsEnabled
	local environment = Environment.new(environmentOptions)

	local controller = Controller.new({
		config = config,
		attachments = attachments,
		gui = gui,
		view = view,
		preview = preview,
		environment = environment,
		getEquippedWeapon = hooks.getEquippedWeapon or Bridge.getEquippedWeapon,
		resolveGunModel = hooks.resolveGunModel or config.resolveGunModel or Bridge.resolveGunModel,
		submit = hooks.submit or Bridge.submit,
		onConfirmed = function(tool, loadout)
			local custom = hooks.onConfirmed or config.onConfirmed
			if custom then
				custom(tool, loadout)
			end
			Bridge.onConfirmed(tool, loadout)
		end,
	})

	if opts.install ~= false then
		uninstall = Bridge.install(controller)
	end
	current = controller
	return controller
end

-- Tears down the running controller (if any).
function CustomizeUI.stop()
	if uninstall then
		uninstall()
		uninstall = nil
	end
	if current then
		current:Destroy()
		current = nil
	end
end

function CustomizeUI.get()
	return current
end

return CustomizeUI
