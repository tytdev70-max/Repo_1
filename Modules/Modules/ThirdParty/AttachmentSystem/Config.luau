--[[
	AttachmentSystem.Config
	────────────────────────
	Every host-specific string the attachment system needs lives here.

	Nothing in this file (or anywhere else in the AttachmentSystem package)
	performs a WaitForChild, and nothing hardcodes a specific game's instance
	tree. The values below are *defaults* chosen to match the existing SPH
	layout so the system is drop-in compatible out of the box, but every one of
	them can be replaced through `AttachmentSystem.Configure(opts)`.
]]

local Config = {}

-- ─── Attachment categories ──────────────────────────────────────────────────
-- Maps an attachment category to the name of the mount part that is searched
-- for on the weapon model. A category that is absent from this table falls
-- back to `category .. DefaultMountSuffix`, which makes adding a brand new
-- category (Handguard, Barrel, DustCover, Laser, Flashlight, UBGL, ...) a
-- single line here rather than an edit in four separate code paths.

Config.DefaultMountSuffix = "Part"

Config.Categories = {
	Optics      = "OpticPart",
	Underbarrel = "GripPart",
	Muzzle      = "MuzzlePart",
	Stock       = "StockPart",
}

-- Presentation order used by the Gunsmith menu. Categories not listed here are
-- appended in alphabetical order so new slots still show up automatically.
Config.CategoryOrder = { "Optics", "Underbarrel", "Muzzle", "Stock" }

-- Categories whose selection is validated most strictly, because the server
-- replicates their contents to other players.
Config.NetworkedCategories = { Optics = true, Muzzle = true, Underbarrel = true, Stock = true }

-- ─── Naming conventions ─────────────────────────────────────────────────────

Config.Naming = {
	-- Folder created under the mount part holding a live attachment's parts.
	equippedSuffix = "_Equipped",

	-- Weapon model attributes.
	activeCustomMuzzle = "ActiveCustomMuzzle",
	originalTransparency = "OriginalTransparency_Muzzle",
	originalEnabled     = "OriginalEnabled_Muzzle",
	muzzlePreHidden     = "MuzzlePreHidden",
	overriddenBy        = "OverriddenByAttachment",
}

-- ─── Weapon model part conventions ──────────────────────────────────────────
-- Names the system looks for inside a weapon model. Overridable per host.

Config.ModelParts = {
	grip        = "Grip",
	base        = "Base",
	muzzle      = "Muzzle",
	laser       = "Laser",
	flashlight  = "Flashlight",
	innerLight  = "InnerSpotLight",
	outerLight  = "OuterSpotLight",
	aimPart     = "AimPart",
	laserColor  = "Color",
}

-- ─── Persistence ────────────────────────────────────────────────────────────
-- Where saved loadouts and base/modified stats live on a Tool.

Config.Storage = {
	savedFolderName    = "SavedAttachments",
	baseStatsAttr      = "OriginalStats",
	modifiedStatsAttr  = "ModifiedStats",
	selectionJSONAttr  = "SavedAttachmentsJSON",
	statsModuleName    = "WeaponStats",
	weaponContainer    = "SPH_Weapon",
}

-- ─── Where attachment assets live ───────────────────────────────────────────
-- `assetRootName`/`attachmentFolderName` are only used as a *fallback* lookup
-- when the host has not called Configure(). Resolve is lazy and pcall-guarded,
-- so a missing asset folder simply yields an inert system rather than a hang.

Config.Assets = {
	assetRootName        = "SPH_Assets",
	attachmentFolderName = "GunAttachments",
	customizationName    = "Customization",
}

-- ─── Replication / menu event names ─────────────────────────────────────────
-- The system owns these names. A host that wants different names overrides
-- them here; SPH's existing `GunEvents` names are used as the defaults so no
-- server or RemoteEvent needs to be renamed.

Config.Events = {
	setupMenu      = "SetupCustomizeGUI",
	cleanupMenu    = "CleanupCustomizeGUI",
	apply          = "ApplyWeaponAttachments",
	reloadStats    = "ReloadWeaponStats",
	remoteFolder   = "GunEvents",
}

-- ─── Input validation limits ────────────────────────────────────────────────
-- These mirror the guards the server already enforces, so the client rejects
-- exactly what the server would reject.

Config.Limits = {
	maxNameLength   = 64,
	maxSelections   = 32,
	maxAttachmentHeightRatio = 2.0,
}

-- ─── Live configuration ─────────────────────────────────────────────────────

local runtime = {
	root = nil,          -- Instance? resolved Folder holding one folder per category
	events = nil,        -- Folder holding the system's RemoteEvents (optional)
	strict = false,      -- when true, unknown categories are rejected outright
}

function Config.GetCategoryPartName(category: string): string
	local mapped = Config.Categories[category]
	if mapped then return mapped end
	return category .. Config.DefaultMountSuffix
end

function Config.GetCategoryList(): {string}
	local seen, ordered = {}, {}
	for _, category in ipairs(Config.CategoryOrder) do
		seen[category] = true
		table.insert(ordered, category)
	end

	local extra = {}
	for category in pairs(Config.Categories) do
		if not seen[category] then
			table.insert(extra, category)
		end end
	table.sort(extra)
	for _, category in ipairs(extra) do
		table.insert(ordered, category)
	end

	return ordered
end

function Config.GetRoot(): Folder?
	return runtime.root
end

function Config.SetRoot(folder: Instance?)
	runtime.root = folder if folder ~= nil and folder:IsA("Folder") else nil
end

function Config.GetEventsFolder(): Folder?
	return runtime.events
end

function Config.SetEventsFolder(folder: Instance?)
	runtime.events = folder if folder ~= nil and folder:IsA("Folder") else nil
end

function Config.IsStrict(): boolean
	return runtime.strict
end

function Config.SetStrict(value: boolean)
	runtime.strict = value == true
end

--[[
	Apply(hostOptions) merges a partial override table. Only keys that are
	actually present are replaced, so `{ Storage = { savedFolderName = "X" } }`
	leaves the rest of Storage intact.
]]
function Config.Apply(hostOptions: { [string]: any }?)
	if type(hostOptions) ~= "table" then
		return
	end

	for _, key in ipairs({
		"Categories",
		"CategoryOrder",
		"NetworkedCategories",
		"Naming",
		"ModelParts",
		"Storage",
		"Assets",
		"Events",
		"Limits",
	}) do
		local incoming = hostOptions[key]
		if type(incoming) == "table" then
			for subKey, subValue in pairs(incoming) do
				Config[key][subKey] = subValue
			end
		end
	end

	if hostOptions.DefaultMountSuffix ~= nil then
		Config.DefaultMountSuffix = hostOptions.DefaultMountSuffix
	end
	if hostOptions.root ~= nil then
		Config.SetRoot(hostOptions.root)
	end
	if hostOptions.events ~= nil then
		Config.SetEventsFolder(hostOptions.events)
	end
	if hostOptions.strict ~= nil then
		Config.SetStrict(hostOptions.strict)
	end
end

return Config
