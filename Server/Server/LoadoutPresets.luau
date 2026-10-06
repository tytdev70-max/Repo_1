-- LoadoutPresets
-- Saved attachment setups ("presets") per player and gun type, kept in a DataStore.
--
-- Rules:
--   * Saving a preset stores it only. The gun is not changed.
--   * Applying a saved preset (the customize menu sends the preset name with
--     ApplyWeaponAttachments) puts it on the gun AND makes it the gun type's ACTIVE
--     preset. Only one preset per gun type can be active.
--   * New copies of that gun type the player receives (gun giver, respawn, rejoin)
--     get the active preset automatically.
--   * When the gun carrying the active preset is dropped or lost (it leaves the
--     player's Backpack/Character: drop, death, respawn) the active mark is cleared.
--     The presets themselves stay saved. Leaving the game clears it only when
--     config.dropOnLeave is on.
--   * A normal Confirm that changes a gun carrying the active preset also clears it
--     (the gun no longer has the preset). Confirming the same attachments keeps it.
--
-- Remote: GunEvents.LoadoutPresets (RemoteFunction), always for the EQUIPPED gun:
--   InvokeServer("list")                 -> state
--   InvokeServer("save", name, loadout)  -> state (+ saved = cleanName)
--   InvokeServer("rename", old, new)     -> state (+ renamed = cleanName)
--   InvokeServer("delete", name)         -> state
--   state = { ok = true, gun, presets = { {name, loadout} }, active, carried,
--             max, maxNameLength, persistent }  or  { ok = false, error = code }

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local ServiceRefs = require(script.Parent.ServiceRefs)
local AssetRefs = require(script.Parent.AssetRefs)
local ServerHelpers = require(script.Parent.ServerHelpers)

local players = ServiceRefs.players
local modules = AssetRefs.modules
local config = AssetRefs.config
local Attachments = AssetRefs.Attachments
local PresetBook = require(modules.Weapons.Presets.PresetBook)
local Settings = require(modules.Weapons.Presets.PresetSettings)
local SPH_Events = require(modules.Core.Networking.SPH_Events)

local ATTR_PRESET = "AppliedPreset" -- on a Tool: name of the active preset it carries
local ATTR_OWNER = "AppliedPresetOwner" -- UserId of the player whose preset it is
local ATTR_CHECKED = "PresetAutoChecked" -- the auto-apply check ran for this Tool
local MAX_DATA_SIZE = 3_500_000 -- characters of JSON (a DataStore key holds 4 MB)
local RETRIES = 3

local LoadoutPresets = {}

type Session = {
	book: any,
	loaded: boolean,
	persistent: boolean, -- false: never write to the DataStore (load failed / no access)
	dirty: boolean,
	leaving: boolean,
	carriers: { [Tool]: { RBXScriptConnection } },
	tokens: number,
	refilled: number,
	connections: { RBXScriptConnection },
}

local sessions: { [Player]: Session } = {}
local store: DataStore? = nil
local storeResolved = false

local function log(...)
	warn("[LoadoutPresets]", ...)
end

local function getStore(): DataStore?
	if storeResolved then
		return store
	end
	storeResolved = true
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, Settings.dataStoreName)
	if ok then
		store = result
	else
		log("DataStore unavailable, presets will last for this session only:", result)
	end
	return store
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

-- ─── carriers: tools that carry the active preset ──────────────────────────────

local function owned(player: Player, tool: Instance): boolean
	local parent = tool.Parent
	if not parent then
		return false
	end
	if parent == player.Character then
		return true
	end
	return parent:IsA("Backpack") and parent.Parent == player
end

local function unmark(session: Session, tool: Tool)
	local connections = session.carriers[tool]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		session.carriers[tool] = nil
	end
	if tool.Parent ~= nil or tool:GetAttribute(ATTR_PRESET) ~= nil then
		tool:SetAttribute(ATTR_PRESET, nil)
		tool:SetAttribute(ATTR_OWNER, nil)
	end
end

local function unmarkGun(session: Session, gun: string, except: Tool?)
	for tool in pairs(session.carriers) do
		if tool.Name == gun and tool ~= except then
			unmark(session, tool)
		end
	end
end

local onLost: (Player, Tool) -> ()

local function markCarrier(session: Session, player: Player, tool: Tool, name: string)
	unmark(session, tool)
	tool:SetAttribute(ATTR_PRESET, name)
	tool:SetAttribute(ATTR_OWNER, player.UserId)
	local function check()
		if not owned(player, tool) then
			onLost(player, tool)
		end
	end
	session.carriers[tool] = {
		tool.AncestryChanged:Connect(check),
		tool.Destroying:Connect(function()
			onLost(player, tool)
		end),
	}
end

-- The gun carrying the active preset was dropped or lost: clear the active mark.
function onLost(player: Player, tool: Tool)
	local session = sessions[player]
	if not session or session.leaving or not session.carriers[tool] then
		return
	end
	local name = tool:GetAttribute(ATTR_PRESET)
	local gun = tool.Name
	unmark(session, tool)
	if name and session.book:GetActive(gun) == name then
		session.book:SetActive(gun, nil)
		session.dirty = true
		unmarkGun(session, gun)
	end
end

-- ─── auto-apply ────────────────────────────────────────────────────────────────

local function isWeapon(instance: Instance): boolean
	return instance:IsA("Tool") and instance:FindFirstChild("SPH_Weapon") ~= nil
end

local function maybeAutoApply(player: Player, tool: Instance)
	local session = sessions[player]
	if not session or not session.loaded or not Settings.enabled or not isWeapon(tool) then
		return -- not loaded yet: the sweep after loading handles it
	end
	if tool:GetAttribute(ATTR_CHECKED) then
		return
	end
	tool:SetAttribute(ATTR_CHECKED, true)
	if Attachments:HasLoadout(tool) then
		return -- already customized (e.g. a gun picked up from the ground)
	end
	local name, loadout = session.book:GetActive(tool.Name)
	if not name then
		return
	end
	local clean = Attachments:SanitizeLoadout(loadout, tool)
	-- Stored on the Tool; EquipGun (server) and the client viewmodel mount it on equip.
	Attachments:SetLoadout(tool, clean)
	markCarrier(session, player, tool :: Tool, name)
end

local function sweepTools(player: Player)
	local containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				maybeAutoApply(player, child)
			end
		end
	end
end

-- ─── persistence ───────────────────────────────────────────────────────────────

local function load(player: Player, session: Session)
	local dataStore = getStore()
	if not dataStore then
		session.loaded = true
		session.persistent = false
		return
	end
	for attempt = 1, RETRIES do
		local ok, result = pcall(dataStore.GetAsync, dataStore, keyFor(player))
		if ok then
			session.book = PresetBook.new(result)
			session.loaded = true
			session.persistent = true
			return
		end
		local message = tostring(result)
		if message:find("StudioAccessToApisNotAllowed") or message:find("API Services") then
			log("Studio has no DataStore access (Game Settings > Security > Enable Studio Access to API Services);"
				.. " presets last for this session only")
			break
		end
		log(("load attempt %d for %s failed: %s"):format(attempt, player.Name, message))
		if attempt < RETRIES then
			task.wait(attempt * 2)
		end
	end
	-- Never write over stored data we could not read.
	session.loaded = true
	session.persistent = false
end

local function save(player: Player, session: Session)
	if not session.persistent or not session.dirty then
		return
	end
	local dataStore = getStore()
	if not dataStore then
		return
	end
	local data = session.book:Serialize()
	session.dirty = false
	for attempt = 1, RETRIES do
		local ok, err = pcall(dataStore.UpdateAsync, dataStore, keyFor(player), function()
			return data
		end)
		if ok then
			return
		end
		log(("save attempt %d for %s failed: %s"):format(attempt, player.Name, tostring(err)))
		if attempt < RETRIES then
			task.wait(attempt * 2)
		end
	end
	session.dirty = true -- try again next autosave / on leave
end

local function fitsStorage(session: Session): boolean
	local ok, json = pcall(HttpService.JSONEncode, HttpService, session.book:Serialize())
	return ok and #json <= MAX_DATA_SIZE
end

-- ─── remote ────────────────────────────────────────────────────────────────────

local function fail(code: string)
	return { ok = false, error = code }
end

local function state(session: Session, player: Player, tool: Tool, extra: { [string]: any }?)
	local list, active = session.book:List(tool.Name)
	local carried = nil
	if tool:GetAttribute(ATTR_OWNER) == player.UserId then
		carried = tool:GetAttribute(ATTR_PRESET)
	end
	local result = {
		ok = true,
		gun = tool.Name,
		presets = list,
		active = active,
		carried = carried,
		max = Settings.maxPresetsPerGun,
		maxNameLength = Settings.maxNameLength,
		persistent = session.persistent,
	}
	for key, value in pairs(extra or {}) do
		result[key] = value
	end
	return result
end

local function allowRequest(session: Session): boolean
	local rate = Settings.maxRequestsPerSecond or 6
	local now = os.clock()
	session.tokens = math.min(rate, session.tokens + (now - session.refilled) * rate)
	session.refilled = now
	if session.tokens < 1 then
		return false
	end
	session.tokens -= 1
	return true
end

local function handle(player: Player, action: any, first: any, second: any)
	if not Settings.enabled then
		return fail("disabled")
	end
	local session = sessions[player]
	if not session then
		return fail("loading")
	end
	if not allowRequest(session) then
		return fail("rate_limited")
	end
	if not session.loaded then
		return fail("loading")
	end
	local tool = ServerHelpers.GetEquippedWeaponTool(player)
	if not tool then
		return fail("no_weapon")
	end
	local gun = tool.Name
	local book = session.book

	if action == "list" then
		return state(session, player, tool)
	elseif action == "save" then
		local loadout = Attachments:SanitizeLoadout(type(second) == "table" and second or {}, tool)
		local cleanName = PresetBook.cleanName(first, Settings.maxNameLength)
		local previous = cleanName and book:Get(gun, cleanName)
		local ok, err, name = book:Save(gun, first, loadout, {
			maxPresets = Settings.maxPresetsPerGun,
			maxNameLength = Settings.maxNameLength,
		})
		if not ok then
			return fail(err or "name")
		end
		if not fitsStorage(session) then
			if previous then
				book:Save(gun, name, previous)
			else
				book:Delete(gun, name)
			end
			return fail("storage_full")
		end
		session.dirty = true
		return state(session, player, tool, { saved = name })
	elseif action == "rename" then
		if type(first) ~= "string" then
			return fail("missing")
		end
		local ok, err, name = book:Rename(gun, first, second, Settings.maxNameLength)
		if not ok then
			return fail(err or "name")
		end
		for carrier in pairs(session.carriers) do
			if carrier.Name == gun and carrier:GetAttribute(ATTR_PRESET) == first then
				carrier:SetAttribute(ATTR_PRESET, name)
			end
		end
		session.dirty = true
		return state(session, player, tool, { renamed = name })
	elseif action == "delete" then
		if type(first) ~= "string" or not book:Delete(gun, first) then
			return fail("missing")
		end
		for carrier in pairs(session.carriers) do
			if carrier.Name == gun and carrier:GetAttribute(ATTR_PRESET) == first then
				unmark(session, carrier)
			end
		end
		session.dirty = true
		return state(session, player, tool)
	end
	return fail("bad_request")
end

-- Called by the ApplyWeaponAttachments handler after the equipped gun got `applied`.
-- `presetName` is sent by the customize menu when the player applied a saved preset.
function LoadoutPresets.OnLoadoutApplied(player: Player, tool: Tool, applied: { [string]: string }, presetName: any)
	local session = sessions[player]
	if not session or not session.loaded or not Settings.enabled then
		return
	end
	if tool:GetAttribute("GunsmithTestGun") then
		return -- Test Loadout copy: never a preset carrier
	end
	local gun = tool.Name
	local book = session.book
	if type(presetName) == "string" then
		local preset = book:Get(gun, presetName)
		if preset and PresetBook.sameLoadout(Attachments:SanitizeLoadout(preset, tool), applied) then
			unmarkGun(session, gun, tool) -- one active preset per gun type
			book:SetActive(gun, presetName)
			session.dirty = true
			markCarrier(session, player, tool, presetName)
			return
		end
	end
	-- Normal confirm: if this gun carried the active preset and now differs, clear it.
	local carried = session.carriers[tool] and tool:GetAttribute(ATTR_PRESET)
	if not carried then
		return
	end
	local preset = book:Get(gun, carried)
	if preset and PresetBook.sameLoadout(Attachments:SanitizeLoadout(preset, tool), applied) then
		return -- same attachments re-confirmed
	end
	unmark(session, tool)
	if book:GetActive(gun) == carried then
		book:SetActive(gun, nil)
		session.dirty = true
		unmarkGun(session, gun)
	end
end

-- ─── lifecycle ─────────────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	if sessions[player] then
		return
	end
	local session: Session = {
		book = PresetBook.new(),
		loaded = false,
		persistent = false,
		dirty = false,
		leaving = false,
		carriers = {},
		tokens = Settings.maxRequestsPerSecond or 6,
		refilled = os.clock(),
		connections = {},
	}
	sessions[player] = session

	local function watch(container: Instance)
		table.insert(session.connections, container.ChildAdded:Connect(function(child)
			maybeAutoApply(player, child)
		end))
	end
	local function onChildAdded(child: Instance)
		if child:IsA("Backpack") then
			watch(child)
			for _, tool in ipairs(child:GetChildren()) do
				maybeAutoApply(player, tool)
			end
		end
	end
	table.insert(session.connections, player.ChildAdded:Connect(onChildAdded))
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		onChildAdded(backpack)
	end
	local function onCharacter(character: Model)
		watch(character)
		for _, child in ipairs(character:GetChildren()) do
			maybeAutoApply(player, child)
		end
	end
	table.insert(session.connections, player.CharacterAdded:Connect(onCharacter))
	if player.Character then
		onCharacter(player.Character)
	end

	task.spawn(function()
		load(player, session)
		if sessions[player] == session then
			sweepTools(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	session.leaving = true -- tools being destroyed now must not count as "lost"
	if config.dropOnLeave then
		-- guns are dropped on leave: treat it like a drop
		for tool in pairs(session.carriers) do
			local name = tool:GetAttribute(ATTR_PRESET)
			if name and session.book:GetActive(tool.Name) == name then
				session.book:SetActive(tool.Name, nil)
				session.dirty = true
			end
		end
	end
	for tool in pairs(session.carriers) do
		local connections = session.carriers[tool]
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end
	table.clear(session.carriers)
	for _, connection in ipairs(session.connections) do
		connection:Disconnect()
	end
	save(player, session)
	if sessions[player] == session then
		sessions[player] = nil
	end
end

function LoadoutPresets.init()
	if not Settings.enabled then
		return
	end
	local remote = SPH_Events.GetOrCreate("GunEvents", "LoadoutPresets", "RemoteFunction") :: RemoteFunction
	remote.OnServerInvoke = function(player, action, first, second)
		local ok, result = pcall(handle, player, action, first, second)
		if not ok then
			log("request failed:", result)
			return fail("server_error")
		end
		return result
	end

	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(Settings.autosaveInterval or 120)
			for player, session in pairs(sessions) do
				if session.dirty and not session.leaving then
					task.spawn(save, player, session)
				end
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for player, session in pairs(sessions) do
			pending += 1
			task.spawn(function()
				save(player, session)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return LoadoutPresets
