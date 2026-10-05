--!nonstrict
-- GunAttachments/Rules
-- Loadout rules: capacity (max attachments per weapon) and declared conflicts.
--
-- Pure functions. Used by System:SanitizeLoadout (so the server enforces them) and by
-- System:CheckSelection (so a UI can show/resolve them before the server sees them).
--
-- Conflicts are declared in attachment configs:
--     ConflictsWith = { "Underbarrel", "Muzzle/Suppressor" }
-- An entry is either a slot name (conflicts with anything in that slot) or
-- "Slot/Name" (conflicts with one attachment). Declarations are symmetric: either side
-- declaring the conflict is enough.

local Rules = {}

local function declares(config: any, otherSlot: string, otherName: string): boolean
	local list = config and config.ConflictsWith
	if type(list) ~= "table" then
		return false
	end
	local qualified = otherSlot .. "/" .. otherName
	for _, entry in ipairs(list) do
		if entry == otherSlot or entry == qualified then
			return true
		end
	end
	return false
end

-- True when (slotA, nameA) and (slotB, nameB) may not be equipped together.
function Rules.conflicts(slotA: string, nameA: string, configA: any, slotB: string, nameB: string, configB: any): boolean
	if slotA == slotB then
		return false -- same slot is a replacement, not a conflict
	end
	return declares(configA, slotB, nameB) or declares(configB, slotA, nameA)
end

-- Applies capacity + conflicts deterministically: entries are visited in slot order;
-- each is accepted unless it conflicts with an already-accepted entry or the capacity
-- is full. Returns (accepted, dropped).
--   orderedSlots: slot names of `loadout` sorted by slot order
--   loadConfig:   function(slot, name) -> config?
--   capacity:     number? (nil = unlimited)
function Rules.apply(
	loadout: { [string]: string },
	orderedSlots: { string },
	loadConfig: (string, string) -> any,
	capacity: number?
): ({ [string]: string }, { { slot: string, name: string, reason: string } })
	local accepted: { [string]: string } = {}
	local acceptedList: { { slot: string, name: string, config: any } } = {}
	local dropped = {}
	for _, slot in ipairs(orderedSlots) do
		local name = loadout[slot]
		if name == nil then
			continue
		end
		local config = loadConfig(slot, name)
		local reason = nil
		for _, other in ipairs(acceptedList) do
			if Rules.conflicts(slot, name, config, other.slot, other.name, other.config) then
				reason = "conflicts with " .. other.slot .. "/" .. other.name
				break
			end
		end
		if not reason and capacity and #acceptedList >= capacity then
			reason = "attachment limit (" .. capacity .. ") reached"
		end
		if reason then
			table.insert(dropped, { slot = slot, name = name, reason = reason })
		else
			accepted[slot] = name
			table.insert(acceptedList, { slot = slot, name = name, config = config })
		end
	end
	return accepted, dropped
end

-- What would happen if `name` were picked for `slot` on top of `loadout` with the
-- "newest pick wins" policy: conflicting entries are displaced; the pick is refused
-- only if capacity would still be exceeded.
-- Returns { ok: boolean, reason: string?, displaced: { string } (slot names) }.
function Rules.check(
	loadout: { [string]: string },
	slot: string,
	name: string,
	loadConfig: (string, string) -> any,
	capacity: number?
)
	local config = loadConfig(slot, name)
	local displaced = {}
	local remaining = 0
	for otherSlot, otherName in pairs(loadout) do
		if otherSlot == slot then
			continue
		end
		if Rules.conflicts(slot, name, config, otherSlot, otherName, loadConfig(otherSlot, otherName)) then
			table.insert(displaced, otherSlot)
		else
			remaining += 1
		end
	end
	table.sort(displaced)
	if capacity and remaining + 1 > capacity then
		return { ok = false, reason = "attachment limit (" .. capacity .. ") reached", displaced = {} }
	end
	return { ok = true, reason = nil, displaced = displaced }
end

return Rules
