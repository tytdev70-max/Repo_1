--[[
	AttachmentSystem.Registry
	─────────────────────────
	Owns the live attachment state for every weapon model in the world.

	A "model" here is whatever Instance the host physically attaches things to
	(usually the first-person viewmodel model, sometimes a third-person copy).
	For each one the registry tracks:

	    entries[model][category] = { name, config, model }

	plus the weapon that owns the model, the set of categories currently
	driving an `OnUpdate` heartbeat, and a one-shot `Destroying` hook so state
	is released as soon as the model goes away rather than at the next sweep.

	All tables use weak keys, so a model the host drops without telling us does
	not pin memory for the rest of the session.
]]

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local Registry = {}

export type Entry = {
	attachmentName: string,
	category: string,
	config: any,
	model: Folder,
}

type ModelState = {
	entries: { [string]: Entry },
	updaters: { [string]: boolean },
	updaterCount: number,
}

-- Shared frozen table returned to callers that have nothing to report, so
-- they can iterate without a nil check. Never handed to code that writes.
local EMPTY: { [string]: Entry } = setmetatable({}, { __metatable = "readonly" })

local states: { [Instance]: ModelState } = setmetatable({}, { __mode = "k" })
local ownership: { [Instance]: Instance } = setmetatable({}, { __mode = "k" })
local destroyHooks: { [Instance]: RBXScriptConnection } = {}

local heartbeat: RBXScriptConnection? = nil
local totalUpdaters = 0

-- ─── Heartbeat ──────────────────────────────────────────────────────────────

--[[
	`OnUpdate` is called as `config.OnUpdate(weaponModel, category, deltaTime)`.
	The previous implementation invoked it as `config.OnUpdate(nil, nil, dt)`,
	which meant an attachment had no way to know which weapon it was on. The
	first two arguments were effectively always nil, so no existing attachment
	can have depended on them being nil.
]]
local function runUpdaters(deltaTime: number)
	for model, state in pairs(states) do
		if not model.Parent then
			Registry.Release(model)
		else
			for category in pairs(state.updaters) do
				local entry = state.entries[category]
				if entry and entry.config and type(entry.config.OnUpdate) == "function" then
					pcall(entry.config.OnUpdate, model, category, deltaTime)
				end
			end
		end
	end
end

local function ensureHeartbeat()
	if heartbeat or totalUpdaters <= 0 then
		return
	end
	heartbeat = RunService.Heartbeat:Connect(runUpdaters)
end

local function maybeStopHeartbeat()
	if totalUpdaters > 0 then
		return
	end
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

-- ─── State lifecycle ────────────────────────────────────────────────────────

local function getOrCreateState(model: Instance): ModelState
	local state = states[model]
	if not state then
		state = { entries = {}, updaters = {}, updaterCount = 0 }
		states[model] = state
	end
	return state
end

--[[
	Release all state for a model without touching the physical parts.
	`Mounter.Teardown` handles the instances; this only clears bookkeeping.
]]
function Registry.Release(model: Instance?)
	if not model then
		return
	end

	local state = states[model]
	if state then
		for category in pairs(state.updaters) do
			totalUpdaters = math.max(0, totalUpdaters - 1)
		end
		states[model] = nil
	end
	ownership[model] = nil

	local hook = destroyHooks[model]
	if hook then
		hook:Disconnect()
		destroyHooks[model] = nil
	end

	maybeStopHeartbeat()
end

local function hookDestroying(model: Instance)
	if destroyHooks[model] then
		return
	end
	destroyHooks[model] = model.Destroying:Connect(function()
		Registry.Release(model)
	end)
end

--[[
	Claim a model for a weapon. If the model was previously owned by a
	different weapon the host is expected to have torn it down already; we
	forget the stale entries so a recycled model cannot report attachments that
	belong to the previous owner's loadout.
]]
function Registry.Claim(model: Instance, weapon: Instance)
	if not model or not weapon then
		return
	end

	local previous = ownership[model]
	if previous and previous ~= weapon then
		Registry.ForgetEntries(model)
	end

	ownership[model] = weapon
	hookDestroying(model)
end

function Registry.GetOwner(model: Instance?): Instance?
	if not model then
		return nil
	end
	return ownership[model]
end

function Registry.IsOwnedBy(model: Instance?, weapon: Instance?): boolean
	if not model or not weapon then
		return false
	end
	local owner = ownership[model]
	if owner == nil then
		-- Never claimed: treat as unowned-but-available so a stat calculation
		-- still runs against a freshly spawned model.
		return true
	end
	return owner == weapon
end

--[[
	Drop just the registry entries for a model (used when a model changes
	owners). The physical parts are *not* touched here.
]]
function Registry.ForgetEntries(model: Instance?)
	if not model then
		return
	end
	local state = states[model]
	if not state then
		return
	end

	for category in pairs(state.updaters) do
		totalUpdaters = math.max(0, totalUpdaters - 1)
	end
	state.entries = {}
	state.updaters = {}
	state.updaterCount = 0
	states[model] = nil

	maybeStopHeartbeat()
end

-- ─── Entries ────────────────────────────────────────────────────────────────

function Registry.Set(model: Instance, category: string, entry: Entry?)
	local state = getOrCreateState(model)
	if entry == nil then
		state.entries[category] = nil
		if state.updaters[category] then
			state.updaters[category] = nil
			state.updaterCount = math.max(0, state.updaterCount - 1)
			totalUpdaters = math.max(0, totalUpdaters - 1)
		end
		maybeStopHeartbeat()
		return
	end

	state.entries[category] = entry

	if type(entry.config.OnUpdate) == "function" and not state.updaters[category] then
		state.updaters[category] = true
		state.updaterCount += 1
		totalUpdaters += 1
		ensureHeartbeat()
	end
end

function Registry.Get(model: Instance?, category: string): Entry?
	if not model then
		return nil
	end
	local state = states[model]
	return state and state.entries[category] or nil
end

--[[
	All live entries for a model. Returns the live internal table, so callers
	must treat it as read-only. Returns an empty table (never nil) when the
	model has no state, which lets callers write `for _, e in pairs(...)`
	without guarding.
]]
function Registry.GetAll(model: Instance?): { [string]: Entry }
	if not model then
		return EMPTY
	end
	local state = states[model]
	return state and state.entries or EMPTY
end

function Registry.Has(model: Instance?, category: string): boolean
	return Registry.Get(model, category) ~= nil
end

function Registry.Count(model: Instance?): number
	local state = model and states[model]
	if not state then
		return 0
	end
	local count = 0
	for _ in pairs(state.entries) do
		count += 1
	end
	return count
end

--[[
	Every category currently occupied on a model, in the configured category
	order. Used by queries that need a stable, deterministic iteration order.
]]
function Registry.GetOccupiedCategories(model: Instance?): {string}
	local result = {}
	local state = model and states[model]
	if not state then
		return result
	end
	for _, category in ipairs(Config.GetCategoryList()) do
		if state.entries[category] then
			table.insert(result, category)
		end
	end
	return result
end

-- ─── Introspection / diagnostics ────────────────────────────────────────────

function Registry.GetUpdaterCount(): number
	return totalUpdaters
end

function Registry.IsHeartbeatRunning(): boolean
	return heartbeat ~= nil
end

--[[
	A human-readable dump of a model's loadout. The previous implementation had
	a `DebugMuzzleState` that computed six locals and returned nothing; this is
	an actual, usable diagnostic that the host can log.
]]
function Registry.Describe(model: Instance?): string
	if not model then
		return "[AttachmentSystem] no model"
	end

	local active = Registry.GetAll(model)
	local parts = {}
	for _, category in ipairs(Registry.GetOccupiedCategories(model)) do
		table.insert(parts, string.format("%s=%s", category, active[category].attachmentName))
	end

	if #parts == 0 then
		return string.format("[AttachmentSystem] %s: no attachments", model.Name)
	end
	return string.format("[AttachmentSystem] %s: %s", model.Name, table.concat(parts, ", "))
end

--[[
	Describes the muzzle resolution for a model, including which of the three
	possible sources won. This is the debug facility the old `DebugMuzzleState`
	was clearly meant to provide.
]]
function Registry.DescribeMuzzle(model: Instance?, resolveMuzzle: any?): string
	if not model then
		return "[AttachmentSystem] no model"
	end

	local lines = { Registry.Describe(model) }
	lines[#lines + 1] = string.format("  hasMuzzleAttachment=%s",
		tostring(Registry.Has(model, "Muzzle")))

	local customName = model:GetAttribute(Config.Naming.activeCustomMuzzle)
	lines[#lines + 1] = string.format("  activeCustomMuzzle=%s", tostring(customName))

	if resolveMuzzle then
		local ok, muzzle = pcall(resolveMuzzle, model)
		if ok then
			lines[#lines + 1] = string.format("  resolved=%s",
				muzzle and muzzle:GetFullName() or "none")
		end
	end

	return table.concat(lines, "\n")
end

return Registry
