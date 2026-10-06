--!nonstrict
-- Customize/Environment
-- Everything the menu does to the rest of the game while it is open, in one place,
-- with symmetric acquire/release. Ported from the legacy controller; behaviour kept:
--
--   open : sink movement/hotbar keys (CAS), WalkSpeed -> 0 (remembered), free + show
--          the mouse every PreRender, hide Backpack CoreGui and any ScreenGui whose name
--          contains "inventory"/"hotbar" (enforced every Heartbeat, incl. new GUIs),
--          keep WalkSpeed at 0, enable Lighting.GUIBlur, disable customize prompts.
--   close: undo all of it. Inventory/backpack and the previous mouse state are only
--          restored when the character has neither "BackpackDisabled" nor
--          "IsUnequippingForArmHiding" (otherwise the mouse icon stays hidden).
--
-- Legacy differences (fixes): no task.wait inside close paths (the 0.1s inventory
-- restore delay is a cancellable task.delay), no duplicated teardown code, and
-- release is idempotent.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")

local Environment = {}
Environment.__index = Environment

local function keyCodes(names: { string }): { Enum.KeyCode }
	local result = {}
	for _, name in ipairs(names) do
		local ok, code = pcall(function()
			return (Enum.KeyCode :: any)[name]
		end)
		if ok and code then
			table.insert(result, code)
		end
	end
	return result
end

-- options: config.environment + { setPromptsEnabled = fn(bool)? }
function Environment.new(options: { [string]: any })
	local self = setmetatable({}, Environment)
	self._options = options
	self._player = Players.LocalPlayer
	self._playerGui = self._player:WaitForChild("PlayerGui")
	self._setPrompts = options.setPromptsEnabled
	self._active = false
	self._connections = {}
	self._guiWatch = {}
	self._savedWalkSpeed = nil
	self._savedMouseBehavior = nil
	self._savedMouseIcon = nil
	self._restoreToken = 0
	return self
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function Environment:_matchesInventory(gui: Instance): boolean
	if not gui:IsA("ScreenGui") then
		return false
	end
	local lower = gui.Name:lower()
	for _, pattern in ipairs(self._options.inventoryNamePatterns) do
		if lower:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

-- True when inventory/backpack/mouse may be restored on close (legacy rule).
function Environment:CanRestoreInventory(): boolean
	local character = self._player.Character
	if not character then
		return true
	end
	for _, attributeName in ipairs(self._options.keepInventoryHiddenAttributes) do
		if character:GetAttribute(attributeName) then
			return false
		end
	end
	return true
end

function Environment:_setInventoryVisible(visible: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, visible)
	end)
	for _, gui in ipairs(self._playerGui:GetChildren()) do
		if self._matchesInventory(self, gui) then
			pcall(function()
				(gui :: ScreenGui).Enabled = visible
			end)
		end
	end
end

function Environment:_watchGui(gui: Instance)
	if self._guiWatch[gui] then
		return
	end
	pcall(function()
		(gui :: ScreenGui).Enabled = false
	end)
	self._guiWatch[gui] = (gui :: ScreenGui):GetPropertyChangedSignal("Enabled"):Connect(function()
		if self._active and (gui :: ScreenGui).Enabled then
			pcall(function()
				(gui :: ScreenGui).Enabled = false
			end)
		end
	end)
end

function Environment:_track(connection: RBXScriptConnection)
	table.insert(self._connections, connection)
end

-- Called once the menu is confirmed open.
function Environment:Acquire()
	if self._active then
		return
	end
	self._active = true
	self._restoreToken += 1
	local options = self._options

	if self._setPrompts then
		pcall(self._setPrompts, false)
	end

	if options.blockInputs then
		local ok, err = pcall(function()
			ContextActionService:BindAction(options.blockActionName, function()
				return Enum.ContextActionResult.Sink
			end, false, table.unpack(keyCodes(options.blockedKeys)))
		end)
		if not ok then
			warn("[CustomizeUI] failed to bind input block:", err)
		end
	end

	local humanoid = humanoidOf(self._player)
	if options.freezeWalkSpeed and humanoid then
		self._savedWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
	end

	if options.forceMouseFree then
		self._savedMouseBehavior = UserInputService.MouseBehavior
		self._savedMouseIcon = UserInputService.MouseIconEnabled
		local function freeMouse()
			pcall(function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			end)
		end
		freeMouse()
		self:_track(RunService.PreRender:Connect(freeMouse))
	end

	if options.suppressInventory then
		for _, gui in ipairs(self._playerGui:GetChildren()) do
			if self:_matchesInventory(gui) then
				self:_watchGui(gui)
			end
		end
		self:_track(self._playerGui.ChildAdded:Connect(function(child)
			if self:_matchesInventory(child) then
				self:_watchGui(child)
			end
		end))
	end

	if options.suppressInventory or options.freezeWalkSpeed then
		self:_track(RunService.Heartbeat:Connect(function()
			if options.suppressInventory then
				self:_setInventoryVisible(false)
			end
			if options.freezeWalkSpeed then
				local current = humanoidOf(self._player)
				if current and current.WalkSpeed ~= 0 then
					current.WalkSpeed = 0
				end
			end
		end))
	end

	if options.blur then
		local blur = Lighting:FindFirstChild("GUIBlur")
		if blur then
			pcall(function()
				(blur :: any).Enabled = true
			end)
		end
	end
end

-- Undo everything. `mode`:
--   nil       normal close: restores per the attribute rule (CanRestoreInventory)
--   "cleanup" weapon unequipped (CleanupCustomizeGUI): as normal, plus the Backpack
--             CoreGui is re-enabled unconditionally (legacy cleanup handler did this)
--   "force"   respawn / death: restore everything; mouse -> Default + visible
--             (legacy forceCloseAndReset)
function Environment:Release(mode: string?)
	local force = mode == "force"
	local wasActive = self._active
	self._active = false
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for _, connection in pairs(self._guiWatch) do
		connection:Disconnect()
	end
	table.clear(self._guiWatch)

	local options = self._options
	pcall(function()
		ContextActionService:UnbindAction(options.blockActionName)
	end)

	if wasActive then
		local humanoid = humanoidOf(self._player)
		if humanoid and self._savedWalkSpeed ~= nil then
			humanoid.WalkSpeed = self._savedWalkSpeed
		end
		self._savedWalkSpeed = nil

		local canRestore = force or self:CanRestoreInventory()
		if options.forceMouseFree then
			pcall(function()
				if force then
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
					UserInputService.MouseIconEnabled = true
				elseif canRestore then
					UserInputService.MouseBehavior = self._savedMouseBehavior or Enum.MouseBehavior.Default
					UserInputService.MouseIconEnabled = if self._savedMouseIcon == nil then true else self._savedMouseIcon
				else
					UserInputService.MouseIconEnabled = false
				end
			end)
		end

		if options.suppressInventory and not canRestore and mode == "cleanup" then
			pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
			end)
		end
		if options.suppressInventory and canRestore then
			self._restoreToken += 1
			local token = self._restoreToken
			task.delay(options.inventoryRestoreDelay or 0, function()
				-- Skip if the menu reopened meanwhile, or the rule changed.
				if token == self._restoreToken and not self._active and (force or self:CanRestoreInventory()) then
					self:_setInventoryVisible(true)
				end
			end)
		end
	end

	if options.blur then
		local blur = Lighting:FindFirstChild("GUIBlur")
		if blur then
			pcall(function()
				(blur :: any).Enabled = false
			end)
		end
	end

	if self._setPrompts then
		pcall(self._setPrompts, true)
	end
end

function Environment:IsActive(): boolean
	return self._active
end

function Environment:Destroy()
	self:Release(nil)
end

return Environment
