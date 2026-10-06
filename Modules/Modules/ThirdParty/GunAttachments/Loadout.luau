--!nonstrict
-- GunAttachments/Loadout
-- Persistence of a tool's selected attachments.
--
-- Storage format (unchanged from the original SPH protocol so existing tools and
-- scripts keep working):
--   Tool/<folderName>          Folder
--       /<Slot>                StringValue, Value = attachment name
--   Tool@<jsonAttribute>       JSON object { [slot] = name }   (mirror, optional)

local Slots = require(script.Parent.Slots)
local Types = require(script.Parent.Types)

type Loadout = Types.Loadout

local Loadout = {}

-- Validates untrusted input (e.g. a RemoteEvent payload). Never errors.
function Loadout.sanitize(raw: any, slots: Slots.SlotTable, maxNameLength: number?): Loadout
	local result: Loadout = {}
	if type(raw) ~= "table" then
		return result
	end
	local limit = maxNameLength or 64
	local count = 0
	for slot, name in pairs(raw) do
		count += 1
		if count > 64 then
			break -- hard cap against oversized payloads
		end
		if Slots.isValid(slots, slot) and type(name) == "string" and name ~= "" and #name <= limit then
			result[slot] = name
		end
	end
	return result
end

function Loadout.read(tool: Instance?, folderName: string): Loadout
	local result: Loadout = {}
	if not tool then
		return result
	end
	local folder = (tool :: any):FindFirstChild(folderName)
	if not folder then
		return result
	end
	for _, entry in ipairs(folder:GetChildren()) do
		if entry:IsA("StringValue") and entry.Value ~= "" then
			result[entry.Name] = entry.Value
		end
	end
	return result
end

function Loadout.has(tool: Instance?, folderName: string): boolean
	return tool ~= nil and (tool :: any):FindFirstChild(folderName) ~= nil
end

-- Writes the loadout by replacing the folder (same as the original server code).
-- Replacing — rather than clearing — matters for replication: when the server destroys
-- the folder, every client copy is destroyed with it, including any client-local
-- values a UI wrote optimistically, so clients can never keep stale duplicates.
function Loadout.write(
	tool: Instance,
	loadout: Loadout,
	folderName: string,
	jsonAttribute: string?,
	newInstance: (string) -> Instance,
	http: any?,
	orderedSlots: { string }
)
	local existing = (tool :: any):FindFirstChild(folderName)
	if existing then
		existing:Destroy()
	end
	local folder = newInstance("Folder") :: any
	folder.Name = folderName
	for _, slot in ipairs(orderedSlots) do
		local name = loadout[slot]
		if name then
			local value = newInstance("StringValue") :: any
			value.Name = slot
			value.Value = name
			value.Parent = folder
		end
	end
	folder.Parent = tool -- parent last: observers see a complete folder
	if jsonAttribute and http then
		local ok, json = pcall(function()
			return http:JSONEncode(loadout)
		end)
		if ok then
			pcall(function()
				(tool :: any):SetAttribute(jsonAttribute, json)
			end)
		end
	end
end

return Loadout
