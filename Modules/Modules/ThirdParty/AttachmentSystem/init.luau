--[[
	═══════════════════════════════════════════════════════════════════════════
	AttachmentSystem
	────────────────
	A standalone, host-agnostic attachment / gunsmith system.

	This is the only module a host needs to require. Everything the host used
	to get from `Weapons.Attachments.AttachmentManager` plus the three gunsmith
	UI modules now lives behind this API, and none of it knows or cares that
	it is running inside SPH.

	Quick start:

	    local AttachmentSystem = require(ReplicatedStorage.SPH_Assets
	                                   .Modules.ThirdParty.AttachmentSystem)

	    -- once, at startup (optional — SPH's layout is the default)
	    AttachmentSystem.Configure({ root = ReplicatedStorage.SPH_Assets.GunAttachments })

	    -- per weapon, on equip
	    AttachmentSystem.PrepareForEquip(gunModel)
	    for category, name in pairs(savedLoadout) do
	        AttachmentSystem.Equip(player, tool, gunModel, name, category)
	    end
	    local stats = AttachmentSystem.ApplyStats(tool, gunModel)

	Design rules this package holds itself to:

	  • No `WaitForChild` at module scope, anywhere. Requiring this package
	    can never block another script's startup.
	  • Nothing returns until it is safe to continue: every failure path
	    returns a value instead of yielding.
	  • All host-specific names live in `Config.luau` and are overridable.
	  • The host never reaches into internals — it calls methods here.
	═══════════════════════════════════════════════════════════════════════════
]]

local Config       = require(script.Config)
local ConfigLoader = require(script.ConfigLoader)
local Registry     = require(script.Registry)
local Mounter      = require(script.Mounter)
local StatModifier = require(script.StatModifier)
local Storage      = require(script.Storage)
local Queries      = require(script.Queries)
local Visuals      = require(script.Visuals)

local AttachmentSystem = {}

-- ─── Setup ──────────────────────────────────────────────────────────────────

--[[
	Point the system at a host. Every field is optional; anything omitted keeps
	its default, which already matches SPH's layout.

	    AttachmentSystem.Configure({
	        root     = Folder,     -- folder holding one sub-folder per category
	        events   = Folder,     -- folder holding the system's RemoteEvents
	        strict   = true,       -- reject categories not in Config.Categories
	        Categories = { Optics = "OpticPart", Barrel = "BarrelPart" },
	        Storage  = { savedFolderName = "MyAttachments" },
	        ModelParts = { muzzle = "MuzzlePort" },
	    })
]]
function AttachmentSystem.Configure(hostOptions: { [string]: any }?)
	Config.Apply(hostOptions)
	ConfigLoader.Reset()
end

--[[
	True when an attachment root could be resolved. Always safe to call — it
	never yields — so a host can gate its attachment features on it.
]]
function AttachmentSystem.IsReady(): boolean
	return ConfigLoader.GetRoot() ~= nil
end

function AttachmentSystem.GetRoot(): Folder?
	return ConfigLoader.GetRoot()
end

-- ─── Definition lookup ──────────────────────────────────────────────────────

function AttachmentSystem.LoadConfig(attachmentName: string, category: string): any?
	return ConfigLoader.Load(attachmentName, category)
end

function AttachmentSystem.IsCompatible(attachmentName: string, category: string, weaponName: string?): boolean
	return ConfigLoader.IsCompatible(attachmentName, category, weaponName)
end

function AttachmentSystem.IsValidRequest(attachmentName: any, category: any): boolean
	return ConfigLoader.IsValidRequest(attachmentName, category)
end

-- Every attachment defined for a category.
function AttachmentSystem.ListAvailable(category: string): {string}
	return ConfigLoader.List(category)
end

-- Every attachment in a category that a given weapon can physically take.
function AttachmentSystem.ListAvailableFor(weaponModel: Instance?, category: string, weaponName: string?): {string}
	return ConfigLoader.ListCompatible(weaponModel, category, weaponName)
end

-- The full gunsmith catalogue: category -> compatible names, in display order.
function AttachmentSystem.BuildCatalogue(weaponModel: Instance?, weaponName: string?): { [string]: {string} }
	local catalogue = {}
	for _, category in ipairs(Config.GetCategoryList()) do
		catalogue[category] = AttachmentSystem.ListAvailableFor(weaponModel, category, weaponName)
	end
	return catalogue
end

-- ─── Lifecycle ──────────────────────────────────────────────────────────────

--[[
	Strip a weapon model back to a clean state before a loadout is applied.

	Destroys any leftover `<name>_Equipped` folders found anywhere in the model,
	restores the parts an attachment had hidden, and empties the registry.
	This is what makes it safe to re-use a model for a different weapon.
]]
function AttachmentSystem.PrepareForEquip(weaponModel: Instance?)
	if not weaponModel then
		return
	end

	for _, category in ipairs(Registry.GetOccupiedCategories(weaponModel)) do
		AttachmentSystem.Unequip(weaponModel, category)
	end

	for _, part in ipairs(weaponModel:GetDescendants()) do
		if part:IsA("Folder") then
			local suffix = Config.Naming.equippedSuffix
			if #part.Name > #suffix and part.Name:sub(-#suffix) == suffix then
				part:Destroy()
			end
		end
	end

	Mounter.RestoreReplacedPart(weaponModel)
	weaponModel:SetAttribute(Config.Naming.activeCustomMuzzle, nil)
	Registry.ForgetEntries(weaponModel)
end

--[[
	Fit an attachment.

	@param player         passed through to `OnEquip`; may be nil on the server
	@param weapon         the Tool that owns the loadout
	@param weaponModel    the model the parts are parented to
	@param attachmentName name of the attachment
	@param category       slot it goes into ("Optics", "Muzzle", ...)

	@return true when the attachment is now fitted. A `false` result is always
	        safe and never leaves the model in a worse state than before.
]]
function AttachmentSystem.Equip(
	player: Player?,
	weapon: Instance?,
	weaponModel: Instance?,
	attachmentName: string,
	category: string
): boolean
	if not weapon or not weaponModel then
		return false
	end
	if not AttachmentSystem.IsValidRequest(attachmentName, category) then
		return false
	end

	-- Already exactly this: nothing to do, and nothing to rebuild.
	local existing = Registry.Get(weaponModel, category)
	if existing and existing.attachmentName == attachmentName then
		return true
	end

	-- A model changing hands must be reset first, or it would keep the
	-- previous weapon's attachments registered against it.
	local owner = Registry.GetOwner(weaponModel)
	if owner and owner ~= weapon then
		AttachmentSystem.PrepareForEquip(weaponModel)
	end
	Registry.Claim(weaponModel, weapon)

	local config = ConfigLoader.Load(attachmentName, category)
	if not config then
		return false
	end
	if not ConfigLoader.IsCompatible(attachmentName, category, weapon.Name) then
		return false
	end

	-- Slot is occupied by a different part: replace it.
	if existing and existing.attachmentName ~= attachmentName then
		AttachmentSystem.Unequip(weaponModel, category)
	end

	local sourceFolder = ConfigLoader.GetAttachmentFolder(attachmentName, category)
	if not sourceFolder then
		return false
	end

	local layout, reason = Mounter.ComputeLayout(weaponModel, sourceFolder, {
		category       = category,
		attachmentName = attachmentName,
		MountOffset    = config.MountOffset,
		RootPart       = config.RootPart,
	})
	if not layout then
		if reason then
			warn(string.format("[AttachmentSystem] %s/%s not fitted to %s: %s",
				category, attachmentName, weaponModel.Name, reason))
		end
		return false
	end

	local node, buildError = Mounter.Build(layout, layout.categoryPart, true)
	if not node then
		if buildError then
			warn(string.format("[AttachmentSystem] %s/%s failed to build: %s",
				category, attachmentName, buildError))
		end
		return false
	end

	-- Parts that should always be visible regardless of authored transparency.
	for _, partName in ipairs(config.VisibleParts or {}) do
		local part = node:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			part.Transparency = 0
		end
	end

	-- Parts of the gun this attachment covers over.
	for _, partName in ipairs(config.HideGunParts or {}) do
		local part = weaponModel:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			if part:GetAttribute(Config.Naming.originalTransparency) == nil then
				part:SetAttribute(Config.Naming.originalTransparency, part.Transparency)
			end
			part.Transparency = config.HideTransparency or 1
		end
	end

	-- Part replacement: swap the muzzle.
	if category == "Muzzle" then
		Mounter.HideReplacedPart(weaponModel)
		if node:FindFirstChild(Config.ModelParts.muzzle, true) then
			weaponModel:SetAttribute(Config.Naming.activeCustomMuzzle, attachmentName)
		end
	end

	-- A laser that is fitted but not switched on should not show its beam.
	if config.EnableLaser then
		for _, child in ipairs(node:GetDescendants()) do
			if child:IsA("Beam") then
				child.Enabled = false
			end
		end
	end

	Registry.Set(weaponModel, category, {
		attachmentName = attachmentName,
		category       = category,
		config         = config,
		model          = node,
	})

	if type(config.OnEquip) == "function" then
		pcall(config.OnEquip, player, weapon, node)
	end

	return true
end

--[[
	Remove whatever is fitted in a category and put back anything it hid.
	Safe to call when the category is empty.
]]
function AttachmentSystem.Unequip(weaponModel: Instance?, category: string)
	local entry = Registry.Get(weaponModel, category)
	if not entry then
		return
	end

	-- Restore the gun parts this attachment covered, using the values we
	-- recorded rather than assuming 0.
	local config = entry.config
	for _, partName in ipairs(config.HideGunParts or {}) do
		local part = weaponModel:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			local original = part:GetAttribute(Config.Naming.originalTransparency)
			if original ~= nil then
				part.Transparency = original
			end
		end
	end

	if category == "Muzzle" then
		Mounter.RestoreReplacedPart(weaponModel)
		weaponModel:SetAttribute(Config.Naming.activeCustomMuzzle, nil)
	end

	Mounter.Teardown(entry.model, weaponModel, { OnUnequip = config.OnUnequip, category = category })

	Registry.Set(weaponModel, category, nil)
end

--[[
	Remove every attachment from a model and release all of its state.
	This is the teardown path: call it when a weapon is holstered, dropped, or
	its model is about to be destroyed.
]]
function AttachmentSystem.ClearAll(weaponModel: Instance?)
	if not weaponModel then
		return
	end

	for _, category in ipairs(Registry.GetOccupiedCategories(weaponModel)) do
		AttachmentSystem.Unequip(weaponModel, category)
	end

	for _, part in ipairs(weaponModel:GetDescendants()) do
		if part:IsA("Folder") then
			local suffix = Config.Naming.equippedSuffix
			if #part.Name > #suffix and part.Name:sub(-#suffix) == suffix then
				part:Destroy()
			end
		end
	end

	weaponModel:SetAttribute(Config.Naming.activeCustomMuzzle, nil)
	Registry.Release(weaponModel)
end

--[[
	Re-apply a saved loadout to a model, replacing whatever is fitted.
	`PrepareForEquip` is implied, so a caller never has to remember to clear
	first.
]]
--[[
	Ordered list of categories to walk for a loadout: the configured ones in
	display order first (so application is deterministic), then *any other*
	category the loadout happens to contain.

	Trailing unknown categories matter: a game that adds a "Barrel" slot and
	saves it to a tool must still get it applied, even if this system's Config
	has never been told about that slot.
]]
local function loadoutCategories(loadout: { [string]: any }): {string}
	local ordered, seen = {}, {}
	for _, category in ipairs(Config.GetCategoryList()) do
		seen[category] = true
		table.insert(ordered, category)
	end

	local extra = {}
	for category in pairs(loadout) do
		if not seen[category] then
			table.insert(extra, category)
		end
	end
	table.sort(extra)
	for _, category in ipairs(extra) do
		table.insert(ordered, category)
	end

	return ordered
end

--[[
	Fit a whole loadout, replacing whatever is fitted.

	@return the number of entries that were fitted successfully, and the
	        number that failed. -1 entries means bad input.
]]
function AttachmentSystem.ApplyLoadout(
	player: Player?,
	weapon: Instance?,
	weaponModel: Instance?,
	loadout: { [string]: string }?
): (number, number)
	if not weapon or not weaponModel or type(loadout) ~= "table" then
		return -1, 0
	end

	AttachmentSystem.PrepareForEquip(weaponModel)

	local fitted, failed = 0, 0
	for _, category in ipairs(loadoutCategories(loadout)) do
		local name = loadout[category]
		if type(name) == "string" and name ~= "" then
			if AttachmentSystem.Equip(player, weapon, weaponModel, name, category) then
				fitted += 1
			else
				failed += 1
			end
		end
	end

	return fitted, failed
end

--[[
	Apply the loadout stored on a tool to a model. The single call most hosts
	want on the equip path.

	@return fitted count, failed count
]]
function AttachmentSystem.ApplySavedLoadout(player: Player?, weapon: Instance?, weaponModel: Instance?)
	return AttachmentSystem.ApplyLoadout(player, weapon, weaponModel, Storage.GetSaved(weapon))
end

-- ─── Registry queries (re-exported) ─────────────────────────────────────────

function AttachmentSystem.GetActive(weaponModel: Instance?): { [string]: any }
	return Queries.GetActive(weaponModel)
end

function AttachmentSystem.Get(weaponModel: Instance?, category: string)
	return Queries.Get(weaponModel, category)
end

function AttachmentSystem.Has(weaponModel: Instance?, category: string): boolean
	return Queries.Has(weaponModel, category)
end

-- ─── Capability queries (re-exported) ───────────────────────────────────────

function AttachmentSystem.GetMuzzle(weaponModel: Instance?): Instance?
	return Queries.GetMuzzle(weaponModel)
end

function AttachmentSystem.HasMuzzleOverride(weaponModel: Instance?): boolean
	return Queries.HasMuzzleOverride(weaponModel)
end

function AttachmentSystem.GetMuzzleConfig(weaponModel: Instance?): any?
	return Queries.GetMuzzleConfig(weaponModel)
end

function AttachmentSystem.IsSuppressed(weaponModelOrTool: Instance?): boolean
	return Queries.IsSuppressed(weaponModelOrTool)
end

function AttachmentSystem.GetOverheatConfig(weaponModel: Instance?): any?
	return Queries.GetOverheatConfig(weaponModel)
end

--[[
	Fire-volume scale for a fitted silencer. 1 when unsuppressed.
]]
function AttachmentSystem.GetSilencerVolumeMultiplier(weaponModel: Instance?): number
	return Queries.GetSilencerVolumeMultiplier(weaponModel)
end

function AttachmentSystem.GetLaserSource(weaponModel: Instance?): Attachment?
	return Queries.GetLaserSource(weaponModel)
end

function AttachmentSystem.HasLaser(weaponModel: Instance?): boolean
	return Queries.HasLaser(weaponModel)
end

function AttachmentSystem.GetLaserColor(source: Instance?): Color3
	return Queries.GetLaserColor(source)
end

function AttachmentSystem.GetFlashlightSource(weaponModel: Instance?): Instance?
	return Queries.GetFlashlightSource(weaponModel)
end

function AttachmentSystem.HasFlashlight(weaponModel: Instance?): boolean
	return Queries.HasFlashlight(weaponModel)
end

function AttachmentSystem.GetFlashlightLights(weaponModelOrPart: Instance?)
	return Queries.GetFlashlightLights(weaponModelOrPart)
end

function AttachmentSystem.GetGrip(weaponModel: Instance?, weaponName: string?)
	return Queries.GetGrip(weaponModel, weaponName)
end

function AttachmentSystem.HasGrip(weaponModel: Instance?): boolean
	return Queries.HasGrip(weaponModel)
end

function AttachmentSystem.GetAimPart(weaponModel: Instance?, sightIndex: number?): Instance?
	return Queries.GetAimPart(weaponModel, sightIndex)
end

function AttachmentSystem.GetOptics(weaponModel: Instance?)
	return Queries.GetOptics(weaponModel)
end

function AttachmentSystem.GetReticleConfig(weaponModel: Instance?): any?
	return Queries.GetReticleConfig(weaponModel)
end

function AttachmentSystem.GetDepthOfFieldConfig(weaponModel: Instance?): any?
	return Queries.GetDepthOfFieldConfig(weaponModel)
end

function AttachmentSystem.GetLeverRingPart(weaponModel: Instance?, leverRingName: string?): Instance?
	return Queries.GetLeverRingPart(weaponModel, leverRingName)
end

function AttachmentSystem.GetLPVOConfig(weaponModel: Instance?, weaponStats: any?): any?
	return Queries.GetLPVOConfig(weaponModel, weaponStats)
end

function AttachmentSystem.ForEachSightSurfaceGui(weaponModel: Instance?, callback: (SurfaceGui) -> (), includeAttachments: boolean?)
	Queries.ForEachSightSurfaceGui(weaponModel, callback, includeAttachments)
end

-- ─── Visuals (re-exported) ──────────────────────────────────────────────────

function AttachmentSystem.ApplyADSVisibility(weaponModel: Instance?, aiming: boolean, weaponStats: any?)
	Visuals.ApplyADSVisibility(weaponModel, aiming, weaponStats)
end

function AttachmentSystem.SetSightVisibility(weaponModel: Instance?, enabled: boolean, isThirdPerson: boolean?)
	Visuals.SetSightVisibility(weaponModel, enabled, isThirdPerson)
end

function AttachmentSystem.ClearMuzzleState(weaponModel: Instance?)
	Queries.ClearMuzzleState(weaponModel)
end

-- ─── Persistence (re-exported) ──────────────────────────────────────────────

function AttachmentSystem.GetSaved(weapon: Instance?): { [string]: string }
	return Storage.GetSaved(weapon)
end

function AttachmentSystem.SetSaved(weapon: Instance?, loadout: { [string]: string }?): boolean
	return Storage.SetSaved(weapon, loadout)
end

function AttachmentSystem.SetSavedEntry(weapon: Instance?, category: string, attachmentName: string?)
	return Storage.SetEntry(weapon, category, attachmentName)
end

function AttachmentSystem.ClearSaved(weapon: Instance?)
	Storage.Clear(weapon)
end

function AttachmentSystem.StoreBaseStats(weapon: Instance?, baseStats: any?): boolean
	return Storage.StoreBaseStats(weapon, baseStats)
end

function AttachmentSystem.GetBaseStats(weapon: Instance?): any?
	return Storage.GetBaseStats(weapon)
end

function AttachmentSystem.GetModifiedStats(weapon: Instance?): any?
	return Storage.GetModifiedStats(weapon)
end

function AttachmentSystem.LoadWeaponStats(weapon: Instance?): any?
	return Storage.LoadWeaponStats(weapon)
end

--[[
	Produce the weapon's effective stats: the base stats with every fitted
	attachment's `ApplyStats` applied. Returns nil only when the weapon has no
	base stats at all.
]]
function AttachmentSystem.ApplyStats(weapon: Instance?, weaponModel: Instance?): any?
	return StatModifier.Apply(weapon, weaponModel)
end

function AttachmentSystem.ReapplyStats(weapon: Instance?, baseStats: any?, weaponModel: Instance?): any?
	return StatModifier.Reapply(weapon, baseStats, weaponModel)
end

function AttachmentSystem.GetStatContributors(weaponModel: Instance?): {string}
	return StatModifier.GetContributors(weaponModel)
end

--[[
	Release everything the system caches about a tool.
	Call from a holster/drop/leave path so a long session does not accumulate
	stats snapshots for tools that no longer exist.
]]
function AttachmentSystem.Forget(weapon: Instance?)
	Storage.Forget(weapon)
end

-- ─── Diagnostics ────────────────────────────────────────────────────────────

function AttachmentSystem.Describe(weaponModel: Instance?): string
	return Registry.Describe(weaponModel)
end

function AttachmentSystem.DescribeMuzzle(weaponModel: Instance?): string
	return Registry.DescribeMuzzle(weaponModel, Queries.GetMuzzle)
end

--[[
	Everything the system knows about a model, as one printable block. Useful
	when a gun "looks wrong" and you need to know what is actually fitted.
]]
function AttachmentSystem.Inspect(weaponModel: Instance?): string
	if not weaponModel then
		return "[AttachmentSystem] no model"
	end

	local lines = { Registry.DescribeMuzzle(weaponModel, Queries.GetMuzzle) }
	lines[#lines + 1] = string.format("  ready=%s heartbeats=%d",
		tostring(AttachmentSystem.IsReady()), Registry.GetUpdaterCount())

	return table.concat(lines, "\n")
end

-- ─── Sub-systems ────────────────────────────────────────────────────────────

-- Exposed for hosts that want to build a custom menu on top of the same
-- primitives, and for tests.
AttachmentSystem.Config       = Config
AttachmentSystem.ConfigLoader = ConfigLoader
AttachmentSystem.Registry     = Registry
AttachmentSystem.Mounter      = Mounter
AttachmentSystem.Storage      = Storage
AttachmentSystem.Queries      = Queries
AttachmentSystem.Visuals      = Visuals
AttachmentSystem.StatModifier = StatModifier

-- The gunsmith menu is attached lazily by the host via
-- `AttachmentSystem.StartGunsmith(...)`, so requiring this module never
-- pulls UI code into a server context.
AttachmentSystem._gunsmith = nil

--[[
	Boot the gunsmith menu. The host supplies the pieces that belong to it —
	its ScreenGui template, its proximity-prompt host, and what to do when a
	loadout is confirmed — and the system owns everything else.

	Not called automatically. See `Gunsmith.luau`.
]]
function AttachmentSystem.StartGunsmith(hostOptions: { [string]: any }?): any?
	local Gunsmith = require(script.Gunsmith)
	AttachmentSystem._gunsmith = Gunsmith.start(hostOptions)
	return AttachmentSystem._gunsmith
end

function AttachmentSystem.GetGunsmith()
	return AttachmentSystem._gunsmith
end

return AttachmentSystem
