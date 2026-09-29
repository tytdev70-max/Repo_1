--[[
	AttachmentSystem.StatModifier
	─────────────────────────────
	The stat pipeline: take a weapon's *base* stats, run every equipped
	attachment's `ApplyStats` over a working copy, and publish the result.

	Two behaviours differ deliberately from the previous implementation:

	  1. `DeepCopy` guards against cycles and preserves shared references, so
	     a weapon whose stats table contains a CFrame (or any self-referential
	     table) can be copied without hanging or dropping data.

	  2. Attribute mirroring is best-effort. A stats table that JSON cannot
	     represent is still computed and returned to the caller; only the
	     `ModifiedStats` mirror is skipped. Previously the unguarded
	     `HttpService:JSONEncode` call threw and aborted the whole pipeline.
]]

local Config    = require(script.Parent.Config)
local Registry  = require(script.Parent.Registry)

local StatModifier = {}

-- ─── Deep copy ──────────────────────────────────────────────────────────────

--[[
	Copy a stats table. Handles cycles via a `seen` map (so the same sub-table
	referenced twice becomes one shared copy rather than two) and recurses into
	nested tables only, passing every other value through untouched.
]]
function StatModifier.DeepCopy(original: any, _seen: { [any]: any }?): any
	if type(original) ~= "table" then
		return original
	end

	local seen = _seen or {}
	local existing = seen[original]
	if existing ~= nil then
		return existing
	end

	local copy = {}
	seen[original] = copy

	for key, value in pairs(original) do
		copy[key] = StatModifier.DeepCopy(value, seen)
	end

	-- Preserve the metatable if there is one; most stats tables are plain, but
	-- a host may use a readable/frozen variant and dropping it would change
	-- behaviour on every downstream read.
	local meta = getmetatable(original)
	if meta and type(meta) == "table" then
		setmetatable(copy, meta)
	end

	return copy
end

-- ─── Weapon model resolution ────────────────────────────────────────────────

--[[
	When no model is supplied, fall back to the model currently shown to the
	player. The previous implementation chained
	`workspace.CurrentCamera -> FindFirstChildWhichIsA("Model") -> "Weapon"`,
	which silently returned nil for any camera without that exact child.
	`resolveProvidedModel` accepts either a Model, a folder containing one, or
	nil, and never assumes a particular ancestry.
]]
local function resolveProvidedModel(candidate: any): Model?
	if not candidate then
		return nil
	end
	if candidate:IsA("Model") then
		return candidate
	end
	if candidate:IsA("Folder") or candidate:IsA("Tool") or candidate:IsA("Model") then
		return candidate:FindFirstChildWhichIsA("Model")
	end
	return nil
end

function StatModifier.FindEquippedModel(): Model?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local direct = camera:FindFirstChildWhichIsA("Model")
	if direct then
		return direct
	end

	for _, child in ipairs(camera:GetChildren()) do
		local model = child:FindFirstChildWhichIsA("Model")
		if model then
			return model
		end
	end

	return nil
end

-- ─── The pipeline ───────────────────────────────────────────────────────────

--[[
	Produce the weapon's effective stats.

	@param weapon        the Tool (or any Instance) holding the loadout
	@param weaponModel   the model the attachments are physically on; when nil
	                     the currently-equipped model is used
	@return the modified stats table, or nil when the weapon has no base stats
]]
function StatModifier.Apply(weapon: Instance?, weaponModel: Instance?): any?
	if not weapon then
		return nil
	end

	-- Required lazily: Storage depends on this module for DeepCopy, so a
	-- top-level require here would form a cycle.
	local Storage = require(script.Parent.Storage)

	local baseStats = Storage.GetBaseStats(weapon)
	if not baseStats then
		return nil
	end

	-- Every caller gets their own working copy, so an ApplyStats that mutates
	-- its argument in place cannot corrupt the cached baseline.
	local modifiedStats = StatModifier.DeepCopy(baseStats)

	local model = resolveProvidedModel(weaponModel) or StatModifier.FindEquippedModel()
	if not model then
		return modifiedStats
	end

	-- A model owned by a different weapon is not ours to modify; hand back the
	-- unmodified baseline rather than a silently wrong result.
	if not Registry.IsOwnedBy(model, weapon) then
		return modifiedStats
	end

	local active = Registry.GetAll(model)
	if not active then
		return modifiedStats
	end

	-- Deterministic order so two attachments touching the same stat key always
	-- produce the same result regardless of hash iteration order.
	for _, category in ipairs(Config.GetCategoryList()) do
		local entry = active[category]
		if entry and entry.config and type(entry.config.ApplyStats) == "function" then
			local ok, result = pcall(entry.config.ApplyStats, modifiedStats)
			if ok and type(result) == "table" then
				modifiedStats = result
			end
			-- A throwing ApplyStats leaves the previous table in place rather
			-- than losing every stat the weapon has.
		end
	end

	Storage.StoreModifiedStats(weapon, modifiedStats)
	return modifiedStats
end

--[[
	The inverse: re-apply the equipped attachments on top of a *different*
	baseline. Used when a host swaps a weapon's stat table out from under the
	attachment system without changing the loadout.
]]
function StatModifier.Reapply(weapon: Instance?, baseStats: any?, weaponModel: Instance?): any?
	if not weapon or type(baseStats) ~= "table" then
		return nil
	end

	local Storage = require(script.Parent.Storage)
	Storage.StoreBaseStats(weapon, baseStats)
	return StatModifier.Apply(weapon, weaponModel)
end

--[[
	The list of attachment names currently contributing stat changes. Useful
	for a host that wants to show "this optic changed your recoil" style
	tooltips without walking the registry itself.
]]
function StatModifier.GetContributors(weaponModel: Instance?): {string}
	local result = {}
	local active = weaponModel and Registry.GetAll(weaponModel)
	if not active then
		return result
	end

	for category, entry in pairs(active) do
		if entry and entry.config and type(entry.config.ApplyStats) == "function" then
			table.insert(result, string.format("%s:%s", category, entry.attachmentName or "?"))
		end
	end
	table.sort(result)
	return result
end

return StatModifier
