--[[
	AttachmentSystem.Gunsmith
	─────────────────────────
	Menu orchestration. Owns the open/close lifecycle, the current selection,
	and the confirm handoff. The rendering lives in `Gunsmith/View`, the
	input/window management in `Gunsmith/InputLock`, the 3D preview in
	`Gunsmith/Preview3D`.

	── Important ──────────────────────────────────────────────────────────────
	This menu is *not* started automatically. Requiring AttachmentSystem does
	not construct any UI.

	In SPH as this code was extracted, the gunsmith was already dormant: the
	menu script at `SPH_Assets.HUD.CustomizeGunGUI` was required by nothing,
	so the proximity prompt was never bound and the `GetSelectedAttachments`
	function was never registered. The extraction deliberately preserves that
	behaviour — starting the menu is now an explicit, one-line host decision:

	    AttachmentSystem.StartGunsmith({
	        template    = ReplicatedStorage.SPH_Assets.HUD.GunGUIs.CustomizeGunGUI,
	        ...
	    })
	───────────────────────────────────────────────────────────────────────────

	Host options
	────────────
	    getPlayerGui()                 -> PlayerGui
	    getCharacter()                 -> the player's Character
	    getEquippedWeapon()            -> the Tool currently held
	    resolveModel(weaponName)       -> the weapon Model to check mounts against
	    getWeaponModel(weaponName)     -> the model to clone for the 3D preview
	    onConfirm(selection)           -> apply the loadout (host's job)
	    onCloseRequested()             -> the host closed the menu
	    onOpened() / onClosed()
	    onItemToggled(category, name, selected)
	    shouldSuppressGui()            -> {GuiObject} to hide while open
	    shouldRestoreMenus()           -> false to leave hidden GUIs hidden
	    suppressedNamePatterns         -> {"inventory", "hotbar"} to watch for
	    enforceSuppression             -> true to re-assert suppression each frame
	    coreGuiToDisable               -> an Enum.CoreGuiType
	    keepMouseDefault               -> true to force the mouse visible
	    sounds = { select=, deselect=, hover= }
	    fieldOfView                    -> preview camera FOV
	    weaponRigPath                  -> how to find the live weapon model
]]

	local Config  = require(script.Parent.Config)
local Storage = require(script.Parent.Storage)
local View    = require(script.Gunsmith.View)
local InputLock = require(script.Gunsmith.InputLock)

local Gunsmith = {}

-- ─── Host plumbing ──────────────────────────────────────────────────────────

local function callHost(host, name, ...)
	local fn = host and host[name]
	if type(fn) ~= "function" then
		return nil
	end
	local results = table.pack(pcall(fn, ...))
	if not results[1] then
		warn(string.format("[AttachmentSystem] host callback '%s' errored: %s", name, results[2]))
		return nil
	end
	return table.unpack(results, 2, results.n)
end

--[[
	Find the weapon model the player is actually looking at, which is where
	attachment mount points live. The host normally supplies this; the default
	walks the camera the same way the old code did.
]]
local function defaultResolveModel(weaponName: string?): Model?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local rig = camera:FindFirstChild("WeaponRig") or camera:FindFirstChildWhichIsA("Model")
	if not rig then
		return nil
	end
	local folder = rig:FindFirstChild("Weapon")
	if not folder then
		return nil
	end
	return folder:FindFirstChildWhichIsA("Model")
end

-- ─── Instance ───────────────────────────────────────────────────────────────

local GunsmithController = {}
GunsmithController.__index = GunsmithController

local function newController(host: { [string]: any }, system: any)
	local self = setmetatable({
		host    = host,
		system  = system,

		gui     = nil,
		view    = nil,
		lock    = InputLock.new(host),

		isOpen  = false,
		weapon  = nil,
		selection = {},

		openedSignal = nil,   -- host hooks these instead of SPH_Events
		closedSignal = nil,
		selectedSignal = nil,
	}, GunsmithController)

	return self
end

function GunsmithController:_resolveGui()
	local template = callHost(self.host, "getTemplate")
	if not template then
		warn("[AttachmentSystem] gunsmith has no template; pass getTemplate()")
		return nil
	end

	local playerGui = callHost(self.host, "getPlayerGui")
	if not playerGui then
		return nil
	end

	-- Reuse the live instance if one already exists (e.g. after a respawn).
	local existing = playerGui:FindFirstChild(template.Name)
	if existing then
		return existing
	end

	local clone = template:Clone()
	clone.Parent = playerGui
	clone.ResetOnSpawn = false
	return clone
end

function GunsmithController:_isEquippedWeapon(tool: Instance?): boolean
	if not tool then
		return false
	end
	local equipped = callHost(self.host, "getEquippedWeapon")
	return equipped == tool
end

-- ─── Public surface ─────────────────────────────────────────────────────────

function GunsmithController:IsOpen(): boolean
	return self.isOpen
end

function GunsmithController:GetWeapon(): Instance?
	return self.weapon
end

function GunsmithController:GetSelection(): { [string]: string }
	return self.selection
end

--[[
	Open the menu on the currently equipped weapon. Idempotent: opening an
	already-open menu closes it first, so the same prompt can toggle.
]]
function GunsmithController:Open(): boolean
	local weapon = callHost(self.host, "getEquippedWeapon")
	if not weapon then
		return false
	end

	if self.isOpen then
		self:Close()
		task.wait(0.2)
	end

	self.isOpen = true
	self.weapon = weapon

	if self.gui then
		self.gui.Enabled = true
		self.gui.DisplayOrder = 1000
	end

	-- Defer one frame so callers can finish their own open sequence before we
	-- start taking input away from them.
	task.defer(function()
		if not self.isOpen or not self:_isEquippedWeapon(weapon) then
			self.isOpen = false
			if self.gui then
				self.gui.Enabled = false
				self.gui.DisplayOrder = 0
			end
			return
		end

		self.lock:Block()
		self.lock:SuppressOtherMenus()
		if self.host.enforceSuppression then
			self.lock:StartEnforcement()
		end
		self.lock:ForceMouse()

		callHost(self.host, "onOpening", weapon)

		local weaponName = weapon.Name
		local model = callHost(self.host, "resolveModel", weaponName) or defaultResolveModel(weaponName)

		if self.view then
			self.view:Clear()
		end
		if not self.view then
			self.view = View.new({
				gui    = self.gui,
				system = self.system,
				host   = self.host,
				onSelectionChanged = function(selection)
					if self.view then
						self.view:RefreshSelection()
					end
					self.selection = selection
					callHost(self.host, "onSelectionChanged", selection)
				end,
				onConfirm = function(selection)
					self:Confirm(selection)
				end,
			})
		end

		if self.view and not self.view:Build(weapon, model, weaponName) then
			warn("[AttachmentSystem] gunsmith failed to build for " .. tostring(weaponName))
		end
		self.selection = self.view and self.view:GetSelection() or {}
	end)

	return true
end

function GunsmithController:Close()
	if not self.isOpen then
		return
	end

	self.isOpen = false
	if self.gui then
		self.gui.Enabled = false
		self.gui.DisplayOrder = 0
	end

	self.lock:Release()
	if self.view then
		self.view:Clear()
	end
	self.weapon = nil
	table.clear(self.selection)

	callHost(self.host, "onClosed")
end

function GunsmithController:Toggle(): boolean
	if self.isOpen then
		self:Close()
		return false
	end
	return self:Open()
end

--[[
	Apply a selection.

	The system owns the parts that are genuinely attachment logic: writing the
	loadout to the tool and telling the host. The host owns everything that is
	weapon logic: re-fitting to the viewmodel, refreshing stats, updating
	springs and FOV, and any replication it needs.

	@return true when the loadout was accepted
]]
function GunsmithController:Confirm(selection: { [string]: string }?)
	if not self.weapon then
		return false
	end

	local loadout = {}
	local count = 0
	if type(selection) == "table" then
		for category, name in pairs(selection) do
			if type(category) == "string" and category ~= ""
			and type(name) == "string" and name ~= "" then
				loadout[category] = name
				count += 1
			end
		end
	end
	if count > Config.Limits.maxSelections then
		warn("[AttachmentSystem] refused a loadout with " .. count .. " entries")
		return false
	end

	Storage.SetSaved(self.weapon, loadout)

	local applied = callHost(self.host, "onConfirm", loadout, self.weapon)

	self:Close()
	return applied ~= false
end

--[[
	Reset the menu. Called when the character dies, respawns, or the tool is
	removed, so the menu can never be left open over a dead player.
]]
function GunsmithController:ForceReset()
	self.isOpen = false
	if self.gui then
		self.gui.Enabled = false
		self.gui.DisplayOrder = 0
	end
	self.lock:Release()
	if self.view then
		self.view:Clear()
	end
	self.weapon = nil
	table.clear(self.selection)
end

-- ─── Module entry point ─────────────────────────────────────────────────────

--[[
	Construct the gunsmith. Safe to call once; later calls return the existing
	controller.
]]
function Gunsmith.start(hostOptions: { [string]: any }?, system: any?)
	if Gunsmith._controller then
		return Gunsmith._controller
	end

	local host = hostOptions or {}
	host.keepMouseDefault = host.keepMouseDefault ~= false
	host.suppressedNamePatterns = host.suppressedNamePatterns or {}

	local controller = newController(host, system)
	local gui = controller:_resolveGui()

	if not gui then
		warn("[AttachmentSystem] gunsmith could not obtain a ScreenGui; not started")
		return nil
	end

	controller.gui = gui
	gui.Enabled = false

	-- Keep the menu tied to the player's lifecycle: death, respawn, and tool
	-- changes all force a reset so it can never linger.
	local player = callHost(host, "getPlayer")
	if player then
		local function reset()
			controller:ForceReset()
		end

		player.CharacterRemoving:Connect(reset)
		player.CharacterAdded:Connect(function(character)
			reset()
			character.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then controller:ForceReset() end
			end)
			character.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") then controller:ForceReset() end
			end)

			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid then
				humanoid.Died:Connect(function()
					if controller.isOpen then
						controller:ForceReset()
					end
				end)
			end
		end)

		if player.Character then
			controller:ForceReset()
		end
	end

	Gunsmith._controller = controller
	return controller
end

function Gunsmith.get()
	return Gunsmith._controller
end

-- Testing / reconfiguration support.
function Gunsmith.stop()
	if Gunsmith._controller then
		Gunsmith._controller:ForceReset()
		if Gunsmith._controller.gui then
			Gunsmith._controller.gui:Destroy()
		end
		Gunsmith._controller = nil
	end
end

return Gunsmith
