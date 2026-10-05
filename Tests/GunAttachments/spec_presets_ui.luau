-- Presets on the client: Customize/Controller preset flow + View/Template presets UI.
-- Run via run.py. The fake server below uses the real PresetBook rules.
local Mocks = require("./mocks")
local G = require("./gui_globals")
local Config = require("./Customize/Config")
local Controller = require("./Customize/Controller")
local TemplateView = require("./Customize/View/Template")
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
local function same(a, b)
	return PresetBook.sameLoadout(a, b)
end

-- ─── fakes ────────────────────────────────────────────────────────────────────

local SLOTS = { { name = "Optics", order = 1 }, { name = "Muzzle", order = 3 } }
local CONTENT = { Optics = { "ACOG", "RedDot" }, Muzzle = { "Compensator", "Suppressor" } }

local function fakeAttachments()
	local attachments = { saved = {} }
	function attachments:GetSlots() return SLOTS end
	function attachments:ListContent(slot) return CONTENT[slot] or {} end
	function attachments:CanEquip() return true end
	function attachments:LoadConfig() return {} end
	function attachments:GetContentFolder() return nil end
	function attachments:CheckSelection() return nil end
	function attachments:GetCapacity() return nil end
	function attachments:GetLoadout(tool) return table.clone(self.saved[tool] or {}) end
	function attachments:SetLoadout(tool, loadout) self.saved[tool] = table.clone(loadout) end
	function attachments:SanitizeLoadout(raw)
		local clean = {}
		for slot, name in pairs(raw or {}) do
			if CONTENT[slot] and table.find(CONTENT[slot], name) then
				clean[slot] = name
			end
		end
		return clean
	end
	return attachments
end

-- In-memory server: list/save/rename/delete like LoadoutPresets (equipped gun "M4").
local function fakeServer()
	local server = { book = PresetBook.new(), calls = {}, carried = nil, max = nil, deferred = false, pending = {} }
	local function state(extra)
		local list, active = server.book:List("M4")
		local result = { ok = true, gun = "M4", presets = list, active = active, carried = server.carried, max = server.max, persistent = true }
		for k, v in pairs(extra or {}) do result[k] = v end
		return result
	end
	function server.invoke(action, a, b)
		table.insert(server.calls, { action, a, b })
		if server.deferred then
			table.insert(server.pending, coroutine.running())
			local reply = coroutine.yield()
			if reply then
				return reply
			end
		end
		if server.failWith then
			return { ok = false, error = server.failWith }
		end
		if action == "list" then
			return state()
		elseif action == "save" then
			local ok, err, name = server.book:Save("M4", a, b, { maxPresets = server.max })
			if not ok then return { ok = false, error = err } end
			return state({ saved = name })
		elseif action == "rename" then
			local ok, err, name = server.book:Rename("M4", a, b)
			if not ok then return { ok = false, error = err } end
			return state({ renamed = name })
		elseif action == "delete" then
			if not server.book:Delete("M4", a) then return { ok = false, error = "missing" } end
			return state()
		end
		return { ok = false, error = "bad_request" }
	end
	return server
end

local function fakeView()
	local view = { flashes = {}, presetStates = {}, sounds = {} }
	function view:Bind(actions) self.actions = actions end
	function view:SetWeapon() end
	function view:SetCatalog(catalog) self.catalog = catalog end
	function view:SetActiveSlot() end
	function view:SetSelection(loadout) self.selection = loadout end
	function view:SetSummary(summary) self.summary = summary end
	function view:Flash(message, kind) table.insert(self.flashes, { message, kind }) end
	function view:PlaySound(kind) table.insert(self.sounds, kind) end
	function view:GetViewport() return nil end
	function view:Destroy() end
	function view:SetPresets(state) table.insert(self.presetStates, state) end
	function view:lastPresets() return self.presetStates[#self.presetStates] end
	function view:lastFlash() local f = self.flashes[#self.flashes]; return f and f[1] end
	return view
end

local function fakeEnvironment()
	local active = false
	return {
		Acquire = function() active = true end,
		Release = function() active = false end,
		IsActive = function() return active end,
	}
end

local function setup(options)
	options = options or {}
	local tool = make("Tool", { Name = "M4" })
	local attachments = fakeAttachments()
	attachments.saved[tool] = options.saved or {}
	local server = options.server or fakeServer()
	local view = fakeView()
	local submits = {}
	local controller = Controller.new({
		config = Config.resolve(options.config or {}),
		attachments = attachments,
		gui = make("ScreenGui", { Name = "CustomizeGunGUI" }),
		view = view,
		preview = nil,
		environment = fakeEnvironment(),
		getEquippedWeapon = function() return tool end,
		resolveGunModel = function() return make("Model", { Name = "M4" }) end,
		submit = function(t, loadout, presetName)
			table.insert(submits, { tool = t, loadout = loadout, preset = presetName })
		end,
		presets = if options.noPresets then nil else server,
	})
	return { controller = controller, server = server, view = view, submits = submits, tool = tool, attachments = attachments }
end

local CQB = { Optics = "RedDot", Muzzle = "Compensator" }
local LONG = { Optics = "ACOG", Muzzle = "Suppressor" }

-- ─── controller ───────────────────────────────────────────────────────────────

test("opening lists the gun's presets (loading first, then the list)", function()
	local server = fakeServer()
	server.book:Save("M4", "CQB", CQB)
	server.book:SetActive("M4", "CQB")
	local env = setup({ server = server, saved = CQB })
	server.carried = "CQB"
	env.controller:Open()
	eq(env.server.calls[1][1], "list")
	local loadingSeen = false
	for _, state in ipairs(env.view.presetStates) do
		if state.loading then loadingSeen = true end
	end
	eq(loadingSeen, true, "loading state pushed first")
	local state = env.view:lastPresets()
	eq(state.available, true); eq(state.loading, false); eq(#state.presets, 1)
	local cqb = state.presets[1]
	eq(cqb.name, "CQB"); eq(cqb.active, true); eq(cqb.carried, true)
	eq(cqb.matchesSelection, true, "selection = gun's saved loadout = preset")
	eq(cqb.summary, "RedDot, Compensator", "summary in slot order")
	eq(state.countText, "1 loadouts")
end)

test("save stores the current picks without touching the gun; default names", function()
	local env = setup({ saved = {} })
	env.controller:Open()
	env.controller:Select("Optics", "RedDot")
	env.view.actions.savePreset("") -- empty -> default name
	local call = env.server.calls[#env.server.calls]
	eq(call[1], "save"); eq(call[2], "Loadout 1")
	eq(same(call[3], { Optics = "RedDot" }), true, "current selection sent")
	eq(#env.submits, 0, "gun not changed")
	eq(env.view:lastFlash(), 'Saved "Loadout 1"')
	eq(#env.view:lastPresets().presets, 1)
	env.view.actions.savePreset("   ")
	eq(env.server.calls[#env.server.calls][2], "Loadout 2", "next free default name")
	env.controller:RenamePreset("Loadout 1", "Loadout 3")
	env.view.actions.savePreset(nil)
	eq(env.server.calls[#env.server.calls][2], "Loadout 4", "skips taken names")
	env.view.actions.savePreset("  CQB ")
	eq(env.server.calls[#env.server.calls][2], "CQB", "typed name trimmed")
end)

test("load puts a preset in the menu only; apply sends it with the preset name", function()
	local server = fakeServer()
	server.book:Save("M4", "Long", LONG)
	local env = setup({ server = server, saved = CQB })
	env.controller:Open()
	env.view.actions.loadPreset("Long")
	eq(same(env.controller:GetSelection(), LONG), true, "loaded into selection")
	eq(env.view.summary.dirty, true, "shows as unsaved")
	eq(#env.submits, 0, "not applied")
	eq(env.view:lastPresets().presets[1].matchesSelection, true)

	env.controller:Revert()
	env.view.actions.applyPreset("Long")
	eq(#env.submits, 1)
	eq(env.submits[1].preset, "Long", "preset name sent to the server")
	eq(same(env.submits[1].loadout, LONG), true)
	eq(same(env.attachments.saved[env.tool], LONG), true, "local copy updated like a confirm")
	eq(env.controller:IsOpen(), false, "closes like Confirm")
	local state = env.view:lastPresets()
	eq(state.active, "Long", "optimistic: active"); eq(state.carried, "Long", "optimistic: on this gun")
end)

test("apply works even when the gun already has the same attachments", function()
	local server = fakeServer()
	server.book:Save("M4", "CQB", CQB)
	local env = setup({ server = server, saved = CQB, config = { behaviour = { confirmWhenUnchanged = false } } })
	env.controller:Open()
	env.controller:ApplyPreset("CQB")
	eq(#env.submits, 1, "not skipped as 'unchanged'")
	eq(env.submits[1].preset, "CQB")
end)

test("normal confirm: changing a gun that carries the active preset clears it; same picks keep it", function()
	local server = fakeServer()
	server.book:Save("M4", "CQB", CQB)
	server.book:SetActive("M4", "CQB")
	server.carried = "CQB"
	local env = setup({ server = server, saved = CQB, config = { behaviour = { closeOnConfirm = false } } })
	env.controller:Open()
	env.controller:Confirm()
	eq(env.submits[1].preset, nil, "no preset name on a normal confirm")
	eq(env.view:lastPresets().active, "CQB", "same attachments: still active")
	env.controller:Select("Optics", "ACOG")
	env.controller:Confirm()
	local state = env.view:lastPresets()
	eq(state.active, nil, "changed: active cleared"); eq(state.carried, nil)
end)

test("delete and rename update the list; errors become messages", function()
	local server = fakeServer()
	server.book:Save("M4", "A", CQB); server.book:Save("M4", "B", LONG)
	local env = setup({ server = server })
	env.controller:Open()
	env.view.actions.renamePreset("A", "B")
	eq(env.view:lastFlash(), "A loadout with that name already exists")
	env.view.actions.renamePreset("A", "Alpha")
	eq(env.view:lastPresets().presets[1].name, "Alpha")
	eq(env.view:lastFlash(), 'Renamed to "Alpha"')
	env.view.actions.deletePreset("B")
	eq(#env.view:lastPresets().presets, 1)
	eq(env.view:lastFlash(), 'Deleted "B"')
	server.max = 1
	env.controller:SavePreset("New")
	eq(env.view:lastFlash(), "This gun has the maximum number of loadouts")
	env.controller:RefreshPresets() -- failed requests carry no state; the next list does
	eq(env.view:lastPresets().canSave, false); eq(env.view:lastPresets().countText, "1 / 1 loadouts")
	env.view.actions.loadPreset("Ghost")
	eq(env.view:lastFlash(), "That loadout no longer exists")
	server.failWith = "loading"
	env.controller:RefreshPresets()
	local state = env.view:lastPresets()
	eq(state.error, "Loadouts are still loading, try again in a moment", "list error shown in the panel")
end)

test("replies arriving after the menu closed are ignored", function()
	local server = fakeServer()
	server.book:Save("M4", "CQB", CQB)
	server.deferred = true
	local env = setup({ server = server })
	env.controller:Open()
	eq(#server.pending, 1, "list request waiting")
	local before = #env.view.presetStates
	env.controller:Close("user")
	server.deferred = false
	coroutine.resume(server.pending[1])
	eq(#env.view.presetStates, before, "no update from the stale reply")
	eq(env.controller:GetPresets().loading, true, "state not filled in")
end)

test("without the presets service the feature reports unavailable", function()
	local env = setup({ noPresets = true })
	env.controller:Open()
	eq(env.view:lastPresets().available, false)
	env.controller:SavePreset("X")
	eq(env.view:lastFlash(), "Loadouts are turned off")
end)

-- ─── template view ────────────────────────────────────────────────────────────

local function presetTemplateGui()
	local item = make("Frame", { Name = "item" }, {
		make("Frame", { Name = "padding" }, { make("TextLabel", { Name = "itemname", Text = "RedDot" }) }),
	})
	local column = make("Frame", { Name = "column", LayoutOrder = 1 }, {
		make("Frame", { Name = "columnheading" }, { make("TextLabel", { Name = "title" }) }),
		make("Frame", { Name = "display" }, { make("ScrollingFrame", { Name = "items" }, { item }) }),
	})
	local presetTemplate = make("Frame", { Name = "PresetTemplate", Visible = true }, {
		make("TextLabel", { Name = "PresetName", Text = "" }),
		make("Frame", { Name = "Info" }, { make("TextLabel", { Name = "PresetAttachments", Text = "" }) }),
		make("Frame", { Name = "ActiveBadge", Visible = false }),
		make("Frame", { Name = "CarriedBadge", Visible = false }),
		make("TextButton", { Name = "ApplyButton", Text = "Apply" }),
		make("TextButton", { Name = "LoadButton", Text = "Load" }),
		make("TextButton", { Name = "RenameButton", Text = "Rename" }),
		make("TextButton", { Name = "DeleteButton", Text = "Delete" }),
	})
	return make("ScreenGui", { Name = "CustomizeGunGUI" }, {
		make("Frame", { Name = "AttachmentsFrame" }, {
			make("Frame", { Name = "Padding" }, { make("Frame", { Name = "AttachmentsColumn" }, { column }) }),
		}),
		make("Frame", { Name = "MainDisplayFrame" }, {
			make("Frame", { Name = "content" }, {
				make("TextButton", { Name = "ConfirmButton" }),
				make("TextBox", { Name = "PresetNameBox", Text = "" }),
				make("TextButton", { Name = "SavePresetButton", Visible = true }),
				make("TextButton", { Name = "LoadoutsButton", Visible = true }),
			}),
		}),
		make("Frame", { Name = "LoadoutsFrame", Visible = false }, {
			make("TextButton", { Name = "LoadoutsCloseButton" }),
			make("TextLabel", { Name = "PresetCount", Text = "" }),
			make("TextLabel", { Name = "PresetsEmpty", Text = "", Visible = false }),
			make("ScrollingFrame", { Name = "PresetList" }, { presetTemplate }),
		}),
	})
end

local function templateView(gui)
	local actions = {}
	local view = TemplateView.new({ gui = gui, config = Config.resolve({}), sounds = {} })
	local function record(name)
		return function(...) table.insert(actions, { name, ... }) end
	end
	view:Bind({
		savePreset = record("savePreset"), applyPreset = record("applyPreset"), loadPreset = record("loadPreset"),
		deletePreset = record("deletePreset"), renamePreset = record("renamePreset"), refreshPresets = record("refreshPresets"),
		pick = record("pick"), clear = record("clear"), confirm = record("confirm"), close = record("close"), revert = record("revert"),
	})
	return view, actions
end

local function presetItems(gui)
	local list = {}
	for _, child in ipairs(gui.LoadoutsFrame.PresetList:GetChildren()) do
		if child:GetAttribute("Preset") then
			list[child:GetAttribute("Preset")] = child
		end
	end
	return list
end

local STATE = {
	available = true, loading = false, countText = "2 loadouts",
	presets = {
		{ name = "CQB", summary = "RedDot, Compensator", active = true, carried = true },
		{ name = "Long", summary = "ACOG, Suppressor", active = false, carried = false },
	},
}

test("template: one copy per preset with labels and badges; prototype hidden", function()
	local gui = presetTemplateGui()
	local view = templateView(gui)
	eq(gui.LoadoutsFrame.PresetList.PresetTemplate.Visible, false, "prototype hidden")
	view:SetPresets(STATE)
	local items = presetItems(gui)
	assert(items.CQB and items.Long, "both presets shown")
	eq(items.CQB.PresetName.Text, "CQB")
	eq(items.CQB.Info.PresetAttachments.Text, "RedDot, Compensator", "found anywhere inside the copy")
	eq(items.CQB.ActiveBadge.Visible, true); eq(items.CQB.CarriedBadge.Visible, true)
	eq(items.Long.ActiveBadge.Visible, false)
	eq(items.Long.LayoutOrder, 2)
	eq(gui.LoadoutsFrame.PresetCount.Text, "2 loadouts")
	eq(gui.LoadoutsFrame.PresetsEmpty.Visible, false)
	view:SetPresets({ available = true, presets = { STATE.presets[2] }, countText = "1 loadouts" })
	items = presetItems(gui)
	eq(items.CQB, nil, "old copies replaced"); assert(items.Long)
	view:SetPresets({ available = true, presets = {}, countText = "0 loadouts" })
	eq(gui.LoadoutsFrame.PresetsEmpty.Visible, true)
	eq(gui.LoadoutsFrame.PresetsEmpty.Text, "No saved loadouts for this gun yet")
end)

test("template: buttons send actions; delete needs two clicks", function()
	local gui = presetTemplateGui()
	local view, actions = templateView(gui)
	view:SetPresets(STATE)
	local long = presetItems(gui).Long
	long.ApplyButton.MouseButton1Click:Fire()
	long.LoadButton.MouseButton1Click:Fire()
	eq(actions[1][1], "applyPreset"); eq(actions[1][2], "Long")
	eq(actions[2][1], "loadPreset"); eq(actions[2][2], "Long")
	local box = gui.MainDisplayFrame.content.PresetNameBox
	box.Text = "Sniper"
	long.RenameButton.MouseButton1Click:Fire()
	eq(actions[3][1], "renamePreset"); eq(actions[3][2], "Long"); eq(actions[3][3], "Sniper")
	eq(box.Text, "", "box cleared")
	long.DeleteButton.MouseButton1Click:Fire()
	eq(#actions, 3, "first click only arms")
	eq(long.DeleteButton.Text, "Sure?")
	long.DeleteButton.MouseButton1Click:Fire()
	eq(actions[4][1], "deletePreset"); eq(actions[4][2], "Long")
	-- the arm times out
	local cqb = presetItems(gui).CQB
	table.clear(G.delayed)
	cqb.DeleteButton.MouseButton1Click:Fire()
	for _, fn in ipairs(G.delayed) do fn() end
	eq(cqb.DeleteButton.Text, "Delete", "text restored")
	cqb.DeleteButton.MouseButton1Click:Fire()
	eq(#actions, 4, "re-armed, not deleted")
end)

test("template: save button, loadouts screen toggle, reset per session", function()
	local gui = presetTemplateGui()
	local view, actions = templateView(gui)
	local content = gui.MainDisplayFrame.content
	content.PresetNameBox.Text = "  CQB "
	content.SavePresetButton.MouseButton1Click:Fire()
	eq(actions[1][1], "savePreset"); eq(actions[1][2], "  CQB ", "raw text (controller trims)")
	eq(content.PresetNameBox.Text, "")
	content.LoadoutsButton.MouseButton1Click:Fire()
	eq(gui.LoadoutsFrame.Visible, true)
	eq(actions[2][1], "refreshPresets", "opening the screen refreshes")
	gui.LoadoutsFrame.LoadoutsCloseButton.MouseButton1Click:Fire()
	eq(gui.LoadoutsFrame.Visible, false)
	content.LoadoutsButton.MouseButton1Click:Fire()
	view:SetCatalog({ slots = {} })
	eq(gui.LoadoutsFrame.Visible, false, "new session starts on the customize screen")
end)

test("template: unavailable hides the controls; Destroy restores the design", function()
	local gui = presetTemplateGui()
	local view = templateView(gui)
	local content = gui.MainDisplayFrame.content
	view:SetPresets({ available = false, presets = {} })
	eq(content.SavePresetButton.Visible, false); eq(content.LoadoutsButton.Visible, false)
	eq(content.PresetNameBox.Visible, true == false, "box hidden too")
	view:SetPresets(STATE)
	eq(content.SavePresetButton.Visible, true, "back when available")
	view:Destroy()
	eq(gui.LoadoutsFrame.PresetList.PresetTemplate.Visible, true, "prototype visibility restored")
	local count = 0
	for _ in pairs(presetItems(gui)) do count += 1 end
	eq(count, 0, "copies removed")
end)

print(("\npresets ui: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("preset ui tests failed")
end
