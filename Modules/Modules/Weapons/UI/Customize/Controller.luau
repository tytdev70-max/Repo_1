--!nonstrict
-- Customize/Controller
-- Orchestrates one customization menu: state machine, session building, user intent
-- → selection → view/preview, and confirm. Game-agnostic: everything SPH-specific
-- (which tool is equipped, where the gun model is, how to submit, what to refresh
-- after confirm) is injected — see Customize/Bridge for SPH's implementations.
--
-- States: "closed" → "opening" (one frame, re-validates the weapon) → "open" → "closed"
--
-- deps:
--   config           resolved config (Customize/Config)
--   attachments      GunAttachments system
--   gui              ScreenGui whose Enabled == menu open (other scripts read this)
--   view             view object (Customize/View interface)
--   preview          Customize/Preview or nil
--   environment      Customize/Environment
--   getEquippedWeapon function() -> Tool?
--   resolveGunModel  function(tool) -> Model?   (mount-point checks)
--   submit           function(tool, loadout, presetName?)  (send to server)
--   onConfirmed      function(tool, loadout)?   (local refresh after confirm)
--   presets          { invoke(action, ...) -> state }?  saved loadouts (Bridge.presets)

local UserInputService = game:GetService("UserInputService")

local Catalog = require(script.Parent.Catalog)
local Selection = require(script.Parent.Selection)
local Signal = require(script.Parent.Signal)

local Controller = {}
Controller.__index = Controller

local sameLoadout -- defined with the preset helpers below

function Controller.new(deps: { [string]: any })
	local self = setmetatable({}, Controller)
	self._deps = deps
	self._config = deps.config
	self._attachments = deps.attachments
	self._gui = deps.gui
	self._view = deps.view
	self._preview = deps.preview
	self._environment = deps.environment
	self._state = "closed"
	self._token = 0
	self._tool = nil
	self._catalog = nil
	self._selection = nil
	self._activeSlot = nil
	self._settingEnabled = false
	self._connections = {}
	self._presets = deps.presets
	self._presetState = nil -- last server state for the open session
	self._presetToken = 0 -- bumps per session; stale replies are ignored
	self._test = deps.test -- Test Loadout service (Bridge.test) or nil
	self._testHud = deps.testHud
	self._testing = nil -- while testing: { tool, selection, activeSlot } to resume with
	self._testRequest = false

	self.Opened = Signal.new() -- (tool)
	self.Closed = Signal.new() -- (reason)
	self.Confirmed = Signal.new() -- (tool, loadout)
	self.SelectionChanged = Signal.new() -- (loadout, change)
	self.PresetsChanged = Signal.new() -- (presetViewState)
	self.TestStarted = Signal.new() -- (tool)
	self.TestEnded = Signal.new() -- (reason: "returned" | "timeout" | "died" | "left" | ...)

	self._view:Bind({
		selectSlot = function(slot)
			self:SelectSlot(slot)
		end,
		pick = function(slot, name)
			self:Pick(slot, name)
		end,
		clear = function(slot)
			self:ClearSlot(slot)
		end,
		confirm = function()
			self:Confirm()
		end,
		revert = function()
			self:Revert()
		end,
		close = function()
			self:Close("user")
		end,
		savePreset = function(name)
			self:SavePreset(name)
		end,
		applyPreset = function(name)
			self:ApplyPreset(name)
		end,
		loadPreset = function(name)
			self:LoadPreset(name)
		end,
		deletePreset = function(name)
			self:DeletePreset(name)
		end,
		renamePreset = function(oldName, newName)
			self:RenamePreset(oldName, newName)
		end,
		refreshPresets = function()
			self:RefreshPresets()
		end,
		testLoadout = function()
			self:TestLoadout()
		end,
		endTest = function()
			self:EndTest()
		end,
	})

	if self._test and self._test.ended then
		table.insert(self._connections, self._test.ended:Connect(function(reason)
			self:_onTestEnded(reason)
		end))
	end

	-- Anything else disabling the ScreenGui closes the menu (legacy contract).
	table.insert(self._connections, self._gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not self._settingEnabled and not self._gui.Enabled and self._state ~= "closed" then
			self:Close("external")
		end
	end))

	local closeKeys = {}
	for _, name in ipairs(self._config.behaviour.closeKeys or {}) do
		local ok, code = pcall(function()
			return (Enum.KeyCode :: any)[name]
		end)
		if ok and code then
			closeKeys[code] = true
		end
	end
	if next(closeKeys) then
		table.insert(self._connections, UserInputService.InputBegan:Connect(function(input)
			if self._state == "open" and closeKeys[input.KeyCode] then
				self:Close("user")
			end
		end))
	end

	self:_setGuiEnabled(false)
	return self
end

function Controller:_setGuiEnabled(enabled: boolean)
	self._settingEnabled = true
	self._gui.Enabled = enabled
	self._gui.DisplayOrder = if enabled then self._config.behaviour.displayOrder else 0
	self._settingEnabled = false
end

-- ─── queries ────────────────────────────────────────────────────────────────

function Controller:IsOpen(): boolean
	return self._state ~= "closed"
end

function Controller:GetState(): string
	return self._state
end

function Controller:GetTool(): Tool?
	return self._tool
end

function Controller:GetSelection(): { [string]: string }
	return if self._selection then self._selection:GetAll() else {}
end

function Controller:GetCatalog()
	return self._catalog
end

-- ─── session ────────────────────────────────────────────────────────────────

function Controller:_summary()
	local selection = self._selection
	if not selection then
		return
	end
	self._view:SetSummary({
		count = selection:Count(),
		capacity = self._attachments:GetCapacity(self._tool),
		dirty = selection:IsDirty(),
	})
end

function Controller:_onSelectionChanged(change)
	local loadout = self._selection:GetAll()
	self._view:SetSelection(loadout)
	if self._preview then
		self._preview:SetLoadout(loadout)
	end
	self:_summary()
	if self._presetState then
		self:_pushPresets() -- "matches the current selection" flags
	end
	if change.displaced and #change.displaced > 0 then
		self._view:Flash("Removed " .. table.concat(change.displaced, ", ") .. " (not compatible with this pick)", "info")
	end
	self.SelectionChanged:Fire(loadout, change)
end

function Controller:_buildSession(tool: Tool)
	local deps, config = self._deps, self._config
	if self._selection then
		self._selection:Destroy()
	end
	self._tool = tool

	local model = deps.resolveGunModel and deps.resolveGunModel(tool) or nil
	local catalog = Catalog.build({
		attachments = self._attachments,
		tool = tool,
		model = model,
		slotMeta = config.slots,
		showUnavailable = config.behaviour.showUnavailable,
		showEmptySlots = config.behaviour.showEmptySlots,
		slotFilter = config.slotFilter,
	})
	self._catalog = catalog

	local selection = Selection.new({
		check = function(loadout, slot, name)
			return self._attachments:CheckSelection(tool, loadout, slot, name)
		end,
		allowEmpty = function(slot)
			local entry = Catalog.find(catalog, slot)
			return entry == nil or entry.allowEmpty
		end,
	})
	self._selection = selection

	local weaponType = nil
	if deps.resolveWeaponType then
		local ok, result = pcall(deps.resolveWeaponType, tool)
		weaponType = if ok and type(result) == "string" then result else nil
	end
	self._view:SetWeapon(tool.Name, { tool = tool, weaponType = weaponType })
	self._view:SetCatalog(catalog)
	-- Saved picks are loaded as-is, even for slots this weapon doesn't show (the
	-- legacy menu kept and re-sent them too; the server sanitizes).
	selection:Load(self._attachments:GetLoadout(tool))
	selection.Changed:Connect(function(change)
		self:_onSelectionChanged(change)
	end)

	local keep = self._activeSlot and Catalog.find(catalog, self._activeSlot)
	local first = catalog.slots[1]
	self._activeSlot = if keep then keep.name elseif first then first.name else nil
	self._view:SetSelection(selection:GetAll())
	self._view:SetActiveSlot(self._activeSlot)

	if self._preview then
		self._preview:Show(tool)
		self._preview:SetLoadout(selection:GetAll())
	end
	self:_summary()
	self._presetToken += 1
	self:RefreshPresets()
end

-- Opens the menu for the equipped weapon. Returns true once open.
function Controller:_debug(...)
	if self._config.behaviour.debug then
		print("[CustomizeUI]", ...)
	end
end

function Controller:Open(): boolean
	local deps = self._deps
	local tool = deps.getEquippedWeapon()
	self:_debug("Open requested; state =", self._state, "equipped SPH tool =", tool)
	if not tool then
		warn("[CustomizeUI] can't open: no equipped Tool with an SPH_Weapon child")
		return false
	end
	if self._testing or self._testRequest then
		self:_debug("Open ignored: testing a loadout")
		return false
	end
	if self._state ~= "closed" then
		self:Close("reopen")
		local delay = self._config.behaviour.reopenDelay
		if delay and delay > 0 then
			task.wait(delay)
		end
	end

	self._token += 1
	local token = self._token
	self._state = "opening"
	self:_setGuiEnabled(true)

	task.wait() -- let equip/unequip settle for one frame (legacy behaviour)
	if token ~= self._token or self._state ~= "opening" then
		return false
	end
	local current = deps.getEquippedWeapon()
	if not current then
		self:_debug("Open aborted: weapon unequipped during the settle frame")
		self._state = "closed"
		self:_setGuiEnabled(false)
		return false
	end

	local ok, err = pcall(function()
		self._environment:Acquire()
		self._state = "open"
		self:_buildSession(current)
	end)
	if not ok then
		warn("[CustomizeUI] open failed, resetting:", err, debug.traceback())
		self:Close("error")
		return false
	end
	self:_debug("Opened for", current, "- gui", self._gui:GetFullName(), "Enabled =", self._gui.Enabled)
	self.Opened:Fire(current)
	return true
end

-- Switches an open menu to another weapon (SetupCustomizeGUI while open).
function Controller:Retarget(tool: Tool)
	if self._state ~= "open" or not tool or tool == self._tool then
		return
	end
	local ok, err = pcall(function()
		self:_buildSession(tool)
	end)
	if not ok then
		warn("[CustomizeUI] retarget failed:", err)
		self:Close("error")
	end
end

-- mode: nil | "cleanup" | "force"  (see Environment:Release)
function Controller:Close(reason: string?, mode: string?)
	if self._state == "closed" then
		if mode == "force" and self._environment:IsActive() then
			self._environment:Release("force")
		end
		return
	end
	self._state = "closed"
	self._token += 1
	self._presetToken += 1 -- replies for this session are now ignored
	self:_setGuiEnabled(false)
	self._environment:Release(mode)
	if self._preview then
		self._preview:Clear()
	end
	if self._selection then
		self._selection:Destroy()
		self._selection = nil
	end
	self._tool = nil
	self._catalog = nil
	self.Closed:Fire(reason or "close")
end

-- ─── user intent ────────────────────────────────────────────────────────────

function Controller:SelectSlot(slot: string)
	if self._state ~= "open" or not self._catalog or not Catalog.find(self._catalog, slot) then
		return
	end
	self._activeSlot = slot
	self._view:SetActiveSlot(slot)
end

-- name == nil means "None" (clear the slot). Picking the selected option again clears
-- it (legacy toggle behaviour).
function Controller:Pick(slot: string, name: string?)
	local selection = self._selection
	if self._state ~= "open" or not selection then
		return
	end
	local ok, reason
	if name == nil then
		if selection:Get(slot) == nil then
			return
		end
		ok, reason = selection:Clear(slot)
		if ok then
			self._view:PlaySound("deselect")
		end
	else
		local wasSelected = selection:Get(slot) == name
		ok, reason = selection:Toggle(slot, name)
		if ok then
			self._view:PlaySound(if wasSelected then "deselect" else "select")
		end
	end
	if not ok and reason then
		self._view:Flash(reason, "warning")
	end
end

function Controller:ClearSlot(slot: string)
	self:Pick(slot, nil)
end

function Controller:Revert()
	if self._selection and self._selection:IsDirty() then
		self._selection:Revert()
		self._view:PlaySound("deselect")
	end
end

-- Programmatic selection (for scripts / custom views). Returns ok, reason.
function Controller:Select(slot: string, name: string): (boolean, string?)
	if not self._selection then
		return false, "menu not open"
	end
	local ok, reason = self._selection:Select(slot, name)
	return ok, reason
end

-- Saves the selection: sanitize (same rules as the server) → optimistic local copy →
-- server → close → local refresh (after the environment restored WalkSpeed, so the
-- refreshed weapon stats are what sticks).
-- presetName: set when applying a saved preset (the server then makes it the gun's
-- active preset, auto-applied to new copies of the gun).
function Controller:Confirm(presetName: string?): boolean
	local tool, selection = self._tool, self._selection
	if self._state ~= "open" or not tool or not selection then
		return false
	end
	local behaviour = self._config.behaviour
	if not selection:IsDirty() and not behaviour.confirmWhenUnchanged and not presetName then
		if behaviour.closeOnConfirm then
			self:Close("confirm")
		end
		return true
	end

	local loadout = self._attachments:SanitizeLoadout(selection:GetAll(), tool)

	local legacyPreview = tool:FindFirstChild("PreviewAttachments")
	if legacyPreview then
		legacyPreview:Destroy()
	end
	self._attachments:SetLoadout(tool, loadout)

	local ok, err = pcall(self._deps.submit, tool, loadout, presetName)
	if not ok then
		warn("[CustomizeUI] submit failed:", err)
		self._view:Flash("Could not save attachments", "error")
		return false
	end
	selection:MarkSaved(loadout)
	self._view:PlaySound("select")
	if self._presetState and self._presetState.ok then
		-- what the server will record (a normal confirm that changes the gun clears it)
		if presetName then
			self._presetState.active = presetName
			self._presetState.carried = presetName
		elseif self._presetState.carried then
			local carried = self:_findPreset(self._presetState.carried)
			if not carried or not sameLoadout(self._attachments:SanitizeLoadout(carried.loadout, tool), loadout) then
				if self._presetState.active == self._presetState.carried then
					self._presetState.active = nil
				end
				self._presetState.carried = nil
			end
		end
		self:_pushPresets()
	end

	if behaviour.closeOnConfirm then
		self:Close("confirm")
	else
		self:_summary()
	end
	if self._deps.onConfirmed then
		local refreshed, refreshErr = pcall(self._deps.onConfirmed, tool, loadout)
		if not refreshed then
			warn("[CustomizeUI] onConfirmed errored:", refreshErr)
		end
	end
	self.Confirmed:Fire(tool, loadout)
	return true
end

-- ─── presets (saved loadouts) ────────────────────────────────────────────────

function sameLoadout(a, b) -- assigns the forward-declared local
	for slot, name in pairs(a or {}) do
		if (b or {})[slot] ~= name then
			return false
		end
	end
	for slot in pairs(b or {}) do
		if (a or {})[slot] == nil then
			return false
		end
	end
	return true
end

function Controller:_presetError(code: string?): string
	local errors = self._config.text.presetErrors or {}
	return errors[code or ""] or errors.server_error or tostring(code)
end

function Controller:_findPreset(name: string?)
	for _, preset in ipairs(self._presetState and self._presetState.presets or {}) do
		if preset.name == name then
			return preset
		end
	end
	return nil
end

-- "Red Dot, Suppressor" in slot order, using the menu's labels.
function Controller:_describeLoadout(loadout: { [string]: string }): string
	local parts, seen = {}, {}
	for _, slot in ipairs(self._catalog and self._catalog.slots or {}) do
		local name = loadout[slot.name]
		if name then
			seen[slot.name] = true
			local label = name
			for _, option in ipairs(slot.options) do
				if option.name == name then
					label = option.label or name
					break
				end
			end
			table.insert(parts, label)
		end
	end
	local rest = {}
	for slot, name in pairs(loadout) do
		if not seen[slot] then
			table.insert(rest, name)
		end
	end
	table.sort(rest)
	for _, name in ipairs(rest) do
		table.insert(parts, name)
	end
	return if #parts > 0 then table.concat(parts, ", ") else self._config.text.empty
end

-- What views receive in SetPresets(state) (see README).
function Controller:GetPresets()
	local text = self._config.text
	if not self._presets then
		return { available = false, loading = false, presets = {} }
	end
	local state = self._presetState
	if not state then
		return { available = true, loading = true, presets = {} }
	end
	if not state.ok then
		return { available = true, loading = false, error = self:_presetError(state.error), presets = {} }
	end
	local current = if self._selection then self._selection:GetAll() else {}
	local list = {}
	for _, preset in ipairs(state.presets or {}) do
		table.insert(list, {
			name = preset.name,
			loadout = table.clone(preset.loadout or {}),
			summary = self:_describeLoadout(preset.loadout or {}),
			active = preset.name == state.active, -- auto-applied to new copies of this gun
			carried = preset.name == state.carried, -- currently on this gun
			matchesSelection = sameLoadout(preset.loadout, current),
		})
	end
	local count = #list
	return {
		available = true,
		loading = false,
		presets = list,
		active = state.active,
		carried = state.carried,
		count = count,
		max = state.max,
		canSave = state.max == nil or count < state.max,
		persistent = state.persistent ~= false,
		maxNameLength = state.maxNameLength,
		countText = if state.max
			then text.presetCountWithMax:format(count, state.max)
			else text.presetCount:format(count),
	}
end

function Controller:_pushPresets()
	local viewState = self:GetPresets()
	if self._view.SetPresets then
		self._view:SetPresets(viewState)
	end
	self.PresetsChanged:Fire(viewState)
end

-- Sends a request without blocking; onResult(state) runs only if the same session is
-- still open when the reply arrives.
function Controller:_presetRequest(action: string, args: { any }, onResult: ((any) -> ())?)
	local presets = self._presets
	if not presets then
		self._view:Flash(self:_presetError("disabled"), "warning")
		return
	end
	local token, tool = self._presetToken, self._tool
	task.spawn(function()
		local state = presets.invoke(action, table.unpack(args, 1, args.n or #args))
		if self._presetToken ~= token or self._tool ~= tool or self._state ~= "open" then
			return
		end
		if type(state) ~= "table" then
			state = { ok = false, error = "unavailable" }
		end
		if state.ok then
			self._presetState = state
			self:_pushPresets()
		end
		if onResult then
			onResult(state)
		end
	end)
end

function Controller:RefreshPresets()
	self._presetState = nil
	self:_pushPresets()
	if not self._presets or self._state ~= "open" then
		return
	end
	self:_presetRequest("list", { n = 0 }, function(state)
		if not state.ok then
			self._presetState = state
			self:_pushPresets()
		elseif state.persistent == false and not self._warnedNotKept then
			self._warnedNotKept = true
			self._view:Flash(self._config.text.presetNotKept, "info")
		end
	end)
end

-- Saves the CURRENT selection as a preset for this gun (the gun is not changed).
-- An empty name gets "Loadout N"; an existing name is overwritten.
function Controller:SavePreset(name: string?)
	if self._state ~= "open" or not self._selection then
		return
	end
	local text = self._config.text
	local wanted = if type(name) == "string" then name:match("^%s*(.-)%s*$") else ""
	if wanted == "" then
		local taken = {}
		local list = self._presetState and self._presetState.presets or {}
		for _, preset in ipairs(list) do
			taken[preset.name] = true
		end
		local index = #list + 1
		while taken[text.presetDefaultName:format(index)] do
			index += 1
		end
		wanted = text.presetDefaultName:format(index)
	end
	local loadout = self._attachments:SanitizeLoadout(self._selection:GetAll(), self._tool)
	self:_presetRequest("save", { wanted, loadout, n = 2 }, function(state)
		if state.ok then
			self._view:PlaySound("select")
			self._view:Flash(text.presetSaved:format(state.saved or wanted), "info")
		else
			self._view:Flash(self:_presetError(state.error), "warning")
		end
	end)
end

function Controller:RenamePreset(oldName: string, newName: string?)
	if self._state ~= "open" or type(oldName) ~= "string" then
		return
	end
	self:_presetRequest("rename", { oldName, newName or "", n = 2 }, function(state)
		if state.ok then
			self._view:Flash(self._config.text.presetRenamed:format(state.renamed or tostring(newName)), "info")
		else
			self._view:Flash(self:_presetError(state.error), "warning")
		end
	end)
end

function Controller:DeletePreset(name: string)
	if self._state ~= "open" or type(name) ~= "string" then
		return
	end
	self:_presetRequest("delete", { name, n = 1 }, function(state)
		if state.ok then
			self._view:PlaySound("deselect")
			self._view:Flash(self._config.text.presetDeleted:format(name), "info")
		else
			self._view:Flash(self:_presetError(state.error), "warning")
		end
	end)
end

-- Puts a preset into the selection WITHOUT applying it (Confirm applies as usual).
function Controller:LoadPreset(name: string): boolean
	local preset = self._state == "open" and self._selection and self:_findPreset(name)
	if not preset then
		self._view:Flash(self:_presetError("missing"), "warning")
		return false
	end
	self._selection:SetCurrent(preset.loadout)
	self._view:Flash(self._config.text.presetLoaded:format(name), "info")
	return true
end

-- Applies a saved preset to the gun now; it becomes the gun's active preset.
function Controller:ApplyPreset(name: string): boolean
	local preset = self._state == "open" and self._selection and self:_findPreset(name)
	if not preset then
		self._view:Flash(self:_presetError("missing"), "warning")
		return false
	end
	self._selection:SetCurrent(preset.loadout)
	return self:Confirm(name)
end

-- ─── Test Loadout ─────────────────────────────────────────────────────────────

function Controller:_testError(code: string?)
	local errors = self._config.text.testErrors or {}
	self._view:Flash(errors[code or ""] or errors.unavailable or "Testing is unavailable", "error")
end

function Controller:IsTesting(): boolean
	return self._testing ~= nil
end

-- Tries the current picks in the test area (the real gun is not changed). The menu
-- closes; returning (button, or the server's time limit) reopens it with the same picks.
function Controller:TestLoadout(): boolean
	if self._state ~= "open" or not self._selection or not self._tool then
		return false
	end
	if not self._test or self._config.test.enabled == false then
		self:_testError("disabled")
		return false
	end
	if self._testRequest or self._testing then
		return false
	end
	local tool = self._tool
	local resume = { tool = tool, selection = self._selection:GetAll(), activeSlot = self._activeSlot }
	local loadout = self._attachments:SanitizeLoadout(resume.selection, tool)
	self._testRequest = true
	local ok, result = pcall(self._test.invoke, "start", tool, loadout)
	self._testRequest = false
	if not ok or type(result) ~= "table" or not result.ok then
		if self._state == "open" then
			self:_testError(if ok and type(result) == "table" then result.error else nil)
		end
		return false
	end
	self._testing = resume
	if self._state ~= "closed" then
		self:Close("test")
	end
	if self._testHud then
		self._testHud:Show()
	end
	self.TestStarted:Fire(tool)
	-- the test may already be over (e.g. died instantly) before this reply arrived
	if self._test.isTesting and not self._test.isTesting() then
		self:_onTestEnded("ended")
	end
	return true
end

-- Leaves the test area (the server ends the test; _onTestEnded resumes the menu).
function Controller:EndTest()
	if not self._testing or self._ending then
		return
	end
	self._ending = true
	local ok, result = pcall(self._test.invoke, "stop")
	self._ending = false
	if not ok or type(result) ~= "table" or not result.ok then
		warn("[Gunsmith] couldn't leave the test:", if ok and type(result) == "table" then result.error else result)
	end
	if self._testing and self._test.isTesting and not self._test.isTesting() then
		self:_onTestEnded("returned") -- the end notice was missed or not sent
	end
end

function Controller:_onTestEnded(reason: string?)
	local resume = self._testing
	if not resume then
		return
	end
	self._testing = nil
	if self._testHud then
		self._testHud:Hide()
	end
	self.TestEnded:Fire(reason or "ended")
	if reason ~= "returned" and reason ~= "timeout" then
		return -- died / left / lost: nothing to go back to
	end
	task.spawn(function()
		local getEquipped = self._deps.getEquippedWeapon
		local deadline = os.clock() + (self._config.test.resumeTimeout or 5)
		while getEquipped() ~= resume.tool and os.clock() < deadline do
			task.wait(0.1)
		end
		if getEquipped() ~= resume.tool or self._state ~= "closed" or self._testing then
			return
		end
		if self:Open() and self._tool == resume.tool and self._selection then
			self._selection:SetCurrent(resume.selection)
			if resume.activeSlot then
				self:SelectSlot(resume.activeSlot)
			end
		end
	end)
end

function Controller:Destroy()
	self:Close("destroy", "force")
	if self._testHud then
		self._testHud:Destroy()
	end
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	if self._preview then
		self._preview:Destroy()
	end
	self._view:Destroy()
	self.Opened:DisconnectAll()
	self.Closed:DisconnectAll()
	self.Confirmed:DisconnectAll()
	self.PresetsChanged:DisconnectAll()
	self.SelectionChanged:DisconnectAll()
	self.TestStarted:DisconnectAll()
	self.TestEnded:DisconnectAll()
end

return Controller
