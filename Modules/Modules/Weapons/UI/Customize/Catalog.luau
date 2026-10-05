--!nonstrict
-- Customize/Catalog
-- Decides which slots and options the menu offers for one weapon. Everything is
-- derived from the attachment system — no slot or attachment names are hard-coded:
--
--   slots   = attachments:GetSlots()                (the package slot list)
--   options = attachments:ListContent(slot)         (content folders)
--   usable  = attachments:CanEquip(model, tool, slot, name)
--             (same checks as Equip: mount part + named Attachment on the gun,
--              config loads, IsCompatible, content folder present)
--
-- So adding a slot to SPHAttachments' slot list, or a new attachment folder, makes it
-- appear here automatically. No Roblox globals are used (unit-testable).

local Catalog = {}

export type Option = {
	name: string,
	label: string,
	icon: string?,
	description: string?,
	available: boolean,
	reason: string?,
}

export type Slot = {
	name: string,
	label: string,
	order: number,
	role: string?,
	allowEmpty: boolean,
	options: { Option },
}

-- "SecondaryOptic" -> "Secondary Optic"
function Catalog.humanize(name: string): string
	local spaced = name:gsub("(%l)(%u)", "%1 %2"):gsub("_", " ")
	return spaced
end

local function attribute(instance: any, name: string): any
	if not instance then
		return nil
	end
	local ok, value = pcall(function()
		return instance:GetAttribute(name)
	end)
	return if ok then value else nil
end

local function stringOrNil(value: any): string?
	return if type(value) == "string" and value ~= "" then value else nil
end

-- params:
--   attachments     GunAttachments system
--   tool            Tool being customized
--   model           gun model used for mount-point checks (nil -> every option unavailable)
--   slotMeta        { [slot]: { label?, order?, hidden?, allowEmpty? } }
--   showUnavailable include options that cannot be equipped (greyed, with reason)
--   showEmptySlots  include slots that have no options for this weapon
--   slotFilter      function(tool, slotDef) -> boolean?  (false hides the slot)
function Catalog.build(params: { [string]: any }): { slots: { Slot } }
	local attachments = params.attachments
	local tool = params.tool
	local model = params.model
	local slotMeta = params.slotMeta or {}
	local slots = {}

	for _, def in ipairs(attachments:GetSlots()) do
		local meta = slotMeta[def.name] or {}
		if meta.hidden then
			continue
		end
		if params.slotFilter then
			local ok, verdict = pcall(params.slotFilter, tool, def)
			if ok and verdict == false then
				continue
			end
		end

		local options = {}
		for _, name in ipairs(attachments:ListContent(def.name)) do
			local available, reason = false, "weapon model not found"
			if model then
				available, reason = attachments:CanEquip(model, tool, def.name, name)
			end
			if available or params.showUnavailable then
				local config = attachments:LoadConfig(def.name, name) or {}
				local folder = attachments:GetContentFolder(def.name, name)
				table.insert(options, {
					name = name,
					label = stringOrNil(config.DisplayName) or stringOrNil(attribute(folder, "DisplayName")) or name,
					icon = stringOrNil(config.Icon) or stringOrNil(attribute(folder, "Icon")),
					description = stringOrNil(config.Description) or stringOrNil(attribute(folder, "Description")),
					available = available == true,
					reason = if available then nil else reason,
				})
			end
		end

		if #options > 0 or params.showEmptySlots then
			table.insert(slots, {
				name = def.name,
				label = meta.label or Catalog.humanize(def.name),
				order = if type(meta.order) == "number" then meta.order else def.order,
				role = def.role,
				allowEmpty = meta.allowEmpty ~= false,
				options = options,
			})
		end
	end

	table.sort(slots, function(a, b)
		if a.order == b.order then
			return a.name < b.name
		end
		return a.order < b.order
	end)
	return { slots = slots }
end

function Catalog.find(catalog: { slots: { Slot } }, slotName: string): Slot?
	for _, slot in ipairs(catalog.slots) do
		if slot.name == slotName then
			return slot
		end
	end
	return nil
end

return Catalog
