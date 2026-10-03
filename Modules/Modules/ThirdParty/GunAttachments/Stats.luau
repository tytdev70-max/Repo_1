--!nonstrict
-- GunAttachments/Stats
-- Base-stats store and the modifier pipeline.
--
-- * Base stats are deep-copied when stored, so the caller's table (often a shared,
--   require-cached WeaponStats module) is never mutated by attachments.
-- * Entries are released when the Tool is destroyed (strong keys: weak Instance keys
--   can be dropped by Roblox while the Instance still exists).
-- * Modifiers run in a caller-provided deterministic order.
-- * Optional JSON snapshots on the Tool let another Lua VM / script recover base stats.

local Util = require(script.Parent.Util)

export type StatsStore = {
	Set: (self: StatsStore, tool: Instance, stats: any) -> (),
	Get: (self: StatsStore, tool: Instance) -> any?,
	Forget: (self: StatsStore, tool: Instance) -> (),
	Clear: (self: StatsStore) -> (),
	WriteModifiedSnapshot: (self: StatsStore, tool: Instance, stats: any) -> (),
}

local Stats = {}
Stats.__index = Stats

Stats.deepCopy = Util.deepCopy

-- Applies modifiers in order. Each modifier is `fn(stats) -> stats?`.
-- * Returning a table replaces the working stats (original contract).
-- * Returning nil keeps the (possibly in-place mutated) working table instead of
--   propagating nil (old code would crash on the next modifier).
-- * An erroring modifier is skipped and reported; the pipeline continues.
function Stats.applyModifiers(base: any, modifiers: { { label: string, fn: any } }, log: Util.Logger?): any
	local working = Util.deepCopy(base)
	for _, modifier in ipairs(modifiers) do
		if type(modifier.fn) == "function" then
			local ok, result = pcall(modifier.fn, working)
			if not ok then
				if log then
					log.warn(("ApplyStats for '%s' errored: %s"):format(modifier.label, tostring(result)))
				end
			elseif type(result) == "table" then
				working = result
			end
		end
	end
	return working
end

function Stats.newStore(options: { [string]: any }, log: Util.Logger): StatsStore
	local statsOptions = options.stats or {}
	local hooks = options.hooks or {}
	local services = options.services or {}
	local self = setmetatable({
		_cache = {} :: { [Instance]: any },
		_destroyHooks = {} :: { [Instance]: any },
		_writeSnapshots = statsOptions.writeSnapshots ~= false,
		_originalAttribute = statsOptions.originalAttribute,
		_modifiedAttribute = statsOptions.modifiedAttribute,
		_onSnapshotRestored = hooks.onSnapshotRestored,
		_http = services.http,
		_log = log,
	}, Stats)
	return (self :: any) :: StatsStore
end

local function getHttp(store: any): any?
	if store._http then
		return store._http
	end
	local ok, service = pcall(function()
		return (game :: any):GetService("HttpService")
	end)
	if ok then
		store._http = service
		return service
	end
	return nil
end

-- Color3/UDim2/functions are not JSON-safe: snapshots are best-effort and must never
-- abort the caller (same policy as the original implementation).
local function writeSnapshot(store: any, tool: Instance, attribute: string?, stats: any)
	if not store._writeSnapshots or not attribute then
		return
	end
	local http = getHttp(store)
	local json = nil
	if http then
		local ok, encoded = pcall(function()
			return http:JSONEncode(stats)
		end)
		if ok then
			json = encoded
		end
	end
	pcall(function()
		(tool :: any):SetAttribute(attribute, json)
	end)
end

local function hookDestroy(store: any, tool: Instance)
	if store._destroyHooks[tool] then
		return
	end
	local ok, connection = pcall(function()
		return (tool :: any).Destroying:Connect(function()
			store:Forget(tool)
		end)
	end)
	if ok and connection then
		store._destroyHooks[tool] = connection
	end
end

function Stats:Set(tool: Instance, stats: any)
	local store = self :: any
	if not tool or type(stats) ~= "table" then
		return
	end
	store._cache[tool] = Util.deepCopy(stats)
	hookDestroy(store, tool)
	writeSnapshot(store, tool, store._originalAttribute, stats)
end

function Stats:Get(tool: Instance): any?
	local store = self :: any
	if not tool then
		return nil
	end
	local cached = store._cache[tool]
	if cached then
		return cached
	end

	if not store._originalAttribute then
		return nil
	end
	local okAttr, json = pcall(function()
		return (tool :: any):GetAttribute(store._originalAttribute)
	end)
	if not okAttr or type(json) ~= "string" then
		return nil
	end
	local http = getHttp(store)
	if not http then
		return nil
	end
	local okDecode, decoded = pcall(function()
		return http:JSONDecode(json)
	end)
	if not okDecode or type(decoded) ~= "table" then
		return nil
	end
	if store._onSnapshotRestored then
		local okHook, err = pcall(store._onSnapshotRestored, tool, decoded)
		if not okHook then
			store._log.warn("onSnapshotRestored errored: " .. tostring(err))
		end
	end
	store._cache[tool] = decoded
	hookDestroy(store, tool)
	return decoded
end

function Stats:Forget(tool: Instance)
	local store = self :: any
	store._cache[tool] = nil
	local hook = store._destroyHooks[tool]
	if hook then
		hook:Disconnect()
		store._destroyHooks[tool] = nil
	end
end

function Stats:Clear()
	local store = self :: any
	for _, hook in pairs(store._destroyHooks) do
		hook:Disconnect()
	end
	table.clear(store._destroyHooks)
	table.clear(store._cache)
end

function Stats:WriteModifiedSnapshot(tool: Instance, stats: any)
	local store = self :: any
	writeSnapshot(store, tool, store._modifiedAttribute, stats)
end

return Stats
