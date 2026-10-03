--!nonstrict
-- GunAttachments/Slots
-- Validated slot table: name -> definition, ordering, mount part resolution.

local Types = require(script.Parent.Types)

type SlotDef = Types.SlotDef

export type SlotTable = {
	byName: { [string]: SlotDef },
	ordered: { SlotDef },
	byRole: { [string]: SlotDef },
	allowUnknown: boolean,
}

local Slots = {}

function Slots.build(definitions: { SlotDef }, allowUnknown: boolean?): SlotTable
	local byName: { [string]: SlotDef } = {}
	local ordered: { SlotDef } = {}
	for index, raw in ipairs(definitions) do
		assert(type(raw) == "table", "GunAttachments: slot definition must be a table")
		assert(type(raw.name) == "string" and raw.name ~= "", "GunAttachments: slot needs a name")
		assert(byName[raw.name] == nil, "GunAttachments: duplicate slot '" .. raw.name .. "'")
		local def: SlotDef = {
			name = raw.name,
			mountPart = if type(raw.mountPart) == "string" then raw.mountPart else raw.name .. "Part",
			order = if type(raw.order) == "number" then raw.order else index,
			role = if type(raw.role) == "string" then raw.role else nil,
			overridesMuzzle = raw.overridesMuzzle == true,
		}
		byName[def.name] = def
		table.insert(ordered, def)
	end
	table.sort(ordered, function(a, b)
		if a.order == b.order then
			return a.name < b.name
		end
		return a.order < b.order
	end)
	local byRole: { [string]: SlotDef } = {}
	for _, def in ipairs(ordered) do
		if def.role and byRole[def.role] == nil then
			byRole[def.role] = def
		end
	end
	return { byName = byName, ordered = ordered, byRole = byRole, allowUnknown = allowUnknown == true }
end

function Slots.isValid(slots: SlotTable, name: any): boolean
	if type(name) ~= "string" or name == "" then
		return false
	end
	return slots.byName[name] ~= nil or slots.allowUnknown
end

-- Definition for a slot; unknown slots get a synthetic definition when allowed
-- (old behaviour: category "X" mounts on "XPart").
function Slots.get(slots: SlotTable, name: string): SlotDef?
	local def = slots.byName[name]
	if def then
		return def
	end
	if slots.allowUnknown and type(name) == "string" and name ~= "" then
		return { name = name, mountPart = name .. "Part", order = math.huge, overridesMuzzle = false }
	end
	return nil
end

function Slots.forRole(slots: SlotTable, role: string): SlotDef?
	return slots.byRole[role]
end

-- Sorts a list of slot names by slot order (unknown slots last, alphabetical).
function Slots.sortNames(slots: SlotTable, names: { string }): { string }
	table.sort(names, function(a, b)
		local defA, defB = slots.byName[a], slots.byName[b]
		local orderA = defA and defA.order or math.huge
		local orderB = defB and defB.order or math.huge
		if orderA == orderB then
			return a < b
		end
		return orderA < orderB
	end)
	return names
end

return Slots
