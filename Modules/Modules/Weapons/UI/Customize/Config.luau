--!nonstrict
-- Customize/Config
-- Every tunable of the Customize UI, with defaults. Pass overrides to
-- CustomizeUI.start({ ... }); tables are deep-merged, so you only specify what you
-- change. Arrays (e.g. blockedKeys) are replaced, not merged.

local Config = {}

Config.defaults = {
	-- ── behaviour ────────────────────────────────────────────────────────────
	behaviour = {
		showUnavailable = false, -- show options the weapon can't take (greyed + reason)
		showEmptySlots = false, -- show slots with no options for this weapon
		closeOnConfirm = true,
		confirmWhenUnchanged = true, -- original always re-sent on confirm (server dedupes)
		reopenDelay = 0, -- legacy waited 0.2s when reopening an open menu
		displayOrder = 1000,
		closeKeys = { "Escape", "ButtonB" }, -- Enum.KeyCode names; {} to disable
		debug = false, -- print each step of opening to the Output window
	},

	-- ── per-slot presentation (keys = slot names; all fields optional) ──────
	--   label = "Sights", order = 1, hidden = true, allowEmpty = false
	slots = {
		Optics = { label = "Optics" },
		Underbarrel = { label = "Underbarrel" },
		Muzzle = { label = "Muzzle" },
		Stock = { label = "Stock" },
		Barrel = { label = "Barrel" },
		Magazine = { label = "Magazine" },
		SecondaryOptic = { label = "Secondary Optic" },
	},

	-- ── layout (scale units unless noted) ───────────────────────────────────
	layout = {
		windowSize = { 0.86, 0.82 }, -- fraction of screen
		windowMaxPixels = { 1500, 860 },
		headerHeight = 0.09,
		footerHeight = 0.1,
		railWidth = 0.21, -- slot list
		panelWidth = 0.31, -- option grid; preview gets the rest
		gap = 10, -- pixels
		optionCell = { 0.31, 0, 0, 92 }, -- UDim2 parts {xScale, xOffset, yScale, yOffset}
		optionPadding = 8, -- pixels
		slotTabHeight = 54, -- pixels
	},

	-- ── theme ────────────────────────────────────────────────────────────────
	theme = {
		font = "GothamMedium",
		fontBold = "GothamBold",
		backdrop = { 0, 0, 0 },
		backdropTransparency = 0.45,
		window = { 18, 20, 24 },
		windowTransparency = 0.04,
		panel = { 28, 31, 37 },
		panelTransparency = 0,
		stroke = { 60, 66, 76 },
		text = { 235, 238, 242 },
		subtext = { 150, 158, 170 },
		accent = { 92, 196, 120 }, -- selected
		accentText = { 15, 20, 16 },
		hover = { 44, 49, 58 },
		card = { 36, 40, 47 },
		cardUnavailable = { 30, 31, 34 },
		danger = { 214, 92, 92 },
		warning = { 230, 180, 80 },
		corner = 8, -- pixels
		tweenTime = 0.12,
	},

	-- ── 3D preview ───────────────────────────────────────────────────────────
	preview = {
		enabled = true,
		fov = 45,
		yaw = -30,
		pitch = 15,
		dragSensitivity = 0.5,
		zoomStep = 0.15, -- fraction of the model's largest dimension per wheel notch
		minRadiusFactor = 0.4,
		maxRadiusFactor = 2.5,
		nearExpand = 0.28,
		nearBuffer = 0.04,
	},

	-- ── session side effects (ported 1:1 from the legacy controller) ────────
	environment = {
		blockInputs = true,
		freezeWalkSpeed = true,
		suppressInventory = true,
		inventoryNamePatterns = { "inventory", "hotbar" },
		forceMouseFree = true,
		blur = true, -- Lighting.GUIBlur, if present
		blockActionName = "BlockAllInputs",
		blockedKeys = {
			"W", "A", "S", "D", "Space", "LeftShift", "RightShift", "LeftControl", "RightControl",
			"One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Zero",
			"ButtonL2", "ButtonR2", "ButtonX", "ButtonY", "DPadUp", "DPadDown", "DPadLeft",
			"DPadRight", "Thumbstick1",
		},
		-- Character attributes that forbid restoring the inventory/backpack on close.
		keepInventoryHiddenAttributes = { "BackpackDisabled", "IsUnequippingForArmHiding" },
		inventoryRestoreDelay = 0.1,
	},

	-- ── text ─────────────────────────────────────────────────────────────────
	text = {
		title = "CUSTOMIZE",
		slotsHeader = "SLOTS",
		none = "None",
		empty = "Empty",
		clear = "Clear",
		confirm = "CONFIRM",
		revert = "Revert",
		hint = "Drag to rotate  ·  Scroll to zoom",
		unsaved = "Unsaved changes",
		noSlots = "This weapon has no attachment slots.",
		count = "%d attachments",
		countWithCapacity = "%d / %d attachments",

		-- presets (saved loadouts)
		presetDefaultName = "Loadout %d",
		presetSaved = "Saved \"%s\"",
		presetRenamed = "Renamed to \"%s\"",
		presetDeleted = "Deleted \"%s\"",
		presetLoaded = "Loaded \"%s\" - press Confirm to apply it",
		presetDeleteConfirm = "Sure?",
		presetsEmpty = "No saved loadouts for this gun yet",
		presetCount = "%d loadouts",
		presetCountWithMax = "%d / %d loadouts",
		presetNotKept = "Saving is unavailable - loadouts will be lost when you leave",
		presetErrors = {
			name = "Enter a name for the loadout",
			limit = "This gun has the maximum number of loadouts",
			exists = "A loadout with that name already exists",
			missing = "That loadout no longer exists",
			no_weapon = "Equip a gun first",
			loading = "Loadouts are still loading, try again in a moment",
			rate_limited = "Too fast - try again in a moment",
			storage_full = "No room to save more loadouts",
			disabled = "Loadouts are turned off",
			unavailable = "Loadouts are unavailable right now",
			server_error = "Something went wrong, try again",
			bad_request = "Something went wrong, try again",
		},

		-- Test Loadout (Gunsmith)
		testReturn = "Return to Gunsmith",
		testErrors = {
			disabled = "Testing is turned off",
			no_zone = "There is no test area in this place",
			busy = "Already testing",
			no_weapon = "Equip a gun first",
			dead = "You can't test right now",
			rate_limited = "Too fast - try again in a moment",
			unavailable = "Testing is unavailable right now",
			bad_request = "Something went wrong, try again",
		},
	},

	-- ── presets (saved loadouts per gun type) ─────────────────────────────────
	-- Server settings (limit, DataStore) live in Weapons/Presets/PresetSettings.
	presets = {
		enabled = true,
	},

	-- ── Test Loadout (Gunsmith) ───────────────────────────────────────────────
	-- Server settings (test area, time limit) live in Weapons/Gunsmith/GunsmithTestSettings.
	test = {
		enabled = true,
		resumeTimeout = 5, -- seconds to wait for the real gun to be equipped again before reopening
	},

	-- ── extension points ─────────────────────────────────────────────────────
	-- view = function(context) -> view   (replace the whole UI; see README)
	-- slotFilter = function(tool, slotDef) -> boolean?
	-- resolveGunModel = function(tool) -> Model?
	-- onConfirmed = function(tool, loadout)
	view = nil,

	-- Which built-in UI to use:
	--   "template"  (default) the CustomizeGunGUI designed in Studio (View/Template).
	--               Falls back to "generated" if the ScreenGui has no template frames.
	--   "generated" the UI built in code (View/init); the template frames are hidden.
	--   "gunsmith"  the Gunsmith ScreenGui (View/Gunsmith); falls back like "template".
	-- If start() gets no ui, GameConfig.customizeMenu decides ("Gunsmith" -> "gunsmith").
	ui = "template",

	-- Options for ui = "gunsmith" (see View/Gunsmith for the expected hierarchy)
	gunsmith = {
		noneItem = true, -- first entry of every list that may be empty: "None" (clears the slot)
		uppercaseCategories = true, -- AttachmentType shows "OPTICS" instead of "Optics"
		selectedColor = { 100, 200, 100 }, -- AttachmentName colour of the picked entry (if it has no "Selected" child)
		unavailableTransparency = 0.6, -- entries shown with behaviour.showUnavailable
		-- Save names for now: "<word> <number>", e.g. "Viper 27"
		randomNameWords = { "Alpha", "Bravo", "Delta", "Echo", "Ghost", "Hawk", "Raven", "Viper", "Wolf", "Cobra", "Falcon", "Nomad" },
	},

	-- Options for ui = "template" (see View/Template for the expected hierarchy)
	template = {
		autoColumns = true, -- slot with options but no column: copy the first column
		autoItems = true, -- attachment with no designed item: copy the first item
		hideEmptyColumns = false, -- hide columns of slots this weapon can't use
		createStatus = true, -- create a Status label for messages if the GUI has none
		selectedColor = { 100, 200, 100 },
		selectedScale = 1.03,
		hoverScale = 1.01,
		unavailableTransparency = 0.6, -- items shown with behaviour.showUnavailable
		legacyOrder = { "Optics", "Underbarrel", "Muzzle", "Stock" }, -- columns named "column"
	},
	slotFilter = nil,
}

local function isArray(value: any): boolean
	return type(value) == "table" and (value[1] ~= nil or next(value) == nil)
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in pairs(value) do
		result[key] = deepCopy(item)
	end
	return result
end

-- Arrays (e.g. blockedKeys) are replaced as a whole; dictionaries are merged. An empty
-- table counts as an array only where the default is an array ({} = "none").
local function replaces(base: any, override: any): boolean
	if type(base) ~= "table" or type(override) ~= "table" then
		return true
	end
	if next(base) ~= nil and isArray(base) then
		return true
	end
	return next(override) ~= nil and isArray(override)
end

local function merge(base: any, override: any): any
	if replaces(base, override) then
		if override == nil then
			return deepCopy(base)
		end
		return override
	end
	local result = {}
	for key, value in pairs(base) do
		result[key] = merge(value, override[key])
	end
	for key, value in pairs(override) do
		if base[key] == nil then
			result[key] = value
		end
	end
	return result
end

function Config.resolve(overrides: { [string]: any }?): { [string]: any }
	return merge(Config.defaults, overrides or {})
end

return Config
