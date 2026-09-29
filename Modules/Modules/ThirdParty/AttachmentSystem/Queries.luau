--[[
	AttachmentSystem.Queries
	────────────────────────
	Everything the host wants to *ask* about a weapon's attachments.

	The previous implementation exposed a mix of "get me the raw registry
	table" and "get me a specific field", which forced every consumer to
	reach into `entry.config.X` and to re-implement lookup rules locally. Three
	separate SPH files, for instance, each re-walked `Tool.SavedAttachments` →
	asset folder → `require(Customization).EnableSilencer` to decide whether a
	weapon was suppressed.

	Everything is answerable from here instead, so the host never has to know
	how a muzzle or a laser is discovered.
]]

local Config    = require(script.Parent.Config)
local ConfigLoader = require(script.Parent.ConfigLoader)
local Registry  = require(script.Parent.Registry)
local Storage   = require(script.Parent.Storage)

local Queries = {}

-- ─── Registry passthrough ───────────────────────────────────────────────────

function Queries.GetActive(weaponModel: Instance?): { [string]: any }
	return Registry.GetAll(weaponModel)
end

function Queries.Get(weaponModel: Instance?, category: string)
	return Registry.Get(weaponModel, category)
end

function Queries.Has(weaponModel: Instance?, category: string): boolean
	return Registry.Has(weaponModel, category)
end

function Queries.Count(weaponModel: Instance?): number
	return Registry.Count(weaponModel)
end

function Queries.GetOccupiedCategories(weaponModel: Instance?): {string}
	return Registry.GetOccupiedCategories(weaponModel)
end

function Queries.GetConfig(attachmentName: string, category: string): any?
	return ConfigLoader.Load(attachmentName, category)
end

function Queries.IsCompatible(attachmentName: string, category: string, weaponName: string?): boolean
	return ConfigLoader.IsCompatible(attachmentName, category, weaponName)
end

function Queries.ListAvailable(category: string): {string}
	return ConfigLoader.List(category)
end

function Queries.ListAvailableFor(weaponModel: Instance?, category: string, weaponName: string?): {string}
	return ConfigLoader.ListCompatible(weaponModel, category, weaponName)
end

--[[
	Search every live entry for one that sets `flag` to true.
	Replaces the repeated "loop over getActive and read data.config.X" pattern.
]]
local function findByFlag(weaponModel: Instance?, flag: string)
	for _, category in ipairs(Registry.GetOccupiedCategories(weaponModel)) do
		local entry = Registry.Get(weaponModel, category)
		if entry and entry.config and entry.config[flag] == true then
			return entry
		end
	end
	return nil
end

-- ─── Muzzle ─────────────────────────────────────────────────────────────────

--[[
	The muzzle that bullets should actually leave from.

	Resolution order, identical to the previous implementation:
	  1. the live Muzzle-category attachment's own `Muzzle` part
	  2. the model attribute's recorded custom muzzle, if its node is present
	  3. the weapon's own `Grip.Muzzle`
]]
function Queries.GetMuzzle(weaponModel: Instance?): Instance?
	if not weaponModel then
		return nil
	end

	local entry = Registry.Get(weaponModel, "Muzzle")
	if entry and entry.model then
		local muzzle = entry.model:FindFirstChild(Config.ModelParts.muzzle, true)
		if muzzle then
			return muzzle
		end
	end

	local customName = weaponModel:GetAttribute(Config.Naming.activeCustomMuzzle)
	if type(customName) == "string" and customName ~= "" then
		local suffix = customName .. Config.Naming.equippedSuffix
		for _, part in ipairs(weaponModel:GetDescendants()) do
			if part:IsA("Folder") and part.Name == suffix then
				local muzzle = part:FindFirstChild(Config.ModelParts.muzzle, true)
				if muzzle then
					return muzzle
				end
			end
		end
	end

	local grip = weaponModel:FindFirstChild(Config.ModelParts.grip)
	if grip then
		return grip:FindFirstChild(Config.ModelParts.muzzle)
	end
	return nil
end

function Queries.HasMuzzleOverride(weaponModel: Instance?): boolean
	return Registry.Has(weaponModel, "Muzzle")
end

function Queries.GetMuzzleConfig(weaponModel: Instance?): any?
	local entry = Registry.Get(weaponModel, "Muzzle")
	return entry and entry.config or nil
end

--[[
	Whether the fitted muzzle suppresses the weapon.

	This is the single authoritative implementation. It works from a live
	weapon model *or* from a Tool's saved loadout, which is what the server
	needs before the viewmodel exists.
]]
function Queries.IsSuppressed(weaponModelOrTool: Instance?, weaponName: string?): boolean
	if not weaponModelOrTool then
		return false
	end

	-- Fast path: something is physically fitted right now.
	local entry = Registry.Get(weaponModelOrTool, "Muzzle")
	if entry and entry.config then
		return entry.config.EnableSilencer == true
	end

	-- Otherwise fall back to the saved loadout.
	local loadout = Storage.GetSaved(weaponModelOrTool)
	local muzzleName = loadout["Muzzle"]
	if not muzzleName or muzzleName == "" then
		return false
	end

	local config = ConfigLoader.Load(muzzleName, "Muzzle")
	return type(config) == "table" and config.EnableSilencer == true
end

--[[
	How much a fitted silencer should scale the weapon's fire volume.

	Scans every fitted attachment (not just the muzzle) so a future
	integrally-suppressed barrel or handguard contributes too, and takes the
	strongest effect when several apply. Returns 1 when unsuppressed.
]]
function Queries.GetSilencerVolumeMultiplier(weaponModel: Instance?): number
	local multiplier = 1

	for _, category in ipairs(Registry.GetOccupiedCategories(weaponModel)) do
		local entry = Registry.Get(weaponModel, category)
		local config = entry and entry.config
		if config and config.EnableSilencer then
			local value = config.SilencerVolumeMultiplier
			if type(value) == "number" then
				multiplier = math.min(multiplier, value)
			end
		end
	end

	return multiplier
end

--[[
	Whether the fitted muzzle is the heat-emitting kind, and its overheat
	profile. `BulletHandler` consumed this directly.
]]
function Queries.GetOverheatConfig(weaponModel: Instance?): any?
	local entry = Registry.Get(weaponModel, "Muzzle")
	if entry and entry.config then
		return entry.config.overHeating
	end
	return nil
end

--[[
	Drop the recorded muzzle override. Called when a weapon model is torn down
	so a recycled model does not advertise a muzzle that is no longer there.
]]
function Queries.ClearMuzzleState(weaponModel: Instance?)
	if not weaponModel then
		return
	end
	local base = weaponModel:FindFirstChild(Config.ModelParts.grip, true)
		or weaponModel:FindFirstChild(Config.ModelParts.base, true)
	if base then
		local muzzle = base:FindFirstChild(Config.ModelParts.muzzle, true)
		if muzzle then
			local target: Instance? = nil
			if muzzle:IsA("Attachment") then
				target = muzzle.Parent
			elseif muzzle:IsA("BasePart") then
				target = muzzle
			end
			if target then
				target:SetAttribute(Config.Naming.muzzlePreHidden, nil)
			end
		end
	end
	weaponModel:SetAttribute(Config.Naming.activeCustomMuzzle, nil)
end

-- ─── Laser ──────────────────────────────────────────────────────────────────

local function findNamedAttachment(root: Instance?, name: string): Attachment?
	if not root then
		return nil
	end
	local direct = root:FindFirstChild(name)
	if direct and direct:IsA("Attachment") then
		return direct
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment") and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

function Queries.GetLaserSource(weaponModel: Instance?): Attachment?
	if not weaponModel then
		return nil
	end

	for _, category in ipairs(Registry.GetOccupiedCategories(weaponModel)) do
		local entry = Registry.Get(weaponModel, category)
		if entry and entry.config and entry.config.EnableLaser then
			local part = findNamedAttachment(entry.model, Config.ModelParts.laser)
			if part then
				return part
			end
		end
	end

	local grip = weaponModel:FindFirstChild(Config.ModelParts.grip)
	if grip then
		local gripLaser = grip:FindFirstChild(Config.ModelParts.laser)
		if gripLaser and gripLaser:IsA("Attachment") then
			return gripLaser
		end
	end

	return findNamedAttachment(weaponModel, Config.ModelParts.laser)
end

function Queries.HasLaser(weaponModel: Instance?): boolean
	return findByFlag(weaponModel, "EnableLaser") ~= nil
		or Queries.GetLaserSource(weaponModel) ~= nil
end

--[[
	The laser's colour, read from the `Color` value object the laser models
	carry. The gunsmith confirm path read this inline; it is part of the
	attachment's contract, so it lives here.
]]
function Queries.GetLaserColor(source: Instance?): Color3
	if not source then
		return Color3.fromRGB(255, 30, 30)
	end
	local holder = source:FindFirstChild(Config.ModelParts.laserColor)
	if holder and holder:IsA("ObjectValue") and holder.Value then
		return holder.Value
	end
	if holder and holder:IsA("Color3Value") then
		return holder.Value
	end
	return Color3.fromRGB(255, 30, 30)
end

-- ─── Flashlight ─────────────────────────────────────────────────────────────

--[[
	The flashlight housing.

	The previous implementation checked the weapon's own `Grip.Flashlight`
	*before* looking at attachments, so a gun with both a rail light and an
	underbarrel light always resolved to the rail light. Attachments are now
	consulted first, because that is the more specific, user-chosen source.
]]
function Queries.GetFlashlightSource(weaponModel: Instance?): Instance?
	if not weaponModel then
		return nil
	end

	for _, category in ipairs(Registry.GetOccupiedCategories(weaponModel)) do
		local entry = Registry.Get(weaponModel, category)
		if entry and entry.config and entry.config.EnableFlashlight then
			local part = entry.model:FindFirstChild(Config.ModelParts.flashlight, true)
			if part then
				return part
			end
		end
	end

	local grip = weaponModel:FindFirstChild(Config.ModelParts.grip)
	if grip then
		local gripFlash = grip:FindFirstChild(Config.ModelParts.flashlight)
		if gripFlash then
			return gripFlash
		end
	end

	return weaponModel:FindFirstChild(Config.ModelParts.flashlight, true)
end

function Queries.HasFlashlight(weaponModel: Instance?): boolean
	return findByFlag(weaponModel, "EnableFlashlight") ~= nil
		or Queries.GetFlashlightSource(weaponModel) ~= nil
end

--[[
	The beam lights inside a flashlight housing. Returned together with the
	housing because every consumer needed all three.

	Accepts either a weapon model (resolved) or an already-resolved housing, so
	callers that just found a part do not pay for a second lookup.
]]
function Queries.GetFlashlightLights(weaponModelOrPart: Instance?): { part: Instance?, inner: Instance?, outer: Instance? }?
	local part = weaponModelOrPart

	if part and not part:IsA("Model") then
		-- Already a housing (or something that is not a model): use it directly.
		part = part:FindFirstChild(Config.ModelParts.flashlight, true) or part
	else
		part = Queries.GetFlashlightSource(part)
	end

	if not part then
		return nil
	end

	return {
		part  = part,
		inner = part:FindFirstChild(Config.ModelParts.innerLight),
		outer = part:FindFirstChild(Config.ModelParts.outerLight),
	}
end

-- ─── Grip / hand positioning ────────────────────────────────────────────────

--[[
	Where the support hand should be for the fitted grip, and how to get
	there. `ArmPositionMod` consumed the raw table and applied the CFrame
	itself.
]]
function Queries.GetGrip(weaponModel: Instance?, weaponName: string?): { [string]: any }?
	local entry = Registry.Get(weaponModel, "Underbarrel")
	if not entry then
		return nil
	end

	local config = entry.config
	if not config or config.EnableHandPositioning ~= true then
		return nil
	end

	local gripPartName = config.HandGripPart
	if type(gripPartName) ~= "string" or gripPartName == "" then
		return nil
	end

	local gripPart = entry.model:FindFirstChild(gripPartName, true)
	if not gripPart then
		return nil
	end

	local worldCFrame
	if gripPart:IsA("Attachment") then
		worldCFrame = gripPart.WorldCFrame
	elseif gripPart:IsA("BasePart") then
		worldCFrame = gripPart.CFrame
	end

	if not worldCFrame then
		return nil
	end

	return {
		gripWorldCFrame     = worldCFrame,
		gripPart            = gripPart,
		handToPosition      = config.HandToPosition or "Left Arm",
		transitionSpeed     = config.HandTransitionSpeed or 15,
		matchRotation       = config.HandMatchRotation ~= false,
	}
end

function Queries.HasGrip(weaponModel: Instance?): boolean
	return Registry.Get(weaponModel, "Underbarrel") ~= nil
		and Registry.Get(weaponModel, "Underbarrel").config.EnableHandPositioning == true
end

-- ─── Optics ─────────────────────────────────────────────────────────────────

--[[
	The part the camera should look down when aiming. An optic can override
	the per-sight-index aim part, which is what lets a red dot and a scope
	share a weapon with two different ADS alignments.
]]
function Queries.GetAimPart(weaponModel: Instance?, sightIndex: number?): Instance?
	local entry = Registry.Get(weaponModel, "Optics")
	if not entry or not entry.model then
		return nil
	end

	local prefix = Config.ModelParts.aimPart
	local index = sightIndex or 1

	if index > 1 then
		local indexed = entry.model:FindFirstChild(prefix .. index, true)
		if indexed then
			return indexed
		end
	end

	return entry.model:FindFirstChild(prefix, true)
end

function Queries.GetOptics(weaponModel: Instance?)
	return Registry.Get(weaponModel, "Optics")
end

function Queries.GetReticleConfig(weaponModel: Instance?): any?
	local entry = Registry.Get(weaponModel, "Optics")
	if entry and entry.config then
		return entry.config.ReticleConfig
	end
	return nil
end

function Queries.GetDepthOfFieldConfig(weaponModel: Instance?): any?
	local entry = Registry.Get(weaponModel, "Optics")
	if entry and entry.config then
		return entry.config.DepthOfField
	end
	return nil
end

--[[
	The lever ring a magnified optic's zoom actuator must move, if the fitted
	optic has one. Falls back to the weapon's own part, matching what
	`ArmPositionMod` did locally.
]]
function Queries.GetLeverRingPart(weaponModel: Instance?, leverRingName: string?): Instance?
	if type(leverRingName) ~= "string" or leverRingName == "" then
		return nil
	end

	local entry = Registry.Get(weaponModel, "Optics")
	if entry and entry.model then
		local lever = entry.model:FindFirstChild(leverRingName, true)
		if lever and lever:IsA("BasePart") then
			return lever
		end
	end

	local base = weaponModel and weaponModel:FindFirstChild(leverRingName)
	if base and base:IsA("BasePart") then
		return base
	end
	return nil
end

--[[
	The fitted optic's magnification profile, falling back to the weapon's own
	`LPVOZoom` block. `ServerHelpers` read `opticsAttachment.config.LPVOZoom`
	directly to decide what to replicate.
]]
function Queries.GetLPVOConfig(weaponModel: Instance?, weaponStats: any?): any?
	local entry = Registry.Get(weaponModel, "Optics")
	if entry and entry.config and type(entry.config.LPVOZoom) == "table" then
		return entry.config.LPVOZoom
	end
	if type(weaponStats) == "table" and type(weaponStats.LPVOZoom) == "table" then
		return weaponStats.LPVOZoom
	end
	return nil
end

--[[
	Every surface GUI a set of reticles lives on, across the weapon model and
	all of its attachments. Several modules each re-walked this to toggle
	ADS visibility; doing it here keeps the definition in one place.
]]
function Queries.ForEachSightSurfaceGui(weaponModel: Instance?, callback: (SurfaceGui) -> (), includeAttachments: boolean?)
	if not weaponModel or not callback then
		return
	end

	local function scan(model: Instance?)
		if not model then
			return
		end
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Name == "SightReticle" then
				local gui = part:FindFirstChildWhichIsA("SurfaceGui")
				if gui then
					callback(gui)
				end
			end
		end
	end

	scan(weaponModel)

	if includeAttachments ~= false then
		for _, category in ipairs(Registry.GetOccupiedCategories(weaponModel)) do
			local entry = Registry.Get(weaponModel, category)
			if entry and entry.model then
				scan(entry.model)
			end
		end
	end
end

return Queries
