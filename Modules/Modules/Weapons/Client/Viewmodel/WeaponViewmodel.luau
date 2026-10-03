local Modules = script:FindFirstAncestor("Modules")

local WeaponContext         = require(Modules.Weapons.Core.WeaponContext)
local vars                  = require(Modules.Weapons.Core.WeaponState).get()
local Attachments           = require(Modules.Weapons.Attachments.SPHAttachments)
local reticleMotionBlurMod  = require(Modules.Weapons.Aiming.ReticleMotionBlurMod)
local ModelQueryCache       = require(Modules.Weapons.Core.ModelQueryCache)
local ContentProvider       = game:GetService("ContentProvider")
local player                = game:GetService("Players").LocalPlayer

-- ─── Upvalues (set by init) ───────────────────────────────────────────────────

local FindProjectilePart, GetThirdPersonGunModel, IdleAnim, character
local lArm, rArm, repPartVisibilityRequest, vmArmAccessories, vmShirt

local WeaponViewmodel = {}

-- ─── Internal helpers ─────────────────────────────────────────────────────────

-- Apply transparency + ForceHidden_Anim to a part and its BasePart descendants
local function applyPartVisibility(part: BasePart, visible: boolean)
	local t = visible and 0 or 1
	part.Transparency = t
	part:SetAttribute("ForceHidden_Anim", not visible)
	for _, child in part:GetDescendants() do
		if child:IsA("BasePart") then
			child.Transparency = t
		end
	end
end

-- Find a named BasePart in a model (returns first match)
local function findNamedPart(model: Instance, name: string): BasePart?
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name == name then
			return desc
		end
	end
	return nil
end

-- ─── TogglePartVisibility ─────────────────────────────────────────────────────

local function TogglePartVisibility(partName: string | { string }, visible: boolean)
	local names: { string } = type(partName) == "table" and partName or { partName }

	for _, name in names do
		if not vars.gunModel then continue end

		local part = vars.gunModel:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			applyPartVisibility(part, visible)
		end

		if vars.equipped then
			repPartVisibilityRequest.send({ PartName = name, Visible = visible })
		end

		local tpGunModel = GetThirdPersonGunModel()
		if tpGunModel then
			local tpPart = findNamedPart(tpGunModel, name)
			if tpPart then
				applyPartVisibility(tpPart, visible)
			end
		end
	end
end

-- ─── SyncThirdPersonProjectile ────────────────────────────────────────────────

type ProjectileVisuals = { parts: { BasePart }, decals: { Decal | Texture } }

-- Collects the BaseParts and Decals/Textures under a projectile/mag part.
-- Cached per projectile part (see ModelQueryCache): this runs every frame in
-- third person, and the projectile's hierarchy almost never changes.
local function collectProjectileVisuals(projectile: Instance): ProjectileVisuals
	local visuals: ProjectileVisuals = { parts = {}, decals = {} }
	for _, child in projectile:GetDescendants() do
		if child:IsA("BasePart") then
			table.insert(visuals.parts, child)
		elseif child:IsA("Decal") or child:IsA("Texture") then
			table.insert(visuals.decals, child :: any)
		end
	end
	return visuals
end

local function GetProjectileVisuals(projectile: Instance): ProjectileVisuals
	return ModelQueryCache.get(projectile, "projectileVisuals", collectProjectileVisuals, nil)
end

local function SyncThirdPersonProjectile()
	if vars.reloading and not vars.cancelReload then return end
	if not vars.equipped or not vars.wepStats or not vars.gunModel then return end

	local shouldBeVisible = false
	if vars.wepStats.openBolt then
		shouldBeVisible = vars.gunAmmo and vars.gunAmmo.MagAmmo and vars.gunAmmo.MagAmmo.Value > 0
	elseif vars.wepStats.operationType == 4 then
		local chambered   = vars.equipped:FindFirstChild("Chambered")
		local hasChamber  = chambered and chambered.Value
		local hasMagAmmo  = vars.gunAmmo and vars.gunAmmo.MagAmmo and vars.gunAmmo.MagAmmo.Value > 0
		shouldBeVisible   = hasChamber or hasMagAmmo
		if not shouldBeVisible and not vars.cancelReload
			and (tick() - vars.lastReloadCompletedTime) < 0.5 then
			shouldBeVisible = true
		end
	else
		local chambered = vars.equipped:FindFirstChild("Chambered")
		shouldBeVisible = chambered and chambered.Value
	end

	local t = shouldBeVisible and 0 or 1

	local fpProjectile = FindProjectilePart(vars.gunModel, vars.wepStats.projectile)
	if fpProjectile then
		fpProjectile:SetAttribute("ForceHidden_Anim", nil)
		fpProjectile.Transparency = t
		fpProjectile.LocalTransparencyModifier = 0
		local visuals = GetProjectileVisuals(fpProjectile)
		for _, part in visuals.parts do
			part.Transparency = t
			part.LocalTransparencyModifier = 0
		end
		for _, decal in visuals.decals do
			decal.Transparency = t
		end
	end

	local tpGunModel   = GetThirdPersonGunModel()
	local tpProjectile = tpGunModel and FindProjectilePart(tpGunModel, vars.wepStats.projectile)
	if tpProjectile then
		tpProjectile:SetAttribute("SPH_FPHidden", nil)
		tpProjectile.Transparency = t
		local visuals = GetProjectileVisuals(tpProjectile)
		for _, part in visuals.parts do
			part.Transparency = t
		end
		for _, decal in visuals.decals do
			decal.Transparency = t
		end
	end
end

-- ─── SetAllSightSurfaceGuis ───────────────────────────────────────────────────

-- Disable/enable SurfaceGuis on all SightReticle parts across all models
local function SetAllSightSurfaceGuis(enabled: boolean)
	local function applyToModel(model: Instance, forceDisable: boolean)
		for _, part in model:GetDescendants() do
			if part.Name == "SightReticle" then
				local sg = part:FindFirstChildWhichIsA("SurfaceGui")
				if sg then sg.Enabled = forceDisable and false or enabled end
			end
		end
	end

	if vars.gunModel then
		applyToModel(vars.gunModel, false)
	end

	for _, data in Attachments:GetActive(vars.gunModel) do
		if data and data.model then
			applyToModel(data.model, false)
		end
	end

	local tpGunModel = GetThirdPersonGunModel()
	if tpGunModel and tpGunModel ~= vars.gunModel then
		applyToModel(tpGunModel, true)  -- TP model always disabled
	end
end

-- ─── CollectAndManageSights ───────────────────────────────────────────────────

local function CollectAndManageSights(gunModel: Instance)
	-- Destroy existing motion blur handles
	for key, handle in vars.reticleBlurHandles do
		reticleMotionBlurMod.Destroy(handle)
	end
	table.clear(vars.reticleBlurHandles)

	vars.fpSights           = {}
	vars.tpSights           = {}
	vars.attachmentFpSights = {}

	local function collectReticles(model: Instance, isFP: boolean)
		for _, part in model:GetDescendants() do
			if part.Name == "SightReticle" then
				local sg = part:FindFirstChildWhichIsA("SurfaceGui")
				if not sg then continue end

				sg.AlwaysOnTop = false
				sg.Enabled     = false

				if isFP then
					table.insert(vars.fpSights, part)
					if part:GetAttribute("EnableParallax") ~= false then
						table.insert(vars.attachmentFpSights, part)
					end
				else
					table.insert(vars.tpSights, part)
				end
			end
		end
	end

	collectReticles(gunModel, true)

	for _, data in Attachments:GetActive(gunModel) do
		if data.model then
			collectReticles(data.model, true)
		end
	end

	local tpGunModel = GetThirdPersonGunModel()
	if tpGunModel and tpGunModel ~= gunModel then
		collectReticles(tpGunModel, false)
	end

	vars.sights = vars.fpSights
end

-- ─── ApplySavedAttachmentsToViewmodel ────────────────────────────────────────

local function ApplySavedAttachmentsToViewmodel(gunModel: Instance, tool: Instance)
	if not tool or not gunModel then return end

	if not Attachments:HasLoadout(tool) then return end

	-- Failures are reported by the attachment system.
	Attachments:ApplyLoadout(gunModel, tool, player)
end

-- ─── VM Accessory cleanup ─────────────────────────────────────────────────────

local function CleanupVMAccessories()
	for _, data in vmArmAccessories do
		if data.clone and data.clone.Parent then
			data.clone:Destroy()
		end
	end
	table.clear(vmArmAccessories)
end

-- ─── RefreshViewmodel ─────────────────────────────────────────────────────────

local function RefreshViewmodel()
	if vars.firstPerson and not vars.equipping then
		vars.viewmodelVisible = true
	end

	local plrShirt      = character:FindFirstChildWhichIsA("Shirt")
	local shirtTemplate = plrShirt and plrShirt.ShirtTemplate or ""

	if shirtTemplate ~= "" then
		if vars.cachedShirtTemplate == shirtTemplate then
			vmShirt.ShirtTemplate = shirtTemplate
		else
			task.spawn(function()
				local ok, err = pcall(ContentProvider.PreloadAsync, ContentProvider, { plrShirt })
				if not ok then
					warn("[Viewmodel] Failed to preload shirt:", tostring(err))
				end
				vars.cachedShirtTemplate = shirtTemplate
				vmShirt.ShirtTemplate    = shirtTemplate
			end)
		end
	else
		vmShirt.ShirtTemplate = ""
	end

	local leftColor  = character["Left Arm"].Color
	local rightColor = character["Right Arm"].Color
	lArm.Color = leftColor
	rArm.Color = rightColor

	for _, part in vars.rig:GetDescendants() do
		if part.Name == "Skin" then
			if part.Parent.Name == "Left Arm" then
				part.Color = leftColor
			elseif part.Parent.Name == "Right Arm" then
				part.Color = rightColor
			end
		end
	end

	IdleAnim()
	CleanupVMAccessories()
end

-- ─── Init ─────────────────────────────────────────────────────────────────────

function WeaponViewmodel.init()
	local ctx = WeaponContext.get()
	FindProjectilePart       = ctx.FindProjectilePart
	GetThirdPersonGunModel   = ctx.GetThirdPersonGunModel
	IdleAnim                 = ctx.IdleAnim
	character                = ctx.character
	lArm                     = ctx.lArm
	rArm                     = ctx.rArm
	repPartVisibilityRequest = ctx.repPartVisibilityRequest
	vmArmAccessories         = ctx.vmArmAccessories
	vmShirt                  = ctx.vmShirt
end

-- ─── Exports ──────────────────────────────────────────────────────────────────

WeaponViewmodel.TogglePartVisibility             = TogglePartVisibility
WeaponViewmodel.SyncThirdPersonProjectile        = SyncThirdPersonProjectile
WeaponViewmodel.SetAllSightSurfaceGuis           = SetAllSightSurfaceGuis
WeaponViewmodel.CollectAndManageSights           = CollectAndManageSights
WeaponViewmodel.ApplySavedAttachmentsToViewmodel = ApplySavedAttachmentsToViewmodel
WeaponViewmodel.CleanupVMAccessories             = CleanupVMAccessories
WeaponViewmodel.SyncArmAccessoriesToViewmodel    = CleanupVMAccessories  -- was just a wrapper
WeaponViewmodel.RefreshViewmodel                 = RefreshViewmodel
WeaponViewmodel.ResetHead                        = function() vars.viewmodelVisible = false end

return WeaponViewmodel