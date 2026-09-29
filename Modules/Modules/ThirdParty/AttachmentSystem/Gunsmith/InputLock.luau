--[[
	AttachmentSystem.Gunsmith.InputLock
	───────────────────────────────────
	Everything the gunsmith needs to do to get exclusive control of the player
	while it is open: swallow movement input, stop the player walking, and keep
	other menus from fighting the gunsmith for screen space.

	The previous implementation hardcoded two SPH-specific behaviours here:

	  • it disabled *any* ScreenGui in the PlayerGui whose name merely
	    contained "inventory" or "hotbar", and
	  • it decided whether to restore them by reading the character
	    attributes `BackpackDisabled` / `IsUnequippingForArmHiding`.

	Both are now delegated to the host through `hostOptions`. With no host
	callbacks the lock still blocks movement, but it touches no GUIs it does
	not own.
]]

local ContextActionService = game:GetService("ContextActionService")
local StarterGui           = game:GetService("StarterGui")
local UserInputService     = game:GetService("UserInputService")

local InputLock = {}

InputLock.__index = InputLock

local BLOCKED_KEYS = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
	Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
	Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl,
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
	Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight,
	Enum.KeyCode.Nine, Enum.KeyCode.Zero,
	Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonX,
	Enum.KeyCode.ButtonY, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown,
	Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.Thumbstick1,
}

function InputLock.new(host)
	return setmetatable({
		host = host,

		blocked            = false,
		originalWalkSpeed  = nil,
		walkSpeedCharacter = nil,

		previousMouseBehavior    = nil,
		previousMouseIconEnabled = nil,

		suppressed         = {},      -- GuiObject -> connection
		watchConnection    = nil,
		enforceConnection  = nil,
		coreGuiWasEnabled  = nil,
	}, InputLock)
end

-- ─── Movement ───────────────────────────────────────────────────────────────

function InputLock:Block()
	if self.blocked then
		return
	end
	self.blocked = true

	pcall(function()
		ContextActionService:BindAction(
			"AttachmentSystemBlockAllInputs",
			function() return Enum.ContextActionResult.Sink end,
			false,
			unpack(BLOCKED_KEYS)
		)
	end)

	local character = self.host and self.host.getCharacter and self.host.getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self.originalWalkSpeed = humanoid.WalkSpeed
		self.walkSpeedCharacter = character
		humanoid.WalkSpeed = 0
	end
end

function InputLock:Unblock()
	if not self.blocked then
		return
	end
	self.blocked = false

	pcall(function()
		ContextActionService:UnbindAction("AttachmentSystemBlockAllInputs")
	end)

	if self.walkSpeedCharacter and self.originalWalkSpeed ~= nil then
		local humanoid = self.walkSpeedCharacter:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = self.originalWalkSpeed
		end
	end
	self.originalWalkSpeed  = nil
	self.walkSpeedCharacter = nil
end

-- ─── Other menus ────────────────────────────────────────────────────────────

--[[
	Ask the host which GUIs should be suppressed while the gunsmith is open.
	Returning an empty list (the default) suppresses nothing, which is the
	safe behaviour for a host that does not opt in.
]]
function InputLock:_getSuppressionTargets(): {Instance}
	local host = self.host
	if not host or type(host.shouldSuppressGui) ~= "function" then
		return {}
	end

	local ok, result = pcall(host.shouldSuppressGui)
	if not ok or type(result) ~= "table" then
		return {}
	end
	return result
end

function InputLock:_suppress(gui: Instance)
	if not gui or self.suppressed[gui] or not gui:IsA("GuiObject") then
		return
	end

	pcall(function() gui.Enabled = false end)
	self.suppressed[gui] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			pcall(function() gui.Enabled = false end)
		end
	end)
end

function InputLock:SuppressOtherMenus()
	local playerGui = self.host and self.host.getPlayerGui and self.host.getPlayerGui()
	if not playerGui then
		return
	end

	for _, gui in ipairs(self:_getSuppressionTargets()) do
		self:_suppress(gui)
	end

	if not self.watchConnection then
		self.watchConnection = playerGui.ChildAdded:Connect(function(child)
			for _, pattern in ipairs(self.host.suppressedNamePatterns or {}) do
				if string.find(string.lower(child.Name), string.lower(pattern)) then
					self:_suppress(child)
					break
				end
			end
		end)
	end
end

function InputLock:RestoreOtherMenus()
	for gui, connection in pairs(self.suppressed) do
		pcall(function() connection:Disconnect() end)
		pcall(function() gui.Enabled = true end)
	end
	table.clear(self.suppressed)

	if self.watchConnection then
		self.watchConnection:Disconnect()
		self.watchConnection = nil
	end
end

--[[
	Steady-state enforcement, for hosts whose other menus fight back. Only runs
	when the host opts in via `enforceSuppression`.
]]
function InputLock:StartEnforcement()
	if self.enforceConnection or not (self.host and self.host.enforceSuppression) then
		return
	end

	local RunService = game:GetService("RunService")
	self.enforceConnection = RunService.Heartbeat:Connect(function()
		local playerGui = self.host.getPlayerGui and self.host.getPlayerGui()
		if not playerGui then
			return
		end
		for _, gui in ipairs(self:_getSuppressionTargets()) do
			pcall(function() gui.Enabled = false end)
		end
		if self.host.coreGuiToDisable then
			pcall(function()
				StarterGui:SetCoreGuiEnabled(self.host.coreGuiToDisable, false)
			end)
		end
		if self.walkSpeedCharacter then
			local humanoid = self.walkSpeedCharacter:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.WalkSpeed ~= 0 then
				humanoid.WalkSpeed = 0
			end
		end
	end)
end

function InputLock:StopEnforcement()
	if self.enforceConnection then
		self.enforceConnection:Disconnect()
		self.enforceConnection = nil
	end
end

--[[
	Whether restoring suppressed GUIs would fight the host. The host decides;
	the gunsmith asks before it puts anything back.
]]
function InputLock:ShouldRestore(): boolean
	local host = self.host
	if not host or type(host.shouldRestoreMenus) ~= "function" then
		return true
	end
	local ok, result = pcall(host.shouldRestoreMenus)
	if not ok then
		return true
	end
	return result ~= false
end

-- ─── Mouse ──────────────────────────────────────────────────────────────────

function InputLock:ForceMouse()
	if not self.previousMouseBehavior then
		self.previousMouseBehavior    = UserInputService.MouseBehavior
		self.previousMouseIconEnabled = UserInputService.MouseIconEnabled
	end
	pcall(function()
		UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
end

function InputLock:RestoreMouse()
	if self.previousMouseBehavior == nil then
		return
	end
	pcall(function()
		UserInputService.MouseBehavior    = self.previousMouseBehavior
		UserInputService.MouseIconEnabled = self.previousMouseIconEnabled
	end)
	self.previousMouseBehavior    = nil
	self.previousMouseIconEnabled = nil
end

-- ─── Full release ───────────────────────────────────────────────────────────

function InputLock:Release()
	self:Unblock()
	self:StopEnforcement()
	self:RestoreOtherMenus()
	if self.shouldRestoreCoreGui ~= false then
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true) end)
	end
	self:RestoreMouse()
end

return InputLock
