--[[
	AttachmentSystem.Storage
	────────────────────────
	Reads and writes a weapon's saved loadout and its stat snapshots.

	The on-disk format is deliberately unchanged from the format the rest of
	the game already understands, so existing tools, the server, and any code
	that inspects `Tool.SavedAttachments` directly keep working:

	    Tool
	      SavedAttachments      (Folder)
	        Optics              (StringValue) -> "Holo"
	        Muzzle              (StringValue) -> "Suppressor"
	      (attributes) OriginalStats / ModifiedStats / SavedAttachmentsJSON

	All of it is funnelled through this module so the format is defined in
	exactly one place and can be re-pointed by a host through Configure().
]]

local HttpService = game:GetService("HttpService")

local Config    = require(script.Parent.Config)
local StatModifier = require(script.Parent.StatModifier)

local Storage = {}

-- Base stats snapshots, keyed by weapon instance. Weak keys so dropped tools
-- are collected even if the host never tells us they went away (fixes the
-- unbounded growth the old ClearOriginalStats stub allowed).
local baseStatsCache: { [Instance]: any } = setmetatable({}, { __mode = "k" })

-- ─── Loadouts ───────────────────────────────────────────────────────────────

function Storage.GetSavedFolder(weapon: Instance?): Folder?
	if not weapon then
		return nil
	end
	local folder = weapon:FindFirstChild(Config.Storage.savedFolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

--[[
	Read the saved loadout as a plain `{[category] = attachmentName}` map.
	Always returns a table (possibly empty); entries with empty values are
	dropped so callers never have to re-check for "".
]]
function Storage.GetSaved(weapon: Instance?): { [string]: string }
	local result = {}
	local folder = Storage.GetSavedFolder(weapon)
	if not folder then
		return result
	end

	for _, entry in ipairs(folder:GetChildren()) do
		if entry:IsA("StringValue") then
			local value = entry.Value
			if type(value) == "string" and value ~= "" then
				result[entry.Name] = value
			end
		end
	end

	return result
end

--[[
	Write a loadout map onto a weapon, replacing whatever was there.
	Returns true when the write succeeded. Malformed input (non-string keys or
	values, too many entries) is rejected rather than partially applied.
]]
function Storage.SetSaved(weapon: Instance?, loadout: { [string]: string }?): boolean
	if not weapon or type(loadout) ~= "table" then
		return false
	end

	local count = 0
	for category, name in pairs(loadout) do
		if type(category) ~= "string" or category == "" then
			return false
		end
		if name ~= nil and type(name) ~= "string" then
			return false
		end
		count += 1
	end
	if count > Config.Limits.maxSelections then
		return false
	end

	local folder = Storage.GetSavedFolder(weapon)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.Storage.savedFolderName
		folder.Parent = weapon
	end

	folder:ClearAllChildren()

	for category, name in pairs(loadout) do
		if type(name) == "string" and name ~= "" then
			local value = Instance.new("StringValue")
			value.Name   = category
			value.Value  = name
			value.Parent = folder
		end
	end

	-- A JSON mirror of the loadout. Kept for compatibility with any host code
	-- that reads the attribute; the folder above remains the source of truth.
	local encoded = tryEncode(loadout)
	if encoded then
		weapon:SetAttribute(Config.Storage.selectionJSONAttr, encoded)
	end

	return true
end

--[[
	Persist a single category entry without touching the rest of the loadout.
	Returns the resulting map.
]]
function Storage.SetEntry(weapon: Instance?, category: string, attachmentName: string?): { [string]: string }
	local loadout = Storage.GetSaved(weapon)
	if type(attachmentName) == "string" and attachmentName ~= "" then
		loadout[category] = attachmentName
	else
		loadout[category] = nil
	end
	Storage.SetSaved(weapon, loadout)
	return loadout
end

function Storage.Clear(weapon: Instance?)
	if not weapon then
		return
	end
	local folder = Storage.GetSavedFolder(weapon)
	if folder then
		folder:ClearAllChildren()
	end
	weapon:SetAttribute(Config.Storage.selectionJSONAttr, nil)
end

-- ─── JSON helpers (never throw) ─────────────────────────────────────────────

--[[
	Attributes can only hold strings, and stats tables may contain values
	(`CFrame`, `Instance`, functions, cycles) that JSON cannot represent.
	These wrappers never throw: they report failure and the caller falls back
	to the in-memory cache. This replaces the unguarded JSONEncode calls that
	previously errored on any weapon whose stats contain a CFrame.
]]
local function tryEncode(value: any): string?
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	if ok and type(encoded) == "string" then
		return encoded
	end
	return nil
end

local function tryDecode(encoded: any): any?
	if type(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(encoded)
	end)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return nil
end

-- ─── Base / modified stats snapshots ────────────────────────────────────────

--[[
	Remember a weapon's *base* stats. The in-memory copy is authoritative; the
	attribute is a best-effort mirror that lets a server hand a fresh client
	the same baseline without re-requiring the module.
]]
function Storage.StoreBaseStats(weapon: Instance?, baseStats: any?): boolean
	if not weapon or type(baseStats) ~= "table" then
		return false
	end

	local snapshot = StatModifier.DeepCopy(baseStats)
	if type(snapshot) ~= "table" then
		return false
	end

	baseStatsCache[weapon] = snapshot

	local encoded = tryEncode(baseStats)
	if encoded then
		weapon:SetAttribute(Config.Storage.baseStatsAttr, encoded)
	end
	return true
end

--[[
	Recover a weapon's base stats: the in-memory snapshot if we have one,
	otherwise the attribute mirror, otherwise the live WeaponStats module.
	Returns nil only when the weapon has no stats at all.
]]
function Storage.GetBaseStats(weapon: Instance?): any?
	if not weapon then
		return nil
	end

	local cached = baseStatsCache[weapon]
	if type(cached) == "table" then
		return cached
	end

	local decoded = tryDecode(weapon:GetAttribute(Config.Storage.baseStatsAttr))
	if decoded then
		baseStatsCache[weapon] = decoded
		return decoded
	end

	local live = Storage.LoadWeaponStats(weapon)
	if type(live) == "table" then
		baseStatsCache[weapon] = live
	end
	return live
end

--[[
	Resolve a weapon's base stats module. The container/module names come from
	Config.Storage, so a host with a different layout only has to override
	those two strings.
]]
function Storage.LoadWeaponStats(weapon: Instance?): any?
	if not weapon then
		return nil
	end

	local container = weapon:FindFirstChild(Config.Storage.weaponContainer) or weapon

	local module = container:FindFirstChild(Config.Storage.statsModuleName)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end

	local ok, stats = pcall(require, module)
	if not ok or type(stats) ~= "table" then
		return nil
	end
	return stats
end

--[[
	Publish the post-attachment stat table. Mirrors the previous
	`ModifiedStats` attribute for host compatibility, but only when the table
	is actually encodable — a failure to mirror is never propagated, because
	the caller already has the correct table in hand.
]]
function Storage.StoreModifiedStats(weapon: Instance?, modifiedStats: any?): boolean
	if not weapon or type(modifiedStats) ~= "table" then
		return false
	end
	local encoded = tryEncode(modifiedStats)
	if encoded then
		weapon:SetAttribute(Config.Storage.modifiedStatsAttr, encoded)
	end
	return true
end

function Storage.GetModifiedStats(weapon: Instance?): any?
	if not weapon then
		return nil
	end
	return tryDecode(weapon:GetAttribute(Config.Storage.modifiedStatsAttr))
end

--[[
	Drop every cached snapshot for a weapon. Call this when a tool leaves a
	player's inventory so a long session cannot accumulate stats tables.
]]
function Storage.Forget(weapon: Instance?)
	if not weapon then
		return
	end
	baseStatsCache[weapon] = nil
end

function Storage.ForgetAll()
	baseStatsCache = setmetatable({}, { __mode = "k" })
end

-- Exposed for the host's server-side stat refresh path.
Storage.TryEncode  = tryEncode
Storage.TryDecode = tryDecode

return Storage
