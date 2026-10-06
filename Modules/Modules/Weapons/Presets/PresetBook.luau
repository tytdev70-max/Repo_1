--!nonstrict
-- Weapons/Presets/PresetBook
-- One player's presets, as plain data that can be stored in a DataStore. Pure Luau:
-- no Roblox APIs, so the rules are unit-tested (Tests/GunAttachments/spec_presets).
--
-- Stored shape (version 1):
--   { version = 1, guns = { [gunName] = {
--       order   = { presetName, ... },                 -- display order (oldest first)
--       presets = { [presetName] = { [slot] = attachmentName } },
--       active  = presetName?,                          -- auto-applied to new copies
--   } } }
--
-- The book does not know which attachments exist: the server sanitizes every loadout
-- (Attachments:SanitizeLoadout) before it is saved or applied.

export type Loadout = { [string]: string }
export type GunEntry = { order: { string }, presets: { [string]: Loadout }, active: string? }
export type Data = { version: number, guns: { [string]: GunEntry } }
export type SaveOptions = { maxPresets: number?, maxNameLength: number? }

local PresetBook = {}
PresetBook.__index = PresetBook

PresetBook.VERSION = 1
PresetBook.MAX_SLOTS = 32 -- per loadout
PresetBook.MAX_FIELD_LENGTH = 64 -- slot and attachment names
PresetBook.MAX_GUN_NAME_LENGTH = 64

-- Trims, removes control characters and collapses spaces. nil if nothing is left.
function PresetBook.cleanName(name: any, maxLength: number?): string?
	if type(name) ~= "string" then
		return nil
	end
	local cleaned = name:gsub("%c", ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
	local limit = maxLength or 24
	if utf8.len(cleaned) == nil then
		return nil -- invalid UTF-8
	end
	if (utf8.len(cleaned) :: number) > limit then
		cleaned = cleaned:sub(1, (utf8.offset(cleaned, limit + 1) :: number) - 1)
		cleaned = cleaned:match("^(.-)%s*$") or cleaned
	end
	return if cleaned == "" then nil else cleaned
end

local function validField(value: any): boolean
	return type(value) == "string" and value ~= "" and #value <= PresetBook.MAX_FIELD_LENGTH
end

-- Copy of `loadout` keeping only string -> string entries (structure check only).
function PresetBook.cleanLoadout(loadout: any): Loadout
	local result: Loadout = {}
	if type(loadout) ~= "table" then
		return result
	end
	local count = 0
	for slot, name in pairs(loadout) do
		if validField(slot) and validField(name) then
			count += 1
			if count > PresetBook.MAX_SLOTS then
				break
			end
			result[slot] = name
		end
	end
	return result
end

local function copy(loadout: Loadout): Loadout
	return table.clone(loadout)
end

-- Builds a book from stored data. Anything malformed is dropped, never trusted.
function PresetBook.new(raw: any?)
	local self = setmetatable({}, PresetBook)
	local data: Data = { version = PresetBook.VERSION, guns = {} }
	if type(raw) == "table" and type(raw.guns) == "table" then
		for gunName, entry in pairs(raw.guns) do
			if type(gunName) ~= "string" or #gunName > PresetBook.MAX_GUN_NAME_LENGTH or type(entry) ~= "table" then
				continue
			end
			local presets = type(entry.presets) == "table" and entry.presets or {}
			local clean: GunEntry = { order = {}, presets = {}, active = nil }
			local seen = {}
			local function add(name: any)
				if type(name) == "string" and not seen[name] and PresetBook.cleanName(name, 200) == name then
					local loadout = presets[name]
					if type(loadout) == "table" then
						seen[name] = true
						table.insert(clean.order, name)
						clean.presets[name] = PresetBook.cleanLoadout(loadout)
					end
				end
			end
			for _, name in ipairs(type(entry.order) == "table" and entry.order or {}) do
				add(name)
			end
			local rest = {}
			for name in pairs(presets) do
				if type(name) == "string" and not seen[name] then
					table.insert(rest, name)
				end
			end
			table.sort(rest)
			for _, name in ipairs(rest) do
				add(name)
			end
			if type(entry.active) == "string" and clean.presets[entry.active] then
				clean.active = entry.active
			end
			if #clean.order > 0 then
				data.guns[gunName] = clean
			end
		end
	end
	self._data = data
	return self
end

function PresetBook:_gun(gunName: string, create: boolean?): GunEntry?
	local entry = self._data.guns[gunName]
	if not entry and create then
		entry = { order = {}, presets = {}, active = nil }
		self._data.guns[gunName] = entry
	end
	return entry
end

function PresetBook:_dropIfEmpty(gunName: string)
	local entry = self._data.guns[gunName]
	if entry and #entry.order == 0 then
		self._data.guns[gunName] = nil
	end
end

-- { { name, loadout } } in display order, plus the active preset name.
function PresetBook:List(gunName: string): ({ { name: string, loadout: Loadout } }, string?)
	local entry = self:_gun(gunName)
	local list = {}
	if not entry then
		return list, nil
	end
	for _, name in ipairs(entry.order) do
		table.insert(list, { name = name, loadout = copy(entry.presets[name]) })
	end
	return list, entry.active
end

function PresetBook:Count(gunName: string): number
	local entry = self:_gun(gunName)
	return if entry then #entry.order else 0
end

function PresetBook:Get(gunName: string, name: string): Loadout?
	local entry = self:_gun(gunName)
	local loadout = entry and entry.presets[name]
	return if loadout then copy(loadout) else nil
end

-- Saves (or overwrites, keeping its place) a preset. Returns ok, errorCode, cleanName.
-- Error codes: "name" (empty/invalid), "gun", "limit".
function PresetBook:Save(gunName: string, name: any, loadout: any, options: SaveOptions?): (boolean, string?, string?)
	local opts = options or {}
	if type(gunName) ~= "string" or gunName == "" or #gunName > PresetBook.MAX_GUN_NAME_LENGTH then
		return false, "gun", nil
	end
	local clean = PresetBook.cleanName(name, opts.maxNameLength)
	if not clean then
		return false, "name", nil
	end
	local entry = self:_gun(gunName, true) :: GunEntry
	if not entry.presets[clean] then
		if opts.maxPresets and #entry.order >= opts.maxPresets then
			self:_dropIfEmpty(gunName)
			return false, "limit", clean
		end
		table.insert(entry.order, clean)
	end
	entry.presets[clean] = PresetBook.cleanLoadout(loadout)
	return true, nil, clean
end

-- Removes a preset (and the active mark if it was active). Returns ok.
function PresetBook:Delete(gunName: string, name: string): boolean
	local entry = self:_gun(gunName)
	if not entry or not entry.presets[name] then
		return false
	end
	entry.presets[name] = nil
	local index = table.find(entry.order, name)
	if index then
		table.remove(entry.order, index)
	end
	if entry.active == name then
		entry.active = nil
	end
	self:_dropIfEmpty(gunName)
	return true
end

-- Renames a preset in place (keeps order and the active mark). Returns ok, errorCode,
-- cleanName. Error codes: "missing", "name", "exists".
function PresetBook:Rename(gunName: string, oldName: string, newName: any, maxNameLength: number?): (boolean, string?, string?)
	local entry = self:_gun(gunName)
	if not entry or not entry.presets[oldName] then
		return false, "missing", nil
	end
	local clean = PresetBook.cleanName(newName, maxNameLength)
	if not clean then
		return false, "name", nil
	end
	if clean == oldName then
		return true, nil, clean
	end
	if entry.presets[clean] then
		return false, "exists", clean
	end
	entry.presets[clean] = entry.presets[oldName]
	entry.presets[oldName] = nil
	local index = table.find(entry.order, oldName)
	if index then
		entry.order[index] = clean
	end
	if entry.active == oldName then
		entry.active = clean
	end
	return true, nil, clean
end

-- Marks `name` as the preset auto-applied to new copies of the gun (nil clears).
-- Returns false if `name` doesn't exist.
function PresetBook:SetActive(gunName: string, name: string?): boolean
	local entry = self:_gun(gunName)
	if name == nil then
		if entry then
			entry.active = nil
		end
		return true
	end
	if not entry or not entry.presets[name] then
		return false
	end
	entry.active = name
	return true
end

-- Active preset name and a copy of its loadout, or nil.
function PresetBook:GetActive(gunName: string): (string?, Loadout?)
	local entry = self:_gun(gunName)
	local name = entry and entry.active
	if not name then
		return nil, nil
	end
	return name, copy((entry :: GunEntry).presets[name])
end

-- Plain table for the DataStore.
function PresetBook:Serialize(): Data
	local guns = {}
	for gunName, entry in pairs(self._data.guns) do
		local presets = {}
		for name, loadout in pairs(entry.presets) do
			presets[name] = copy(loadout)
		end
		guns[gunName] = { order = table.clone(entry.order), presets = presets, active = entry.active }
	end
	return { version = PresetBook.VERSION, guns = guns }
end

-- True when two loadouts contain exactly the same slot -> attachment pairs.
function PresetBook.sameLoadout(a: Loadout?, b: Loadout?): boolean
	local left, right = a or {}, b or {}
	for slot, name in pairs(left) do
		if right[slot] ~= name then
			return false
		end
	end
	for slot in pairs(right) do
		if left[slot] == nil then
			return false
		end
	end
	return true
end

return PresetBook
