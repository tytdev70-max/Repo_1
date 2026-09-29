--[[
	Weapons/UI/CustomizeGunGUI  —  SPH ⇄ AttachmentSystem gunsmith adapter
	─────────────────────────────────────────────────────────────────────────
	All attachment logic lives in the standalone provider at
	`Modules/ThirdParty.AttachmentSystem`. This file is the glue that tells it
	about SPH: which ScreenGui to build on, where the gun models and the live
	viewmodel are, what "an SPH weapon" means, and what the game has to do
	after a loadout is confirmed.

	Note on behaviour
	─────────────────
	The gunsmith is **not started by this adapter**. As extracted, SPH's
	gunsmith was already dormant — the menu script under
	`SPH_Assets.HUD` was required by nothing, so no prompt was ever bound and
	`GunEvents.GetSelectedAttachments` was never registered. Preserving that
	is deliberate: switching the menu on is a gameplay decision, not a
	refactoring side effect.

	Call `CustomizeGunGUI.StartGunsmith()` to enable it.
]]

local CustomizeGunGUI = {}

local Modules = script:FindFirstAncestor("Modules")

local CustomizeGunHandler = require(script.Parent.CustomizeGunHandler)

-- SPH context, filled in by Init.
local ctx = {}
local gunsmith = nil
local promptBound = false

-- ─── SPH-specific answers ──────────────────────────────────────────────────

local function isSPHWeapon(instance: Instance?): boolean
	return instance ~= nil and instance:FindFirstChild("SPH_Weapon") ~= nil
end

local function getEquippedWeapon(): Tool?
	local player = ctx.player
	local character = player and player.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChildWhichIsA("Tool")
	return isSPHWeapon(tool) and tool or nil
end

--[[
	The weapon model the player is looking at. Attachment mount points live
	here, so it is what compatibility checks have to run against.
]]
local function resolveModel(_weaponName: string?): Model?
	local player = ctx.player
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local rig = camera:FindFirstChild("WeaponRig")
	if not rig then
		return nil
	end
	local folder = rig:FindFirstChild("Weapon")
	if not folder then
		return nil
	end
	return folder:FindFirstChildWhichIsA("Model")
end

--[[
	The model the gunsmith's 3D preview clones. This is SPH's business (it
	knows where weapon models are); the provider only asks for one.
]]
local function getWeaponModel(weaponName: string?): Instance?
	local assets = ctx.assets
	if not assets or not weaponName then
		return nil
	end
	local models = assets:FindFirstChild("WeaponModels")
	return models and models:FindFirstChild(weaponName) or nil
end

--[[
	Everything SPH has to do after a loadout is confirmed. The provider has
	already written the loadout to the tool; the weapon reaction — re-fitting
	the viewmodel, refreshing stats, springs, FOV, ADS, and the light/laser
	models — is weapon logic and stays here.
]]
local function onConfirm(selection: { [string]: string }, weapon: Tool?): boolean
	local attachmentSystem = ctx.attachmentSystem
	local vars             = ctx.vars
	if not attachmentSystem or not vars or not weapon then
		return false
	end

	local equipped   = vars.equipped
	local gunModel   = vars.gunModel
	local player     = ctx.player
	if equipped ~= weapon or not gunModel then
		return false
	end

	-- Re-fit the viewmodel from scratch so a swapped part cannot leave
	-- anything from the previous loadout behind.
	attachmentSystem.PrepareForEquip(gunModel)
	for category, name in pairs(selection) do
		if type(name) == "string" and name ~= "" then
			attachmentSystem.Equip(player, equipped, gunModel, name, category)
		end
	end

	if ctx.collectAndManageSights then
		ctx.collectAndManageSights(gunModel)
	end
	if ctx.mobileSupport then
		ctx.mobileSupport.UpdateMobileButtonVisibility()
	end

	-- Lasers and flashlights keep their runtime state across a refit, so nudge
	-- them back on exactly as the previous implementation did.
	if vars.laserEnabled then
		local laserSource = attachmentSystem.GetLaserSource(gunModel)
		local tpLaserSource
		if ctx.getThirdPersonGunModel then
			local tpGunModel = ctx.getThirdPersonGunModel()
			tpLaserSource = tpGunModel and attachmentSystem.GetLaserSource(tpGunModel)
		end

		local source = laserSource or tpLaserSource
		if source then
			local color = attachmentSystem.GetLaserColor(source)
			if ctx.glareMod then
				ctx.glareMod.SetLaserModelActive(laserSource, tpLaserSource,
					vars.firstPerson, true, color)
			end
		end

		_attachmentPulse(ctx, 1)
	end

	if vars.flashlightEnabled then
		local flashlightPart = attachmentSystem.GetFlashlightSource(gunModel)
		if flashlightPart and vars.flashFX and vars.flashFX.mod then
			vars.flashFX.mod.SetEnabled(flashlightPart, true)
		end

		local tpFlashlightPart
		if ctx.getThirdPersonGunModel then
			local tpGunModel = ctx.getThirdPersonGunModel()
			if tpGunModel then
				tpFlashlightPart = attachmentSystem.GetFlashlightSource(tpGunModel)
				if tpFlashlightPart and vars.flashFX and vars.flashFX.mod then
					vars.flashFX.mod.SetEnabled(tpFlashlightPart, not vars.firstPerson)
				end
			end
		end

		if ctx.glareMod and (flashlightPart or tpFlashlightPart) then
			local color = ctx.glareMod.ResolveFlashlightColor(flashlightPart or tpFlashlightPart)
			ctx.glareMod.SetFlashlightModelActive(flashlightPart, tpFlashlightPart,
				vars.firstPerson, true, color)
		end

		_attachmentPulse(ctx, 0)
	end

	-- Weapon stats.
	attachmentSystem.StoreBaseStats(equipped, attachmentSystem.LoadWeaponStats(equipped))
	local newWepStats = attachmentSystem.ApplyStats(equipped, gunModel)
	if not newWepStats then
		return false
	end

	local humanoid = ctx.humanoid
	local character = ctx.character
	if humanoid and character then
		local baseWalkSpeed = ctx.gameConfig.walkSpeed or 16
		humanoid.WalkSpeed = baseWalkSpeed * (newWepStats.walkSpeedMultiplier or 1.0)
		character:SetAttribute("SprintSpeedMultiplier", newWepStats.sprintSpeedMultiplier or 1.0)
	end

	vars.aimFOVTarget = newWepStats.aimFovDefault or newWepStats.aimFov or ctx.defaultFOV
	if ctx.aimFOVTargetRef then
		ctx.aimFOVTargetRef.value = vars.aimFOVTarget
	end
	newWepStats.aimFovMin = newWepStats.aimFovMin or 30
	newWepStats.aimFovMax = newWepStats.aimFovMax or ctx.defaultFOV

	if ctx.recoilSpring and newWepStats.recoil then
		ctx.recoilSpring.Damping = newWepStats.recoil.damping
		ctx.recoilSpring.Speed    = newWepStats.recoil.speed
	end
	if ctx.gunRecoilSpring and newWepStats.gunRecoil then
		ctx.gunRecoilSpring.Damping = newWepStats.gunRecoil.damping
		ctx.gunRecoilSpring.Speed    = newWepStats.gunRecoil.speed
	end

	vars.wepStats = newWepStats

	if ctx.aimingSystemMod then
		ctx.aimingSystemMod.UpdateADSVisual(gunModel, newWepStats, vars.sightIndex,
			vars.aiming == true, ctx.attachmentSystem)
	end

	RefreshStats()
	return true
end

-- Toggle a light attachment off and back on so the client re-receives it.
local function _attachmentPulse(context, attachmentType: number)
	local toggle = context.playerToggleAttachment
	if not toggle then
		return
	end
	task.spawn(function()
		task.wait(0.2)
		toggle.send({ AttachmentType = attachmentType, Enabled = false })
		task.wait(0.05)
		toggle.send({ AttachmentType = attachmentType, Enabled = true })
	end)
end

--[[
	Server-driven stat refresh. The provider recomputes the stats; SPH reapplies
	whatever the weapon system derives from them.
]]
function RefreshStats()
	local attachmentSystem = ctx.attachmentSystem
	local vars             = ctx.vars
	local equipped         = vars and vars.equipped
	if not attachmentSystem or not equipped or not vars.wepStats then
		return
	end

	attachmentSystem.StoreBaseStats(equipped, attachmentSystem.LoadWeaponStats(equipped))
	local newWepStats = attachmentSystem.ApplyStats(equipped, vars.gunModel)
	if not newWepStats then
		return
	end

	if ctx.mobileSupport then
		ctx.mobileSupport.UpdateMobileButtonVisibility()
	end

	local humanoid  = ctx.humanoid
	local character = ctx.character
	if humanoid and character then
		local baseWalkSpeed = ctx.gameConfig.walkSpeed or 16
		humanoid.WalkSpeed = baseWalkSpeed * (newWepStats.walkSpeedMultiplier or 1.0)
		character:SetAttribute("SprintSpeedMultiplier", newWepStats.sprintSpeedMultiplier or 1.0)
	end

	vars.aimFOVTarget = newWepStats.aimFovDefault or newWepStats.aimFov or ctx.defaultFOV
	if ctx.aimFOVTargetRef then
		ctx.aimFOVTargetRef.value = vars.aimFOVTarget
	end
	newWepStats.aimFovMin = newWepStats.aimFovMin or 30
	newWepStats.aimFovMax = newWepStats.aimFovMax or ctx.defaultFOV

	vars.wepStats = newWepStats
end

-- ─── Lifecycle ──────────────────────────────────────────────────────────────

--[[
	Called from SystemModuleInits. Records SPH's context and subscribes to the
	server's stat-refresh event, but does *not* open the gunsmith.
]]
function CustomizeGunGUI.Init(config)
	ctx = {
		player        = config.player,
		assets        = config.assets,
		vars          = require(Modules.Weapons.Core.WeaponState).get(),
		attachmentSystem = config.attachmentSystem,
		mobileSupport = config.mobileSupport,
		aimingSystemMod = config.aimingSystemMod,
		recoilSpring  = config.recoilSpring,
		gunRecoilSpring = config.gunRecoilSpring,
		aimFOVTargetRef = config.aimFOVTargetRef,
		gameConfig    = config.gameConfig,
		defaultFOV    = config.defaultFOV,
		playerToggleAttachment = config.playerToggleAttachment,
		collectAndManageSights = config.collectAndManageSights,
		glareMod      = config.glareMod,
		getThirdPersonGunModel = config.getThirdPersonGunModel,
		humanoid      = config.humanoid,
		character     = config.character,
	}

	local gunEvents = config.assets:WaitForChild("Events"):WaitForChild("GunEvents")
	local reloadStatsEvent = gunEvents:FindFirstChild("ReloadWeaponStats")
	if reloadStatsEvent then
		reloadStatsEvent.OnClientEvent:Connect(function(weapon)
			if ctx.vars and weapon == ctx.vars.equipped and ctx.vars.wepStats then
				RefreshStats()
			end
		end)
	else
		warn("[Gunsmith] ReloadWeaponStats event not found - "
			.. "stats won't refresh after a customization")
	end
end

--[[
	Explicitly enable the gunsmith. Idempotent.

	    CustomizeGunGUI.StartGunsmith()
]]
function CustomizeGunGUI.StartGunsmith()
	if gunsmith then
		return gunsmith
	end

	local attachmentSystem = ctx.attachmentSystem
	if not attachmentSystem then
		warn("[Gunsmith] StartGunsmith called before Init")
		return nil
	end

	gunsmith = attachmentSystem.StartGunsmith({
		getPlayer            = function() return ctx.player end,
		getPlayerGui         = function() return ctx.player and ctx.player.PlayerGui end,
		getCharacter         = function() return ctx.player and ctx.player.Character end,
		getEquippedWeapon    = getEquippedWeapon,
		resolveModel         = resolveModel,
		getWeaponModel       = getWeaponModel,
		onConfirm            = onConfirm,
		keepMouseDefault     = true,

		-- SPH's own inventory suppression, delegated to the provider's
		-- input lock instead of being hardcoded there.
		shouldRestoreMenus = function()
			local character = ctx.player and ctx.player.Character
			if not character then
				return true
			end
			return not (character:GetAttribute("BackpackDisabled")
				or character:GetAttribute("IsUnequippingForArmHiding"))
		end,
		suppressedNamePatterns = { "inventory", "hotbar" },
		shouldSuppressGui = function()
			local playerGui = ctx.player and ctx.player.PlayerGui
			local found = {}
			if playerGui then
				for _, child in ipairs(playerGui:GetChildren()) do
					if child:IsA("ScreenGui") then
						local name = string.lower(child.Name)
						if string.find(name, "inventory") or string.find(name, "hotbar") then
							table.insert(found, child)
						end
					end
				end
			end
			return found
		end,
		coreGuiToDisable  = Enum.CoreGuiType.Backpack,
		enforceSuppression = true,
	})

	if gunsmith and not promptBound then
		promptBound = true
		CustomizeGunHandler.BindCallbacks(
			function() gunsmith:Open() end,
			function() return gunsmith:IsOpen() end
		)
	end

	return gunsmith
end

function CustomizeGunGUI.GetGunsmith()
	return gunsmith
end

return CustomizeGunGUI
