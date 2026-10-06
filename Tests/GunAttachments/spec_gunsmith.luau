-- Gunsmith: View/Gunsmith on the Studio hierarchy + the controller's Test Loadout flow.
-- Run via run.py.
local Mocks = require("./mocks")
local G = require("./gui_globals")
local Config = require("./Customize/Config")
local Controller = require("./Customize/Controller")
local GunsmithView = require("./Customize/View/Gunsmith")
local PresetBook = require("./Presets/PresetBook")

local make = Mocks.make

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label or "value", tostring(expected), tostring(actual)), 2)
	end
end

-- The hierarchy from the Gunsmith references (HUD.GunGUIs.Gunsmith).
local function gunsmithGui(options)
	options = options or {}
	local itemChildren = {
		make("TextButton", { Name = "InvisibleButton" }),
		make("TextLabel", { Name = "AttachmentName", Text = "LVPO", TextColor3 = G.Color3.new(1, 1, 1) }),
	}
	if options.selectedMarker then
		table.insert(itemChildren, make("Frame", { Name = "Selected", Visible = false }))
	end
	local function button(name)
		return make("TextButton", { Name = name })
	end
	return make("ScreenGui", { Name = "Gunsmith" }, {
		make("Frame", { Name = "Container" }, {
			make("Frame", { Name = "WeaponViewport" }, { make("ViewportFrame", { Name = "Viewport" }) }),
			make("Frame", { Name = "General" }, {
				make("Frame", { Name = "Stats" }),
				make("TextLabel", { Name = "WeaponName", Text = "" }),
				make("TextLabel", { Name = "WeaponType", Text = "" }),
				button("ClearAllAtachments"), button("CancelLoadout"), button("ApplyLoadout"),
				button("TestLoadout"),
				-- a frame-styled button: the GuiButton inside is used
				make("Frame", { Name = "SaveLoadout" }, { make("ImageButton", { Name = "Hitbox" }) }),
			}),
			make("Frame", { Name = "Attachments" }, {
				make("TextButton", { Name = "BackToCategoryAttachments", Visible = true }),
				make("Frame", { Name = "Attachments" }, {
					make("ScrollingFrame", { Name = "AttachmentCategory", Visible = true }, {
						make("Frame", { Name = "AttachmentCategoryTemplate", Visible = true }, {
							make("TextButton", { Name = "InvisibleButton" }),
							make("TextLabel", { Name = "AttachmentName", Text = "None" }),
							make("TextLabel", { Name = "AttachmentType", Text = "OPTIC" }),
						}),
					}),
					make("ScrollingFrame", { Name = "Attachments", Visible = true }, {
						make("Frame", { Name = "AttachmentTemplate", Visible = true }, itemChildren),
					}),
				}),
			}),
		}),
	})
end

local function parts(gui)
	local container = gui.Container
	local lists = container.Attachments.Attachments
	return {
		general = container.General,
		back = container.Attachments.BackToCategoryAttachments,
		categories = lists.AttachmentCategory,
		items = lists.Attachments,
	}
end

local function copies(list)
	local result = {}
	for _, child in ipairs(list:GetChildren()) do
		if child:GetAttribute("CustomizeAuto") then
			table.insert(result, child)
		end
	end
	table.sort(result, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	return result
end

local CATALOG = {
	slots = {
		{ name = "Optics", label = "Optics", allowEmpty = true, options = {
			{ name = "LVPO", label = "LVPO", available = true },
			{ name = "RMR", label = "RMR Dot", available = true },
			{ name = "Thermal", label = "Thermal", available = false, reason = "Too heavy" },
		} },
		{ name = "Muzzle", label = "Muzzle", allowEmpty = true, options = {
			{ name = "Suppressor", label = "Suppressor", available = true },
		} },
	},
}

local function newView(gui, overrides)
	local actions = {}
	local view = GunsmithView.new({ gui = gui, config = Config.resolve(overrides or {}), sounds = {} })
	local names = { "selectSlot", "pick", "clear", "confirm", "close", "testLoadout", "savePreset", "revert" }
	local bound = {}
	for _, name in ipairs(names) do
		bound[name] = function(...) table.insert(actions, { name, ... }) end
	end
	view:Bind(bound)
	return view, actions
end

-- ─── view ─────────────────────────────────────────────────────────────────────

test("isGunsmith recognises the hierarchy; templates hidden; starts on the categories", function()
	local gui = gunsmithGui()
	eq(GunsmithView.isGunsmith(gui), true)
	eq(GunsmithView.isGunsmith(make("ScreenGui", { Name = "CustomizeGunGUI" })), false)
	newView(gui)
	local p = parts(gui)
	eq(p.categories.AttachmentCategoryTemplate.Visible, false, "category template hidden")
	eq(p.items.AttachmentTemplate.Visible, false, "item template hidden")
	eq(p.categories.Visible, true); eq(p.items.Visible, false); eq(p.back.Visible, false)
end)

test("missing() names the exact element; waitUntilReady reports readiness", function()
	local gui = gunsmithGui()
	eq(GunsmithView.missing(gui), nil)
	eq(GunsmithView.waitUntilReady(gui, 0), true)
	gui.Container.Attachments.Attachments.Attachments.AttachmentTemplate:Destroy()
	eq(GunsmithView.missing(gui), "Gunsmith.Container.Attachments.Attachments.Attachments (missing: AttachmentTemplate)")
	eq(GunsmithView.waitUntilReady(gui, 0), false)
	local renamed = gunsmithGui()
	renamed.Container.Attachments.Attachments.AttachmentCategory.Name = "AttachmentCategories"
	eq(GunsmithView.missing(renamed), "Gunsmith.Container.Attachments.Attachments (missing: AttachmentCategory)")
end)

test("one category per slot: type label, picked attachment or None", function()
	local gui = gunsmithGui()
	local view = newView(gui)
	view:SetWeapon("M4A1", { weaponType = "Rifle" })
	view:SetCatalog(CATALOG)
	view:SetSelection({ Optics = "RMR" })
	local p = parts(gui)
	eq(p.general.WeaponName.Text, "M4A1"); eq(p.general.WeaponType.Text, "Rifle")
	local rows = copies(p.categories)
	eq(#rows, 2)
	eq(rows[1].AttachmentType.Text, "OPTICS"); eq(rows[1].AttachmentName.Text, "RMR Dot", "display label")
	eq(rows[2].AttachmentType.Text, "MUZZLE"); eq(rows[2].AttachmentName.Text, "None")
	eq(rows[1].Visible, true)
	view:SetWeapon("Glock", nil)
	eq(p.general.WeaponType.Text, "", "no type -> empty")
end)

test("category click opens its list (None first); back returns", function()
	local gui = gunsmithGui()
	local view, actions = newView(gui)
	view:SetCatalog(CATALOG)
	view:SetSelection({})
	local p = parts(gui)
	copies(p.categories)[1].InvisibleButton.MouseButton1Click:Fire()
	eq(actions[1][1], "selectSlot"); eq(actions[1][2], "Optics")
	eq(p.categories.Visible, false); eq(p.items.Visible, true); eq(p.back.Visible, true)
	local items = copies(p.items)
	eq(#items, 4, "None + 3 options")
	eq(items[1].AttachmentName.Text, "None"); eq(items[2].AttachmentName.Text, "LVPO"); eq(items[3].AttachmentName.Text, "RMR Dot")
	eq(items[4]:GetAttribute("Available"), false)
	eq(items[4].AttachmentName.TextTransparency, 0.6, "unavailable dimmed")
	p.back.MouseButton1Click:Fire()
	eq(p.categories.Visible, true); eq(p.items.Visible, false); eq(p.back.Visible, false)
	-- controller's own SetActiveSlot (e.g. on open) doesn't open the list
	view:SetActiveSlot("Muzzle")
	eq(p.items.Visible, false)
end)

test("picking, None and unavailable entries", function()
	local gui = gunsmithGui()
	local view, actions = newView(gui)
	view:SetCatalog(CATALOG)
	view:SetSelection({})
	local p = parts(gui)
	copies(p.categories)[1].InvisibleButton.MouseButton1Click:Fire()
	local items = copies(p.items)
	items[3].InvisibleButton.MouseButton1Click:Fire()
	eq(actions[2][1], "pick"); eq(actions[2][2], "Optics"); eq(actions[2][3], "RMR")
	items[1].InvisibleButton.MouseButton1Click:Fire()
	eq(actions[3][1], "clear"); eq(actions[3][2], "Optics")
	items[4].InvisibleButton.MouseButton1Click:Fire()
	eq(#actions, 3, "unavailable: no action")
end)

test("picked entry: tint without a Selected child, Selected child when designed", function()
	local gui = gunsmithGui()
	local view = newView(gui)
	view:SetCatalog(CATALOG)
	view:SetSelection({ Optics = "LVPO" })
	local p = parts(gui)
	copies(p.categories)[1].InvisibleButton.MouseButton1Click:Fire()
	local items = copies(p.items)
	local original = p.items.AttachmentTemplate.AttachmentName.TextColor3
	eq(items[2]:GetAttribute("Selected"), true)
	eq(items[2].AttachmentName.TextColor3 ~= original, true, "tinted")
	eq(items[1]:GetAttribute("Selected"), false)
	view:SetSelection({})
	eq(items[1]:GetAttribute("Selected"), true, "None marked when empty")
	eq(items[2].AttachmentName.TextColor3 == original, true, "tint removed")
	eq(copies(p.categories)[1].AttachmentName.Text, "None")

	local gui2 = gunsmithGui({ selectedMarker = true })
	local view2 = newView(gui2)
	view2:SetCatalog(CATALOG)
	view2:SetSelection({ Optics = "RMR" })
	local p2 = parts(gui2)
	copies(p2.categories)[1].InvisibleButton.MouseButton1Click:Fire()
	local items2 = copies(p2.items)
	eq(items2[3].Selected.Visible, true); eq(items2[2].Selected.Visible, false)
end)

test("noneItem = false and slots that can't be empty have no None entry", function()
	local gui = gunsmithGui()
	local view = newView(gui, { gunsmith = { noneItem = false } })
	view:SetCatalog(CATALOG)
	copies(parts(gui).categories)[2].InvisibleButton.MouseButton1Click:Fire()
	eq(#copies(parts(gui).items), 1)
	local gui2 = gunsmithGui()
	local view2 = newView(gui2)
	view2:SetCatalog({ slots = { { name = "Magazine", label = "Magazine", allowEmpty = false, options = { { name = "Std", available = true } } } } })
	copies(parts(gui2).categories)[1].InvisibleButton.MouseButton1Click:Fire()
	eq(#copies(parts(gui2).items), 1, "required slot: no None")
end)

test("general buttons: apply, cancel, test, save (random fresh name), clear all", function()
	local gui = gunsmithGui()
	local view, actions = newView(gui, { gunsmith = { randomNameWords = { "Viper" } } })
	view:SetCatalog(CATALOG)
	view:SetSelection({ Optics = "LVPO", Muzzle = "Suppressor" })
	local general = parts(gui).general
	general.ApplyLoadout.MouseButton1Click:Fire()
	general.CancelLoadout.MouseButton1Click:Fire()
	general.TestLoadout.MouseButton1Click:Fire()
	eq(actions[1][1], "confirm"); eq(actions[2][1], "close"); eq(actions[3][1], "testLoadout")
	-- every number but 7 is taken: the random name must be "Viper 7"
	local presets = {}
	for n = 1, 99 do
		if n ~= 7 then table.insert(presets, { name = "Viper " .. n }) end
	end
	view:SetPresets({ presets = presets })
	local found = false
	for _ = 1, 40 do
		table.clear(actions)
		general.SaveLoadout.Hitbox.MouseButton1Click:Fire()
		eq(actions[1][1], "savePreset")
		if actions[1][2] == "Viper 7" then found = true break end
	end
	-- 20 tries per click; across 40 clicks the free name must come up
	eq(found, true, "fresh name picked")
	table.clear(actions)
	general.ClearAllAtachments.MouseButton1Click:Fire()
	eq(#actions, 2, "one clear per picked slot")
	eq(actions[1][1], "clear")
end)

test("new session resets to the categories; Destroy restores the design", function()
	local gui = gunsmithGui()
	local view = newView(gui)
	view:SetCatalog(CATALOG)
	local p = parts(gui)
	copies(p.categories)[1].InvisibleButton.MouseButton1Click:Fire()
	view:SetCatalog(CATALOG)
	eq(p.categories.Visible, true, "back on categories"); eq(#copies(p.items), 0, "old list removed")
	eq(#copies(p.categories), 2, "categories rebuilt, not duplicated")
	view:Destroy()
	eq(#copies(p.categories), 0); eq(p.categories.AttachmentCategoryTemplate.Visible, true)
	eq(p.items.AttachmentTemplate.Visible, true); eq(p.back.Visible, true, "original visibility")
	eq(view:GetViewport() == p.categories, false)
end)

-- ─── controller: weapon type + Test Loadout ──────────────────────────────────

local CONTENT = { Optics = { "LVPO", "RMR" }, Muzzle = { "Suppressor" } }
local function fakeAttachments()
	local a = { saved = {} }
	function a:GetSlots() return { { name = "Optics", order = 1 }, { name = "Muzzle", order = 3 } } end
	function a:ListContent(slot) return CONTENT[slot] or {} end
	function a:CanEquip() return true end
	function a:LoadConfig() return {} end
	function a:GetContentFolder() return nil end
	function a:CheckSelection() return nil end
	function a:GetCapacity() return nil end
	function a:GetLoadout(tool) return table.clone(self.saved[tool] or {}) end
	function a:SetLoadout(tool, loadout) self.saved[tool] = table.clone(loadout) end
	function a:SanitizeLoadout(raw)
		local clean = {}
		for slot, name in pairs(raw or {}) do
			if CONTENT[slot] and table.find(CONTENT[slot], name) then clean[slot] = name end
		end
		return clean
	end
	return a
end

local function fakeTest()
	local ended = Mocks.newSignal()
	local t = { calls = {}, testing = false, reply = { ok = true }, ended = ended }
	function t.invoke(action, ...)
		table.insert(t.calls, { action, ... })
		if action == "start" and t.reply.ok then t.testing = true end
		if action == "stop" then t.testing = false end
		return t.reply
	end
	function t.isTesting() return t.testing end
	function t.finish(reason) t.testing = false; ended:Fire(reason) end
	return t
end

local function fakeHud()
	local hud = { shown = false }
	function hud:Show() self.shown = true end
	function hud:Hide() self.shown = false end
	function hud:Destroy() self.shown = false end
	return hud
end

local function setup(options)
	options = options or {}
	local tool = make("Tool", { Name = "M4" })
	local equipped = tool
	local attachments = fakeAttachments()
	attachments.saved[tool] = { Optics = "LVPO" }
	local gui = gunsmithGui()
	local view = GunsmithView.new({ gui = gui, config = Config.resolve({}), sounds = {} })
	local flashes = {}
	local flash = view.Flash
	view.Flash = function(self, message, kind) table.insert(flashes, message); flash(self, message, kind) end
	local testService = if options.noTest then nil else fakeTest()
	local hud = fakeHud()
	local controller = Controller.new({
		config = Config.resolve({}),
		attachments = attachments,
		gui = gui,
		view = view,
		environment = { Acquire = function() end, Release = function() end, IsActive = function() return false end },
		getEquippedWeapon = function() return equipped end,
		resolveGunModel = function() return make("Model", { Name = "M4" }) end,
		resolveWeaponType = function() return "Rifle" end,
		submit = function() end,
		test = testService,
		testHud = hud,
	})
	return {
		controller = controller, gui = gui, view = view, test = testService, hud = hud, tool = tool,
		flashes = flashes, setEquipped = function(t) equipped = t end,
	}
end

test("controller passes the weapon type to the view", function()
	local env = setup()
	env.controller:Open()
	eq(env.gui.Container.General.WeaponType.Text, "Rifle")
	eq(env.gui.Container.General.WeaponName.Text, "M4")
end)

test("Test: sends the current picks, closes the menu, shows the return button, blocks opening", function()
	local env = setup()
	env.controller:Open()
	env.controller:Pick("Optics", "RMR")
	env.gui.Container.General.TestLoadout.MouseButton1Click:Fire()
	local call = env.test.calls[1]
	eq(call[1], "start"); eq(call[2], env.tool)
	eq(PresetBook.sameLoadout(call[3], { Optics = "RMR" }), true, "unsaved picks are tested")
	eq(env.controller:IsOpen(), false, "menu closed")
	eq(env.gui.Enabled, false)
	eq(env.hud.shown, true, "return button shown")
	eq(env.controller:IsTesting(), true)
	eq(env.controller:Open(), false, "can't open the menu while testing")
end)

test("Return: menu reopens on the real gun with the same unsaved picks", function()
	local env = setup()
	env.controller:Open()
	env.controller:Pick("Optics", "RMR")
	env.controller:Pick("Muzzle", "Suppressor")
	env.controller:TestLoadout()
	env.controller:EndTest() -- what the return button does
	eq(env.test.calls[2][1], "stop")
	eq(env.hud.shown, false, "button hidden")
	eq(env.controller:IsOpen(), true, "menu back")
	eq(env.controller:IsTesting(), false)
	local selection = env.controller:GetSelection()
	eq(selection.Optics, "RMR"); eq(selection.Muzzle, "Suppressor")
	local rows = copies(parts(env.gui).categories)
	eq(rows[1].AttachmentName.Text, "RMR", "categories show the resumed picks")
end)

test("time limit resumes too; death does not reopen", function()
	local env = setup()
	env.controller:Open()
	env.controller:TestLoadout()
	env.test.finish("timeout")
	eq(env.controller:IsOpen(), true, "timeout -> back in the menu")

	local env2 = setup()
	env2.controller:Open()
	env2.controller:TestLoadout()
	env2.setEquipped(nil)
	env2.test.finish("died")
	eq(env2.controller:IsOpen(), false, "died -> stays closed")
	eq(env2.hud.shown, false)
	eq(env2.controller:IsTesting(), false)
end)

test("server refusal keeps the menu open with a message", function()
	local env = setup()
	env.controller:Open()
	env.test.reply = { ok = false, error = "no_zone" }
	env.controller:TestLoadout()
	eq(env.controller:IsOpen(), true)
	eq(env.hud.shown, false)
	eq(env.flashes[#env.flashes], "There is no test area in this place")
	local env2 = setup({ noTest = true })
	env2.controller:Open()
	env2.controller:TestLoadout()
	eq(env2.flashes[#env2.flashes], "Testing is turned off")
end)

test("a test that already ended before the reply arrived is cleaned up", function()
	local env = setup()
	env.controller:Open()
	local invoke = env.test.invoke
	env.test.invoke = function(...)
		local reply = invoke(...)
		env.test.testing = false -- e.g. died right away
		return reply
	end
	env.controller:TestLoadout()
	eq(env.controller:IsTesting(), false)
	eq(env.hud.shown, false)
end)

print(("\ngunsmith: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("gunsmith tests failed")
end
