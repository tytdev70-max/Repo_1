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
--   submit           function(tool, loadout)    (send to server)
--   onConfirmed      function(tool, loadout)?   (local refresh after confirm)

local UserInputService = game:GetService("UserInputService")

local Catalog = require(script.Parent.Catalog)
local Selection = require(script.Parent.Selection)
local Signal = require(script.Parent.Signal)

local Controller = {}
Controller.__index = Controller

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

	self.Opened = Signal.new() -- (tool)
	self.Closed = Signal.new() -- (reason)
	self.Confirmed = Signal.new() -- (tool, loadout)
	self.SelectionChanged = Signal.new() -- (loadout, change)

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
	})

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

	self._view:SetWeapon(tool.Name)
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
		self:_debug("Open aborted: no equipped Tool with an SPH_Weapon child")
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
function Controller:Confirm(): boolean
	local tool, selection = self._tool, self._selection
	if self._state ~= "open" or not tool or not selection then
		return false
	end
	local behaviour = self._config.behaviour
	if not selection:IsDirty() and not behaviour.confirmWhenUnchanged then
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

	local ok, err = pcall(self._deps.submit, tool, loadout)
	if not ok then
		warn("[CustomizeUI] submit failed:", err)
		self._view:Flash("Could not save attachments", "error")
		return false
	end
	selection:MarkSaved(loadout)
	self._view:PlaySound("select")

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

function Controller:Destroy()
	self:Close("destroy", "force")
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
	self.SelectionChanged:DisconnectAll()
end

return Controller
