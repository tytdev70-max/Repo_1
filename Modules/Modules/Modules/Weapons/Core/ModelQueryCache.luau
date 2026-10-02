--!strict
-- Weapons/Core/ModelQueryCache
--
-- Memoizes "search the instance tree" results (GetDescendants / FindFirstChild*
-- chains) for a root Instance such as vars.gunModel, the third-person gun model,
-- a sight part or a projectile part.
--
-- Why: several per-frame (RenderStepped) paths re-derived the same data from the
-- weapon model every frame, e.g. `tpModel:GetDescendants()` just to find the
-- "SightReticle" parts. GetDescendants allocates a new array with every descendant
-- (often hundreds for a gun with attachments) and each FindFirstChild* crosses the
-- Lua/C++ bridge. The answer only changes when the model's hierarchy changes.
--
-- How it stays correct:
--   * Each root gets one entry with its query results.
--   * Any DescendantAdded / DescendantRemoving on the root clears ALL its results
--     (attachments being equipped/unequipped, mags removed, etc.).
--   * Destroying the root clears its results and drops its connections.
--   * A cached single-Instance result whose Parent became nil is recomputed.
--   * Entries are weak-keyed, so roots that are simply dropped get collected.
--   * Renaming a descendant is NOT observed; call ModelQueryCache.invalidate(root)
--     if you rename parts at runtime and rely on name-based queries.
--
-- Usage (no per-call closure allocation):
--   local part = ModelQueryCache.get(model, "projectile:Mag", computeFn, extraArg)
--   -- computeFn(model, extraArg) runs only on a miss; nil results are cached too.

local ModelQueryCache = {}

type Entry = {
	queries: { [string]: any },
	conns: { RBXScriptConnection },
	dead: boolean,
}

-- Sentinel so "not found" (nil) results are cached as well
local NIL_RESULT = table.freeze({})

local entries: { [Instance]: Entry } = setmetatable({}, { __mode = "k" }) :: any

local stats = {
	hits = 0,
	misses = 0,
	invalidations = 0,
}

local function clearEntry(entry: Entry)
	if next(entry.queries) ~= nil then
		table.clear(entry.queries)
		stats.invalidations += 1
	end
end

local function getEntry(root: Instance): Entry
	local entry = entries[root]
	if entry and not entry.dead then
		return entry
	end

	local newEntry: Entry = { queries = {}, conns = {}, dead = false }
	-- NOTE: handlers capture only `newEntry` (never `root`) so the weak key can be collected.
	local function onHierarchyChanged()
		clearEntry(newEntry)
	end
	table.insert(newEntry.conns, root.DescendantAdded:Connect(onHierarchyChanged))
	table.insert(newEntry.conns, root.DescendantRemoving:Connect(onHierarchyChanged))
	table.insert(newEntry.conns, root.Destroying:Connect(function()
		newEntry.dead = true
		clearEntry(newEntry)
		for _, conn in newEntry.conns do
			conn:Disconnect()
		end
		table.clear(newEntry.conns)
	end))

	entries[root] = newEntry
	return newEntry
end

-- Returns the cached result of `compute(root, arg)` for (root, key).
function ModelQueryCache.get<A, R>(root: Instance?, key: string, compute: (Instance, A) -> R, arg: A): R
	if not root then
		return nil :: any
	end

	local entry = getEntry(root)
	local cached = entry.queries[key]

	if cached ~= nil then
		if cached == NIL_RESULT then
			stats.hits += 1
			return nil :: any
		end
		-- Guard against a single cached Instance that was removed without an event
		-- reaching us yet (e.g. immediate-mode handler ordering).
		if typeof(cached) ~= "Instance" or (cached :: Instance).Parent ~= nil then
			stats.hits += 1
			return cached
		end
	end

	stats.misses += 1
	local result = compute(root, arg)
	if result == nil then
		entry.queries[key] = NIL_RESULT
	else
		entry.queries[key] = result
	end
	return result
end

-- Manually drop every cached result for `root` (e.g. after renaming parts).
function ModelQueryCache.invalidate(root: Instance?)
	if not root then
		return
	end
	local entry = entries[root]
	if entry then
		clearEntry(entry)
	end
end

function ModelQueryCache.getStats(): { hits: number, misses: number, invalidations: number }
	return table.clone(stats)
end

function ModelQueryCache.resetStats()
	stats.hits = 0
	stats.misses = 0
	stats.invalidations = 0
end

return ModelQueryCache