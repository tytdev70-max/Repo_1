--!nonstrict
-- Customize/Selection
-- Pure selection model for one customization session (no Roblox dependencies).
--
-- Holds `saved` (what the weapon had when the menu opened / last confirm) and
-- `current` (what the player has picked). Enforces per-slot "can be empty" and
-- delegates capacity/conflict rules to an injected `check` function (normally
-- GunAttachments:CheckSelection, so UI and server apply identical rules).
--
--   local sel = Selection.new({ check = fn?, allowEmpty = fn? })
--   sel:Load({ Optics = "RedDot" })
--   sel:Toggle("Optics", "RedDot")         --> clears Optics
--   sel:Select("Underbarrel", "VGrip")     --> ok, reason, displacedSlots
--   sel.Changed:Connect(function(change) ... end)
--
-- change = { kind = "select"|"clear"|"load"|"revert", slot = string?, name = string?,
--            displaced = { string } }

local Signal = require(script.Parent.Signal)

export type Loadout = { [string]: string }
export type CheckResult = { ok: boolean, reason: string?, displaced: { string }? }

local Selection = {}
Selection.__index = Selection

local function copy(loadout: Loadout?): Loadout
	local result = {}
	if loadout then
		for slot, name in pairs(loadout) do
			if type(slot) == "string" and type(name) == "string" and name ~= "" then
				result[slot] = name
			end
		end
	end
	return result
end

local function equal(a: Loadout, b: Loadout): boolean
	for slot, name in pairs(a) do
		if b[slot] ~= name then
			return false
		end
	end
	for slot, name in pairs(b) do
		if a[slot] ~= name then
			return false
		end
	end
	return true
end

function Selection.new(options: { check: ((Loadout, string, string) -> CheckResult?)?, allowEmpty: ((string) -> boolean)? }?)
	local opts = options or {}
	local self = setmetatable({
		_saved = {} :: Loadout,
		_current = {} :: Loadout,
		_check = opts.check,
		_allowEmpty = opts.allowEmpty,
	}, Selection)
	self.Changed = Signal.new()
	return self
end

-- Replaces both saved and current (start of a session).
function Selection:Load(loadout: Loadout?)
	self._saved = copy(loadout)
	self._current = copy(loadout)
	self.Changed:Fire({ kind = "load", displaced = {} })
end

-- Marks the current selection as saved (after confirm).
function Selection:MarkSaved(loadout: Loadout?)
	self._saved = copy(loadout or self._current)
end

function Selection:Get(slot: string): string?
	return self._current[slot]
end

function Selection:GetAll(): Loadout
	return copy(self._current)
end

function Selection:GetSaved(): Loadout
	return copy(self._saved)
end

function Selection:Count(): number
	local count = 0
	for _ in pairs(self._current) do
		count += 1
	end
	return count
end

function Selection:IsDirty(): boolean
	return not equal(self._saved, self._current)
end

function Selection:CanClear(slot: string): boolean
	if self._allowEmpty then
		local ok, verdict = pcall(self._allowEmpty, slot)
		if ok and verdict == false then
			return false
		end
	end
	return true
end

-- Picks `name` for `slot`. Rules run first; conflicting slots are cleared ("newest
-- pick wins"). Returns (ok, reason?, displacedSlots).
function Selection:Select(slot: string, name: string): (boolean, string?, { string })
	if type(slot) ~= "string" or type(name) ~= "string" or name == "" then
		return false, "invalid selection", {}
	end
	if self._current[slot] == name then
		return true, nil, {}
	end
	local displaced = {}
	if self._check then
		local ok, result = pcall(self._check, self:GetAll(), slot, name)
		if not ok then
			return false, "rule check failed: " .. tostring(result), {}
		end
		if result then
			if not result.ok then
				return false, result.reason or "not allowed", {}
			end
			displaced = result.displaced or {}
		end
	end
	for _, other in ipairs(displaced) do
		self._current[other] = nil
	end
	self._current[slot] = name
	self.Changed:Fire({ kind = "select", slot = slot, name = name, displaced = displaced })
	return true, nil, displaced
end

function Selection:Clear(slot: string): (boolean, string?)
	if self._current[slot] == nil then
		return true, nil
	end
	if not self:CanClear(slot) then
		return false, slot .. " cannot be empty"
	end
	self._current[slot] = nil
	self.Changed:Fire({ kind = "clear", slot = slot, displaced = {} })
	return true, nil
end

-- Original click semantics: clicking the selected item clears the slot, clicking
-- another item selects it.
function Selection:Toggle(slot: string, name: string): (boolean, string?, { string })
	if self._current[slot] == name then
		local ok, reason = self:Clear(slot)
		return ok, reason, {}
	end
	return self:Select(slot, name)
end

function Selection:Revert()
	self._current = copy(self._saved)
	self.Changed:Fire({ kind = "revert", displaced = {} })
end

function Selection:Destroy()
	self.Changed:DisconnectAll()
end

return Selection
