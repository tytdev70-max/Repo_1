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
-- View/Template is optional: if it is missing (e.g. not copied into Studio) the menu
-- still works with the generated UI instead of failing to load at all.
local TemplateView = nil
do
	local module = script.View:FindFirstChild("Template")
	if module then
		local ok, result = pcall(require, module)
		if ok then
			TemplateView = result
		else
			warn("[CustomizeUI] View.Template failed to load: " .. tostring(result))
		end
	else
		warn("[CustomizeUI] ModuleScript Customize.View.Template not found - the Studio GUI can't be used")
	end
end
local Bridge = require(script.Bridge)

local CustomizeUI = {}

CustomizeUI.Config = Config
CustomizeUI.Controller = Controller
CustomizeUI.View = View
CustomizeUI.TemplateView = TemplateView
CustomizeUI.Bridge = Bridge

local GUI_NAME = "CustomizeGunGUI" -- other scripts read PlayerGui.CustomizeGunGUI.Enabled
local LEGACY_FRAMES = { "AttachmentsFrame", "MainDisplayFrame" }

local current: any = nil
local uninstall: (() -> ())? = nil

-- Exactly one ScreenGui named CustomizeGunGUI must exist (WeaponInput/WeaponFireMod
-- look it up by name). Reuse it if present (legacy template, or the ScreenGui this
-- script lives in); otherwise create it.
local function prepareGui(explicit: ScreenGui?, legacyMode: string, generated: boolean?): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = explicit or playerGui:FindFirstChild(GUI_NAME)
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = GUI_NAME
		gui.ResetOnSpawn = false
		gui.Parent = playerGui
	end
	gui = gui :: ScreenGui
	if not generated then
		return gui -- template mode: the Studio design is used exactly as built
	end
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
--                  onConfirmed?, presets? }  — override any Bridge behaviour
--   install      false to skip SPH event wiring (tests / custom hosts)
function CustomizeUI.start(options: { [string]: any }?)
	local opts = options or {}
	CustomizeUI.stop()

	local config = Config.resolve(opts)
	local attachments = opts.attachments
		or require(script:FindFirstAncestor("Modules").Weapons.Attachments.SPHAttachments)
	local hooks = opts.hooks or {}
	local gui = prepareGui(opts.gui, opts.legacyFrames or "hide", false)
	local viewFactory = config.view
	if not viewFactory then
		if config.ui == "template" and TemplateView and TemplateView.isTemplate(gui) then
			viewFactory = TemplateView.new
		else
			if config.ui == "template" and TemplateView then
				warn("[CustomizeUI] " .. gui:GetFullName() .. " has no template frames "
					.. "(AttachmentsFrame.Padding.AttachmentsColumn, MainDisplayFrame.content.ConfirmButton); "
					.. "using the generated UI")
			end
			prepareGui(gui, opts.legacyFrames or "hide", true)
			viewFactory = View.new
		end
	end
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
		presets = if config.presets.enabled then (hooks.presets or Bridge.presets()) else nil,
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
	gui:SetAttribute("CustomizeUIRunning", true)
	return controller
end

-- Tears down the running controller (if any).
function CustomizeUI.stop()
	if current and current._gui and current._gui.Parent then
		current._gui:SetAttribute("CustomizeUIRunning", nil)
	end
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

-- Prints a checklist of everything the menu needs. Call it from the client
-- (Studio Play mode: command bar set to "Client", or any LocalScript):
--   require(game.ReplicatedStorage.SPH_Assets.Modules.Weapons.UI.Customize).diagnose()
function CustomizeUI.diagnose()
	local lines = {}
	local function check(ok, text)
		table.insert(lines, (if ok then "  [ OK ] " else "  [FAIL] ") .. text)
		return ok
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild(GUI_NAME)
	check(current ~= nil, "menu started (CustomizeUI.start was called)")
	check(gui ~= nil, "PlayerGui." .. GUI_NAME .. " exists")
	if gui then
		local copies = 0
		for _, child in ipairs(playerGui:GetChildren()) do
			if child.Name == GUI_NAME then
				copies += 1
			end
		end
		check(copies == 1, ("exactly one %s in PlayerGui (found %d)"):format(GUI_NAME, copies))
		check(TemplateView ~= nil, "Customize.View.Template module loaded")
		if TemplateView then
			check(TemplateView.isTemplate(gui),
				"template frames present (AttachmentsFrame.Padding.AttachmentsColumn, MainDisplayFrame.content.ConfirmButton)")
		end
		check(current == nil or current._gui == gui, "menu uses this ScreenGui")
		local entry = gui:FindFirstChild(GUI_NAME, true)
		check(entry ~= nil and entry:IsA("LocalScript"), "CustomizeGunGUI LocalScript inside the ScreenGui")
	end
	local handlerOk, handler = pcall(Bridge.handler)
	if check(handlerOk, "CustomizeGunHandler loaded" .. (if handlerOk then "" else ": " .. tostring(handler))) then
		local count = handler.GetPromptCount and handler.GetPromptCount() or -1
		check(count ~= 0, ("customize prompts found (ProximityPrompt inside a part named ProxPart): %d"):format(count))
		check(handler.IsBound == nil or handler.IsBound(), "prompt connected to the menu (BindCallbacks)")
	end
	local character = player and player.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	check(tool ~= nil, "a Tool is equipped" .. (if tool then " (" .. tool.Name .. ")" else ""))
	if tool then
		check(tool:FindFirstChild("SPH_Weapon") ~= nil, "equipped Tool has an SPH_Weapon child")
	end
	print("[CustomizeUI] diagnose:\n" .. table.concat(lines, "\n"))
	return lines
end

return CustomizeUI
