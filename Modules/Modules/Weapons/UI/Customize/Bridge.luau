--!nonstrict
-- Customize/Bridge
-- The ONLY file of the Customize UI that knows about SPH. Supplies the controller's
-- game hooks and wires every legacy contract (see Docs/CustomizeUI/01-Analysis.md §5):
--
--   H1  GunEvents.CustomizeConfirmed (BindableEvent, new) — fired after confirm with
--       (tool, loadout); Weapons/UI/CustomizeGunGUI refreshes the viewmodel from it
--       (replaces its old hook on the template's ConfirmButton).
--   H2  GunEvents.GetSelectedAttachments (BindableFunction) — current selection copy.
--   H3  GunEvents.SetupCustomizeGUI — fired on every equip: re-targets an open menu,
--       ignored while closed (the legacy script rebuilt the hidden menu every time).
--   H4  GunEvents.CleanupCustomizeGUI — fired on unequip: closes without saving.
--   H7  CustomizeGunHandler.BindCallbacks / SetPromptsEnabled / Refresh.
--   H11 GunEvents.ApplyWeaponAttachments:FireServer(tool, loadout) — once per confirm.
--   Character lifecycle: respawn/death force-close; tool changes refresh prompts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script:FindFirstAncestor("Modules")
local SPH_Events = require(Modules.Core.Networking.SPH_Events)

local Bridge = {}

local player = Players.LocalPlayer

-- The equipped SPH weapon (a Tool with an SPH_Weapon child) or nil.
function Bridge.getEquippedWeapon(): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	if tool and tool:FindFirstChild("SPH_Weapon") then
		return tool
	end
	return nil
end

local function assets(): Instance?
	return ReplicatedStorage:FindFirstChild("SPH_Assets")
end

-- Clean source model for the preview: SPH_Assets.WeaponModels/<tool.Name>.
function Bridge.getSourceModel(tool: Tool): Model?
	local root = assets()
	local models = root and root:FindFirstChild("WeaponModels")
	return models and models:FindFirstChild(tool.Name) or nil
end

-- Gun model whose mount points decide what is offered. Legacy used the first-person
-- viewmodel (Camera.WeaponRig.Weapon.<Model>); if it isn't there (e.g. mid-equip), the
-- clean source model is used instead of hiding everything.
function Bridge.resolveGunModel(tool: Tool): Model?
	local camera = workspace.CurrentCamera
	if camera then
		local rig = camera:FindFirstChild("WeaponRig")
		local weaponFolder = rig and rig:FindFirstChild("Weapon")
		local model = weaponFolder and weaponFolder:FindFirstChildWhichIsA("Model")
		if model then
			return model
		end
	end
	return Bridge.getSourceModel(tool)
end

function Bridge.submit(tool: Tool, loadout: { [string]: string }, presetName: string?)
	local root = assets()
	local events = root and root:FindFirstChild("Events")
	local gunEvents = events and events:FindFirstChild("GunEvents")
	local remote = gunEvents and gunEvents:FindFirstChild("ApplyWeaponAttachments")
	if not remote then
		error("ApplyWeaponAttachments remote not found")
	end
	remote:FireServer(tool, loadout, presetName) -- presetName: applying a saved preset
end

-- Presets: GunEvents.LoadoutPresets (RemoteFunction, created by the server's
-- LoadoutPresets service). invoke(action, ...) -> state table (never errors).
function Bridge.presets()
	local remote: RemoteFunction? = nil
	local function getRemote(): RemoteFunction?
		if remote and remote.Parent then
			return remote
		end
		remote = (SPH_Events.Find("GunEvents", "LoadoutPresets")
			or SPH_Events.WaitFor("GunEvents", "LoadoutPresets", 5)) :: RemoteFunction?
		return remote
	end
	return {
		invoke = function(action: string, ...: any)
			local fn = getRemote()
			if not fn then
				return { ok = false, error = "unavailable" }
			end
			local ok, result = pcall(fn.InvokeServer, fn, action, ...)
			if not ok or type(result) ~= "table" then
				return { ok = false, error = "unavailable" }
			end
			return result
		end,
	}
end

-- Weapon type shown by the Gunsmith (Rifle, Pistol...): WepStats.WeaponType, else the
-- Tool's WeaponType attribute. (wepStats.weaponType is SPH's "Gun"/"Grenade" switch, not used.)
function Bridge.resolveWeaponType(tool: Tool): string?
	local sph = tool:FindFirstChild("SPH_Weapon")
	local statsModule = sph and sph:FindFirstChild("WeaponStats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, stats = pcall(require, statsModule)
		if ok and type(stats) == "table" and type(stats.WeaponType) == "string" and stats.WeaponType ~= "" then
			return stats.WeaponType
		end
	end
	local attribute = tool:GetAttribute("WeaponType")
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end
	return nil
end

-- Test Loadout: GunEvents.GunsmithTest (RemoteFunction, created by the server's
-- GunsmithTest service). The server marks the player with the attribute
-- GunsmithTesting while a test runs and sets GunsmithTestEnd (the reason) when it ends.
function Bridge.test()
	local Signal = require(script.Parent.Signal)
	local ended = Signal.new()
	local remote: RemoteFunction? = nil
	local function getRemote(): RemoteFunction?
		if remote and remote.Parent then
			return remote
		end
		remote = (SPH_Events.Find("GunEvents", "GunsmithTest")
			or SPH_Events.WaitFor("GunEvents", "GunsmithTest", 5)) :: RemoteFunction?
		return remote
	end
	local connection = player:GetAttributeChangedSignal("GunsmithTesting"):Connect(function()
		if not player:GetAttribute("GunsmithTesting") then
			ended:Fire(player:GetAttribute("GunsmithTestEnd") or "ended")
		end
	end)
	return {
		invoke = function(action: string, ...: any)
			local fn = getRemote()
			if not fn then
				return { ok = false, error = "unavailable" }
			end
			local ok, result = pcall(fn.InvokeServer, fn, action, ...)
			if not ok or type(result) ~= "table" then
				return { ok = false, error = "unavailable" }
			end
			return result
		end,
		isTesting = function(): boolean
			return player:GetAttribute("GunsmithTesting") == true
		end,
		ended = ended,
		destroy = function()
			connection:Disconnect()
			ended:DisconnectAll()
		end,
	}
end

function Bridge.confirmedEvent(): BindableEvent
	return SPH_Events.GetOrCreate("GunEvents", "CustomizeConfirmed", "BindableEvent") :: BindableEvent
end

function Bridge.onConfirmed(tool: Tool, loadout: { [string]: string })
	Bridge.confirmedEvent():Fire(tool, loadout)
end

function Bridge.handler()
	return require(Modules.Weapons.UI.CustomizeGunHandler)
end

function Bridge.setPromptsEnabled(enabled: boolean)
	Bridge.handler().SetPromptsEnabled(enabled)
end

-- Wires the controller into SPH. Returns a disconnect function.
function Bridge.install(controller: any): () -> ()
	local connections = {}
	local characterConnections = {}
	local handler = Bridge.handler()

	local function track(list, connection)
		table.insert(list, connection)
	end
	local function clearCharacterConnections()
		for _, connection in ipairs(characterConnections) do
			connection:Disconnect()
		end
		table.clear(characterConnections)
	end

	-- H7: prompts open the menu; prompt state follows open/closed.
	handler.BindCallbacks(function()
		if controller._config.behaviour.debug then
			print("[CustomizeUI] prompt triggered")
		end
		task.spawn(function()
			controller:Open()
		end)
	end, function()
		return controller:IsOpen()
	end)
	track(connections, controller.Opened:Connect(function()
		handler.Refresh()
	end))
	track(connections, controller.Closed:Connect(function()
		handler.Refresh()
	end))

	-- H3 / H4
	local setupEvent = SPH_Events.GetOrCreate("GunEvents", "SetupCustomizeGUI", "BindableEvent") :: BindableEvent
	local cleanupEvent = SPH_Events.GetOrCreate("GunEvents", "CleanupCustomizeGUI", "BindableEvent") :: BindableEvent
	track(connections, setupEvent.Event:Connect(function(tool)
		if typeof(tool) == "Instance" and tool:IsA("Tool") and controller:IsOpen() then
			controller:Retarget(tool)
		end
	end))
	track(connections, cleanupEvent.Event:Connect(function()
		controller:Close("cleanup", "cleanup")
	end))

	-- H2
	local getSelected = SPH_Events.GetOrCreate("GunEvents", "GetSelectedAttachments", "BindableFunction") :: BindableFunction
	getSelected.OnInvoke = function()
		return controller:GetSelection()
	end

	-- H1: make sure the event exists before anyone looks for it.
	Bridge.confirmedEvent()

	-- character lifecycle
	local function onCharacterAdded(character: Model)
		clearCharacterConnections()
		controller:Close("respawn", "force")
		handler.Refresh()
		track(characterConnections, character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				handler.Refresh()
			end
		end))
		track(characterConnections, character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				handler.Refresh()
			end
		end))
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		if humanoid then
			track(characterConnections, (humanoid :: Humanoid).Died:Connect(function()
				controller:Close("died", "force")
			end))
		end
	end
	track(connections, player.CharacterAdded:Connect(onCharacterAdded))
	track(connections, player.CharacterRemoving:Connect(function()
		clearCharacterConnections()
		controller:Close("respawn", "force")
	end))
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	handler.Refresh()

	return function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
		clearCharacterConnections()
		if getSelected.OnInvoke then
			getSelected.OnInvoke = nil
		end
	end
end

return Bridge
